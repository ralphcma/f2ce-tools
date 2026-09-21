-- All exchange hauling sales use this guard, not just refused-sale recovery.
-- The next bay requires a new local commodity receipt so a falling bid cannot
-- blindly drain the whole hold. Counted bulk purchases are unchanged.
local function normalized(value) return tostring(value or ""):lower() end
local function room_key()
    local room = gmcp and gmcp.room and gmcp.room.info
    if not room or not room.system or not room.area or room.num == nil then return nil end
    return normalized(room.system) .. "\t" .. normalized(room.area) .. "\t" .. tostring(room.num)
end

function f2t_hauling_cargo_floor()
    local cargo = gmcp and gmcp.char and gmcp.char.ship and gmcp.char.ship.cargo
    if type(cargo) ~= "table" or #cargo == 0 then return nil end
    local floor = 0
    for _, lot in ipairs(cargo) do
        local cost = tonumber(lot.cost)
        if normalized(lot.commodity) ~= normalized(F2T_HAULING_STATE.current_commodity)
            or not cost or cost ~= cost or cost < 0 or cost == math.huge then return nil end
        floor = math.max(floor, cost)
    end
    return floor
end

local function clear_wait(watch)
    if watch.timer then killTimer(watch.timer); watch.timer = nil end
    watch.wait = nil
end

function f2t_hauling_recovery_cleanup()
    local watch = F2T_HAULING_STATE.recovery_watch
    if watch then clear_wait(watch) end
    F2T_HAULING_STATE.recovery_watch = nil
    F2T_HAULING_STATE.sell_recovery = nil
    F2T_HAULING_STATE.recovery_after_sequence = nil
    F2T_HAULING_STATE.recovery_expected_lots = nil
end

local function stop_recovery(message)
    f2t_hauling_recovery_cleanup()
    if message then cecho("\n<red>[hauling]<reset> " .. message .. "\n") end
    f2t_hauling_do_stop()
end

local function finish_recovery()
    local state = F2T_HAULING_STATE
    if state.recovery_watch then clear_wait(state.recovery_watch) end
    state.sell_recovery = nil
    state.recovery_after_sequence = nil
    state.recovery_expected_lots = nil
    cecho("\n<green>[hauling]<reset> Cargo cleared; moving to the next commodity in the saved rotation.\n")
    f2t_hauling_complete_commodity_cycle()
    f2t_hauling_remove_current_commodity()
end

-- Called only from genuine GMCP events registered for an active hauling run.
function f2t_hauling_recovery_observe(kind)
    local state = F2T_HAULING_STATE
    if not state.active then return end
    local key = room_key()
    local watch = state.recovery_watch
    if not watch then watch = {sequence=0, rows={}}; state.recovery_watch = watch end
    if watch.room ~= key then watch.room = key; watch.rows = {} end
    if kind == "full" and key then
        watch.rows = {}
        for name, row in pairs(gmcp.exchange and gmcp.exchange.commodities or {}) do
            if type(row) == "table" then
                watch.sequence = watch.sequence + 1
                watch.rows[normalized(name)] = {bid=tonumber(row.buy) or 0, sequence=watch.sequence, at=os.time()}
            end
        end
    elseif kind == "tick" and key then
        local row = gmcp.exchange and gmcp.exchange.commodity
        if type(row) == "table" and type(row.name) == "string" then
            watch.sequence = watch.sequence + 1
            watch.rows[normalized(row.name)] = {bid=tonumber(row.buy) or 0, sequence=watch.sequence, at=os.time()}
        end
    end
    if watch.wait then watch.wait() end
end

