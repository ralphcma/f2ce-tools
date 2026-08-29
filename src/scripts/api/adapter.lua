-- Native F2CE adapter for F2CE.API.v1.
--
-- This file is the only API layer allowed to touch implementation globals.
-- Module consumers receive copied state and opaque handles from v1.lua.

local api = F2CE and F2CE.API and F2CE.API.v1
if not api then return end

local unpack_values = table.unpack or unpack

local function clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[clone(key, seen)] = clone(item, seen) end
    return result
end

local repeating_timers = {}

local adapter = {
    name = "f2ce-native",
    compatibility = "F2CE-Tools >= 3.2.5",
}

function adapter.f2ceVersion()
    if F2T_VERSION and F2T_VERSION ~= "unknown" then return F2T_VERSION end
    if type(getPackageInfo) == "function" then
        local info = getPackageInfo("f2ce-tools")
        if type(info) == "table" and info.version then return info.version end
    end
    return "unknown"
end

function adapter.registerEvent(event_name, callback)
    if type(registerAnonymousEventHandler) ~= "function" then return nil end
    local ok, id = pcall(registerAnonymousEventHandler, event_name, callback)
    if ok then return id end
    return nil
end

function adapter.unregisterEvent(id)
    if id and type(killAnonymousEventHandler) == "function" then pcall(killAnonymousEventHandler, id) end
end

function adapter.timer(delay, callback, repeating)
    if type(tempTimer) ~= "function" then return nil end
    if not repeating then return tempTimer(delay, callback) end
    local token = { active = true, timer_id = nil }
    local function tick()
        if not token.active then return end
        callback()
        if token.active then token.timer_id = tempTimer(delay, tick) end
    end
    token.timer_id = tempTimer(delay, tick)
    repeating_timers[token] = true
    return token
end

function adapter.cancelTimer(id)
    if type(id) == "table" and repeating_timers[id] then
        id.active = false
        repeating_timers[id] = nil
        if id.timer_id and type(killTimer) == "function" then pcall(killTimer, id.timer_id) end
        return
    end
    if id and type(killTimer) == "function" then pcall(killTimer, id) end
end

function adapter.muxletContentAvailable()
    return type(Mux) == "table" and type(Mux.registerContent) == "function"
end

function adapter.sendCommand(command, options)
    if type(send) ~= "function" then return false end
    send(command, options and options.echo == true)
    return true
end

function adapter.gmcpSnapshot(path)
    local node = gmcp
    for _, key in ipairs(path or {}) do
        if type(node) ~= "table" then return nil end
        node = node[key]
    end
    return clone(node)
end

function adapter.navSetOwner(owner, on_interrupt)
    if type(f2t_map_set_nav_owner) == "function" then f2t_map_set_nav_owner(owner, on_interrupt); return true end
    return false
end
function adapter.navClearOwner() if type(f2t_map_clear_nav_owner) == "function" then f2t_map_clear_nav_owner(); return true end; return false end
function adapter.navigate(destination, options)
    if type(f2t_map_navigate) ~= "function" then return false, "f2t_map_navigate is unavailable" end
    local result, detail = f2t_map_navigate(destination, options)
    if result == nil then F2T_SPEEDWALK_LAST_RESULT = nil end
    return result, detail
end
function adapter.navPause() return type(f2t_map_speedwalk_pause) == "function" and f2t_map_speedwalk_pause() or false end
function adapter.navResume() return type(f2t_map_speedwalk_resume) == "function" and f2t_map_speedwalk_resume() or false end
function adapter.navStop() return type(f2t_map_speedwalk_stop) == "function" and f2t_map_speedwalk_stop() or false end
function adapter.navState()
    return {
        active = F2T_SPEEDWALK_ACTIVE == true,
        paused = F2T_SPEEDWALK_PAUSED == true,
        result = F2T_SPEEDWALK_LAST_RESULT,
        destination_room_id = tonumber(F2T_SPEEDWALK_DESTINATION_ROOM_ID),
        current_step = tonumber(F2T_SPEEDWALK_CURRENT_STEP) or 0,
        total_steps = type(F2T_SPEEDWALK_DIR) == "table" and #F2T_SPEEDWALK_DIR or 0,
        interruption_pending = F2T_SPEEDWALK_CUSTOMS_PENDING == true,
    }
end

