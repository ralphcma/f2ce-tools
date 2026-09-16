-- Explicit single-bay operations only. No navigation, retry, factory flush,
-- purchase or implicit start. Private closures retain the authorized preview.
local API,S=F2CE.API.v1,F2CE.API.v1.services
local function integer(n,lo,hi)
    n=tonumber(n); return n and n==math.floor(n) and n>=lo and n<=hi and n or nil
end
local function norm(s) return type(s)=="string" and s:lower() or "" end
local function cargo_key(c)
    return norm(c.commodity).."\0"..norm(c.origin).."\0"..tostring(c.cost_per_ton or c.cost)
end
local function manifest(rows)
    local result={}
    for _,c in ipairs(rows) do local key=cargo_key(c); result[key]=(result[key] or 0)+1 end
    return result
end
local function equal(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
local function changed(rows,cargo,delta)
    local result=manifest(rows); local key=cargo_key(cargo)
    result[key]=(result[key] or 0)+delta
    if result[key]==0 then result[key]=nil end
    return result
end
local function ground(room,planet)
    if type(room)~="table" or norm(room.area)~=norm(planet) or not S.name(room.system,true)
        or not integer(room.num,0,99999999) or type(room.flags)~="table" then return nil end
    for k,v in pairs(room.flags) do if v=="space" or (k=="space" and v==true) then return nil end end
    return norm(room.system).."\0"..norm(room.area).."\0"..room.num
end
local function snapshot(planet)
    local company,why=API.company.snapshot(); if not company then return nil,why end
    local room=API.data.get("room"); local location=ground(room,planet)
    if not location then return nil,S.error("E_DEPOT_LOCATION","must be on the requested planet, not in space") end
    local ship=API.data.get("ship")
    if type(ship)~="table" or type(ship.registry)~="string" or ship.registry=="" or type(ship.hold)~="table"
        or type(ship.cargo)~="table" or not integer(ship.hold.max,75,75000)
        or not integer(ship.hold.cur,0,ship.hold.max) or ship.hold.cur+#ship.cargo*75~=ship.hold.max then
        return nil,S.error("E_DEPOT_SHIP","complete ship hold and ordinary cargo GMCP required; job cargo is not supported")
    end
    for _,c in ipairs(ship.cargo) do
        if type(c)~="table" or not S.name(c.commodity) or not S.name(c.origin,true)
            or not integer(c.cost,0,1000000000) or c.destination then
            return nil,S.error("E_DEPOT_SHIP","invalid or job cargo cannot be transferred")
        end
    end
    local cash=integer(API.data.get("cash"),0,9007199254740991)
    if not cash or not integer(company.cash,-9007199254740991,9007199254740991) then
        return nil,S.error("E_DEPOT_CASH","current personal and company cash required")
    end
    return {company=company,ship=ship,cash=cash,location=location,rank=API.data.get("vitals").rank}
end
local function select_cargo(state,options)
    if options.side=="store" then
        for _,c in ipairs(state.ship.cargo) do if norm(c.commodity)==norm(options.commodity) then return c end end
    else
        for _,c in ipairs(state.depot.bays) do if c.number==options.bay then return c end end
    end
end
local function ready(state,options)
    local c=select_cargo(state,options)
    if not c then return nil,S.error("E_DEPOT_CARGO","requested cargo is absent") end
    local cost=(c.cost_per_ton or c.cost)*75
    if options.side=="store" and state.depot.free_bays<1 then return nil,S.error("E_DEPOT_FULL","depot has no free bay") end
    if options.side=="fetch" and state.ship.hold.cur<75 then return nil,S.error("E_DEPOT_FULL","ship has no full free bay") end
    if state.cash-(options.side=="fetch" and cost or 0)<options.personal_reserve
        or state.company.cash-(options.side=="store" and cost or 0)<options.company_reserve then
        return nil,S.error("E_DEPOT_RESERVE","transfer would breach personal or company cash reserve")
    end
    local stamina=API.data.get("stamina")
    local threshold=math.max(25,tonumber(API.settings.get("stamina","threshold")) or 0)
    if type(stamina)~="table" or not integer(stamina.max,1,1000000) or not integer(stamina.cur,0,stamina.max)
        or stamina.cur*100/stamina.max<=threshold then return nil,S.error("E_STAMINA","recover stamina before preparing a transfer") end
    if API.protection and API.protection.isRecovering() then return nil,S.error("E_DEATH","death recovery is active") end
    return c,cost
end
function API.company.prepareTransfer(context,options,callback)
    options=S.copy(options or {})
    if type(callback)~="function" or (options.side~="store" and options.side~="fetch") or not S.name(options.planet,true)
        or not integer(options.personal_reserve,0,9007199254740991) or not integer(options.company_reserve,0,9007199254740991)
        or (options.side=="store" and not S.name(options.commodity))
        or (options.side=="fetch" and not integer(options.bay,1,50)) then
        return nil,S.error("E_ARGUMENT","side, planet, cargo/bay and both cash reserves are required")
    end
    options.personal_reserve=tonumber(options.personal_reserve); options.company_reserve=tonumber(options.company_reserve)
    options.bay=tonumber(options.bay)
    local operation="company.depot."..options.side
    local allowed,why=S.authorize(context,"company.depot.preview",options); if not allowed then return nil,why end
    local initial; initial,why=snapshot(options.planet); if not initial then return nil,why end
    local lease; lease,why=API.commands.acquire(context,{service=operation}); if not lease then return nil,why end
    local active,sent,phase=true,false,"reading"
    local token,timer,child,preview,completion
    local subscriptions={}; local epoch=0
    local handle={}
    local function clear_read()
        epoch=epoch+1
        if timer then API._adapter.cancelTimer(timer); timer=nil end
        if child then child:cancel("transfer_read_finished"); child=nil end
        for _,sub in ipairs(subscriptions) do sub:cancel() end; subscriptions={}
    end
    local function cleanup(reason)
        if not active then return false end
        active=false; clear_read(); lease:release(reason); S.forget(context,token); return true
    end
    function handle:status() return {active=active,phase=phase,sent=sent,uncertain=sent and phase~="confirmed"} end
    function handle:cancel(reason)
        if not active then return true end
        phase=sent and "unconfirmed" or "cancelled"; cleanup(reason or phase); return true
    end
    local function finish(value,err)
        phase=value and "confirmed" or (sent and "unconfirmed" or "failed")
        if not cleanup(phase) then return end
        if err and sent then err=S.error("E_DEPOT_UNCONFIRMED",tostring(err).."; one transfer may have occurred; inspect manually; NEVER retry automatically") end
        if S.live(context) then
            local ok,detail=pcall(completion or callback,value,err)
            if not ok then API.events.emit("api.callback_error",{label=operation,error=tostring(detail)}) end
        end
    end
    local function bound(seconds,fn)
        timer=API._adapter.timer(seconds,fn,false)
        if not timer then finish(nil,S.error("E_CAPABILITY","transfer timer unavailable")); return false end
        return true
    end
    local function read_all(done)
        if not active then return end
        clear_read(); local my_epoch=epoch; local received={}
        local function receive(channel)
            if not active or epoch~=my_epoch then return end
            received[channel]=true
            if not (received.room and received.ship and received.cash and received.stamina) then return end
            clear_read()
            local state,err=snapshot(options.planet)
            if not state then finish(nil,err); return end
            if state.location~=initial.location or state.rank~=initial.rank or state.company.name~=initial.company.name
                or norm(state.company.ceo)~=norm(initial.company.ceo) or state.ship.registry~=initial.ship.registry then
                finish(nil,S.error("E_COMPANY_IDENTITY","location, ship, character or owner changed")); return
            end
            local h,problem=API.company._depotWithLease(context,options.planet,function(depot,error_value)
                child=nil
                if not active then return end
                if not depot then finish(nil,error_value); return end
                local current,invalid=snapshot(options.planet)
                if not current or current.location~=initial.location or current.rank~=initial.rank
                    or current.company.name~=initial.company.name or norm(current.company.ceo)~=norm(initial.company.ceo)
                    or current.ship.registry~=initial.ship.registry then finish(nil,invalid or S.error("E_COMPANY_IDENTITY","identity changed during depot read")); return end
                current.depot=depot; done(current)
            end,lease)
            if not h then finish(nil,problem) elseif h:status().active then child=h end
        end
        for _,channel in ipairs({"room","ship","cash","stamina"}) do
            local name=channel
            subscriptions[#subscriptions+1]=API.events.subscribe("data."..name,function(event)
                if event.received then receive(name) end
            end)
        end
        if not bound(15,function() finish(nil,S.error("E_COMPANY_TIMEOUT","fresh room/ship/cash/stamina GMCP was not received")) end) then return end
        local ok,err=lease:send("score",{operation="company.depot.preview",reason="fresh transfer state"})
        if not ok then finish(nil,err) end
    end
    function handle:confirm(done)
        if not active or phase~="ready" or type(done)~="function" then return nil,S.error("E_AUTHORITY","active, unexpired preview required") end
        local permitted,problem=S.authorize(context,operation,options); if not permitted then finish(nil,problem); return nil,problem end
        completion=done; phase="revalidating"
        read_all(function(before)
            local cargo,cost=ready(before,options)
            if not cargo then finish(nil,cost); return end
            if not equal(before.ship,preview.ship) or not equal(before.depot.bays,preview.depot.bays)
                or before.depot.capacity~=preview.depot.capacity then
                finish(nil,S.error("E_DEPOT_CHANGED","inventory changed since preview; create a new preview")); return
            end
            local authorized,err=S.authorize(context,operation,options)
            if not authorized then finish(nil,err); return end
            phase="settling"; sent=true -- once only, including transport uncertainty
            local command=options.side=="store" and "store "..cargo.commodity or "fetch "..options.bay
            local ok,problem=lease:send(command,{operation=operation,reason="explicitly confirmed single bay"})
            if not ok then finish(nil,problem); return end
            read_all(function(after)
                local delta=options.side=="fetch" and 1 or -1
                if not equal(manifest(after.ship.cargo),changed(before.ship.cargo,cargo,delta))
                    or not equal(manifest(after.depot.bays),changed(before.depot.bays,cargo,-delta))
                    or after.ship.hold.cur~=before.ship.hold.cur-delta*75
                    or after.depot.free_bays~=before.depot.free_bays+delta
                    or after.cash~=before.cash-delta*cost or after.company.cash~=before.company.cash+delta*cost then
                    finish(nil,S.error("E_DEPOT_RECONCILE","ship, depot or money movement does not match one bay")); return
                end
                finish({side=options.side,planet=options.planet,commodity=cargo.commodity,tons=75,value=cost,
                    personal_cash=after.cash,company_cash=after.company.cash,confirmed=true})
            end)
        end)
        return true
    end
    token=context:own(operation,handle,function(value) value:cancel("module_cleanup") end)
    read_all(function(state)
        local cargo,cost=ready(state,options)
        if not cargo then finish(nil,cost); return end
        preview=state; phase="ready"
        if not bound(30,function() finish(nil,S.error("E_DEPOT_EXPIRED","transfer preview expired without confirmation")) end) then return end
        local ok,err=pcall(callback,{side=options.side,planet=options.planet,commodity=cargo.commodity,tons=75,value=cost,
            personal_cash=state.cash,company_cash=state.company.cash,personal_reserve=options.personal_reserve,
            company_reserve=options.company_reserve,expires_in=30})
        if not ok then handle:cancel("preview_callback_failed"); API.events.emit("api.callback_error",{label=operation,error=tostring(err)}) end
    end)
    return handle
end