function f2t_hauling_phase_recovery_sell()
    local state = F2T_HAULING_STATE
    if not state.active or state.paused then return end
    local cargo = gmcp and gmcp.char and gmcp.char.ship and gmcp.char.ship.cargo
    if type(cargo) == "table" and #cargo == 0 and state.recovery_expected_lots == 0 then
        finish_recovery()
        return
    end
    local floor = f2t_hauling_cargo_floor()
    if not floor or not state.sell_location then
        stop_recovery("Cargo/cost could not be verified; stopping with cargo preserved.")
        return
    end
    local watch = state.recovery_watch
    if not watch then watch = {sequence=0, rows={}}; state.recovery_watch = watch end
    clear_wait(watch)
    local market = state.exchange_market
    state.current_phase = "waiting_sell_quote"
    local function current()
        return state == F2T_HAULING_STATE and state.active and not state.paused and state.exchange_market == market
            and state.recovery_watch == watch and state.current_phase == "waiting_sell_quote"
    end
    local function next_buyer(reason)
        clear_wait(watch)
        cecho("\n<yellow>[hauling]<reset> " .. reason .. "; trying another buyer with cargo preserved.\n")
        f2t_hauling_find_next_sell_location()
    end
    local function advance()
        if not current() then return end
        local room = gmcp.room.info
        local quote = watch.rows[normalized(state.current_commodity)]
        local live_cargo = gmcp.char.ship.cargo
        if type(live_cargo) ~= "table" then return end
        if state.recovery_expected_lots and #live_cargo ~= state.recovery_expected_lots then return end
        if not quote or watch.room ~= room_key() or os.time() - quote.at > 15
            or normalized(room.area) ~= normalized(state.sell_location.planet)
            or normalized(room.system) ~= normalized(state.sell_location.system)
            or not f2t_has_value(room.flags or {}, "exchange")
            or quote.sequence <= (state.recovery_after_sequence or 0) then return end
        floor = f2t_hauling_cargo_floor()
        if not floor then return end
        if quote.bid ~= quote.bid or quote.bid == math.huge then return end
        if quote.bid <= 0 or quote.bid < floor then
            next_buyer("Local bid is no longer break-even or better")
            return
        end
        clear_wait(watch)
        state.current_phase = "selling"
        state.sell_location.price = quote.bid
        local before = #live_cargo
        local sent_sequence = watch.sequence
        -- Exactly one bay, including at the originally selected buyer.
        f2t_bulk_sell_start(state.current_commodity, 1, function(_, lots, status, _reason, code, receipt)
            if state ~= F2T_HAULING_STATE or not state.active or state.exchange_market ~= market
                or state.recovery_watch ~= watch then return end
            if status == "error" then stop_recovery("Sale order timed out or failed; no automatic retry."); return end
            if lots == 0 and (code == "not_buying" or code == "sale_restricted") then
                if state.paused then
                    state.current_phase = "finding_sell"
                    return
                end
                f2t_hauling_find_next_sell_location()
                return
            end
            local revenue = receipt and tonumber(receipt.revenue)
            if lots ~= 1 or not revenue or revenue ~= revenue or revenue <= 0 or revenue == math.huge then
                stop_recovery("Sale receipt is uncertain; no automatic retry.")
                return
            end
            state.current_commodity_stats.lots_sold = state.current_commodity_stats.lots_sold + 1
            state.current_commodity_stats.total_revenue = state.current_commodity_stats.total_revenue + revenue
            if revenue < floor * 75 then
                stop_recovery("Bid changed before the server executed the sale; stopping remaining cargo.")
                return
            end
            state.recovery_expected_lots = before - 1
            -- Accept the genuine post-order tick even if it preceded the text
            -- sale receipt. Cargo and receipt still must both reconcile.
            state.recovery_after_sequence = sent_sequence
            state.current_phase = "waiting_sell_quote"
            local function settled()
                if not current() or type(gmcp.char.ship.cargo) ~= "table"
                    or #gmcp.char.ship.cargo ~= before - 1 then return end
                clear_wait(watch)
                if before == 1 then
                    finish_recovery()
                else
                    -- Transition honors deferred user/stamina pause before another bay.
                    f2t_hauling_transition("selling")
                end
            end
            watch.wait = settled
            watch.timer = tempTimer(3, function()
                if not current() then return end
                stop_recovery("Sale cargo did not reconcile; stopping without retry.")
            end)
            settled()
        end)
    end
    watch.wait = advance
    watch.timer = tempTimer(3, function()
        if not current() then return end
        next_buyer("Fresh local sale quote unavailable")
    end)
    advance()
end
