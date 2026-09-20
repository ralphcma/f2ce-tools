-- Exercise real bulk callbacks, refusal trigger bodies and exchange phases.
local root = tostring(arg and arg[1] or ".")
local sent, timers, navigated, output, queries, removed, stopped, analysis, deferred, pending
local passed, failed = 0, 0
local function equal(actual, expected, label)
    if actual ~= expected then error((label or "value") .. ": expected " .. tostring(expected)
        .. ", got " .. tostring(actual), 2) end
end
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed=passed+1; print("PASS " .. name)
    else failed=failed+1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
function f2t_debug_log() end
function f2t_settings_register() end
function f2t_register_help() end
function cecho(message) output[#output+1] = message end
function send(command) sent[#sent+1] = command end
function tempTimer(seconds, callback)
    local timer = {seconds=seconds, callback=callback}
    timers[timer] = true
    return timer
end
function killTimer(timer) timers[timer] = nil end
function f2t_resolve_commodity(value) return value, false end
function f2t_has_value(values, wanted)
    for _, value in ipairs(values) do if value == wanted then return true end end
    return false
end
function f2t_map_brief_hold_release() end
function f2t_price_check_commodity(commodity, callback)
    queries = queries + 1
    if deferred then pending=callback else callback(commodity, {}, analysis) end
end
dofile(root .. "/src/scripts/commodities/init.lua")
dofile(root .. "/src/scripts/commodities/bulk_buy.lua")
dofile(root .. "/src/scripts/commodities/bulk_sell.lua")
dofile(root .. "/src/scripts/hauling/state_machine.lua")
dofile(root .. "/src/scripts/hauling/exchange_phases.lua")
function f2t_hauling_do_stop()
    stopped=stopped+1
    F2T_HAULING_STATE.active=false
    F2T_HAULING_STATE.exchange_market=nil
end
function f2t_hauling_stop() f2t_hauling_do_stop() end
function f2t_hauling_remove_current_commodity() removed=removed+1 end
function f2t_hauling_phase_navigate_to_buy()
    navigated[#navigated+1]=F2T_HAULING_STATE.buy_location.planet
end
function f2t_hauling_phase_navigate_to_sell()
    navigated[#navigated+1]=F2T_HAULING_STATE.sell_location.planet
end
local function row(planet, price, system) return {planet=planet, price=price, system=system or "System"} end
local function cargo(count)
    gmcp.char.ship.cargo={}
    for _=1,count do table.insert(gmcp.char.ship.cargo, {commodity="NanoFabrics", cost=100, origin="Supplier A"}) end
    gmcp.char.ship.hold={cur=225-count*75, max=225}
end
local function reset()
    sent, timers, navigated, output, queries, removed, stopped = {}, {}, {}, {}, 0, 0, 0
    deferred, pending=false, nil
    analysis={top_sell={row("Supplier A",100),row("Supplier B",105)},
        top_buy={row("Buyer A",200),row("Buyer B",190)}, profit=100}
    F2T_BULK_STATE={active=false}
    F2T_HAULING_STATE={active=true, paused=false, current_commodity="NanoFabrics",
        current_phase="buying", margin_threshold_pct=40, commodity_cycles=0, sell_attempts=0,
        actual_cost=100, current_commodity_stats={lots_bought=0,total_cost=0,lots_sold=0,total_revenue=0}}
    gmcp={room={info={flags={"exchange"}}},char={ship={}}}
    cargo(0)
    f2t_hauling_get_commodity_details("NanoFabrics")
    equal(queries,1,"initial market query")
    navigated={}
end
local function trigger(name) dofile(root .. "/src/triggers/commodities/" .. name .. ".lua") end
local function buy() F2T_HAULING_STATE.current_phase="buying"; f2t_hauling_phase_buy() end
local function sell() F2T_HAULING_STATE.current_phase="selling"; f2t_hauling_phase_sell() end
local function no_timer() equal(next(timers),nil,"watchdog cancelled") end

test("unavailable supplier advances immediately without another price poll", function()
    reset(); buy(); trigger("buy_error_not_selling")
    equal(navigated[1],"Supplier B"); equal(queries,1); equal(stopped,0)
    equal(sent[1],"buy nanofabrics 3"); equal(#sent,1); no_timer()
end)
test("not-buying refusal advances immediately without reselecting first buyer", function()
    reset(); cargo(3); sell(); trigger("sell_error_not_buying")
    equal(navigated[1],"Buyer B"); equal(queries,1); equal(#sent,1)
    equal(sent[1],"sell cargo"); equal(#gmcp.char.ship.cargo,3); no_timer()
end)
test("Galactic Administration refusal bypasses the watchdog", function()
    reset(); cargo(3); sell(); trigger("sell_error_restricted")
    equal(navigated[1],"Buyer B"); equal(queries,1); equal(stopped,0); no_timer()
end)
test("partial buy followed by refusal delivers its confirmed cargo", function()
    reset(); buy(); cargo(1); f2t_bulk_buy_success(); trigger("buy_error_not_selling")
    equal(navigated[1],"Buyer A"); equal(#sent,1)
    equal(F2T_HAULING_STATE.current_commodity_stats.lots_bought,1)
    equal(F2T_HAULING_STATE.current_commodity_stats.total_cost,7500); no_timer()
end)
test("partial sale followed by restriction keeps remainder and records sold lots", function()
    reset(); cargo(3); sell(); cargo(2); f2t_bulk_sell_success("NanoFabrics",200,15000)
    trigger("sell_error_restricted")
    equal(navigated[1],"Buyer B"); equal(#gmcp.char.ship.cargo,2)
    equal(F2T_HAULING_STATE.current_commodity_stats.lots_sold,1)
    equal(F2T_HAULING_STATE.current_commodity_stats.total_revenue,15000); no_timer()
end)
test("reordered refreshed prices never revisit either rejected buyer", function()
    reset(); cargo(3); sell(); trigger("sell_error_not_buying")
    analysis.top_buy={row("buyer b",210),row("Buyer A",200),row("Buyer C",180)}
    sell(); trigger("sell_error_not_buying")
    equal(queries,2); equal(#navigated,2); equal(navigated[2],"Buyer C"); no_timer()
end)
test("exhausted suppliers skip commodity after just one refresh", function()
    reset(); buy(); trigger("buy_error_not_selling"); buy(); trigger("buy_error_not_selling")
    equal(queries,2); equal(removed,1); equal(stopped,0); equal(#navigated,1); no_timer()
end)
test("exhausted buyers stop with cargo intact rather than retry or jettison", function()
    reset(); cargo(3); sell(); trigger("sell_error_not_buying"); sell(); trigger("sell_error_restricted")
    equal(queries,2); equal(stopped,1); equal(removed,0); equal(#gmcp.char.ship.cargo,3)
    equal(#sent,2); no_timer()
end)
test("alternative supplier still has to meet the configured margin", function()
    reset(); F2T_HAULING_STATE.exchange_market.buy[2].price=180
    analysis.top_sell[2].price=180
    buy(); trigger("buy_error_not_selling")
    equal(#navigated,0); equal(removed,1); equal(queries,2)
end)
test("alternative buyer still has to meet the configured margin", function()
    reset(); F2T_HAULING_STATE.exchange_market.sell[2].price=110
    analysis.top_buy[2].price=110
    cargo(3); sell(); trigger("sell_error_restricted")
    equal(#navigated,0); equal(stopped,1); equal(#gmcp.char.ship.cargo,3)
end)
test("invalid price response stops cleanly instead of indexing nil", function()
    reset(); analysis=nil
    f2t_hauling_get_commodity_details("NanoFabrics")
    equal(stopped,1); equal(#navigated,0)
end)
test("refused supplier remains excluded during repeat commodity details", function()
    reset(); buy(); trigger("buy_error_not_selling")
    f2t_hauling_get_commodity_details("NanoFabrics")
    equal(F2T_HAULING_STATE.buy_location.planet,"Supplier B")
end)
test("empty refreshed side cannot retain old commodity locations", function()
    reset(); analysis.top_sell={}
    f2t_hauling_get_commodity_details("NanoFabrics")
    equal(F2T_HAULING_STATE.buy_location,nil); equal(removed,1); equal(#navigated,0)
end)
test("late alternative-price reply cannot resume a stopped run", function()
    reset(); cargo(3); sell(); trigger("sell_error_not_buying")
    deferred=true; sell(); trigger("sell_error_restricted"); local reply=pending
    f2t_hauling_do_stop(); F2T_HAULING_STATE.active=true
    analysis.top_buy={row("Buyer C",200)}; reply("NanoFabrics",{},analysis)
    equal(#navigated,1); equal(#sent,2)
end)
test("pause requested at refusal prevents navigation until explicit resume", function()
    reset(); buy(); F2T_HAULING_STATE.pause_requested=true; trigger("buy_error_not_selling")
    equal(F2T_HAULING_STATE.paused,true); equal(#navigated,0)
    equal(F2T_HAULING_STATE.current_phase,"navigating_to_buy")
    F2T_HAULING_STATE.paused=false; f2t_hauling_transition(F2T_HAULING_STATE.current_phase)
    equal(navigated[1],"Supplier B")
end)
test("paused alternative refresh resumes without repeating rejected purchase", function()
    reset(); buy(); trigger("buy_error_not_selling")
    deferred=true; buy(); trigger("buy_error_not_selling")
    F2T_HAULING_STATE.paused=true
    analysis.top_sell={row("Supplier C",105)}; pending("NanoFabrics",{},analysis)
    equal(#navigated,1); equal(F2T_HAULING_STATE.current_phase,"finding_buy")
    deferred=false; F2T_HAULING_STATE.paused=false
    f2t_hauling_transition("finding_buy"); equal(navigated[2],"Supplier C"); equal(#sent,2)
end)
test("graceful stop never starts another supplier trip", function()
    reset(); buy(); F2T_HAULING_STATE.stopping=true; trigger("buy_error_not_selling")
    equal(stopped,1); equal(#navigated,0); equal(queries,1)
end)
test("timed-out partial buy stops without treating partial results as permission", function()
    reset(); buy(); cargo(1); f2t_bulk_buy_success()
    local timer=F2T_BULK_STATE.watchdogTimerId; timers[timer]=nil; timer.callback()
    equal(stopped,1); equal(#navigated,0); equal(#sent,1); equal(#gmcp.char.ship.cargo,1)
end)
test("timed-out sell stops without attempting another buyer", function()
    reset(); cargo(3); sell()
    local timer=F2T_BULK_STATE.watchdogTimerId; timers[timer]=nil; timer.callback()
    equal(stopped,1); equal(#navigated,0); equal(#sent,1); equal(#gmcp.char.ship.cargo,3)
end)
test("mixed-cargo watchdog aborts queue without sending its next sale", function()
    reset(); cargo(2); gmcp.char.ship.cargo[2].commodity="Woods"
    local result
    f2t_bulk_sell_start(nil,nil,function(_,_,status,reason,code) result={status,reason,code} end)
    local timer=F2T_BULK_STATE.watchdogTimerId; timers[timer]=nil; timer.callback()
    equal(#sent,1); equal(result[1],"error"); equal(result[3],"timeout")
end)
test("manual bulk callbacks retain refusal reason and reset before reentry", function()
    reset(); local result
    f2t_bulk_buy_start("NanoFabrics",1,function(_,lots,status,reason,code)
        result={lots,status,reason,code}
        equal(F2T_BULK_STATE.active,false)
        f2t_bulk_buy_start("Woods",1,function() end)
    end)
    trigger("buy_error_not_selling")
    equal(result[1],0); equal(result[2],"failed"); equal(result[4],"not_selling")
    equal(F2T_BULK_STATE.error_code,nil); equal(F2T_BULK_STATE.commodity,"Woods")
end)
test("unsolicited refusal cannot move inactive automation", function()
    reset(); F2T_HAULING_STATE.active=false
    trigger("buy_error_not_selling"); trigger("sell_error_not_buying"); trigger("sell_error_restricted")
    equal(#sent,0); equal(#navigated,0)
end)
test("commodity change does not blacklist the planet for other goods", function()
    reset(); buy(); trigger("buy_error_not_selling")
    F2T_HAULING_STATE.current_commodity="Woods"
    f2t_hauling_get_commodity_details("Woods")
    equal(F2T_HAULING_STATE.buy_location.planet,"Supplier A")
end)
test("same planet name in a different system is a distinct alternative", function()
    reset(); F2T_HAULING_STATE.exchange_market.buy={row("Supplier A",100),row("Supplier A",100,"Other")}
    buy(); trigger("buy_error_not_selling")
    equal(F2T_HAULING_STATE.buy_location.system,"Other"); equal(queries,1)
end)
test("late reply for the previous commodity cannot overwrite new route", function()
    reset(); deferred=true; f2t_hauling_get_commodity_details("NanoFabrics"); local reply=pending
    F2T_HAULING_STATE.current_commodity="Woods"; deferred=false
    f2t_hauling_get_commodity_details("Woods"); local before=#navigated
    reply("NanoFabrics",{},{top_sell={row("Stale",100)},top_buy={row("Stale Buyer",200)}})
    equal(#navigated,before); equal(F2T_HAULING_STATE.buy_location.planet,"Supplier A")
end)
test("existing cargo refusal does not jettison it to make room for purchases", function()
    reset(); cargo(3); buy(); trigger("sell_error_restricted")
    equal(stopped,1); equal(#sent,1); equal(#gmcp.char.ship.cargo,3)
end)
test("dump watchdog cannot navigate or jettison uncertain cargo", function()
    reset(); cargo(3); f2t_hauling_phase_dump_cargo()
    local timer=F2T_BULK_STATE.watchdogTimerId; timers[timer]=nil; timer.callback()
    equal(stopped,1); equal(#navigated,0); equal(#sent,1); equal(#gmcp.char.ship.cargo,3)
end)
print(string.format("RESULT %d passed, %d failed",passed,failed))
if failed > 0 then os.exit(1) end
