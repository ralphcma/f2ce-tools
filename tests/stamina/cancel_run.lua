local root=arg[1] or "."
local passed,failed=0,0
local timers,nav_callback,cancelled,sent,client,room_handler
local function equal(a,b) assert(a==b,"expected "..tostring(b)..", got "..tostring(a)) end
local function reset(phase)
    timers,cancelled,sent={},0,0
    client=function() return false end
    F2T_STAMINA_STATE=nil; F2T_SPEEDWALK_OWNER="stamina"; F2T_SPEEDWALK_ACTIVE=true
    cecho=function() end; f2t_debug_log=function() end
    tempTimer=function(_,fn) timers[#timers+1]=fn; return #timers end
    killTimer=function() end; killAnonymousEventHandler=function() end
    registerAnonymousEventHandler=function(_,fn) room_handler=fn; return 1 end
    f2t_settings_get=function(_,key) if key=="food_source" then return "Test.Food.1" else return 30 end end
    f2t_map_navigation_cancel=function() cancelled=cancelled+1; F2T_SPEEDWALK_ACTIVE=false end
    f2t_map_clear_nav_owner=function() F2T_SPEEDWALK_OWNER=nil end
    f2t_map_navigate=function(_,o) nav_callback=o.on_result; return "walking" end
    send=function(command) equal(command,"buy food"); sent=sent+1 end
    dofile(root.."/src/scripts/stamina/monitor.lua")
    f2t_stamina_register_client({check_active=client,pause_callback=function() end,resume_callback=function() error("unexpected resume") end})
    F2T_STAMINA_STATE.current_phase=phase
    F2T_STAMINA_STATE.current_stamina=25; F2T_STAMINA_STATE.max_stamina=100; F2T_STAMINA_STATE.food_trip_epoch=1
end
local function test(name,fn) local ok,err=pcall(fn); if ok then passed=passed+1; print("PASS "..name) else failed=failed+1; print("FAIL "..name..": "..err) end end

test("owned cancellation invalidates queued food buys and releases its route",function()
    reset("buying_food"); f2t_stamina_phase_buy_food(); equal(sent,1)
    assert(f2t_stamina_cancel_client_trip(client)); f2t_stamina_unregister_client()
    timers[1](); equal(sent,1); equal(cancelled,1); equal(F2T_SPEEDWALK_OWNER,nil); equal(F2T_STAMINA_STATE.current_phase,"idle")
end)
test("foreign callback cannot cancel or clear another client's food trip",function()
    reset("buying_food"); equal(f2t_stamina_cancel_client_trip(function() end),false)
    equal(F2T_STAMINA_STATE.current_phase,"buying_food"); equal(cancelled,0)
end)
test("food cancellation never clears a foreign navigation owner",function()
    reset("navigating_to_food"); F2T_SPEEDWALK_OWNER="another-module"
    assert(f2t_stamina_cancel_client_trip(client)); equal(cancelled,0); equal(F2T_SPEEDWALK_OWNER,"another-module")
end)
test("an old buy timer cannot act on a later trip with the same phase",function()
    reset("buying_food"); f2t_stamina_phase_buy_food(); local old=timers[1]
    f2t_stamina_cancel_client_trip(client); F2T_STAMINA_STATE.current_phase="buying_food"
    old(); equal(sent,1); equal(#timers,1)
end)
test("an old navigation callback cannot abort a replacement food trip",function()
    reset("navigating_to_food"); f2t_stamina_phase_navigate_to_food(); local old=nav_callback
    f2t_stamina_cancel_client_trip(client); F2T_STAMINA_STATE.current_phase="navigating_to_food"
    old(false); equal(F2T_STAMINA_STATE.current_phase,"navigating_to_food"); equal(F2T_STAMINA_STATE.food_trip_failed,nil)
end)
test("cancellation from the pause callback cannot start a food route",function()
    reset("idle"); F2T_STAMINA_STATE.client_check_active=function() return true end
    F2T_STAMINA_STATE.client_pause_callback=function() f2t_stamina_cancel_client_trip(F2T_STAMINA_STATE.client_check_active) end
    f2t_stamina_start_food_trip(); equal(F2T_STAMINA_STATE.current_phase,"idle"); equal(sent,0)
end)
test("old room-completion and pause-poll timers do not advance a new trip",function()
    reset("navigating_to_food"); room_handler(); local old=timers[1]
    f2t_stamina_cancel_client_trip(client); F2T_STAMINA_STATE.current_phase="navigating_to_food"; F2T_SPEEDWALK_LAST_RESULT="completed"
    old(); equal(sent,0)
    reset("waiting_for_client_pause"); F2T_STAMINA_STATE.client_check_active=function() return true end
    f2t_stamina_phase_wait_for_client_pause(); old=timers[1]
    f2t_stamina_cancel_client_trip(F2T_STAMINA_STATE.client_check_active); F2T_STAMINA_STATE.current_phase="waiting_for_client_pause"
    old(); equal(#timers,1)
end)
print(string.format("RESULT %d passed, %d failed",passed,failed)); if failed>0 then os.exit(1) end
