-- Read-only system workforce/economy snapshot. An ordered company report AND
-- fresh company GMCP fence the footer-less di system response. Silence is not
-- success; this never enables map capture/exploration or changes planet policy.
local API,S=F2CE.API.v1,F2CE.API.v1.services
local function trim(s) return s:match("^%s*(.-)%s*$") end
local function pattern(s) return (s:gsub("([^%w])","%%%1"):gsub("%% ","%%s+")) end
local economies={None=true,Agricultural=true,Resource=true,Industrial=true,Technical=true,Biological=true,Leisure=true}
local function count(text,word) local _,n=text:gsub(word,""); return n end
local function number(s)
    if not s or not s:match("^%d+$") then return nil end
    local n=tonumber(s); return n and n<=1000000000 and n or nil
end
function API.company._parseSystem(text,system)
    if type(text)~="string" or #text>131072 then return nil,"system response exceeds bounds" end
    text=text:gsub("\27%[[%d;]*m","")
    local flat=trim(text:gsub("%s+"," "))
    local header="System information for the "..system.." system:"
    if flat:sub(1,#header):lower()~=header:lower() or count(flat,"System information for the ")~=1 then return nil,"missing or mismatched system header" end
    local blocks,current={},nil
    for line in text:gmatch("[^\r\n]+") do
        -- Server planet headers start at column one; subsequent fields and
        -- wrapped header continuations belong to that block.
        if line:match("^%S.-,") then
            current={line}; blocks[#blocks+1]=current
            if #blocks>256 then return nil,"too many system planets" end
        elseif current then current[#current+1]=line end
    end
    local result={system=system,planets={}}
    for _,block in ipairs(blocks) do
        local row=trim(table.concat(block," "):gsub("%s+"," "))
        local planet,star=row:match("^([^,]+), (.-) system, .- cartel")
        if not planet or star:lower()~=system:lower() or not S.name(planet,true) then return nil,"invalid planet/system identity" end
        local key=planet:lower()
        if result.planets[key] then return nil,"duplicate planet" end
        if count(row,"Economy:")~=1 then return nil,"missing or duplicate economy" end
        local economy=row:match("Economy: (%a+)")
        if not economies[economy] then return nil,"unknown economy" end
        local available,total=(row.." "):match("Workers available: (%d+)/(%d+) ")
        if economy~="None" and (count(row,"Workers available:")~=1 or not number(available) or not number(total)
            or tonumber(available)>tonumber(total)) then return nil,"invalid workforce counts" end
        if economy=="None" and count(row,"Workers available:")~=0 then return nil,"unexpected workforce for non-economic planet" end
        result.planets[key]={planet=planet,system=system,economy=economy,
            available=available and tonumber(available),total=total and tonumber(total),
            closed=row:find("Closed to visitors",1,true)~=nil}
    end
    if #blocks==0 then return nil,"no complete planet records" end
    return result
end

local function read_system(context,system,callback,borrowed)
    local name=S.name(system,true)
    if not name or type(callback)~="function" then return nil,S.error("E_ARGUMENT","valid system and callback required") end
    local operation="company.system.inspect"
    local allowed,why=S.authorize(context,operation,{system=name}); if not allowed then return nil,why end
    local company; company,why=API.company.snapshot(); if not company then return nil,why end
    local who=API.data.get("vitals")
    local channel=who.rank=="Industrialist" and "business" or "company"
    local adapter=API._adapter
    if type(adapter.observeLine)~="function" or type(adapter.unobserveLine)~="function" then return nil,S.error("E_CAPABILITY","line observer required") end
    local lease=borrowed
    if lease then
        if lease~=API.commands._lease or not lease.active or lease.module_id~=context.module_id then
            return nil,S.error("E_COMMAND_CONTENTION","invalid borrowed system lease")
        end
    else lease,why=API.commands.acquire(context,{service=operation}); if not lease then return nil,why end end
    local active,timer,observer,subscription,token=true
    local lines,record,received={},nil,false
    local started,line_count,byte_count=false,0,0
    local expected_header=("System information for the "..name.." system:"):lower()
    local handle={}
    local function cleanup(reason)
        if not active then return false end
        active=false
        if timer then adapter.cancelTimer(timer) end
        if observer then adapter.unobserveLine(observer) end
        if subscription then subscription:cancel() end
        if not borrowed then lease:release(reason) end
        S.forget(context,token); return true
    end
    function handle:cancel(reason) cleanup(reason or "system_cancelled"); return true end
    function handle:status() return {active=active,operation=operation} end
    local function finish(value,err)
        if not cleanup(err and "system_read_failed" or "system_read_complete") then return end
        if S.live(context) then
            local ok,detail=pcall(callback,S.copy(value),err)
            if not ok then API.events.emit("api.callback_error",{label=operation,error=tostring(detail)}) end
        end
    end
    local function complete() if record and received then record.captured_at=os.time(); finish(record) end end
    token=context:own(operation,handle,function(value) value:cancel("module_cleanup") end)
    subscription=API.events.subscribe("data."..channel,function(event)
        if not active or not event.received then return end
        local current=API.data.get("vitals"); local owner=API.company.snapshot()
        if not current or current.name~=who.name or current.rank~=who.rank or not owner
            or owner.name~=company.name or owner.ceo~=company.ceo then
            return finish(nil,S.error("E_COMPANY_IDENTITY","owner or rank changed during system capture"))
        end
        received=true; complete()
    end)
    observer=adapter.observeLine(function(value)
        if not active then return end
        value=value:gsub("\27%[[%d;]*m","")
        line_count,byte_count=line_count+1,byte_count+#value+1
        if line_count>2000 or byte_count>131072 then return finish(nil,S.error("E_SYSTEM_DISPLAY","response exceeds bounds")) end
        -- GMCP may precede the trailing text of score/look/company. Do not
        -- treat that earlier command's output or company header as our report.
        if not started then
            if trim(value:match("^[^\r\n]*")):lower()~=expected_header then return end
            started=true
        end
        lines[#lines+1]=value
        local joined=table.concat(lines,"\n")
        if not record then
            local marker=channel=="business" and company.name.." registered business - CEO " or "Company Report for "..company.name..":"
            local pos=joined:find(pattern(marker))
            if pos then
                local detail; record,detail=API.company._parseSystem(joined:sub(1,pos-1),name)
                if not record then return finish(nil,S.error("E_SYSTEM_DISPLAY",detail)) end
                complete()
            end
        end
    end)
    if not observer then cleanup("observer_missing"); return nil,S.error("E_CAPABILITY","system observer unavailable") end
    timer=adapter.timer(15,function() finish(nil,S.error("E_COMPANY_TIMEOUT","complete system report and company fence not received within 15 seconds")) end,false)
    if not timer then cleanup("timer_missing"); return nil,S.error("E_CAPABILITY","system timer unavailable") end
    for _,command in ipairs({"di system "..name,channel=="business" and "di business" or "di company"}) do
        local sent,err=lease:send(command,{reason=operation,operation=operation})
        if not sent then cleanup("send_failed"); return nil,err end
    end
    return handle
end
function API.company.system(context,system,callback) return read_system(context,system,callback) end
API.company._systemWithLease=read_system
