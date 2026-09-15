-- Component-mode food recovery with a bounded in-flight movement handoff.
-- Never sends a literal yes and never starts a second navigation engine.
local API, S = F2CE.API.v1, F2CE.API.v1.services
local P = { client = nil, last_death = false }
API.protection = P
function P.deathState() return API._adapter.deathState and S.copy(API._adapter.deathState()) or nil end
function P.isRecovering() local state = P.deathState(); return state and state.active == true or false end
function P.staminaState() return API._adapter.staminaState and S.copy(API._adapter.staminaState()) or nil end
function P.status()
    local state = P.staminaState()
    if not state then return nil, S.error("E_STAMINA", "F2CE stamina state is unavailable") end
    local threshold = tonumber(API.settings.get("stamina", "threshold"))
    if not threshold or threshold ~= threshold or threshold < 0 or threshold > 99 then
        return nil, S.error("E_STAMINA", "F2CE stamina threshold is unavailable or invalid")
    end
    local vitals = API.data.get("vitals")
    local values = type(vitals) == "table" and vitals.stamina
    local current = type(values) == "table" and tonumber(values.cur) or tonumber(state.current_stamina)
    local maximum = type(values) == "table" and tonumber(values.max) or tonumber(state.max_stamina)
    return { monitoring_active = state.monitoring_active == true, phase = state.current_phase,
        threshold = threshold, current = current, maximum = maximum,
        percent = current and maximum and maximum > 0 and math.floor(current / maximum * 100) or nil,
        handoff_pending = P.client and P.client.handoff ~= nil or false }
end
local Client = {}; Client.__index = Client
function Client:isOwned()
    return P.client == self and self.active and API._adapter.staminaOwns(self.check)
end
function Client:status()
    local status, err = P.status(); if not status then return nil, err end
    status.owned = self:isOwned(); return status
end
function Client:detach()
    if not self.active then return true end
    self.active = false
    if self.handoff and self.handoff.timer then API._adapter.cancelTimer(self.handoff.timer) end
    self.handoff = nil
    API._adapter.staminaUnregister(self.check) -- exact callback only
    if P.client == self then P.client = nil end
    S.forget(self.context, self.token)
    return true
end
function Client:fail(reason)
    self:detach()
    pcall(self.spec.onHandoffFailure, tostring(reason))
    API.events.emit("stamina.handoff_failed", { module_id = self.context.module_id, reason = tostring(reason) })
    return false
end
local function navigation_busy(state)
    return state.active or state.exploring or state.circuit_active or state.owner or API.navigation._lease
end
function Client:pause()
    if not self:isOwned() or not S.live(self.context) then return false end
    if self.handoff then return true end
    local state, lease = API.navigation.environment(), API.navigation._lease
    local waiting = state.waiting == true
    if state.exploring or (state.owner and (not lease or state.owner ~= lease.native_owner))
        or (lease and lease.module_id ~= self.context.module_id)
        or ((state.active or waiting) and not lease) then
        return self:fail("navigation ownership changed before stamina handoff")
    end
    if state.active and type(state.waiting) ~= "boolean" then return self:fail("movement-wait state is unavailable") end
    if waiting and (not state.expected_room_id or not state.before_room_id
        or state.before_room_id == state.expected_room_id) then return self:fail("outstanding movement cannot be confirmed") end
    local receipt = API.data.receipt("room")
    local handoff = waiting and { expected = state.expected_room_id, generation = receipt and receipt.generation or 0, polls = 0 } or nil
    self.handoff = handoff
    local ok, paused = pcall(self.spec.pause)
    if not ok or paused ~= true then return self:fail("client could not pause for stamina refill") end
    if not self:isOwned() then return false end
    if navigation_busy(API.navigation.environment()) then return self:fail("client did not release navigation for stamina refill") end
    local pending_command = API.commands._lease
    if pending_command then
        local may_drain, draining = pcall(self.spec.isSettlingCommands or function() return false end)
        if pending_command.module_id ~= self.context.module_id or not may_drain or draining ~= true then
            return self:fail("unfinished command operation blocks stamina refill")
        end
        -- An already-issued cargo command must finish, not be replayed or
        -- abandoned while food navigation begins. Hold the same bounded gate
        -- used for an outstanding movement receipt; never accept a new lease.
        handoff = handoff or { polls = 0 }
        handoff.command = pending_command
        self.handoff = handoff
    end
    if not handoff then return true end
    local function poll()
        if self.handoff ~= handoff then return end
        handoff.timer = nil
        if not self:isOwned() or not S.live(self.context) or P.isRecovering()
            or navigation_busy(API.navigation.environment()) then return self:fail("authority changed while settling movement") end
        local arrived = API.data.receipt("room")
        local current_command = API.commands._lease
        if current_command and current_command ~= handoff.command then
            return self:fail("command ownership changed while settling stamina handoff")
        end
        local movement_ready = not handoff.expected or (arrived and arrived.generation > handoff.generation
            and arrived.room_id == handoff.expected and API.navigation.environment().room_id == handoff.expected)
        if movement_ready and not current_command then
            self.handoff = nil
            API.events.emit("stamina.handoff_ready", { module_id = self.context.module_id })
            return
        end
        handoff.polls = handoff.polls + 1
        if handoff.polls >= 200 then return self:fail("movement or cargo confirmation timed out before stamina refill (10 seconds)") end
        handoff.timer = API._adapter.timer(0.05, poll, false)
        if not handoff.timer then return self:fail("movement-settle timer unavailable") end
    end
    poll()
    return self:isOwned()
