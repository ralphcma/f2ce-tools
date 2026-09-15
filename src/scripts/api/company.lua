-- Read-only company/factory bridge. No buying, selling, dividend or promotion
-- commands are exposed here. One broker lease spans request AND response.
local API, S = F2CE.API.v1, F2CE.API.v1.services
local C = {}; API.company = C
local function identity()
    local vitals = API.data.get("vitals")
    local rank = type(vitals) == "table" and vitals.rank
    if rank ~= "Industrialist" and rank ~= "Manufacturer" and rank ~= "Financier" then
        return nil, S.error("E_COMPANY_RANK", "Industrialist, Manufacturer or Financier required")
    end
    if type(vitals.name) ~= "string" or vitals.name == "" then return nil, S.error("E_COMPANY_IDENTITY", "character unavailable") end
    return {name=vitals.name, rank=rank}
end
function C.snapshot()
    local who, why=identity(); if not who then return nil, why end
    local value=API.data.get("company")
    if type(value) ~= "table" or type(value.ceo) ~= "string" or value.ceo:lower() ~= who.name:lower()
        or type(value.name) ~= "string" or value.name == "" or type(value.factories) ~= "table" then
        return nil, S.error("E_COMPANY_DATA", "company snapshot missing or belongs to another character")
    end
    return value, API.data.receipt("company")
end

local function request(context, operation, payload, callback)
    if type(callback) ~= "function" then return nil, S.error("E_ARGUMENT", "callback required") end
    local allowed, why=S.authorize(context,operation,payload); if not allowed then return nil,why end
    local who; who,why=identity(); if not who then return nil,why end
    local company, command
    if operation == "company.refresh" then command=who.rank=="Industrialist" and "di business" or "di company" else
        company,why=C.snapshot(); if not company then return nil,why end
        local number=tonumber(payload.number)
        if not number or number~=math.floor(number) or number<1 or number>15 then return nil,S.error("E_ARGUMENT","factory number must be 1..15") end
        local found=false
        for _, factory in pairs(company.factories) do
            if type(factory)=="table" and tonumber(factory.number)==number then found=true end
        end
        if not found then return nil,S.error("E_FACTORY_IDENTITY","factory is absent from this company's snapshot") end
        payload.number=number; command="display factory " .. number
    end
    local lease; lease,why=API.commands.acquire(context,{service=operation}); if not lease then return nil,why end
    local active, timer, token, observer, subscription=true,nil,nil,nil,nil
    local handle={}
    local function cleanup(reason)
        if not active then return false end
        active=false
        if timer then API._adapter.cancelTimer(timer) end
        if observer then API._adapter.unobserveLine(observer) end
        if subscription then subscription:cancel() end
        lease:release(reason); S.forget(context,token)
        return true
    end
    function handle:cancel(reason) cleanup(reason or "company_cancelled"); return true end
    function handle:status() return {active=active,operation=operation} end
    local function finish(value, error_value)
        if not cleanup(error_value and "company_read_failed" or "company_read_complete") then return end
        if S.live(context) then
            local ok,detail=pcall(callback,S.copy(value),error_value)
            if not ok then API.events.emit("api.callback_error",{label=operation,error=tostring(detail)}) end
        end
    end
    token=context:own(operation,handle,function(value) value:cancel("module_cleanup") end)
    local function same_character()
        local current=identity()
        return current and current.name:lower()==who.name:lower() and current.rank==who.rank
    end
    if operation=="company.refresh" then
        subscription=API.events.subscribe("data.company",function(event)
            if not active or not event.received then return end
            if not same_character() then return finish(nil,S.error("E_COMPANY_IDENTITY","character changed during refresh")) end
            local value,err=C.snapshot()
            if value then finish(value) else finish(nil,err) end
        end)
    else
        local lines, started={},false
        observer=API._adapter.observeLine(function(value)
            if not active then return end
            local clean=value:gsub("\27%[[%d;]*m", "")
            if clean:find("You don't have a factory with that number!",1,true) then
                return finish(nil,S.error("E_FACTORY_MISSING","factory no longer exists"))
            end
            if clean:find("Production Facility #",1,true) then
                if started then return finish(nil,S.error("E_FACTORY_DISPLAY","multiple factory headers")) end
                started=true
            end
            if not started then return end
            lines[#lines+1]=clean
            if #lines>100 then return finish(nil,S.error("E_FACTORY_DISPLAY","display exceeds line bound")) end
            -- Support a wrapped final line without treating silence as success.
            if table.concat(lines," "):gsub("%s+"," "):find("Next batch is %d+%% complete") then
                local record,detail=API._adapter.parseFactory(lines,payload.number)
                local current=C.snapshot()
                if not same_character() or not current or current.name~=company.name then
                    return finish(nil,S.error("E_COMPANY_IDENTITY","company changed during factory capture"))
                end
                if not record or record.owner~=company.name then return finish(nil,S.error("E_FACTORY_DISPLAY",detail or "company mismatch")) end
                finish(record)
            end
        end)
        if not observer then cleanup("observer_missing"); return nil,S.error("E_CAPABILITY","factory line observer unavailable") end
    end
    timer=API._adapter.timer(15,function() finish(nil,S.error("E_COMPANY_TIMEOUT","complete company/factory response not received within 15 seconds")) end,false)
    if not timer then cleanup("timer_missing"); return nil,S.error("E_CAPABILITY","company timer unavailable") end
    local sent,err=lease:send(command,{reason=operation,operation=operation})
    if not sent then cleanup("send_failed"); return nil,err end
    return handle
end
function C.refresh(context,callback) return request(context,"company.refresh",{},callback) end
function C.inspect(context,number,callback) return request(context,"company.inspect",{number=number},callback) end
