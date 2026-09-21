local root = tostring(arg and arg[1] or ".")
local sent, callback_result = {}, nil

gmcp = {
    room = {info={flags={"exchange"}}},
    char = {ship={hold={cur=225, max=1050}, cargo={}}},
}

function f2t_resolve_commodity(value) return value, false end
function f2t_has_value(values, wanted)
    for _, value in ipairs(values or {}) do if value == wanted then return true end end
    return false
end
function f2t_debug_log() end
function cecho() end
function send(command) sent[#sent + 1] = command end
function f2t_bulk_watchdog_start() end
function f2t_bulk_watchdog_stop() end

F2T_BULK_STATE = {active=false}
dofile(root .. "/src/scripts/commodities/bulk_buy.lua")
dofile(root .. "/src/scripts/commodities/bulk_sell.lua")

local passed, failed = 0, 0
local function equal(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)), 2)
    end
end
local function reset()
    sent, callback_result = {}, nil
    F2T_BULK_STATE = {active=false}
end
local function test(name, callback)
    local ok, reason = pcall(callback)
    if ok then passed = passed + 1; io.write("PASS ", name, "\n")
    else failed = failed + 1; io.stderr:write("FAIL ", name, ": ", tostring(reason), "\n") end
end

test("fill-hold buy sends one counted command and counts replies", function()
    reset()
    gmcp.char.ship.hold = {cur=225, max=1050}
    gmcp.char.ship.cargo = {}
    local started = f2t_bulk_buy_start("Nanos", nil, function(commodity, lots, status)
        callback_result = {commodity, lots, status}
    end)
    equal(started, true, "counted buy starts")
    equal(#sent, 1, "counted buy command count")
    equal(sent[1], "buy nanos 3", "counted buy command")
    f2t_bulk_buy_success()
    f2t_bulk_buy_success()
    equal(#sent, 1, "intermediate buy replies")
    f2t_bulk_buy_success()
    equal(callback_result[2], 3, "confirmed bought bays")
    equal(callback_result[3], "success", "buy callback status")
end)

test("complete single-commodity sale sends sell cargo and counts replies", function()
    reset()
    gmcp.char.ship.cargo = {
        {commodity="Nanos", cost=100}, {commodity="Nanos", cost=100},
        {commodity="Nanos", cost=100},
    }
    local started = f2t_bulk_sell_start("Nanos", 3, function(commodity, lots, status)
        callback_result = {commodity, lots, status}
    end)
    equal(started, true, "all-cargo sell starts")
    equal(#sent, 1, "all-cargo command count")
    equal(sent[1], "sell cargo", "all-cargo command")
    f2t_bulk_sell_success("Nanos", 120, 9000)
    f2t_bulk_sell_success("Nanos", 120, 9000)
    equal(#sent, 1, "intermediate sell replies")
    f2t_bulk_sell_success("Nanos", 120, 9000)
    equal(callback_result[2], 3, "confirmed sold bays")
    equal(callback_result[3], "success", "sell callback status")
end)

test("partial sale stays bounded to commodity and count", function()
    reset()
    gmcp.char.ship.cargo = {
        {commodity="Nanos", cost=100}, {commodity="Nanos", cost=100},
        {commodity="Nanos", cost=100}, {commodity="Woods", cost=100},
    }
    equal(f2t_bulk_sell_start("Nanos", 2, function() end), true, "partial sell starts")
    equal(#sent, 1, "partial sell command count")
    equal(sent[1], "sell nanos 2", "partial sell command")
end)

test("full-hold GMCP before fourteen text receipts cannot finish a counted buy early", function()
    reset(); gmcp.char.ship.hold={cur=1050,max=1050}; gmcp.char.ship.cargo={}
    local completions=0
    f2t_bulk_buy_start("Artifacts",nil,function(_,lots,status,_,_,receipt)
        completions=completions+1; callback_result={lots=lots,status=status,receipt=receipt}
    end)
    gmcp.char.ship.hold.cur=0
    for i=1,14 do gmcp.char.ship.cargo[i]={commodity="Artifacts",cost=100+i} end
    for i=1,13 do
        f2t_bulk_buy_success(7500+75*i)
        equal(completions,0,"all receipts remain necessary even when GMCP says full")
        equal(F2T_BULK_STATE.active,true,"counted buy remains active")
    end
    f2t_bulk_buy_success(8550)
    equal(completions,1,"one final callback"); equal(callback_result.lots,14,"all bought lots")
    equal(callback_result.receipt.count,14,"all cost receipts")
    equal(callback_result.receipt.cost,112875,"sum all varying costs")
    equal(#sent,1,"no duplicate purchase"); equal(sent[1],"buy artifacts 14","one counted buy")
end)

test("missing hold GMCP during replies is not an early completion signal", function()
    reset(); gmcp.char.ship.hold={cur=150,max=1050}
    f2t_bulk_buy_start("Artifacts",2,function(_,lots) callback_result=lots end)
    gmcp.char.ship.hold=nil
    f2t_bulk_buy_success(7500); equal(callback_result,nil,"first receipt waits")
    f2t_bulk_buy_success(7575); equal(callback_result,2,"second receipt completes")
    equal(#sent,1,"missing GMCP cannot duplicate purchase")
end)

local function sale(count, callback)
    gmcp.char.ship.cargo={}
    for _=1,count+1 do table.insert(gmcp.char.ship.cargo,{commodity="Libraries",cost=400}) end
    return f2t_bulk_sell_start("Libraries",count,callback or function(_,lots,status,_,code,receipt)
        callback_result={lots=lots,status=status,code=code,receipt=receipt}
    end)
end
local function customs(line, continuation)
    matches={line}
    dofile(root .. "/src/triggers/commodities/" .. (continuation and "sell_customs_continuation" or "sell_customs") .. ".lua")
end
local function receipt(line, commodity, gross)
    matches={line,commodity or "Libraries",gross or "49425"}
    dofile(root .. "/src/triggers/commodities/sell_success.lua")
end
local tax_line="The Candy cartel deducts 11,430ig customs from the 49,425ig sale proceeds, leaving 37,995ig net."
local sold_line="75 tons of Libraries sold for 49425ig from your ship"

test("reported Candy customs and short sale receipt count one net sale", function()
    reset(); sale(1); customs(tax_line)
    equal(callback_result,nil,"customs is not a sale confirmation")
    equal(F2T_BULK_STATE.remaining,1,"customs cannot decrement bays")
    receipt(sold_line)
    equal(callback_result.lots,1,"one confirmed bay"); equal(callback_result.status,"success","sale recognized")
    equal(callback_result.receipt.revenue,37995,"net revenue not gross")
    equal(callback_result.receipt.gross_revenue,49425,"gross retained for deduction estimates")
    equal(sent[1],"sell libraries 1","one sale"); equal(#sent,1,"no retry")
    receipt(sold_line); equal(callback_result.lots,1,"late duplicate ignored after completion")
    equal(F2T_BULK_STATE.sale_customs,nil,"tax capture cleared")
end)

test("legacy sale receipt without customs retains its full proceeds", function()
    reset(); sale(1)
    receipt("75 tons of Libraries sold to the exchange for 49,425ig from your ship","Libraries","49,425")
    equal(callback_result.receipt.revenue,49425,"untaxed proceeds")
end)

test("server-wrapped customs notice pairs with the following sale", function()
    reset(); sale(1)
    customs("The Candy cartel deducts 11,430ig customs from the 49,425ig sale proceeds, leaving")
    equal(callback_result,nil,"incomplete notice waits")
    customs(" 37,995ig net.",true); receipt(sold_line)
    equal(callback_result.receipt.revenue,37995,"wrapped net")
end)

test("counted sale applies each customs notice only to its own receipt", function()
    reset(); sale(2); customs(tax_line); receipt(sold_line)
    equal(callback_result,nil,"second bay still pending")
    receipt(sold_line)
    equal(callback_result.lots,2,"both receipts")
    equal(callback_result.receipt.revenue,87420,"one taxed and one untaxed receipt")
    equal(callback_result.receipt.gross_revenue,98850,"gross accumulation")
    equal(#sent,1,"one counted command")
end)

test("invalid customs arithmetic stops without retry or gross accounting", function()
    reset(); sale(1)
    customs(tax_line:gsub("37,995","37,994"))
    equal(callback_result.status,"error","invalid tax fails closed")
    equal(callback_result.code,"invalid_receipt","specific failure")
    equal(callback_result.lots,0,"customs is not an acknowledgement")
    equal(#sent,1,"no retry"); equal(F2T_BULK_STATE.sale_customs,nil,"capture cleared")
end)

test("incomplete customs cannot silently account the later gross as net", function()
    reset(); sale(1); customs("The Candy cartel deducts 11,430ig customs from the")
    receipt(sold_line)
    equal(callback_result.status,"error","missing net stops")
    equal(callback_result.receipt.revenue,0,"no gross fallback"); equal(#sent,1,"no retry")
end)

test("mismatched customs gross or commodity cannot confirm an order", function()
    for _,kind in ipairs({"gross","commodity"}) do
        reset(); sale(1); customs(tax_line)
        receipt(sold_line,kind=="commodity" and "Artifacts" or "Libraries",kind=="gross" and "49000" or "49425")
        equal(callback_result.status,"error","mismatch stops"); equal(callback_result.lots,0,"no false confirmation")
        equal(#sent,1,"no duplicate")
    end
end)

test("customs alone still times out and cannot leak into another order", function()
    reset(); sale(1); customs(tax_line); f2t_bulk_sell_error("timeout","timeout")
    equal(callback_result.status,"error","customs did not confirm sale")
    equal(F2T_BULK_STATE.sale_customs,nil,"timeout clears capture")
    sale(1); receipt(sold_line); equal(callback_result.receipt.revenue,49425,"new order is untaxed")
end)

test("customs outside a sell and stray continuation lines do nothing", function()
    reset(); customs(tax_line); equal(F2T_BULK_STATE.sale_customs,nil,"idle ignores customs")
    F2T_BULK_STATE.active=true; F2T_BULK_STATE.command="buy"
    customs(tax_line); equal(F2T_BULK_STATE.sale_customs,nil,"buy ignores customs")
    sale(1); customs("37,995ig net.",true); receipt(sold_line)
    equal(callback_result.receipt.revenue,49425,"no unrelated continuation capture")
end)

test("ambiguous duplicate customs stops a queue without selling the next commodity", function()
    reset(); gmcp.char.ship.cargo={{commodity="Libraries",cost=400},{commodity="Artifacts",cost=200}}
    f2t_bulk_sell_start(nil,nil,function(_,lots,status,_,code) callback_result={lots=lots,status=status,code=code} end)
    customs(tax_line); customs(tax_line)
    equal(callback_result.status,"error","queue fails closed")
    equal(callback_result.lots,0,"no sale confirmation"); equal(#sent,1,"no next-commodity order")
end)

test("valid zero net customs is recorded instead of falling back to gross", function()
    reset(); sale(1)
    customs("The Candy cartel deducts 49,425ig customs from the 49,425ig sale proceeds, leaving 0ig net.")
    receipt(sold_line); equal(callback_result.receipt.revenue,0,"zero net is real")
    equal(callback_result.status,"success","valid sale acknowledged")
end)

io.write(string.format("RESULT %d passed, %d failed\n", passed, failed))
if failed > 0 then os.exit(1) end
