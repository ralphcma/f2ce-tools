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

io.write(string.format("RESULT %d passed, %d failed\n", passed, failed))
if failed > 0 then os.exit(1) end
