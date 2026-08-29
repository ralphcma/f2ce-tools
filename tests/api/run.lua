local api_source = arg and arg[1] or "src/scripts/api/v1.lua"
local Mock = dofile("tests/api/mock_adapter.lua")
dofile(api_source)

local API = assert(F2CE and F2CE.API and F2CE.API.v1, "API did not load")
local passed, failed = 0, 0

local function equal(actual, expected, message)
    if actual ~= expected then error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2) end
end
local function truthy(value, message) if not value then error(message or "expected truthy value", 2) end end
local function code(err, expected) equal(type(err) == "table" and err.code or nil, expected, "error code") end

local mock
local function reset()
    API:_reload()
    mock = Mock.new()
    API._install({
        name = mock.name,
        f2ceVersion = function() return mock:f2ceVersion() end,
        registerEvent = function(...) return mock:registerEvent(...) end,
        unregisterEvent = function(...) return mock:unregisterEvent(...) end,
        timer = function(...) return mock:timer(...) end,
        cancelTimer = function(...) return mock:cancelTimer(...) end,
        alias = function(...) return mock:alias(...) end,
        cancelAlias = function(...) return mock:cancelAlias(...) end,
        trigger = function(...) return mock:trigger(...) end,
        cancelTrigger = function(...) return mock:cancelTrigger(...) end,
        sendCommand = function(...) return mock:sendCommand(...) end,
        gmcpSnapshot = function(...) return mock:gmcpSnapshot(...) end,
        navSetOwner = function(...) return mock:navSetOwner(...) end,
        navClearOwner = function(...) return mock:navClearOwner(...) end,
        navigate = function(...) return mock:navigate(...) end,
        navPause = function(...) return mock:navPause(...) end,
        navResume = function(...) return mock:navResume(...) end,
        navStop = function(...) return mock:navStop(...) end,
        navState = function(...) return mock:navState(...) end,
        priceCheck = function(...) return mock:priceCheck(...) end,
        priceCommandDescription = function(...) return mock:priceCommandDescription(...) end,
        haulingStatus = function(...) return mock:haulingStatus(...) end,
        haulingStart = function(...) return mock:haulingStart(...) end,
        haulingPause = function(...) return mock:haulingPause(...) end,
        haulingResume = function(...) return mock:haulingResume(...) end,
        haulingStop = function(...) return mock:haulingStop(...) end,
        haulingTerminate = function(...) return mock:haulingTerminate(...) end,
        mapRoomHasFlag = function(...) return mock:mapRoomHasFlag(...) end,
        mapFindRoomsWithFlag = function(...) return mock:mapFindRoomsWithFlag(...) end,
        mapFindExchange = function(...) return mock:mapFindExchange(...) end,
        mapResolve = function(...) return mock:mapResolve(...) end,
        mapAreas = function(...) return mock:mapAreas(...) end,
        mapSystems = function(...) return mock:mapSystems(...) end,
        mapReachability = function(...) return mock:mapReachability(...) end,
    })
end

local function enabled(id, extra)
    local spec = extra or {}; spec.id = id; spec.version = spec.version or "1.0.0"
    assert(API.modules.register(spec)); return assert(API.modules.enable(id))
end

local tests = {}
function tests.version_and_capability_failure()
    reset()
    truthy(API.versions.satisfies("1.2.3", ">=1.0.0")); truthy(not API.versions.satisfies("1.2.3", ">=2.0.0"))
    local ok, err = API.validateDependency({ api = ">=2.0.0" }); equal(ok, nil); code(err, "E_API_VERSION")
    API.capabilities["test.missing"] = { available = false }
    ok, err = API.requireCapabilities({ "test.missing" }); equal(ok, nil); code(err, "E_CAPABILITY")
end

function tests.duplicate_module_ids()
    reset(); assert(API.modules.register({ id = "test.duplicate" }))
    local context, err = API.modules.register({ id = "test.duplicate" }); equal(context, nil); code(err, "E_DUPLICATE_MODULE")
end

function tests.reload_idempotence()
    reset(); local cleanups = 0
    local spec = { id = "test.reload", auto_enable = true, initialize = function(context) context:own("custom", true, function() cleanups = cleanups + 1 end) end }
    assert(API.modules.reload(spec)); assert(API.modules.reload(spec)); equal(cleanups, 1)
    equal(API.modules.status("test.reload").state, "enabled")
end

function tests.scoped_cleanup()
    reset(); local context = enabled("test.resources")
    assert(context:alias("^x$", function() end)); assert(context:trigger("^y$", function() end)); assert(context:timer(1, function() end))
    assert(context:on("test.event", function() end)); API.modules.disable("test.resources")
    equal(mock.cancelled.aliases, 1); equal(mock.cancelled.triggers, 1); equal(mock.cancelled.timers, 1)
end

