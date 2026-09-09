-- SPDX-License-Identifier: GPL-2.0-only
-- Native Walker binding. Gameplay goes through F2CE.API.v1, never the
-- separately installed Fed2ModuleAPI or legacy implementation globals.
local EW = F2T_EXCHANGE_WALKER
local module_id = "f2ce.exchange_walker"
local context, registered_api, session
local bridge = { core = {}, capture = {}, commands = {}, po = {} }
EW.f2ce = bridge

local function api()
    return F2CE and F2CE.API and F2CE.API.v1
end

function EW.isBlocked()
    if type(getPackages) == "function" then
        for key, value in pairs(getPackages() or {}) do
            local name = type(key) == "string" and key or value
            if tostring(name):lower() == "exchange-walker-live" then return true end
        end
    end
    local legacy = rawget(_G, "ExchangeWalkerLive")
    return type(legacy) == "table" and legacy ~= EW and legacy.NATIVE ~= true
        and not (legacy.ui and legacy.ui.shutting_down == true)
end

function bridge.room()
    local current = api()
    return current and current.data.refresh("room") or nil
end

function bridge.core.ownership()
    local current = api()
    local room = bridge.room()
    local vitals = current and current.data.refresh("vitals")
    local owner = type(room) == "table" and room.owner
    local player = type(vitals) == "table" and vitals.name
    return type(owner) == "string" and owner ~= "" and type(player) == "string"
        and owner:lower() == player:lower(), owner, player
end

function bridge.core.check(options)
    local current = api()
    if not current or not current.exchange then return false, "Built-in F2CE module API is not ready" end
    if EW.isBlocked() then return false, "Remove the standalone exchange-walker-live package before enabling the native module" end
    if EW.settings_error then return false, EW.settings_error end
    local valid, reason = current.validateDependency({ api = ">=1.1.0", f2ce = ">=3.3.0",
        capabilities = { "exchange.capture", "exchange.settings", "commands" } })
    if not valid then return false, tostring(reason) end
    if options and options.gmcp then
        if type(bridge.room()) ~= "table" or type(current.data.refresh("vitals")) ~= "table" then
            return false, "Current room and character GMCP are required"
        end
    end
    return true
end

function bridge.core.capabilities()
    local current = api()
    return { api_version = current and current.version or "missing",
        f2ce_version = current and current.f2ce_version,
        profiles = { capture = { available = current and current.hasCapability("exchange.capture") or false } },
        display = { registration = Mux and type(Mux.registerContent) == "function" or false } }
end

function bridge.capture.cancel()
    local old = session
    session = nil
    if old then return old:release("walker_cancel") end
    return true
end

function bridge.register()
    local current = api()
    local ok, reason = bridge.core.check()
    if not ok then return false, reason end
    if registered_api == current and current.modules.status(module_id) then return true end
    if current.modules.status(module_id) then return false, "Native Walker module ID is already owned" end
    context, reason = current.modules.register({ id = module_id, version = EW.VERSION,
        requires = { api = ">=1.1.0", capabilities = { "exchange.capture", "exchange.settings" } },
        enable = function(new_context) context = new_context end,
        disable = function(_, why)
            EW.cancel(why)
            EW.enabled, EW.plan = false, nil
            EW.refresh()
        end,
        unload = function() bridge.capture.cancel() end,
    })
    if not context then return false, tostring(reason) end
    registered_api = current
    return true
end

function bridge.enable()
    if not api() or not api().character.hasRank("Founder") then return nil, "Founder rank or higher is required" end
    local ready, reason = bridge.register()
    if not ready then return nil, reason end
    context, reason = api().modules.enable(module_id)
    return context, reason and tostring(reason)
end

function bridge.disable(reason)
    bridge.capture.cancel()
    if registered_api then return registered_api.modules.disable(module_id, reason or "walker_off") end
    return true
end

local function acquire(reason)
    if not api() or not api().character.hasRank("Founder") then return nil, "Founder rank or higher is required" end
    if not EW.enabled or EW.isBlocked() then return nil, "Native Exchange Walker is OFF or a standalone instance is present" end
    if session and session:status().active then return session end
    local current = api()
    if current ~= registered_api or not context then return nil, "Native API was reloaded; explicitly re-arm Walker" end
    local why
    session, why = current.exchange.acquire(context, { reason = reason })
    return session, why and tostring(why)
end

local function capture(kind, target, callback)
    if not EW.busy or tostring(target or ""):lower() ~= tostring(EW.capture_target or ""):lower() then
        return false, "Capture does not match the active Walker request"
    end
    local current, why = acquire("Exchange Walker reviewed capture")
    if not current then return false, why end
    local accepted, reason = current:capture(kind, target, function(rows, failure)
        if kind == "production" or failure then bridge.capture.cancel() end
        callback(failure and nil or rows)
    end)
    return accepted == true, reason and tostring(reason)
end

function bridge.capture.exchange(target, callback) return capture("exchange", target, callback) end
function bridge.capture.production(target, callback) return capture("production", target, callback) end
bridge.po.captureExchange = bridge.capture.exchange
bridge.po.captureProduction = bridge.capture.production

function bridge.commands.stockpile(kind, commodity, value, planet)
    local pending = EW.pending_confirmation and EW.pending_confirmation.action
    if not EW.applying or not pending or pending.kind ~= kind or pending.commodity ~= commodity
        or pending.value ~= value or pending.planet ~= planet then
        return false, "Setting does not match the reviewed pending action"
    end
    local current, why = acquire("Exchange Walker explicit reviewed apply")
    if not current then return false, why end
    local sent, reason = current:set({ kind = kind, commodity = commodity, value = value, planet = planet })
    return sent ~= nil, reason and tostring(reason)
end

function bridge.shutdown()
    bridge.capture.cancel()
    if registered_api then registered_api.modules.unregister(module_id, "walker_unload") end
    registered_api, context = nil, nil
end
