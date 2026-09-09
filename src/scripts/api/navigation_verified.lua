-- Bounded semantic re-resolution over native navigation leases. No guessed
-- exits or map edits; customs, death and foreign ownership are not retried.
local API, S = F2CE.API.v1, F2CE.API.v1.services
function API.navigation.verify(context, destination, options)
    options = options or {}
    if not S.live(context) or type(destination) ~= "string" or destination == "" then
        return nil, S.error("E_ARGUMENT", "enabled context and semantic destination required")
    end
    local function bounded(value, default, lower, upper)
        value = tonumber(value) or default
        if value ~= value then value = default end
        return math.max(lower, math.min(upper, value))
    end
    local session = { active = true, attempt = 0, max_attempts = math.floor(bounded(options.max_attempts, 3, 1, 4)),
        timeout = bounded(options.timeout, 180, 15, 600), visits = {}, destination = destination }
    local token, timer, request, lease, room_token, advancing
    local finish, attempt, retry
    local function cancel_timer() if timer then API._adapter.cancelTimer(timer); timer = nil end end
    local function release(reason)
        local old = request; request = nil
        if old then old:cancelImmediate(reason) end
        if lease then lease:release(reason); lease = nil end
    end
    finish = function(ok, reason)
        if not session.active then return end
        session.active, session.success, session.reason = false, ok, tostring(reason)
        cancel_timer(); release(reason)
        if room_token then room_token:cancel() end
        S.forget(context, token)
        if S.live(context) and not session.cancelled then
            local callback = ok and options.on_arrival or options.on_failure
            if callback then pcall(callback, reason, session.attempt) end
        end
    end
    retry = function(reason)
        if not session.active or advancing then return end
        local text = tostring(reason):lower()
        if API.protection.isRecovering() or text:find("custom", 1, true) or text:find("death", 1, true)
            or text:find("stamina", 1, true) or text:find("foreign", 1, true) then return finish(false, reason) end
        advancing = true; cancel_timer(); release(reason); advancing = false
        if session.attempt >= session.max_attempts then return finish(false, "route recovery exhausted: " .. tostring(reason)) end
        if options.on_retry then pcall(options.on_retry, reason, session.attempt + 1) end
        timer = API._adapter.timer(bounded(options.retry_delay, 0.5, 0.1, 2), attempt, false)
        if not timer then finish(false, "route retry timer unavailable") end
    end
    attempt = function()
        timer = nil
        if not session.active or not S.live(context) then return finish(false, "module disabled") end
        if API.protection.isRecovering() then return finish(false, "death recovery is active") end
        session.attempt = session.attempt + 1
        session.visits, session.last_room_id = {}, nil
        local resolved = API.map.resolve(destination)
        session.target_room_id = resolved and resolved.room_id
        if not session.target_room_id then return retry("destination cannot be resolved") end
        local err; lease, err = API.navigation.acquire(context, { reason = "verified route", destination = destination })
        if not lease then return finish(false, tostring(err)) end
        timer = API._adapter.timer(session.timeout, function() retry("route attempt timed out") end, false)
        if not timer then return finish(false, "route timeout unavailable") end
        local started, why = lease:request(destination, {
            interactive = false, suppress_hint = true, compensate_incomplete_map = true,
            on_complete = function()
                if not session.active or advancing then return end
                local current, target = API.navigation.environment(), API.map.resolve(destination)
                local room = API.data.get("room") or {}
                local flags, exchange = room.flags or {}, false
                for key, value in pairs(flags) do if (key == "exchange" and value == true) or value == "exchange" then exchange = true end end
                if target and tonumber(target.room_id) == tonumber(current.room_id)
                    and (not options.require_exchange or exchange) then finish(true, "confirmed authoritative arrival")
                else retry("route ended without authoritative arrival") end
            end,
            on_failure = function(result) if session.active and not advancing then retry(result.reason or "route failed") end end,
            on_interrupt = function(result) finish(false, "navigation interrupted: " .. tostring(result.interruption_reason)) end,
        })
        if started and session.active then request = started
        elseif not started and session.active and not timer then retry(tostring(why)) end
    end
    function session:cancel(reason)
        if not self.active then return true end
        self.cancelled = true
        finish(false, reason or "cancelled"); return true
    end
    function session:status() return { active = self.active, attempt = self.attempt, target_room_id = self.target_room_id, reason = self.reason } end
    token = context:own("verified_navigation", session, function(value) value:cancel("module_cleanup") end)
    room_token = context:on("data.room", function(payload)
        if not session.active or not payload.received then return end
        local current = API.navigation.environment()
        if current.room_id ~= session.last_room_id then
            session.last_room_id = current.room_id
            if current.room_id then
                local count = (session.visits[current.room_id] or 0) + 1
                session.visits[current.room_id] = count
                if count > bounded(options.max_room_visits, 3, 2, 5) then retry("repeated-room navigation loop") end
            end
        end
    end)
    attempt()
    return session
end
