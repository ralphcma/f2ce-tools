-- Native services needed by hauling consumers. No implementation globals:
-- adapter.lua alone binds native capture, trade, protection and price code.
local API = F2CE.API.v1
local S = {}
API.services = S
local unpack_values = table.unpack or unpack
function S.copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for k, v in pairs(value) do result[k] = S.copy(v) end; return result
end
function S.error(code, message) return API.errors.new(code, tostring(message)) end
function S.live(context)
    local record = type(context) == "table" and API._modules[context.module_id]
    return record and record.context == context and context:_live()
end
function S.authorize(context, operation, payload)
    if not S.live(context) then return nil, S.error("E_MODULE_DISABLED", "enabled module context required") end
    local spec = API._modules[context.module_id].spec
    if type(spec.authorize) ~= "function" then return nil, S.error("E_AUTHORITY", "explicit command authorization callback required") end
    local ok, allowed, why = pcall(spec.authorize, operation, S.copy(payload or {}))
    if not ok or allowed ~= true then return nil, S.error("E_AUTHORITY", ok and (why or "operation denied") or allowed) end
    return true
end
function S.name(value, location)
    if type(value) ~= "string" or value:find("[%c;|]") then return nil end
    local text = value:match("^%s*(.-)%s*$"):gsub("%s+", " ")
    local pattern = location and "^[%w][%w%s%'%-%.]*$" or "^[%a][%a%s%-]*$"
    if #text < 1 or #text > (location and 80 or 40) or not text:match(pattern) then return nil end
    return text
end
function S.forget(context, token)
    if not token then return end
    token:cancel()
    for i = #context._resources, 1, -1 do
        if context._resources[i] == token then table.remove(context._resources, i); break end
    end
end

-- Every typed operation is authorized before formatting; a transport receipt
-- is never mistaken for a game acknowledgement.
API.actions = {}
function API.actions.command(context, operation, payload)
    payload = payload or {}
    local ok, why = S.authorize(context, operation, payload); if not ok then return nil, why end
    if operation == "futures.refresh" then return "di futures" end
    local commodity = S.name(payload.commodity)
    if not commodity then return nil, S.error("E_ARGUMENT", "invalid commodity") end
    if operation == "futures.buy" then return "buy futures " .. commodity end
    if operation == "futures.liquidate" then return "liquidate " .. commodity end
    if operation == "prices.local" then return "check price " .. commodity end
    if operation == "prices.premium" then
        local scope = payload.scope or "all"
        if scope ~= "all" and scope ~= "buy" and scope ~= "sell" then return nil, S.error("E_ARGUMENT", "invalid premium scope") end
        return "check premium " .. commodity .. " " .. scope
    end
    return nil, S.error("E_ARGUMENT", "unknown typed command")
end
function API.actions.send(context, operation, payload)
    local command, why = API.actions.command(context, operation, payload)
    if not command then return nil, why end
    local lease; lease, why = API.commands.acquire(context, { service = operation })
    if not lease then return nil, why end
    local sent, failure = lease:send(command, { reason = operation, operation = operation })
    lease:release("typed_command_sent")
    return sent, failure
end

-- Holds the broker until native callback/cancellation/timeout, with compare-
-- and-cancel ownership in the adapter. Callback gets copied values, after
-- release, so a completed capture can safely start navigation or a trade.
function S.operation(context, operation, payload, start, cancel, callback, timeout)
    local allowed, why = S.authorize(context, operation, payload)
    if not allowed then return nil, why end
    if type(callback) ~= "function" then return nil, S.error("E_ARGUMENT", "callback required") end
    local lease; lease, why = API.commands.acquire(context, { service = operation })
    if not lease then return nil, why end
    local active, timer, token = true, nil, nil
    local handle, done = {}, nil
    function handle:cancel(reason)
        if not active then return true end
        active = false
        if timer then API._adapter.cancelTimer(timer) end
        local ok, result = pcall(cancel, done, reason or "cancelled")
        lease:release(reason or "cancelled")
        S.forget(context, token)
        return ok and result ~= false
    end
    function handle:status() return { active = active, operation = operation } end
    done = function(...)
        if not active then return end
        local args = { n = select("#", ...), ... }
        active = false
        if timer then API._adapter.cancelTimer(timer) end
        lease:release("operation_complete")
        S.forget(context, token)
        if S.live(context) then
            local ok, err = pcall(callback, unpack_values(S.copy(args), 1, args.n))
            if not ok then API.events.emit("api.callback_error", { label = operation, error = tostring(err) }) end
        end
    end
    token = context:own(operation, handle, function(value) value:cancel("module_cleanup") end)
    timer = API._adapter.timer(timeout or 60, function()
        if not active then return end
        handle:cancel("operation_timeout")
        if S.live(context) then callback(nil, nil, "error", "native operation timed out") end
    end, false)
    if not timer then handle:cancel("timer_missing"); return nil, S.error("E_CAPABILITY", "operation timer unavailable") end
    API.commands._record({ id = lease.id .. ":" .. operation, module_id = context.module_id,
        lease_id = lease.id, status = "delegated", timestamp = os.time(), command = operation,
        metadata = { reason = operation, payload = S.copy(payload) } })
    local ok, accepted, failure = pcall(start, done)
    if not ok or accepted == false then
        handle:cancel("start_failed")
        return nil, S.error("E_OPERATION_START", ok and (failure or "native operation rejected") or accepted)
    end
    return handle
