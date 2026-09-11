local script_path = assert(arg[1], "usage: lua topology_capture_safety_run.lua <topology_capture.lua>")

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
    local env = {
        F2T_MAP_ENABLED = options.map_enabled ~= false,
        F2T_CONNECTED = options.connected ~= false,
        connected = options.connected ~= false,
        auto_sync = options.auto_sync ~= false,
        sent = {},
        callbacks = {},
        armed = nil,
        close_count = 0,
        debug_messages = {},
        busy = options.busy == true,
    }

    env.send = function(command) table.insert(env.sent, command) end
    env.cecho = function() end
    env.f2t_capture_close = function()
        env.close_count = env.close_count + 1
        env.armed = nil
    end
    env.f2t_capture_arm = function(_, callback) env.armed = callback end
    env.f2t_settings_get = function(component, key)
        if component == "map" and key == "topology_auto_sync" then return env.auto_sync end
    end
    env.f2t_check_connection = function()
        env.F2T_CONNECTED = env.connected
        return env.connected
    end
    env.f2t_debug_log = function(fmt, ...)
        table.insert(env.debug_messages, string.format(fmt, ...))
    end
    env.F2CE = { API = { v1 = { navigation = {}, commands = {
        _nativeBlocker = function() return env.busy and {kind="speedwalk"} or nil end,
    } } } }

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
    return env
end

local tests = {}

function tests.automatic_start_respects_every_gate()
    for _, options in ipairs({
        { map_enabled = false },
        { auto_sync = false },
        { connected = false },
    }) do
        local env = scenario(options)
        local callback_count = 0
        local started = env.f2t_map_topology_sync(function(ok)
            callback_count = callback_count + 1
            equal(ok, false, "denied callback result")
        end, { automatic = true, silent = true })
        equal(started, false, "automatic denied start")
        equal(#env.sent, 0, "automatic denied command count")
        equal(callback_count, 1, "automatic denied callback count")
    end
end

function tests.automatic_start_defers_to_native_reservations()
    local env = scenario({busy=true})
    local started, reason = env.f2t_map_topology_sync(nil,{automatic=true,silent=true})
    equal(started,false,"busy automatic start")
    equal(reason,"native busy","busy start reason")
    equal(#env.sent,0,"busy automatic command count")
    equal(env.F2T_MAP_TOPOLOGY_CAPTURE.active,false,"busy automatic capture state")
    env.busy=false
    check(env.f2t_map_topology_sync(nil,{automatic=true,silent=true}),"retry should start")
    equal(env.sent[1],"display cartels","retry first command")
end

function tests.capture_start_failures_restore_inactive_state()
    for _, kind in ipairs({"timer","send"}) do
        local env=scenario()
        if kind=="timer" then env.f2t_capture_arm=function() error("timer failed") end
        else env.send=function() error("send failed") end end
        local callbacks=0
        local started=env.f2t_map_topology_sync(function(ok) callbacks=callbacks+1; equal(ok,false,"failure callback") end,
            {automatic=true,silent=true})
        equal(started,false,kind.." start")
        equal(env.F2T_MAP_TOPOLOGY_CAPTURE.active,false,kind.." inactive")
        equal(callbacks,1,kind.." callback count")
    end
end

function tests.second_phase_send_failure_restores_inactive_state()
    local env=scenario(); local callbacks=0
    check(env.f2t_map_topology_sync(function(ok) callbacks=callbacks+1; equal(ok,false,"phase callback") end,
        {automatic=true,silent=true}))
    env.send=function() error("second send failed") end
    local timer=assert(env.armed); timer()
    equal(env.F2T_MAP_TOPOLOGY_CAPTURE.active,false,"second phase inactive")
    equal(callbacks,1,"second phase callback count")
end

function tests.reload_retires_only_the_old_topology_capture()
    local env=scenario(); local callbacks=0
    check(env.f2t_map_topology_sync(function(ok) callbacks=callbacks+1; equal(ok,false,"reload callback") end,
        {automatic=true,silent=true}))
    env.F2T_CAPTURE_WINDOWS={other={timerId=999}}
    local chunk
    if setfenv then
        chunk=assert(loadfile(script_path)); setfenv(chunk,env)
    else
        chunk=assert(loadfile(script_path,"t",env))
    end
    chunk()
    equal(env.F2T_MAP_TOPOLOGY_CAPTURE.active,false,"reload inactive")
    equal(callbacks,1,"reload callback count")
    equal(env.F2T_CAPTURE_WINDOWS.other.timerId,999,"foreign capture preserved")
end

function tests.automatic_capture_stops_before_second_command_when_disabled()
    local env = scenario()
    local callback_count = 0
    check(env.f2t_map_topology_sync(function(ok)
        callback_count = callback_count + 1
        equal(ok, false, "cancel callback result")
    end, { automatic = true, silent = true }), "automatic sync should start")
    equal(env.sent[1], "display cartels", "first automatic command")

    env.F2T_MAP_ENABLED = false
    local phase_timer = assert(env.armed, "capture timer was not armed")
    phase_timer()

    equal(#env.sent, 1, "disabled capture must send no second command")
    equal(env.F2T_MAP_TOPOLOGY_CAPTURE.active, false, "capture active after cancel")
    equal(callback_count, 1, "cancel callback count")
end

function tests.automatic_capture_stops_before_second_command_when_disconnected()
    local env = scenario()
    check(env.f2t_map_topology_sync(nil, { automatic = true, silent = true }))
    env.connected = false
    local phase_timer = assert(env.armed, "capture timer was not armed")
    phase_timer()
    equal(#env.sent, 1, "disconnected capture must send no second command")
    equal(env.F2T_MAP_TOPOLOGY_CAPTURE.active, false, "capture active after disconnect")
end

function tests.manual_sync_remains_explicitly_available()
    local env = scenario({ map_enabled = false, auto_sync = false })
    check(env.f2t_map_topology_sync(nil, { silent = true }), "manual sync should start")
    equal(env.sent[1], "display cartels", "manual first command")
    local phase_timer = assert(env.armed, "manual capture timer was not armed")
    phase_timer()
    equal(env.sent[2], "display syndicates", "manual second command")
    equal(env.F2T_MAP_TOPOLOGY_CAPTURE.active, true, "manual capture should continue")
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