function tests.navigation_contention_and_callbacks()
    reset(); local a, b = enabled("test.nav.a"), enabled("test.nav.b")
    local lease = assert(API.navigation.acquire(a)); local other, err = API.navigation.acquire(b); equal(other, nil); code(err, "E_NAV_CONTENTION")
    local completed = false; local handle = assert(lease:request("market", { on_complete = function() completed = true end }))
    mock:completeNavigation(true); API.navigation._tick(); truthy(completed); equal(handle:status().state, "completed")
end

function tests.navigation_graceful_and_immediate_cancel()
    reset(); local context = enabled("test.nav.cancel")
    local lease = assert(API.navigation.acquire(context)); local request = assert(lease:request("market"))
    assert(request:cancel("test_graceful")); equal(request:status().state, "cancelling"); mock:runTimers()
    equal(request:status().state, "cancelled"); equal(mock.nav_stop_count, 1)
    lease = assert(API.navigation.acquire(context)); request = assert(lease:request("market"))
    assert(request:cancelImmediate("test_immediate")); equal(request:status().state, "cancelled"); equal(mock.nav_stop_count, 2)
end

function tests.command_denial_and_zero_transmission()
    reset(); local context = enabled("test.command")
    local lease = assert(API.commands.acquire(context, { purpose = "test" }))
    local ack = assert(lease:send("look", { reason = "offline test" })); equal(ack.status, "sent"); equal(#mock.sent, 1)
    API.modules.disable("test.command"); local result, err = lease:send("buy fuel", { reason = "must be denied" })
    equal(result, nil); code(err, "E_COMMAND_LEASE"); equal(#mock.sent, 1)
    local disabled_context = API._modules["test.command"].context
    local denied; denied, err = API.commands.acquire(disabled_context); equal(denied, nil); code(err, "E_MODULE_DISABLED"); equal(#mock.sent, 1)
end

function tests.provider_registration_and_fallback()
    reset(); local context = enabled("test.provider")
    assert(API.prices.registerProvider(context, { id = "test.provider.primary", priority = 100, scopes = { "cartel" }, request = function(request, done) return false end }))
    local result; assert(API.prices.request(context, "petroleum", { scope = "cartel" }, function(value, err) assert(not err); result = value end))
    truthy(result); equal(result.provider, "f2ce.builtin"); equal(mock.builtin_price_calls, 1); equal(#mock.sent, 1)
    truthy(#API.commands.audit() >= 1)
end

function tests.provider_timeout_ignores_late_callback()
    reset(); local context = enabled("test.provider.timeout"); local late_done
    assert(API.prices.registerProvider(context, { id = "test.provider.slow", priority = 200, request = function(request, done) late_done = done; return true end }))
    local result; assert(API.prices.request(context, "water", { timeout = 1 }, function(value) result = value end))
    mock:runTimers(); equal(result.provider, "f2ce.builtin")
    late_done({ commodity = "water", provider = "late" }); equal(result.provider, "f2ce.builtin")
end

function tests.callback_errors_are_contained()
    reset(); local observed = false
    API.events.subscribe("api.callback_error", function() observed = true end)
    API.events.subscribe("test.explode", function() error("boom") end)
    API.events.emit("test.explode", {}); truthy(observed, "callback error event not emitted")
end

function tests.nil_and_partial_gmcp_are_copied()
    reset(); equal(API.data.refresh("futures_market"), nil)
    mock.gmcp = { room = { info = { id = 7, flags = { "exchange" } } }, char = {} }
    local room = API.data.refresh("room"); equal(room.id, 7); room.id = 999
    equal(API.data.get("room").id, 7); equal(API.data.refresh("cargo"), nil)
end

function tests.reconnect_reset()
    reset(); local context = enabled("test.reconnect"); local lease = assert(API.navigation.acquire(context)); assert(lease:request("market"))
    mock:fireEvent("sysDisconnectionEvent"); equal(API.navigation.status().state, "idle"); equal(mock.nav_stop_count, 1)
end

function tests.unload_during_active_work()
    reset(); local context = enabled("test.unload"); local lease = assert(API.navigation.acquire(context)); assert(lease:request("market"))
    API.modules.unregister("test.unload"); equal(API.modules.status("test.unload"), nil); equal(API.navigation.status().state, "idle"); equal(mock.nav_stop_count, 1)
end

function tests.hauling_modes_and_release()
    reset(); local context = enabled("test.haul")
    local handle, err = API.hauling.start(context, { mode = "po" }); equal(handle, nil); code(err, "E_HAUL_MODE")
    handle = assert(API.hauling.start(context, { mode = "exchange" })); equal(mock.haul.mode, "exchange")
    mock.haul.active = false; API.hauling._refresh(); equal(API.commands._lease, nil)
end

local names = {}; for name in pairs(tests) do names[#names + 1] = name end; table.sort(names)
for _, name in ipairs(names) do
    local ok, err = xpcall(tests[name], function(value) return debug.traceback(tostring(value), 2) end)
    if ok then passed = passed + 1; io.write("PASS ", name, "\n") else failed = failed + 1; io.write("FAIL ", name, "\n", err, "\n") end
end
io.write(string.format("RESULT %d passed, %d failed\n", passed, failed))
if failed > 0 then os.exit(1) end