end

API.discovery = {}
function API.discovery.system(context, name, callback)
    name = S.name(name, true)
    if not name then return nil, S.error("E_ARGUMENT", "invalid system") end
    return S.operation(context, "po.scan", { system = name }, function(done)
        return API._adapter.systemStart(name, done)
    end, API._adapter.systemCancel, function(planets, excluded, missing, failure)
        callback(planets, excluded, missing == true, failure)
    end, 30)
end
API.trading = {}
function API.trading.bulk(context, options, callback)
    options = options or {}
    local name, lots, side = S.name(options.commodity), tonumber(options.lots), options.side
    if not name or not lots or lots ~= math.floor(lots) or lots < 1 or lots > 100
        or (side ~= "buy" and side ~= "sell") then return nil, S.error("E_ARGUMENT", "valid commodity, side and 1..100 lots required") end
    return S.operation(context, "po." .. side, options, function(done)
        return API._adapter.bulkStart(side, name, lots, done)
    end, API._adapter.bulkCancel, callback, 120)
end
API.settings = {}
function API.settings.get(component, key)
    if not API._adapter or not API._adapter.setting then return nil end
    local ok, value = pcall(API._adapter.setting, component, key)
    if ok then return S.copy(value) end
    return nil, S.error("E_SETTINGS", value)
end
function API.prices.analyze(commodity, lines, count)
    if not S.name(commodity) or type(lines) ~= "table" then return nil, S.error("E_ARGUMENT", "commodity and price lines required") end
    local ok, result, why = pcall(API._adapter.priceAnalyze, commodity, S.copy(lines), count)
    if not ok or not result then return nil, S.error("E_PRICE_ANALYSIS", ok and why or result) end
    return S.copy(result)
end
function API.prices.display(commodity, analysis)
    if API._adapter.priceDisplay then return API._adapter.priceDisplay(commodity, S.copy(analysis)) end
end

-- Called at the stock price check's explicit native hook, never by replacing
-- f2t_price_check_commodity. Only API-owned hauling uses registered providers.
function API.prices.offerNative(commodity, callback)
    local owner = API.hauling._owner
    if not owner or API.prices._active or type(callback) ~= "function" then return false end
    local state = API.hauling.status()
    if not state.active or state.mode ~= "exchange" then return false end
    local provider = false
    for _, item in pairs(API.prices._providers) do
        if item.active and item.module_id == owner then provider = true; break end
    end
    if not provider then return false end
    local context = API._modules[owner].context
    API.prices.request(context, commodity, { scope = "hauling", timeout = 125, fallback = false, _nativeHauling = true }, function(result, err)
        if not S.live(context) then return end
        if not result then
            API.hauling.stop()
            API.events.emit("hauling.price_failed", { module_id = owner, reason = tostring(err) })
            callback(commodity, nil, nil)
        else callback(result.commodity or commodity, result.parsed, result.analysis) end
    end)
    return true
end
function S.install()
    local capabilities = API._adapter.consumerCapabilities and API._adapter.consumerCapabilities() or {}
    for name, available in pairs(capabilities) do API.capabilities[name] = { available = available, detail = "native consumer service" } end
    API.capabilities["gmcp.receipts"] = { available = type(API._adapter.mapRoomIdentity) == "function", detail = "receipt-time mapped room identity" }
    API.capabilities["commands.typed"] = { available = true, detail = "authorized futures and price commands" }
    API.capabilities["prices.hauling_provider"] = { available = true, detail = "native hauling provider hook" }
    if API.protection then API.protection.install() end
end
