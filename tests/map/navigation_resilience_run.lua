local speedwalk_source = assert(arg[1], "speedwalk.lua is required")
local whereis_source = assert(arg[2], "whereis_capture.lua is required")
local navigate_source = assert(arg[3], "navigate.lua is required")
local exit_source = assert(arg[4], "exit.lua is required")
local query_source = assert(arg[5], "room_query.lua is required")
local import_source = assert(arg[6], "import_export.lua is required")

local passed, failed = 0, 0
local function check(value, message) if not value then error(message or "check failed", 2) end end
local function equal(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message or "values differ",
            tostring(expected), tostring(actual)), 2)
    end
end

local rooms = {
    [1] = {name="Start", area=1, data={fed2_system="Sol",fed2_area="Start",fed2_num="1"}, exits={east=400}},
    [100] = {name="Wayward orbit", area=10, data={fed2_system="Stellar",fed2_area="Stellar Space",
        fed2_num="10",fed2_planet="Wayward",fed2_flag_orbit="true"}, exits={}},
    [101] = {name="Wayward (via board)", area=20, data={fed2_system="Stellar",fed2_area="Wayward",
        fed2_num="999",fed2_planet="Wayward",fed2_flag_shuttlepad="true"}, exits={}},
    [102] = {name="Landing pad", area=20, data={fed2_system="Stellar",fed2_area="Wayward",
        fed2_num="396",fed2_planet="Wayward",fed2_flag_shuttlepad="true"}, exits={}},
    [200] = {name="Cached source", area=30, data={fed2_system="Cache",fed2_area="Cache",
        fed2_num="1",fed2_exits="e:2"}, exits={}, stubs={4}},
    [201] = {name="Cached target", area=30, data={fed2_system="Cache",fed2_area="Cache",
        fed2_num="2"}, exits={}},
    [300] = {name="Old duplicate orbit", area=40, data={fed2_system="DupSys",fed2_area="Dup Space",
        fed2_num="10",fed2_planet="Dup",fed2_flag_orbit="true"}, exits={}},
    [301] = {name="Live duplicate orbit", area=40, data={fed2_system="DupSys",fed2_area="Dup Space",
        fed2_num="11",fed2_planet="Dup",fed2_flag_orbit="true",fed2_seen_at="100"}, exits={}},
    [302] = {name="Dup landing pad", area=50, data={fed2_system="DupSys",fed2_area="Dup",
        fed2_num="396",fed2_planet="Dup",fed2_flag_shuttlepad="true"}, exits={}},
    [400] = {name="Other room", area=1, data={fed2_system="Sol",fed2_area="Start",fed2_num="2"}, exits={}},
}
local specials = {[100]={board=101}, [102]={board=100}, [301]={board=302}, [302]={board=301}}
local area_names = {[1]="Start",[10]="Stellar Space",[20]="Wayward",[30]="Cache",
    [40]="Dup Space",[50]="Dup"}
local area_ids = {}; for id, name in pairs(area_names) do area_ids[name:lower()] = id end
local direction_number = {north=1,northeast=2,northwest=3,east=4,west=5,south=6,
    southeast=7,southwest=8,up=9,down=10,["in"]=11,out=12,
    n=1,ne=2,nw=3,e=4,w=5,s=6,se=7,sw=8,u=9,d=10}
local number_direction = {[1]="north",[2]="northeast",[3]="northwest",[4]="east",
    [5]="west",[6]="south",[7]="southeast",[8]="southwest",[9]="up",
    [10]="down",[11]="in",[12]="out"}
local sent, timers, next_timer = {}, {}, 0

