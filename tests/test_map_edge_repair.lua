local map_dir = assert(arg[1], "map source directory is required")
local function check(value, message) if not value then error(message or "check failed", 2) end end
local function equal(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "mismatch",
            tostring(expected), tostring(actual)), 2)
    end
end

local special, ordinary, replanned = nil, nil, false
function killTimer() end
function send() error("unit test must not transmit commands") end
function cecho() end
function f2t_debug_log() end
function f2t_map_describe_room(room) return tostring(room) end
function f2t_map_direction_to_number(direction)
    return ({north=1, east=3, south=5, west=7, up=9, down=10, ['in']=11, out=12})[direction]
end
function getRoomUserData() return "" end
function removeSpecialExit(from, command) special = {removed=true, from=from, command=command} end
function addSpecialExit(from, to, command) special = {from=from, to=to, command=command} end
function setExit(from, to, direction) ordinary = {from=from, to=to, direction=direction} end
function setExitStub() end
function f2t_map_speedwalk_restore_mode() end
function f2t_map_speedwalk_recompute_path() replanned = true end
function f2t_map_room_has_flag() return false end
function f2t_settings_get(_, key)
    if key == "speedwalk_max_retries" then return 3 end
    if key == "speedwalk_timeout" then return 5 end
end

assert(loadfile(map_dir .. "/speedwalk.lua"))()
-- Replace the loaded route planner with an observation point; this unit test
-- verifies edge repair and must not invoke Mudlet pathfinding.
function f2t_map_speedwalk_recompute_path() replanned = true end

local function prime(command)
    special, ordinary, replanned = nil, nil, false
    F2T_SPEEDWALK_ACTIVE = true
    F2T_SPEEDWALK_PAUSED = false
    F2T_SPEEDWALK_WAITING_FOR_MOVE = true
    F2T_SPEEDWALK_MOVE_TIMEOUT_ID = 1
    F2T_SPEEDWALK_LAST_COMMAND = command
    F2T_SPEEDWALK_EXPECTED_ROOM_ID = 99
    F2T_SPEEDWALK_ROOM_BEFORE_MOVE = 1
    F2T_SPEEDWALK_CURRENT_STEP = 1
    F2T_SPEEDWALK_DIR = {command}
    F2T_SPEEDWALK_PATH = {99}
    F2T_SPEEDWALK_DESTINATION_ROOM_ID = 99
    F2T_MAP_CURRENT_ROOM_ID = 2
end

prime("board")
f2t_map_speedwalk_on_room_change()
equal(special.from, 1, "board source repaired")
equal(special.to, 2, "board destination follows confirmed arrival")
equal(special.command, "board", "board special exit retained")
check(replanned, "board repair replans the remaining route")

prime("in")
f2t_map_speedwalk_on_room_change()
equal(ordinary.from, 1, "in source repaired")
equal(ordinary.to, 2, "in destination follows confirmed arrival")
equal(ordinary.direction, 11, "in uses Mudlet direction number")
check(replanned, "in repair replans the remaining route")

local flags = {
    [10] = {shuttlepad=true},
    [11] = {exchange=true},
}
local reachable = {[10]=true, [11]=false}
function roomExists(room) return room == 5 or flags[room] ~= nil end
function f2t_map_area_room_list() return {10, 11} end
function getRoomUserData(room, key)
    local flag = key:match("^fed2_flag_(.+)$")
    return flag and flags[room] and flags[room][flag] and "true" or ""
end
function getPath(_, room) return reachable[room] == true end

assert(loadfile(map_dir .. "/explore_query.lua"))()
check(not f2t_map_explore_planet_has_reachable_flags(7, {"shuttlepad", "exchange"}, 5),
    "existing but disconnected exchange does not mark the planet complete")
reachable[11] = true
check(f2t_map_explore_planet_has_reachable_flags(7, {"shuttlepad", "exchange"}, 5),
    "planet is complete when every required flag is reachable from orbit")

local explore_file = assert(io.open(map_dir .. "/explore_system.lua", "rb"))
local explore_source = explore_file:read("*a")
explore_file:close()
check(explore_source:find("f2t_map_explore_planet_has_reachable_flags", 1, true),
    "system brief completion uses reachable flag validation")

-- Reloading a Mudlet package does not reset the server's description mode.
-- If F2CE had issued `brief`, the reloaded script must remember that debt and
-- restore `full`; otherwise all room descriptions remain hidden until some
-- later speedwalk happens to finish normally.
local sent = {}
function send(command) sent[#sent + 1] = command end
F2T_SPEEDWALK_BRIEF_SWITCHED = true
F2T_MAP_BRIEF_HOLD_OWNER = nil
assert(loadfile(map_dir .. "/speedwalk.lua"))()
equal(#sent, 1, "reload restores one F2CE-owned description mode")
equal(sent[1], "full", "reload restores the configured full mode")

sent = {}
assert(loadfile(map_dir .. "/speedwalk.lua"))()
equal(#sent, 0, "idle reload does not change a user-selected description mode")

print("F2CE map edge repair tests passed")
