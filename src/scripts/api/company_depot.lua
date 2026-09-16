-- Read-only depot inventory. The next company/business report is an ordered
-- response fence, because display depot has no footer or inventory GMCP.
local API, S = F2CE.API.v1, F2CE.API.v1.services
local function has_depot(company, planet)
    if type(company.depots)~="table" then return nil end
    for _, name in ipairs(company.depots or {}) do
        if type(name)=="string" and name:lower()==planet:lower() then return name end
    end
end
local function read_depot(context, planet, callback, borrowed)
    if type(callback)~="function" then return nil,S.error("E_ARGUMENT","callback required") end
    local name = S.name(planet,true)
    if not name then return nil,S.error("E_ARGUMENT","valid depot planet required") end
    local operation="company.depot.inspect"
    local allowed,why=S.authorize(context,operation,{planet=name}); if not allowed then return nil,why end
    local company; company,why=API.company.snapshot(); if not company then return nil,why end
    name=has_depot(company,name)
    if not name or not S.name(name,true) then return nil,S.error("E_DEPOT_IDENTITY","depot is absent from this owner's snapshot") end
    if type(API._adapter.parseDepot)~="function" or type(API._adapter.observeLine)~="function"
        or type(API._adapter.unobserveLine)~="function" then return nil,S.error("E_CAPABILITY","native depot parser and observer required") end
    local vitals=API.data.get("vitals")
    local channel=vitals.rank=="Industrialist" and "business" or "company"
    local lease=borrowed
    if lease then
        if lease~=API.commands._lease or not lease.active or lease.module_id~=context.module_id then
            return nil,S.error("E_COMMAND_CONTENTION","invalid borrowed depot lease")
        end
    else lease,why=API.commands.acquire(context,{service=operation}); if not lease then return nil,why end end
    local active,timer,observer,subscription,token=true
    local lines, report, record, received, summary={},false,nil,false,nil
    local handle={}
    local function cleanup(reason)
        if not active then return false end
        active=false
        if timer then API._adapter.cancelTimer(timer) end
        if observer then API._adapter.unobserveLine(observer) end
        if subscription then subscription:cancel() end
        if not borrowed then lease:release(reason) end
        S.forget(context,token)
        return true
    end
    function handle:cancel(reason) cleanup(reason or "depot_cancelled"); return true end
    function handle:status() return {active=active,operation=operation} end
    local function finish(value,err)
        if not cleanup(err and "depot_failed" or "depot_complete") then return end
        if S.live(context) then
            local ok,detail=pcall(callback,S.copy(value),err)
            if not ok then API.events.emit("api.callback_error",{label=operation,error=tostring(detail)}) end
        end
    end
    local function same_owner()
        local current=API.company.snapshot()
        local who=API.data.get("vitals")
        return current and who and who.rank==vitals.rank and current.name==company.name
            and current.ceo:lower()==company.ceo:lower() and has_depot(current,name)
    end
    local function complete()
        if not active or not received or not record then return end
        if not same_owner() then return finish(nil,S.error("E_COMPANY_IDENTITY","owner, rank or depot changed during capture")) end
        if channel=="company" then
            if not summary then return end
            if summary.capacity~=record.capacity or summary.used~=record.used_bays or summary.efficiency~=record.efficiency then
                return finish(nil,S.error("E_DEPOT_CHANGED","depot inventory and fresh company summary disagree; repeat inspection"))
            end
        end
        record.owner,record.ceo=company.name,company.ceo
        record.captured_at=os.time()
        record.completeness=channel=="company" and "ordered_fence_and_occupancy" or "ordered_read_fence"
        finish(record)
    end
    token=context:own(operation,handle,function(value) value:cancel("module_cleanup") end)
    subscription=API.events.subscribe("data."..channel,function(event)
        if not active or not event.received then return end
        if not same_owner() then return finish(nil,S.error("E_COMPANY_IDENTITY","owner, rank or depot changed during capture")) end
        received=true; complete()
    end)
    observer=API._adapter.observeLine(function(value)
        if not active then return end
        local clean=value:gsub("\27%[[%d;]*m", ""):gsub("%s+"," "):match("^%s*(.-)%s*$")
        -- Ambient exchange ticker can interleave while standing at a depot's
        -- exchange. Ignore only these exact server forms, never arbitrary
        -- chat/diagnostics or an unrecognized depot row.
        if clean:match("^%+%+%+ The exchange display shows the prices for [%a][%w]* %+%+%+$")
            or clean:match("^%+%+%+ Exchange has %d+ tons for sale %+%+%+$")
            or clean:match("^%+%+%+ Offer price is %d+ig/ton for first 75 tons %+%+%+$")
            or clean:match("^%+%+%+ Exchange will buy 75 tons at %d+ig/ton %+%+%+$") then return end
        -- Headers may wrap. Buffer the whole bounded response until the exact
        -- report identity closes the depot block, then parse every depot byte.
        lines[#lines+1]=clean
        local joined=table.concat(lines," "):gsub("%s+"," ")
        if #lines>300 or #joined>49152 then return finish(nil,S.error("E_DEPOT_DISPLAY","response exceeds bound")) end
        if not report then
            local marker=channel=="business" and company.name.." registered business - CEO " or "Company Report for "..company.name..":"
            local pos=joined:find(marker,1,true)
            if pos then
                local text=joined:sub(1,pos-1):match("^%s*(.-)%s*$")
                local detail
                record,detail=API._adapter.parseDepot({text},name)
                if not record then return finish(nil,S.error("E_DEPOT_DISPLAY",detail or "invalid depot response")) end
                report=true
            end
        end
        if report and channel=="company" then
            local start=joined:find(name.." - Capacity: ",1,true)
            if start then
                local capacity,used,eff=joined:sub(start+#name):match("^ %- Capacity: (%d+) bays %((%d+) in use%) (%d+)%% efficiency")
                if capacity then summary={capacity=tonumber(capacity),used=tonumber(used),efficiency=tonumber(eff)} end
            end
        end
        complete()
    end)
    if not observer then cleanup("observer_missing"); return nil,S.error("E_CAPABILITY","depot observer unavailable") end
    timer=API._adapter.timer(15,function() finish(nil,S.error("E_COMPANY_TIMEOUT","complete owner-bound depot response not received within 15 seconds")) end,false)
    if not timer then cleanup("timer_missing"); return nil,S.error("E_CAPABILITY","depot timer unavailable") end
    for _,command in ipairs({"display depot "..name,channel=="business" and "di business" or "di company"}) do
        local sent,err=lease:send(command,{reason=operation,operation=operation})
        if not sent then cleanup("send_failed"); return nil,err end
    end
    return handle
end
function API.company.depot(context,planet,callback) return read_depot(context,planet,callback) end
-- Internal transaction composition; authorization and exact lease ownership
-- are still checked. The outer transfer retains its lease between reads.
API.company._depotWithLease=read_depot
