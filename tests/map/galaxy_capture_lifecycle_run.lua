-- Real Galaxy + shared capture-window code; mock only Mudlet transport/time/UI.
local root = arg[1] or "."
local passed = 0
local function scenario()
    local e = { now=0, timers={}, handlers={}, sent={}, triggers={}, ids=0,
        F2T_LOGGED_IN=true, F2T_CONNECTED=true }
    setmetatable(e, {__index=_G})
    e.os = {time=function() return math.floor(e.now) end}
    e.f2t_debug_log = function() end
    e.f2t_settings_register = function() end
    e.f2t_check_connection = function() return e.F2T_CONNECTED end
    e.enableTrigger = function(name) e.triggers[name]=true end
    e.disableTrigger = function(name) e.triggers[name]=false end
    e.tempTimer = function(delay, callback)
        e.ids=e.ids+1; e.timers[e.ids]={at=e.now+delay, callback=callback}; return e.ids
    end
    e.killTimer = function(id) e.timers[id]=nil end
    e.registerAnonymousEventHandler = function(name, cb)
        e.ids=e.ids+1; e.handlers[e.ids]={name=name, callback=cb}; return e.ids
    end
    e.killAnonymousEventHandler = function(id) e.handlers[id]=nil end
    e.raiseEvent = function(name)
        for _, h in pairs(e.handlers) do if h.name==name then h.callback() end end
    end
    e.sendAll = function(command)
        assert(e.F2T_CAPTURE_WINDOWS.galaxy.timerId, "cleanup must be armed before send")
        e.sent[#e.sent+1]=command
    end
    function e.load(path)
        local f=assert(loadfile(root.."/src/scripts/"..path..".lua")); setfenv(f,e); f()
    end
    function e.advance(seconds)
        local finish=e.now+seconds
        while true do
            local id, first
            for candidate,t in pairs(e.timers) do
                if t.at<=finish and (not first or t.at<first.at) then id,first=candidate,t end
            end
            if not id then break end
            e.now=first.at; e.timers[id]=nil; first.callback()
        end
        e.now=finish
    end
    e.load("map/capture"); e.load("ui/content/galaxy")
    return e
end
local function closed(e)
    assert(e.F2T_GALAXY.capture_active==false and e.F2T_GALAXY.loading==false)
    assert(e.F2T_CAPTURE_WINDOWS.galaxy==nil)
    assert(e.triggers.galaxy_nav_line==false and e.triggers.galaxy_nav_end==false)
end
local function test(name, fn) fn(); passed=passed+1; print("PASS Galaxy "..name) end

test("arms before sending, parses response, closes on silence", function()
    local e=scenario(); assert(e.f2t_galaxy_scrape()); assert(e.sent[1]=="di systems")
    e.f2t_galaxy_capture_line("Test System - Test Syndicate syndicate - Test Cartel cartel - Founder Test: Test Planet(T)")
    e.advance(0.5); closed(e)
    assert(e.F2T_GALAXY.loaded)
    assert(e.F2T_GALAXY.cartels["Test Cartel"].systems["Test System"].planets[1].name=="Test Planet")
end)
test("continuous blank traffic cannot extend the 15 second limit", function()
    local e=scenario(); assert(e.f2t_galaxy_scrape())
    for _=1,61 do e.f2t_galaxy_capture_blank(); e.advance(0.25) end
    closed(e); assert(#e.sent==1)
end)
test("send and timer failures restore flags and catch-all triggers", function()
    for _,kind in ipairs({"send", "timer", "nil_timer", "missing_service"}) do
        local e=scenario()
        if kind=="send" then e.sendAll=function() error("transport rejected") end
        elseif kind=="timer" then e.tempTimer=function() error("timer rejected") end
        elseif kind=="nil_timer" then e.tempTimer=function() return nil end
        else e.f2t_capture_arm=false end
        assert(not e.f2t_galaxy_scrape()); closed(e); assert(#e.sent==0)
    end
end)
test("UI failure cannot prevent cleanup", function()
    local e=scenario(); e.f2t_galaxy_refresh_open=function() error("UI unavailable") end
    assert(e.f2t_galaxy_scrape()); pcall(e.advance, 4); closed(e)
end)
test("existing navigation and command reservations defer without takeover", function()
    for _,kind in ipairs({"owner", "movement", "nav_lease", "command_lease", "capture"}) do
        local e=scenario(); local api={navigation={}, commands={}}
        e.F2CE={API={v1=api}}
        if kind=="owner" then e.F2T_SPEEDWALK_OWNER="foreign"
        elseif kind=="movement" then e.F2T_SPEEDWALK_WAITING_FOR_MOVE=true
        elseif kind=="nav_lease" then api.navigation._lease={}
        elseif kind=="command_lease" then api.commands._lease={}
        else api.commands._nativeBlocker=function() return {kind="topology_capture"} end end
        assert(not e.f2t_galaxy_scrape()); e.advance(20); closed(e); assert(#e.sent==0)
        e.F2T_SPEEDWALK_OWNER=nil; e.F2T_SPEEDWALK_WAITING_FOR_MOVE=false
        api.navigation._lease=nil; api.commands._lease=nil; api.commands._nativeBlocker=nil
        e.advance(0.5); assert(#e.sent==1 and e.F2T_GALAXY.capture_active)
    end
end)
test("disconnect cancels scheduled and active work without clearing another capture", function()
    for _,active in ipairs({false,true}) do
        local e=scenario(); e.F2T_CAPTURE_WINDOWS.other={timerId=999}
        if active then assert(e.f2t_galaxy_scrape()) else e.f2t_galaxy_schedule_scrape(3) end
        local count=#e.sent; e.raiseEvent("sysDisconnectionEvent"); e.advance(20)
        closed(e); assert(#e.sent==count); assert(e.F2T_CAPTURE_WINDOWS.other.timerId==999)
    end
end)
test("reload retires old capture and handlers but retains complete index", function()
    local e=scenario(); e.F2T_GALAXY.cartels={sentinel={}}; local index=e.F2T_GALAXY.cartels
    assert(e.f2t_galaxy_scrape()); e.load("ui/content/galaxy"); closed(e)
    assert(e.F2T_GALAXY.cartels==index)
    local n=0; for _ in pairs(e.handlers) do n=n+1 end; assert(n==5)
    e.advance(20); assert(#e.sent==1); assert(e.F2T_GALAXY.cartels==index)
end)
print("Galaxy capture lifecycle: "..passed.." groups passed")