function adapter.priceCheck(commodity, options, done)
    if type(f2t_price_check_commodity) ~= "function" then done(nil, "built-in price provider unavailable"); return false end
    f2t_price_check_commodity(commodity, function(canonical, buy_data, sell_data)
        if buy_data == nil and sell_data == nil then done(nil, "built-in price request failed"); return end
        done({ commodity = canonical or commodity, buy = clone(buy_data), sell = clone(sell_data), provider = "f2ce.builtin", scope = options and options.scope })
    end)
    return true
end

function adapter.priceCommandDescription(commodity)
    local canonical = commodity
    if type(f2t_resolve_commodity) == "function" then canonical = f2t_resolve_commodity(commodity) or commodity end
    return string.format("check price %s cartel", string.lower(tostring(canonical)))
end

function adapter.haulingStatus()
    local state = type(F2T_HAULING_STATE) == "table" and clone(F2T_HAULING_STATE) or {}
    state.active = state.active == true
    state.available = type(f2t_hauling_start) == "function"
    return state
end
function adapter.haulingStart(mode)
    if type(f2t_hauling_start) ~= "function" then return false, "f2t_hauling_start is unavailable" end
    f2t_hauling_start(mode)
    return true
end
function adapter.haulingPause(immediate) if type(f2t_hauling_pause) ~= "function" then return false end; f2t_hauling_pause(immediate); return true end
function adapter.haulingResume() if type(f2t_hauling_resume) ~= "function" then return false end; f2t_hauling_resume(); return true end
function adapter.haulingStop() if type(f2t_hauling_stop) ~= "function" then return false end; f2t_hauling_stop(); return true end
function adapter.haulingTerminate() if type(f2t_hauling_terminate) ~= "function" then return false end; f2t_hauling_terminate(); return true end

function adapter.mapRoomHasFlag(room_id, flag)
    return type(f2t_map_room_has_flag) == "function" and f2t_map_room_has_flag(room_id, flag) or false
end
function adapter.mapFindRoomsWithFlag(area, flag)
    local area_id = tonumber(area)
    if not area_id and type(f2t_map_get_area_id) == "function" then area_id = f2t_map_get_area_id(area) end
    return type(f2t_map_find_all_rooms_with_flag) == "function" and clone(f2t_map_find_all_rooms_with_flag(area_id, flag)) or {}
end
function adapter.mapFindExchange(area)
    local rooms = adapter.mapFindRoomsWithFlag(area, "exchange")
    local results = {}
    for _, room_id in ipairs(rooms) do
        results[#results + 1] = {
            room_id = room_id,
            name = type(getRoomName) == "function" and getRoomName(room_id) or nil,
            area_id = type(getRoomArea) == "function" and getRoomArea(room_id) or nil,
        }
    end
    return results
end
function adapter.mapResolve(location)
    if type(f2t_map_resolve_location) ~= "function" then return nil, "resolver unavailable" end
    local room_id, err, hint = f2t_map_resolve_location(location)
    return { room_id = room_id, error = err, hint = clone(hint) }
end
function adapter.mapAreas()
    if type(getAreaTable) ~= "function" then return {} end
    local source, result = getAreaTable() or {}, {}
    for name, id in pairs(source) do result[#result + 1] = { id = id, name = name } end
    table.sort(result, function(a, b) return tostring(a.name) < tostring(b.name) end)
    return result
end
function adapter.mapSystems()
    local result, seen = {}, {}
    local galaxy = type(F2T_GALAXY) == "table" and F2T_GALAXY or {}
    local systems = galaxy.systems or galaxy.system or {}
    for key, value in pairs(systems) do
        local name = type(value) == "table" and (value.name or key) or key
        if name and not seen[name] then result[#result + 1] = clone(value); if type(result[#result]) ~= "table" then result[#result] = { name = name } else result[#result].name = result[#result].name or name end; seen[name] = true end
    end
    table.sort(result, function(a, b) return tostring(a.name) < tostring(b.name) end)
    return result
end
function adapter.mapReachability(from_room, to_room)
    from_room, to_room = tonumber(from_room), tonumber(to_room)
    if not from_room or not to_room or type(getPath) ~= "function" then return { reachable = false, reason = "valid room ids and getPath are required" } end
    local reachable = getPath(from_room, to_room) == true
    return { reachable = reachable, from_room = from_room, to_room = to_room, directions = reachable and clone(speedWalkDir) or {}, rooms = reachable and clone(speedWalkPath) or {} }
end

local function install()
    local current = F2CE and F2CE.API and F2CE.API.v1
    if current and current._install then current._install(adapter) end
end

-- Package scripts are evaluated before a zero-delay timer fires, so the
-- adapter observes all native F2CE functions regardless of folder ordering.
if type(tempTimer) == "function" then tempTimer(0, install) else install() end