end
function Client:ensure(defer_check)
    if not self.active or P.client ~= self or not S.live(self.context) then return nil, S.error("E_STAMINA", "stamina client authority was lost") end
    local status, err = self:status(); if not status then return nil, err end
    if status.threshold <= 0 then return nil, S.error("E_STAMINA", "stamina auto-eat threshold is disabled") end
    if not status.monitoring_active then return nil, S.error("E_STAMINA", "stamina monitoring is inactive") end
    if status.current and status.current <= 0 then return nil, S.error("E_STAMINA", "stamina is exhausted") end
    if P.isRecovering() then return nil, S.error("E_DEATH", "death recovery is active") end
    if not self:isOwned() then
        local native, nav = P.staminaState(), API.navigation.environment()
        if nav.exploring and native.has_client then status.delegated = "map-exploration"; return status end
        if nav.exploring or native.has_client or API.hauling.status().active then
            return nil, S.error("E_STAMINA", "stamina service has a foreign client")
        end
        if not API._adapter.staminaRegister(self.config) or not self:isOwned() then
            return nil, S.error("E_STAMINA", "stamina protection could not be restored")
        end
        status.reclaimed = true
    end
    if not defer_check then
        local ok, why = pcall(API._adapter.staminaCheck)
        if not ok then return nil, S.error("E_STAMINA", why) end
    end
    local refreshed, failure = self:status()
    if not refreshed then return nil, failure end
    if not refreshed.owned then return nil, S.error("E_STAMINA", "stamina ownership changed during check") end
    refreshed.reclaimed = status.reclaimed
    return refreshed
end
function P.attach(context, spec)
    if not S.live(context) then return nil, S.error("E_MODULE_DISABLED", "enabled protection context required") end
    for _, key in ipairs({ "pause", "resume", "isActive", "onHandoffFailure" }) do
        if type(spec) ~= "table" or type(spec[key]) ~= "function" then return nil, S.error("E_ARGUMENT", "stamina callbacks required") end
    end
    if not API.hasCapability("protection.stamina") then return nil, S.error("E_CAPABILITY", "native stamina service is unavailable") end
    if P.client or API.hauling.status().active then return nil, S.error("E_STAMINA_BUSY", "stamina already owned") end
    local status, err = P.status(); if not status then return nil, err end
    if status.threshold <= 0 then return nil, S.error("E_STAMINA", "enable stamina threshold (1..99) before automation") end
    if P.staminaState().has_client then return nil, S.error("E_STAMINA_BUSY", "foreign native stamina client") end
    local client = setmetatable({ context = context, spec = spec, active = true }, Client)
    P.client = client
    client.check = function()
        if not client.active or not S.live(context) or P.isRecovering() then
            client:fail("protection authority changed"); return true
        end
        if client.handoff then return true end -- hold food trip until real room receipt
        local ok, result = pcall(spec.isActive)
        if not ok then client:fail("activity callback failed"); return true end
        return result == true
    end
    client.config = {
        check_active = client.check,
        pause_callback = function() return client:pause() end,
        resume_callback = function()
            if not client:isOwned() or not S.live(context) or P.isRecovering() then return false end
            if client.handoff then return client:fail("refill completed before movement settled") end
            return spec.resume()
        end,
    }
    client.token = context:own("stamina", client, function(value) value:detach() end)
    local ok, accepted = pcall(API._adapter.staminaRegister, client.config)
    if not ok or accepted ~= true or not client:isOwned() then client:detach(); return nil, S.error("E_STAMINA", "native registration failed") end
    if not status.monitoring_active then API._adapter.staminaStart() end
    -- Publish the handle before a consumer calls ensure(): low stamina can
    -- synchronously invoke a callback that queries/detaches that handle.
    local ready, failure = client:ensure(true)
    if not ready then client:detach(); return nil, failure end
    return client
end
function P.install()
    if P.timer then API._adapter.cancelTimer(P.timer) end
    P.timer = API._adapter.timer(0.25, function()
        local active = P.isRecovering()
        if active ~= P.last_death then
            P.last_death = active
            if active and P.client then P.client:fail("death recovery interrupted activity") end
            API.events.emit(active and "death.started" or "death.completed", P.deathState() or {})
        end
    end, true)
    API._adapter_tokens[#API._adapter_tokens + 1] = { id = P.timer, cancel = API._adapter.cancelTimer }
end
