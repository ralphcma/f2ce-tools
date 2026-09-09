local script_path = assert(arg[1], "usage: lua startup_topology_sync_run.lua <events.lua>")

local passed, failed = 0, 0

local function check(condition, message)
    if not condition then error(message or "check failed", 2) end
end

local function equal(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s",
            message or "values differ", tostring(expected), tostring(actual)), 2)
    end
end

local function scenario(options)
    options = options or {}
    local handlers, timers = {}, {}
    local next_timer_id = 0

    local env = {
        F2T_MAP_ENABLED = options.map_enabled ~= false,
        F2T_CONNECTED = options.connected ~= false,
        connected = options.connected ~= false,
        auto_sync = options.auto_sync ~= false,
        gmcp = {
            char = {
                vitals = { name = options.name == nil and "Test Pilot" or options.name },
            },
        },
        handlers = handlers,
        timers = timers,
        sync_calls = 0,
        sync_attempts = 0,
        busy_starts = options.busy_starts or 0,
        debug_messages = {},
    }

    env.registerAnonymousEventHandler = function(event, callback)
        handlers[event] = handlers[event] or {}
        table.insert(handlers[event], callback)
        return #handlers[event]
    end
    env.tempTimer = function(_, callback)
        next_timer_id = next_timer_id + 1
        timers[next_timer_id] = { callback = callback, killed = false }
        return next_timer_id
    end
    env.killTimer = function(id)
        if timers[id] then timers[id].killed = true end
        return true
    end
    env.f2t_settings_get = function(component, key)
        if component == "map" and key == "topology_auto_sync" then return env.auto_sync end
    end
    env.f2t_check_connection = function()
        env.F2T_CONNECTED = env.connected
        return env.connected
    end
    env.f2t_map_topology_sync = function()
        env.sync_attempts = env.sync_attempts + 1
        if env.busy_starts > 0 then
            env.busy_starts = env.busy_starts - 1
            return false, "native busy"
        end
        env.sync_calls = env.sync_calls + 1
        return true
    end
    env.f2t_debug_log = function(fmt, ...)
        table.insert(env.debug_messages, string.format(fmt, ...))
    end

    setmetatable(env, { __index = _G })
    local chunk, load_error
    if setfenv then
        chunk, load_error = loadfile(script_path)
        if chunk then setfenv(chunk, env) end
    else
        chunk, load_error = loadfile(script_path, "t", env)
    end
    assert(chunk, load_error)
    chunk()

    function env:emit(event)
        for _, callback in ipairs(handlers[event] or {}) do callback(event) end
    end

    function env:active_timer_ids()
        local ids = {}
        for id, timer in pairs(timers) do
            if not timer.killed then table.insert(ids, id) end
        end
        table.sort(ids)
        return ids
    end

    function env:fire_timer(id)
        local timer = assert(timers[id], "unknown timer")
        if not timer.killed then
            timer.killed = true
            timer.callback()
        end
    end

    return env
end

local tests = {}

function tests.enabled_connection_schedules_and_runs_once()
    local env = scenario()
    local ids = env:active_timer_ids()
    equal(#ids, 1, "startup timer count")

    env:emit("gmcp.char.vitals")
    equal(#env:active_timer_ids(), 1, "duplicate vitals must not add a timer")

    env:fire_timer(ids[1])
    equal(env.sync_calls, 1, "topology sync count")
    env:emit("gmcp.char.vitals")
    equal(#env:active_timer_ids(), 0, "completed login must not schedule again")
end

function tests.native_busy_retries_without_starting_a_command_capture()
    local env = scenario({ busy_starts = 1 })
    env:fire_timer(env:active_timer_ids()[1])
    equal(env.sync_attempts, 1, "first deferred attempt count")
    equal(env.sync_calls, 0, "busy attempt must not start topology")
    local retry = env:active_timer_ids()
    equal(#retry, 1, "one bounded retry timer")
    env:fire_timer(retry[1])
    equal(env.sync_attempts, 2, "retry attempt count")
    equal(env.sync_calls, 1, "retry starts after reservation clears")
end

function tests.disabled_map_sends_zero_commands()
    local env = scenario({ map_enabled = false })
    equal(#env:active_timer_ids(), 0, "disabled map timer count")
    env:emit("gmcp.char.vitals")
    equal(#env:active_timer_ids(), 0, "disabled map retry timer count")
    equal(env.sync_calls, 0, "disabled map sync count")
end

function tests.disabled_auto_sync_sends_zero_commands()
    local env = scenario({ auto_sync = false })
    equal(#env:active_timer_ids(), 0, "disabled auto-sync timer count")
    env:emit("gmcp.char.vitals")
    equal(env.sync_calls, 0, "disabled auto-sync sync count")
end

function tests.prelogin_and_disconnected_states_schedule_nothing()
    local prelogin = scenario({ name = "" })
    equal(#prelogin:active_timer_ids(), 0, "pre-login timer count")

    local disconnected = scenario({ connected = false })
    equal(#disconnected:active_timer_ids(), 0, "disconnected timer count")
    equal(disconnected.sync_calls, 0, "disconnected sync count")
end

function tests.disable_while_waiting_sends_zero_and_can_retry()
    local env = scenario()
    local first = env:active_timer_ids()[1]
    env.F2T_MAP_ENABLED = false
    env:fire_timer(first)
    equal(env.sync_calls, 0, "disabled-during-wait sync count")

    env.F2T_MAP_ENABLED = true
    env:emit("gmcp.char.vitals")
    local ids = env:active_timer_ids()
    check(#ids >= 1, "re-enabled map should schedule a later retry")
    env:fire_timer(ids[#ids])
    equal(env.sync_calls, 1, "re-enabled retry sync count")
end

function tests.disconnect_cancels_pending_work_and_reconnect_is_fresh()
    local env = scenario()
    local first = env:active_timer_ids()[1]
    env.connected = false
    env:emit("sysDisconnectionEvent")
    check(env.timers[first].killed, "disconnect must kill the pending timer")
    env:fire_timer(first)
    equal(env.sync_calls, 0, "disconnected timer sync count")

    env.connected = true
    env:emit("gmcp.char.vitals")
    local ids = env:active_timer_ids()
    check(#ids >= 1, "reconnect should schedule fresh work")
    env:fire_timer(ids[#ids])
    equal(env.sync_calls, 1, "reconnect sync count")
end

for name, test in pairs(tests) do
    local ok, err = pcall(test)
    if ok then
        passed = passed + 1
        io.write("PASS ", name, "\n")
    else
        failed = failed + 1
        io.stderr:write("FAIL ", name, ": ", tostring(err), "\n")
    end
end

io.write(string.format("RESULT %d passed, %d failed\n", passed, failed))
if failed > 0 then os.exit(1) end
