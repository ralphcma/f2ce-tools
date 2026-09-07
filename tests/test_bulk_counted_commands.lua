local root = tostring(arg and arg[1] or ".")
local sent, callback_result = {}, nil

gmcp = {
  room = { info = { flags = { "exchange" } } },
  char = { ship = { hold = { cur = 225, max = 1050 }, cargo = {} } },
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

F2T_BULK_STATE = { active = false }

dofile(root .. "/src/scripts/commodities/bulk_buy.lua")
dofile(root .. "/src/scripts/commodities/bulk_sell.lua")

local function equal(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
  end
end

local function reset()
  sent, callback_result = {}, nil
  F2T_BULK_STATE = { active = false }
end

local started = f2t_bulk_buy_start("Nanos", nil, function(commodity, lots, status)
  callback_result = { commodity, lots, status }
end)
equal(started, true, "counted buy starts")
equal(#sent, 1, "counted buy sends once")
equal(sent[1], "buy nanos 3", "counted buy uses free bays")
f2t_bulk_buy_success()
f2t_bulk_buy_success()
equal(#sent, 1, "intermediate buy replies do not duplicate command")
f2t_bulk_buy_success()
equal(callback_result[2], 3, "buy callback reports all confirmed bays")
equal(callback_result[3], "success", "buy callback status")

reset()
gmcp.char.ship.cargo = {
  { commodity = "Nanos", cost = 100 },
  { commodity = "Nanos", cost = 100 },
  { commodity = "Nanos", cost = 100 },
}
started = f2t_bulk_sell_start("Nanos", 3, function(commodity, lots, status)
  callback_result = { commodity, lots, status }
end)
equal(started, true, "all-cargo sell starts")
equal(sent[1], "sell cargo", "single-commodity full hold uses sell cargo")
f2t_bulk_sell_success("Nanos", 120, 9000)
f2t_bulk_sell_success("Nanos", 120, 9000)
equal(#sent, 1, "intermediate sale replies do not duplicate command")
f2t_bulk_sell_success("Nanos", 120, 9000)
equal(callback_result[2], 3, "sell callback reports total confirmed bays")
equal(callback_result[3], "success", "sell callback status")

reset()
gmcp.char.ship.cargo = {
  { commodity = "Nanos", cost = 100 },
  { commodity = "Nanos", cost = 100 },
  { commodity = "Nanos", cost = 100 },
  { commodity = "Woods", cost = 100 },
}
started = f2t_bulk_sell_start("Nanos", 2, function() end)
equal(started, true, "partial sell starts")
equal(sent[1], "sell nanos 2", "partial cargo uses bounded counted sell")

print("PASS: counted commodity commands")
