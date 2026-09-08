-- Offline lifecycle regression: native mapper calls are mocked; no game I/O.
local script_path = arg[1] or "src/scripts/ui/content/map.lua"
local function equal(actual, expected, message)
    assert(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local env = { timers = {}, wrappers = {}, closes = 0, creates = 0, registrations = 0 }
setmetatable(env, { __index = _G })
env.Mux = { _content = {} }
env.Mux.registerContent = function(id, def)
    env.registrations = env.registrations + 1
    env.Mux._content[id] = def
end
env.tempTimer = function(_, callback)
    env.timers[#env.timers + 1] = callback
end
env.f2t_debug_log = function() end
env.f2t_settings_get = function() return 10 end
env.getRoomArea = function() return 1 end
env.roomExists = function() return true end
env.setMapZoom = function() end
env.getMapZoom = function() return 10 end
env.centerview = function() end
env.updateMap = function() end
env.F2T_MAP_CURRENT_ROOM_ID = 1
env.f2t_map_handle_gmcp_room = function() error("A known-room UI remount must not replay the room handler") end
env.F2T_CONTENT_REGISTRARS = {}
env.Geyser = { Mapper = {} }
function env.Geyser.Mapper:new(spec, parent)
    env.creates = env.creates + 1
    local mapper = { name = spec.name, container = parent }
    function mapper:hide() self.hidden = true end
    function mapper:show() self.hidden = false end
    function mapper:reposition() end
    function mapper:move() end
    function mapper:resize() end
    function mapper:raise() end
    function mapper:type_delete() env.closes = env.closes + 1 end
    function mapper:delete()
        self.container.children[self.name] = nil
        env.wrappers[self.name] = nil
        self:type_delete()
    end
    parent.children[mapper.name] = mapper
    env.wrappers[mapper.name] = mapper
    return mapper
end
local function target()
    local slot = { children = {} }
    function slot:delete()
        local children = {}
        for _, child in pairs(self.children) do children[#children + 1] = child end
        for _, child in ipairs(children) do child:delete() end
    end
    return { _gid = "test_map", content = slot, contentBg = {
        echo = function() end, hide = function() end, setStyleSheet = function() end,
    } }
end
local function flush()
    while #env.timers > 0 do table.remove(env.timers, 1)() end
end
local chunk = assert(loadfile(script_path))
setfenv(chunk, env)
chunk()
env.f2tRegisterMapContent()
local def = env.Mux._content.fed2_map
local first = target()
def.apply(first)
flush()
equal(env.creates, 1, "first mount creates one mapper")
equal(env.f2tMapHasLiveMapper(), true, "first mount is live")
def._activeTargetRef = first
env.f2tRegisterMapContent()
equal(env.Mux._content.fed2_map, def, "repeat registration retains definition")
equal(def._activeTargetRef, first, "repeat registration retains singleton owner")
equal(env.registrations, 1, "unchanged definition is not registered twice")
def.remove(first)
first.content:delete()
equal(env.closes, 0, "remove then recursive slot deletion never closes native mapper")
equal(next(env.wrappers), nil, "release unlinks the obsolete Geyser wrapper")
equal(env.f2tMapHasLiveMapper(), false, "release clears live state")
local second = target()
def.apply(second)
flush()
equal(env.creates, 2, "map mounts again after removal")
equal(env.f2tMapHasLiveMapper(), true, "second mount is live")
second.content:delete()
equal(env.closes, 0, "direct recursive slot deletion is also protected")
def.remove(second)
local cancelled = target()
def.apply(cancelled)
def.remove(cancelled)
cancelled.content:delete()
flush()
equal(env.creates, 2, "remove before deferred build cancels mapper creation")
equal(next(env.wrappers), nil, "cancelled mount leaves no wrappers")
equal(env.closes, 0, "all cleanup paths preserve the native widget")
print("PASS Map content lifecycle: release, remount, singleton registration, direct deletion, deferred cancellation")