function roomExists(id) return rooms[tonumber(id)] ~= nil end
function getRooms() local result={}; for id, room in pairs(rooms) do result[id]=room.name end; return result end
function getRoomName(id) return rooms[id] and rooms[id].name end
function getRoomHashByID(id) return f2t_map_generate_hash_from_room(id) end
function getRoomArea(id) return rooms[id] and rooms[id].area end
function getRoomAreaName(id) return area_names[id] end
function getRoomUserData(id, key) return rooms[id] and rooms[id].data[key] or "" end
function setRoomUserData(id, key, value) rooms[id].data[key]=tostring(value) end
function getAllRoomUserData(id) return rooms[id] and rooms[id].data or {} end
function getRoomExits(id) return rooms[id] and rooms[id].exits or {} end
function getExitStubs(id) return rooms[id] and rooms[id].stubs or {} end
function getExitStubs1(id) return getExitStubs(id) end
function setExit(id, destination, number)
    local direction=number_direction[number]
    if destination == -1 then rooms[id].exits[direction]=nil else rooms[id].exits[direction]=destination end
end
function setExitStub(id, number, enabled)
    local result={}
    for _, existing in ipairs(rooms[id].stubs or {}) do if existing ~= number then result[#result+1]=existing end end
    if enabled then result[#result+1]=number end
    rooms[id].stubs=result
end
function getSpecialExitsSwap(id) return specials[id] or {} end
function getSpecialExits(id)
    local result={}
    for command, destination in pairs(specials[id] or {}) do
        result[destination]=result[destination] or {}; result[destination][command]=true
    end
    return result
end
function addSpecialExit(id, destination, command)
    specials[id]=specials[id] or {}; specials[id][command]=destination
end
function removeSpecialExit(id, command) if specials[id] then specials[id][command]=nil end end
function f2t_map_area_room_list(area)
    local result={}; for id, room in pairs(rooms) do if room.area == area then result[#result+1]=id end end
    table.sort(result); return result
end
function f2t_map_get_area_id(name) return name and area_ids[name:lower()] end
function f2t_map_direction_to_number(direction) return direction_number[direction] end
function f2t_map_normalize_direction(direction) return number_direction[direction_number[direction]] or direction end
function f2t_map_get_opposite_direction(direction)
    return ({n="s",s="n",e="w",w="e",north="south",south="north",east="west",west="east"})[direction]
end
function f2t_map_generate_hash_from_room(id)
    local data=rooms[id] and rooms[id].data
    if not data then return nil end
    return string.format("%s.%s.%s",data.fed2_system,data.fed2_area,data.fed2_num)
end
function f2t_map_get_room_by_hash(hash)
    for id in pairs(rooms) do if f2t_map_generate_hash_from_room(id) == hash then return id end end
end
function f2t_map_describe_room(id) return tostring(id or "nil") end
function f2t_map_get_system_space_area_actual(name)
    if name and name:lower() == "dupsys" then return "Dup Space" end
end
function f2t_map_lookup_planet() return nil end
function f2t_map_destination_get() return nil end
function getPath(from, to) return roomExists(from) and roomExists(to) end
function send(command) sent[#sent+1]=command end
function cecho() end
function f2t_debug_log() end
function f2t_settings_get(_, key)
    if key == "speedwalk_timeout" then return 3 end
    if key == "speedwalk_after_mode" then return "full" end
    if key == "speedwalk_brief" then return false end
    if key == "nav_explore_confirm" then return false end
end
function tempTimer(_, callback) next_timer=next_timer+1; timers[next_timer]=callback; return next_timer end
function killTimer(id) timers[id]=nil; return true end
function centerview() end
function f2t_map_circuit_delete_triggers() end
function getAreaTable() local result={}; for id,name in pairs(area_names) do result[name]=id end; return result end
function getRoomCoordinates() return 0,0,0 end
function getRoomEnv() return 0 end
function getRoomChar() return "" end
function roomLocked() return false end
function hasExitLock() return false end
function getAllAreaUserData() return {} end
function getCustomEnvColorTable() return {} end

dofile(exit_source)
dofile(query_source)
dofile(speedwalk_source)
dofile(whereis_source)
dofile(navigate_source)
dofile(import_source)

local tests={}

function tests.import_reconciliation_repairs_known_stubs_and_board_targets()
    local regular, boards=f2t_map_reconcile_cached_routes()
    check(regular >= 1,"cached regular exit was not repaired")
    equal(rooms[200].exits.east,201,"cached regular destination")
    equal(#rooms[200].stubs,0,"resolved stub count")
    equal(boards,1,"board repair count")
    equal(specials[100].board,102,"orbit board destination")
    equal(getRoomUserData(100,"fed2_board_actual_hash"),"Stellar.Wayward.396","learned board hash")
end

function tests.learned_board_endpoint_survives_bad_gmcp_hash()
    specials[100].board=101
    f2t_map_process_special_exits(100,{board="Stellar.Wayward.999"})
    equal(specials[100].board,102,"learned board endpoint")
end

function tests.duplicate_orbit_prefers_reciprocal_reachable_pair()
    F2T_MAP_CURRENT_ROOM_ID=1
    equal(f2t_map_find_orbit_room("Dup Space","Dup"),301,"selected duplicate orbit")
end

function tests.speedwalk_keeps_long_lived_owner_and_repairs_live_board()
    F2T_MAP_CIRCUIT_STATE={active=false}
    F2T_SPEEDWALK_OWNER="api:test"
    F2T_SPEEDWALK_ACTIVE=true
    F2T_MAP_CURRENT_ROOM_ID=1
    f2t_map_speedwalk_complete()
    equal(F2T_SPEEDWALK_OWNER,"api:test","owner after one walk")

    specials[100].board=101
    F2T_SPEEDWALK_ACTIVE=true
    F2T_SPEEDWALK_WAITING_FOR_MOVE=true
    F2T_SPEEDWALK_ROOM_BEFORE_MOVE=100
    F2T_SPEEDWALK_EXPECTED_ROOM_ID=101
    F2T_SPEEDWALK_LAST_COMMAND="board"
    F2T_SPEEDWALK_CURRENT_STEP=1
    F2T_SPEEDWALK_DIR={"board","east"}
    F2T_SPEEDWALK_DESTINATION_ROOM_ID=400
    F2T_MAP_CURRENT_ROOM_ID=102
    local replanned=false
    f2t_map_speedwalk_recompute_path=function() replanned=true; return true end
    f2t_map_speedwalk_on_room_change()
    equal(specials[100].board,102,"live board correction")
    check(replanned,"corrected board route was not replanned")
end

function tests.stale_copied_edge_is_never_sent()
    sent={}
    F2T_SPEEDWALK_ACTIVE=true
    F2T_SPEEDWALK_PAUSED=false
    F2T_SPEEDWALK_WAITING_FOR_ARRIVAL=false
    F2T_SPEEDWALK_CURRENT_STEP=0
    F2T_SPEEDWALK_DIR={"e"}
    F2T_SPEEDWALK_PATH={201}
    F2T_SPEEDWALK_DESTINATION_ROOM_ID=201
    F2T_SPEEDWALK_BLIND=false
    F2T_MAP_CURRENT_ROOM_ID=1
    local replanned=false
    f2t_map_speedwalk_recompute_path=function() replanned=true; return true end
    f2t_map_speedwalk_next_step()
    check(replanned,"stale route was not replanned")
    equal(#sent,0,"commands sent from stale route")
end

function tests.speedwalk_terminal_wakes_api_without_room_gmcp()
    timers={}; next_timer=0
    local ticks=0
    F2CE={API={v1={navigation={_tick=function() ticks=ticks+1 end}}}}
    F2T_SPEEDWALK_ACTIVE=true
    F2T_MAP_CURRENT_ROOM_ID=1
    f2t_map_speedwalk_complete()
    for _, callback in pairs(timers) do callback() end
    equal(ticks,1,"API terminal-state notification count")
    F2CE=nil
end

function tests.cancel_stops_every_async_navigation_layer()
    F2T_SPEEDWALK_ACTIVE=true
    F2T_SPEEDWALK_OWNER="api:test"
    F2T_MAP_EXPLORE_STATE={active=true}
    F2T_MAP_CIRCUIT_STATE={active=true}
    F2T_MAP_WHEREIS_CAPTURE={active=true,timer_id=tempTimer(5,function() end)}
    local explore_stopped=false
    f2t_map_explore_stop=function() explore_stopped=true; F2T_MAP_EXPLORE_STATE.active=false end
    f2t_map_circuit_stop=function() F2T_MAP_CIRCUIT_STATE.active=false end
    local before=f2t_map_navigation_current_epoch()
    f2t_map_navigation_cancel("test")
    equal(f2t_map_navigation_current_epoch(),before+1,"cancel epoch")
    equal(F2T_SPEEDWALK_ACTIVE,false,"speedwalk after cancel")
    equal(F2T_MAP_WHEREIS_CAPTURE.active,false,"whereis after cancel")
    check(explore_stopped,"exploration was left active")
    equal(F2T_MAP_CIRCUIT_STATE.active,false,"circuit after cancel")
    equal(F2T_SPEEDWALK_OWNER,"api:test","API owner must be compare-and-released by API")
end

function tests.cancelled_navigation_drops_queued_result_callback()
    timers={}; next_timer=0
    F2T_MAP_CURRENT_ROOM_ID=1
    local old_resolver=f2t_map_resolve_location
    f2t_map_resolve_location=function() return nil,"missing",nil end
    local callbacks=0
    equal(f2t_map_navigate("missing",{on_result=function() callbacks=callbacks+1 end}),"failed")
    f2t_map_navigation_cancel("test")
    for _, callback in pairs(timers) do callback() end
    equal(callbacks,0,"cancelled callback count")
    f2t_map_resolve_location=old_resolver
end

function tests.unknown_location_retry_is_bounded()
    timers={}; next_timer=0
    F2T_MAP_CURRENT_ROOM_ID=nil
    local old_ensure=f2t_map_ensure_current_location
    f2t_map_ensure_current_location=function(callback) callback(); return false end
    local callbacks,status=0
    equal(f2t_map_navigate("never",{on_result=function(_,result) callbacks=callbacks+1;status=result end}),
        "pending","outer unknown-location status")
    for _, callback in pairs(timers) do callback() end
    equal(callbacks,1,"bounded retry callback count")
    equal(status,"failed","bounded retry result")
    f2t_map_ensure_current_location=old_ensure
    F2T_MAP_CURRENT_ROOM_ID=1
end

function tests.headless_export_preserves_command_keyed_special_exits()
    local captured
    yajl={to_string=function(document) captured=document; return "{}" end}
    local real_io=io
    io=setmetatable({open=function()
        return {write=function() end,close=function() end}
    end},{__index=real_io})
    local ok=f2t_map_save_json_headless("unused.json")
    io=real_io
    check(ok,"headless export failed")
    local found=false
    for _,area in ipairs(captured.areas) do
        for _,room in ipairs(area.rooms) do
            if room.id == 100 then
                for _,edge in ipairs(room.exits or {}) do
                    if edge.name == "board" and edge.exitId == specials[100].board then found=true end
                end
            end
        end
    end
    check(found,"board special exit was omitted from headless export")
end

local names={}; for name in pairs(tests) do names[#names+1]=name end; table.sort(names)
for _,name in ipairs(names) do
    local ok,err=xpcall(tests[name],function(value) return debug.traceback(tostring(value),2) end)
    if ok then passed=passed+1; io.write("PASS ",name,"\n")
    else failed=failed+1; io.stderr:write("FAIL ",name,": ",err,"\n") end
end
io.write(string.format("RESULT %d passed, %d failed\n",passed,failed))
if failed > 0 then os.exit(1) end
