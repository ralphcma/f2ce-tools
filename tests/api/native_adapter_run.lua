local api_source = arg and arg[1] or "src/scripts/api/v1.lua"
local adapter_source = arg and arg[2] or "src/scripts/api/adapter.lua"

gmcp = {}
F2T_VERSION = "3.3.0"
F2T_SPEEDWALK_ACTIVE = false
F2T_SPEEDWALK_PAUSED = false
F2T_SPEEDWALK_LAST_RESULT = nil
F2T_SPEEDWALK_OWNER = nil
F2T_SPEEDWALK_DIR = {}
F2T_MAP_EXPLORE_STATE = { active = false }
F2T_MAP_CIRCUIT_STATE = { active = false }
F2T_HAULING_STATE = { active = false }
F2T_DEATH_STATE = { active = false }
F2T_BULK_STATE = { active = false }
F2T_MAP_WHEREIS_CAPTURE = { active = false }
F2T_MAP_DI_SYSTEM_CAPTURE = { active = false }
F2T_MAP_TOPOLOGY_CAPTURE = { active = false }
F2T_GALAXY = { capture_active = false }
f2t_factory = { capturing = false }
f2t_po = { phase = "idle" }
F2T_MAP_CURRENT_ROOM_ID = 1

local event_id = 0
function registerAnonymousEventHandler()
    event_id = event_id + 1
    return event_id
end
function killAnonymousEventHandler() end
function tempTimer(_, callback) callback(); return 1 end
function killTimer() end
function getPackageInfo() return { version = F2T_VERSION } end
function send() end

function f2t_map_set_nav_owner(owner, callback)
    F2T_SPEEDWALK_OWNER = owner
    F2T_SPEEDWALK_ON_INTERRUPT = callback
end
function f2t_map_clear_nav_owner()
    F2T_SPEEDWALK_OWNER = nil
    F2T_SPEEDWALK_ON_INTERRUPT = nil
end

local native_nav_result = "walking"
local native_nav_options
function f2t_map_navigate(_, options)
    native_nav_options = options
    return native_nav_result
end
function f2t_map_resolve_location(destination)
    if destination == "target" then return 42 end
    return nil
end
function f2t_map_speedwalk_pause() return true end
function f2t_map_speedwalk_resume() return true end
function f2t_map_speedwalk_stop() return true end

local reject_hauling = false
function f2t_hauling_start()
    if not reject_hauling then F2T_HAULING_STATE.active = true end
end

dofile(api_source)
dofile(adapter_source)

local adapter = assert(F2CE.API.v1._adapter, "native adapter did not install")
local passed, failed = 0, 0

local function equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end
local function truthy(value, message) if not value then error(message or "expected truthy value", 2) end end

local tests = {}

function tests.navigation_status_and_stale_result()
    F2T_SPEEDWALK_LAST_RESULT = "completed"
    native_nav_result = "pending"
    local result = adapter.navigate("target", { compensate_incomplete_map = true })
    equal(result, "pending")
    equal(F2T_SPEEDWALK_LAST_RESULT, nil, "adapter must clear a prior speedwalk result")
    truthy(native_nav_options.compensate_incomplete_map)
end

function tests.navigation_compare_and_release_ownership()
    F2T_SPEEDWALK_OWNER = "hauling"
    local acquired, blocker = adapter.navAcquireOwner("api:test")
    equal(acquired, false); equal(blocker.owner, "hauling"); equal(F2T_SPEEDWALK_OWNER, "hauling")

    F2T_SPEEDWALK_OWNER = nil
    truthy(adapter.navAcquireOwner("api:test")); equal(F2T_SPEEDWALK_OWNER, "api:test")
    F2T_SPEEDWALK_OWNER = "stamina"
    local released = adapter.navReleaseOwner("api:test")
    equal(released, false); equal(F2T_SPEEDWALK_OWNER, "stamina", "replacement owner must be retained")
    F2T_SPEEDWALK_OWNER = nil
end

function tests.native_command_blockers()
    F2T_MAP_EXPLORE_STATE.active = true
    equal(adapter.nativeCommandBlocker().kind, "map_exploration")
    F2T_MAP_EXPLORE_STATE.active = false
    F2T_HAULING_STATE.active = true
    equal(adapter.nativeCommandBlocker().kind, "hauling")
    F2T_HAULING_STATE.active = false
    F2T_BULK_STATE.active = true
    equal(adapter.nativeCommandBlocker().kind, "bulk_trade")
    F2T_BULK_STATE.active = false
    f2t_factory.capturing = true
    equal(adapter.nativeCommandBlocker().kind, "factory_capture")
    f2t_factory.capturing = false
    f2t_factory.flushing = true
    equal(adapter.nativeCommandBlocker().kind, "factory_flush")
    f2t_factory.flushing = false
    equal(adapter.nativeCommandBlocker(), nil)
end

function tests.destination_and_hauling_acceptance()
    F2T_MAP_CURRENT_ROOM_ID = 42
    truthy(adapter.navDestinationReached("target"))
    F2T_MAP_CURRENT_ROOM_ID = 1

    reject_hauling = true
    local accepted = adapter.haulingStart()
    equal(accepted, false); equal(F2T_HAULING_STATE.active, false)
    reject_hauling = false
    truthy(adapter.haulingStart()); equal(F2T_HAULING_STATE.active, true)
    F2T_HAULING_STATE.active = false
end

function tests.borrowed_hauling_price_shares_only_stationary_own_reservation()
    F2T_HAULING_STATE.active = true
    F2T_SPEEDWALK_OWNER = "hauling"
    equal(adapter.nativeCommandBlocker(true), nil)
    equal(adapter.nativeCommandBlocker().kind, "navigation_owner")
    F2T_SPEEDWALK_ACTIVE = true
    equal(adapter.nativeCommandBlocker(true).kind, "speedwalk")
    F2T_SPEEDWALK_ACTIVE = false
    F2T_SPEEDWALK_WAITING_FOR_MOVE = true
    equal(adapter.nativeCommandBlocker(true).kind, "movement_pending")
    F2T_SPEEDWALK_WAITING_FOR_MOVE = false
    F2T_SPEEDWALK_OWNER = "stamina"
    equal(adapter.nativeCommandBlocker(true).kind, "navigation_owner")
    F2T_SPEEDWALK_OWNER = "hauling"
    F2T_BULK_STATE.active = true
    equal(adapter.nativeCommandBlocker(true).kind, "bulk_trade")
    F2T_BULK_STATE.active = false
    F2T_PRICE_CALLBACK = function() end
    equal(adapter.nativeCommandBlocker(true).kind, "price_request")
    F2T_PRICE_CALLBACK = nil
    F2T_HAULING_STATE.active = false
    equal(adapter.nativeCommandBlocker(true).kind, "navigation_owner")
    F2T_SPEEDWALK_OWNER = nil
end

local names = {}; for name in pairs(tests) do names[#names + 1] = name end; table.sort(names)
for _, name in ipairs(names) do
    local ok, err = xpcall(tests[name], function(value) return debug.traceback(tostring(value), 2) end)
    if ok then passed = passed + 1; io.write("PASS ", name, "\n")
    else failed = failed + 1; io.write("FAIL ", name, "\n", err, "\n") end
end
io.write(string.format("RESULT %d passed, %d failed\n", passed, failed))
if failed > 0 then os.exit(1) end
