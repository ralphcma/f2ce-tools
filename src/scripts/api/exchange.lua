-- Native F2CE.API.v1 exchange service. A scoped session owns the command
-- broker across capture pairs or a confirmed apply sequence. No auto-enable.
local API = F2CE and F2CE.API and F2CE.API.v1
if not API then return end
local exchange = {}
API.exchange = exchange
local Session = {}
Session.__index = Session

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function err(code, message)
    return API.errors.new(code, message)
end

local function planet_name(value)
    if value == nil then return nil end
    if type(value) ~= "string" then return nil, "planet must be a string" end
    local text = value:match("^%s*(.-)%s*$"):gsub("%s+", " ")
    if text == "" or #text > 80 or value:find("[%c;|]")
        or not text:match("^[%w][%w%s%'%-%.]*$") then return nil, "invalid planet name" end
    return text
end

function Session:_valid()
    return not self.closed and self.context:_live() and self.lease:_valid()
end

function Session:status()
    return { active = self:_valid(), capturing = self.pending ~= nil,
        module_id = self.context.module_id, lease_id = self.lease.id }
end

function Session:release(reason)
    if self.closed then return true end
    self.closed = true
    local request = self.pending
    self.pending = nil
    local ok, detail = true, nil
    if request then
        if request.timer then API._adapter.cancelTimer(request.timer) end
        local called, result, why = pcall(API._adapter.exchangeCancel, request.callback)
        ok, detail = called and result, called and why or tostring(result)
    end
    self.lease:release(reason or "exchange_session_released")
    if self.cleanup_token then
        local token = self.cleanup_token
        self.cleanup_token = nil
        token:cancel()
        for index = #self.context._resources, 1, -1 do
            if self.context._resources[index] == token then table.remove(self.context._resources, index); break end
        end
    end
    return ok, detail
end

function exchange.acquire(context, options)
    options = options or {}
    if type(options.reason) ~= "string" or options.reason == "" then
        return nil, err("E_EXCHANGE_REASON", "an explicit exchange-operation reason is required")
    end
    local lease, why = API.commands.acquire(context, { service = "exchange", reason = options.reason })
    if not lease then return nil, why end
    local session = setmetatable({ context = context, lease = lease, reason = options.reason }, Session)
    local owned, own_error = context:own("exchange_session", session, function(value)
        value:release("module_cleanup")
    end)
    if not owned then lease:release("context_closed"); return nil, own_error end
    session.cleanup_token = owned
    return session
end

function Session:capture(kind, planet, callback, options)
    if not self:_valid() then return nil, err("E_EXCHANGE_SESSION", "enabled module and active session required") end
    if self.pending then return nil, err("E_CAPTURE_BUSY", "this session already has a pending capture") end
    if kind ~= "exchange" and kind ~= "production" then return nil, err("E_ARGUMENT", "unknown capture kind") end
    if type(callback) ~= "function" then return nil, err("E_ARGUMENT", "capture callback required") end
    local target, invalid = planet_name(planet)
    if invalid then return nil, err("E_ARGUMENT", invalid) end
    local adapter = API._adapter
    if not adapter or not adapter.exchangeCapture or not adapter.exchangeCancel
        or not adapter.timer or not adapter.cancelTimer then
        return nil, err("E_CAPABILITY", "native exchange capture and timeout services required")
    end
    local blocker = API.commands._nativeBlocker()
    if blocker then return nil, API.errors.new("E_COMMAND_CONTENTION", "native activity blocks exchange capture", blocker) end
    local timeout = tonumber(options and options.timeout) or 15
    if timeout ~= timeout or timeout < 1 or timeout > 60 then return nil, err("E_ARGUMENT", "capture timeout must be 1..60 seconds") end
    local request = { kind = kind, planet = target }
    self.pending = request
    local function done(rows, failure)
        if self.pending ~= request or not self:_valid() then return end
        self.pending = nil
        if request.timer then adapter.cancelTimer(request.timer) end
        local payload = { kind = kind, planet = target, module_id = self.context.module_id,
            rows = copy(rows), error = failure and tostring(failure) or nil }
        API.events.emit(failure and "exchange.capture_failed" or "exchange.captured", payload)
        -- Events can disable/reload a consumer before its callback executes.
        if not self:_valid() then return end
        local ok, why = pcall(callback, copy(rows), failure)
        if not ok then
            self:release("callback_failed")
            API.events.emit("api.callback_error", { label = "exchange capture", error = tostring(why) })
        end
    end
    request.callback = done
    request.timer = adapter.timer(timeout, function()
        if self.pending ~= request then return end
        adapter.exchangeCancel(done)
        done(nil, err("E_CAPTURE_TIMEOUT", "exchange capture timed out"))
        -- A timeout cannot leave a forgotten command lease locked forever.
        self:release("capture_timeout")
    end, false)
    if not request.timer then self.pending = nil; return nil, err("E_CAPABILITY", "capture timeout could not be armed") end
    local command = kind == "exchange" and "display exchange" or "display production"
    if target then command = command .. (kind == "production" and " all " or " ") .. target end
    API.commands._record({ id = self.lease.id .. ":capture", module_id = self.context.module_id,
        lease_id = self.lease.id, command = command, status = "delegated", timestamp = os.time(),
        metadata = { service = "exchange", reason = self.reason, kind = kind, planet = target } })
    local ok, accepted, why = pcall(adapter.exchangeCapture, kind, target, done)
    if not ok or accepted ~= true then
        if self.pending == request then
            self.pending = nil
            adapter.cancelTimer(request.timer)
            adapter.exchangeCancel(done)
        end
        return nil, err("E_CAPTURE_START", tostring(ok and why or accepted))
    end
    return true
end

-- A sent result is NOT a server acknowledgement. Keep the session leased
-- until the consumer validates the exact response or cancels/times out.
function Session:set(change)
    if not self:_valid() then return nil, err("E_EXCHANGE_SESSION", "enabled module and active session required") end
    if self.pending then return nil, err("E_CAPTURE_BUSY", "cannot mutate during capture") end
    change = type(change) == "table" and change or {}
    local kind, commodity, value = change.kind, change.commodity, tonumber(change.value)
    if type(commodity) ~= "string" or #commodity > 40 or not commodity:match("^[%a][%w]*$") then
        return nil, err("E_ARGUMENT", "canonical commodity name required")
    end
    local bounds = { min = {0, 10000}, max = {0, 20000}, spread = {6, 40} }
    local bound = bounds[kind]
    if not bound or not value or value ~= value or value < bound[1] or value > bound[2]
        or value ~= math.floor(value) then return nil, err("E_ARGUMENT", "setting value outside accepted integer range") end
    local target, invalid = planet_name(change.planet)
    if invalid then return nil, err("E_ARGUMENT", invalid) end
    if not target then
        local room, vitals = API.data.refresh("room"), API.data.refresh("vitals")
        if type(room) ~= "table" or type(vitals) ~= "table" or type(room.owner) ~= "string"
            or room.owner == "" or type(vitals.name) ~= "string"
            or room.owner:lower() ~= vitals.name:lower() then
            return nil, err("E_OWNERSHIP", "current exchange ownership is not confirmed")
        end
    end
    local command = kind == "spread" and string.format("set spread %d %s", value, commodity)
        or string.format("set stockpile %s %d %s", kind, value, commodity)
    if target then command = command .. " " .. target end
    return self.lease:send(command, { reason = self.reason, service = "exchange", change = copy(change), echo = false })
end
