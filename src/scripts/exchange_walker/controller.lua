-- SPDX-License-Identifier: GPL-2.0-only
-- Copyright (C) 2026 Exchange Walker Live contributors
-------------------------------------------------------------------------------
-- Exchange Walker native F2CE module
-- Ported from Exchange Walker Live 3.3.3 (e7276b81); GPL notices retained.
--
-- Configurable local/remote owner stockpile planner. Gameplay operations use the built-in F2CE.API.v1 exchange service.
-- Muxlet owns the settings window and content lifecycle.
-- Loading and reconnecting always return to OFF. Preview sends only the F2CE
-- display commands; apply is a separate explicit action and advances only after
-- each expected server acknowledgement.
-------------------------------------------------------------------------------

local previous = rawget(_G, "F2T_EXCHANGE_WALKER")
if type(previous) == "table" and type(previous.shutdown) == "function" then previous.shutdown() end
local EW = { NATIVE = true }
F2T_EXCHANGE_WALKER = EW

EW.VERSION = "3.4.0-native.6"
EW.API_CONTRACT = "ExchangeWalkerLive/1.0"
EW.MIN_F2CE_VERSION = "3.3.0"
EW.enabled = false
EW.busy = false
EW.applying = false
EW.plan = nil
EW.plan_max_age_seconds = 120
EW.apply_progress_interval = 10
EW.command_spacing_seconds = 0.20
EW.confirmation_timeout_seconds = 6
EW.pending_confirmation = nil
EW.apply_index = nil
EW.capture_target = nil
EW.operation_mode = "manual"
EW.runtime = { trigger_ids = {}, handler_ids = {}, alias_id = nil }
EW.events = { subscribers = {}, next_id = 0 }
EW.settings = {
  interval_minutes = 30,
  surplus_spread = 40,
  breakeven_spread = 6,
  deficit_spread = 6,
  deficit_min = 0,
  deficit_max = 0,
  breakeven_min = 0,
  breakeven_max = 0,
  growth_buffer = 1000,
  reserve_trigger = 10000,
  reserve_min = 10000,
  reserve_max = 20000,
  targets = {},
  excluded_commodities = {},
}
EW.scheduler = {
  enabled = false, running = false, timer_id = nil,
  targets = {}, index = 0, completed = 0, failures = 0,
}
EW.ui = {
  content_id = "exchange_walker_live",
  preferred_pane_id = "pane_15",
  preferred_pane_start = 15,
  preferred_pane_end = 32,
  registered = false,
  registered_target = nil,
  placement_timer = nil,
  placement_attempt = 0,
  placement_attempt_limit = 20,
  instances = {},
  instance_counter = 0,
  history = {},
  history_limit = 600,
  shutting_down = false,
}

local function normalized(value)
  return string.lower(tostring(value or ""))
end

local function finite_number(value)
  local number = tonumber(value)
  if number == nil or number ~= number or number == math.huge or number == -math.huge then
    return nil
  end
  return number
end

local function trimmed(value)
  return tostring(value or ""):match("^%s*(.-)%s*$"):gsub("%s+", " ")
end

local function safe_planet(value)
  local text = trimmed(value)
  if text == "" or #text > 80 or text:find("[%c;|]")
      or not text:match("^[%w][%w%s%'%-%.]*$") then return nil end
  return text
end

local function copy_targets(values)
  local result, seen = {}, {}
  for _, value in ipairs(type(values) == "table" and values or {}) do
    local planet = safe_planet(value)
    local key = planet and normalized(planet) or nil
    if key and not seen[key] then seen[key], result[#result + 1] = true, planet end
  end
  table.sort(result, function(left, right) return normalized(left) < normalized(right) end)
  return result
end

local function copy_exclusions(values)
  local result, seen = {}, {}
  for _, value in ipairs(type(values) == "table" and values or {}) do
    local commodity = safe_planet(value)
    local key = commodity and normalized(commodity) or nil
    if key and not seen[key] then seen[key], result[#result + 1] = true, commodity end
  end
  table.sort(result, function(left, right) return normalized(left) < normalized(right) end)
  return result
end

local setting_keys = {
  "interval_minutes", "surplus_spread", "breakeven_spread", "deficit_spread",
  "deficit_min", "deficit_max", "breakeven_min", "breakeven_max",
  "growth_buffer", "reserve_trigger", "reserve_min", "reserve_max",
}

local function validate_settings(candidate)
  local clean = { targets = copy_targets(candidate.targets),
    excluded_commodities = copy_exclusions(candidate.excluded_commodities) }
  for _, key in ipairs(setting_keys) do
    local value = finite_number(candidate[key])
    if value == nil or value ~= math.floor(value) then return nil, key .. " must be an integer" end
    clean[key] = value
  end
  if clean.interval_minutes < 5 or clean.interval_minutes > 1440 then
    return nil, "interval_minutes must be between 5 and 1440"
  end
  if clean.surplus_spread < 6 or clean.surplus_spread > 40
      or clean.breakeven_spread < 6 or clean.breakeven_spread > 40
      or clean.deficit_spread < 6 or clean.deficit_spread > 40 then
    return nil, "deficit, breakeven, and surplus spreads must be between 6 and 40"
  end
  if clean.deficit_min < 0 or clean.deficit_min > 10000 or clean.deficit_max < clean.deficit_min
      or clean.deficit_max > 20000 then
    return nil, "deficit limits must satisfy 0 <= min <= 10000 and min <= max <= 20000"
  end
  if clean.breakeven_min < 0 or clean.breakeven_min > 10000
      or clean.breakeven_max < clean.breakeven_min
      or clean.breakeven_max > 20000 then
    return nil, "breakeven limits must satisfy 0 <= min <= 10000 and min <= max <= 20000"
  end
  if clean.growth_buffer < 0 or clean.growth_buffer > 10000 then
    return nil, "growth_buffer must be between 0 and 10000"
  end
  if clean.reserve_trigger < 0 or clean.reserve_trigger > 10000 then
    return nil, "reserve_trigger must be between 0 and 10000"
  end
  if clean.reserve_min < 0 or clean.reserve_min > 10000
      or clean.reserve_max < 0 or clean.reserve_max > 20000
      or clean.reserve_min > clean.reserve_max then
    return nil, "reserve limits must satisfy 0 <= min <= 10000 and min <= max <= 20000"
  end
  if clean.reserve_trigger + clean.growth_buffer > 20000 then
    return nil, "reserve_trigger plus growth_buffer cannot exceed 20000"
  end
  return clean
end

-- Configuration is registered/persisted by settings.lua in Muxlet Settings.
EW.policy = { validate = validate_settings, keys = setting_keys,
  safePlanet = safe_planet, copyTargets = copy_targets, copyExclusions = copy_exclusions }

local function current_room_identity()
  local info = EW.f2ce.room()
  if type(info) ~= "table" then return nil end
  return table.concat({
    tostring(info.id or ""), tostring(info.mapId or ""),
    tostring(info.system or ""), tostring(info.area or ""),
    tostring(info.num or ""),
  }, "|")
end

local function current_planet_name()
  local info = EW.f2ce.room()
  if type(info) ~= "table" then return "Current planet" end
  return tostring(info.area or info.name or "Current planet")
end

local function emit(event_name, payload)
  local listeners = EW.events.subscribers[event_name]
  if type(listeners) ~= "table" then return end
  for _, callback in pairs(listeners) do pcall(callback, payload or {}) end
end

local function main_notice(color, message)
  if type(cecho) == "function" then
    cecho(string.format("\n<%s>[Exchange Walker]<reset> %s\n", color, message))
  end
end

local function console_write(console, markup)
  if type(console) ~= "table" then return false end
  if type(console.cecho) == "function" then return pcall(console.cecho, console, markup .. "\n") end
  if type(console.echo) == "function" then
    local plain = tostring(markup):gsub("<[^>]+>", "")
    return pcall(console.echo, console, plain .. "\n")
  end
  return false
end

function EW.ui.append(markup)
  markup = tostring(markup or "")
  EW.ui.history[#EW.ui.history + 1] = markup
  while #EW.ui.history > EW.ui.history_limit do table.remove(EW.ui.history, 1) end
  local routed = false
  for _, instance in pairs(EW.ui.instances) do
    routed = console_write(instance.console, markup) or routed
  end
  return routed
end

function EW.ui.clear()
  EW.ui.history = {}
  for _, instance in pairs(EW.ui.instances) do
    if instance.console and type(instance.console.clear) == "function" then
      pcall(instance.console.clear, instance.console)
    end
  end
end

function EW.ui.replace(lines)
  EW.ui.clear()
  local routed = false
  for _, line_text in ipairs(lines or {}) do routed = EW.ui.append(line_text) or routed end
  if not routed and type(cecho) == "function" then
    cecho("\n" .. table.concat(lines or {}, "\n") .. "\n")
  end
  return routed
end

local function notice(color, message)
  local markup = string.format("<%s>[Exchange Walker]<reset> %s", color, message)
  local routed = EW.ui.append(markup)
  if not routed or color == "red" or color == "yellow" then main_notice(color, message) end
end

local function cancel_timer(field)
  if EW[field] then
    if type(killTimer) == "function" then pcall(killTimer, EW[field]) end
    EW[field] = nil
  end
end

local function state_payload()
  return {
    version = EW.VERSION, api_contract = EW.API_CONTRACT,
    enabled = EW.enabled, busy = EW.busy, applying = EW.applying,
    planet = EW.plan and EW.plan.planet or nil,
    action_count = EW.plan and #EW.plan.actions or 0,
    plan_applied = EW.plan and EW.plan.applied == true or false,
    scheduler_enabled = EW.scheduler.enabled, scheduler_running = EW.scheduler.running,
    interval_minutes = EW.settings.interval_minutes,
    targets = copy_targets(EW.settings.targets),
    excluded_commodities = copy_exclusions(EW.settings.excluded_commodities),
  }
end

local function update_ui()
  if EW.ui.updateTable then
    local ok, reason = pcall(EW.ui.updateTable)
    if not ok and EW.ui.render_error ~= tostring(reason) then
      main_notice("red", "Board display failed; controls and saved settings remain independent: " .. tostring(reason))
    end
    EW.ui.render_error = not ok and tostring(reason) or nil
  end
  local state = EW.enabled and "ON" or "OFF"
  local activity = EW.applying and "APPLYING" or (EW.busy and "CAPTURING" or "IDLE")
  local plan_text = EW.plan and string.format("%d changes", #EW.plan.actions) or "no plan"
  local auto_text = EW.scheduler.enabled and (EW.scheduler.running and "AUTO RUNNING" or "AUTO WAITING") or "AUTO OFF"
  for _, instance in pairs(EW.ui.instances) do
    local controls = instance.controls
    if controls and controls.status and type(controls.status.echo) == "function" then
      pcall(controls.status.echo, controls.status,
        string.format("<center>Exchange Walker %s | %s | %s | %s</center>",
          state, activity, auto_text, plan_text))
    end
    if controls and controls.toggle and type(controls.toggle.echo) == "function" then
      pcall(controls.toggle.echo, controls.toggle,
        string.format("<center>%s</center>", EW.enabled and "OFF" or "ON"))
    end
    if controls and controls.auto and type(controls.auto.echo) == "function" then
      pcall(controls.auto.echo, controls.auto,
        string.format("<center>%s</center>", EW.scheduler.enabled and "AUTO OFF" or "AUTO ON"))
    end
  end
  emit("state.changed", state_payload())
end

local schedule_next_cycle

local function destroy_widget(widget)
  if type(widget) ~= "table" then return end
  if type(widget.hide) == "function" then pcall(widget.hide, widget) end
  if type(widget.delete) == "function" then pcall(widget.delete, widget) end
end

local function create_label(parent, name, x, y, width, height, text, color, callback, tooltip)
  local label = Geyser.Label:new({ name = name, x = x, y = y, width = width, height = height }, parent)
  if type(label.setStyleSheet) == "function" then
    label:setStyleSheet(string.format([[
      QLabel { background-color: %s; color: white; border: 1px solid #737884;
        padding: 2px; font-weight: bold; }
      QLabel:hover { border: 1px solid white; }
    ]], color))
  end
  if type(label.echo) == "function" then label:echo("<center>" .. text .. "</center>") end
  if callback and type(label.setClickCallback) == "function" then label:setClickCallback(callback) end
  if tooltip and type(label.setToolTip) == "function" then label:setToolTip(tooltip) end
  if type(label.show) == "function" then label:show() end
  return label
end

local function current_ew()
  local value = rawget(_G, "F2T_EXCHANGE_WALKER")
  return type(value) == "table" and value or nil
end

local function dynamic_call(method)
  return function()
    local current = current_ew()
    if current and type(current[method]) == "function" then return current[method]() end
  end
end

local function build_mux_content(target)
  if EW.ui.buildTable then return EW.ui.buildTable(target) end
  if target.contentBg and type(target.contentBg.hide) == "function" then
    pcall(target.contentBg.hide, target.contentBg)
  end
  EW.ui.instance_counter = EW.ui.instance_counter + 1
  local prefix = "ExchangeWalkerLiveMux" .. tostring(EW.ui.instance_counter)
  local controls = {}
  controls.status = create_label(target.content, prefix .. "Status", 0, 0, "100%", 24,
    "Exchange Walker OFF | IDLE | no plan", "#252936", nil,
    "Current Exchange Walker lifecycle and preview state.")
  controls.toggle = create_label(target.content, prefix .. "Toggle", "0%", 26, "14%", 26,
    "ON", "#166534", dynamic_call("toggle"), "Arm or disarm Exchange Walker.")
  controls.preview = create_label(target.content, prefix .. "Preview", "14%", 26, "14%", 26,
    "PREVIEW", "#24558a", dynamic_call("preview"),
    "Capture display exchange and display production through F2CE Tools.")
  controls.apply = create_label(target.content, prefix .. "Apply", "28%", 26, "14%", 26,
    "APPLY", "#714018", dynamic_call("apply"), "Apply the reviewed unexpired plan once.")
  controls.auto = create_label(target.content, prefix .. "Auto", "42%", 26, "16%", 26,
    "AUTO", "#375a37", dynamic_call("autoToggle"), "Enable or disable scheduled remote management.")
  controls.run = create_label(target.content, prefix .. "Run", "58%", 26, "14%", 26,
    "RUN NOW", "#55427a", dynamic_call("autoRunNow"), "Run one configured remote-management cycle now.")
  controls.cancel = create_label(target.content, prefix .. "Cancel", "72%", 26, "14%", 26,
    "CANCEL", "#7f1d1d", dynamic_call("cancel"), "Cancel capture or unsent changes.")
  controls.clear = create_label(target.content, prefix .. "Clear", "86%", 26, "14%", 26,
    "CLEAR", "#3e4657", function()
      local current = current_ew()
      if current and current.ui then current.ui.clear() end
    end, "Clear Exchange Walker display history.")
  controls.settings = create_label(target.content, prefix .. "Settings", 0, 54, "100%", 26,
    "SETTINGS: F2CE-Tools / Exchange Walker", "#252936", function()
      if EW.settings.open then EW.settings.open() end
    end, "Timer, targets, stockpile policies, spreads, and exclusions are in Muxlet Settings.")
  local console = Geyser.MiniConsole:new({
    name = prefix .. "Console", x = 0, y = 82, width = "100%", height = "100%-82px",
    fontSize = 9, scrollBar = true,
  }, target.content)
  if type(console.setColor) == "function" then pcall(console.setColor, console, 18, 18, 26) end
  if type(console.enableAutoWrap) == "function" then pcall(console.enableAutoWrap, console) end
  if type(console.show) == "function" then pcall(console.show, console) end
  EW.ui.instances[target] = { target = target, controls = controls, console = console }
  EW.ui.registered_target = target
  for _, line_text in ipairs(EW.ui.history) do console_write(console, line_text) end
  update_ui()
end

local function destroy_mux_content(target)
  if EW.ui.destroyTable then EW.ui.destroyTable(target) end
  local instance = EW.ui.instances[target]
  if not instance then return end
  if instance.controls then for _, widget in pairs(instance.controls) do destroy_widget(widget) end end
  destroy_widget(instance.console)
  EW.ui.instances[target] = nil
  if EW.ui.registered_target == target then EW.ui.registered_target = nil end
end

function EW.ui.registerMuxContent()
  if not (Geyser and Geyser.Label and Geyser.MiniConsole) then
    return false, "Geyser Label/MiniConsole is unavailable"
  end
  if EW.isBlocked and EW.isBlocked() then return false, "standalone Exchange Walker is still installed" end
  if not (Mux and Mux.registerContent) then return false, "Muxlet is not ready" end
  if EW.ui.definition and Mux._content and Mux._content[EW.ui.content_id] == EW.ui.definition then return true end
  local definition = {
    name = "Exchange Walker",
    description = "Planet-owner production, stockpile, spread, preview, and apply display.",
    group = "F2CE-Tools", internal = EW.rankAllowed and not EW.rankAllowed() or false, singleton = false,
    apply = function(target)
      local ok, reason = pcall(build_mux_content, target)
      if not ok then
        main_notice("red", "Mux content failed: " .. tostring(reason))
        error(reason, 0)
      end
    end,
    remove = function(target) destroy_mux_content(target) end,
    resize = function(target)
      if EW.ui.reflowTable then EW.ui.reflowTable(target, false)
      elseif EW.ui.resizeTable then EW.ui.resizeTable(target); update_ui() end
    end,
    serialize = function(_target) return {} end,
    restore = function(target, _data)
      if EW.ui.reflowTable then EW.ui.reflowTable(target, true) else update_ui() end
    end,
    onReveal = function(target)
      if EW.ui.reflowTable then EW.ui.reflowTable(target, true) else update_ui() end
    end,
  }
  local ok, reason = pcall(Mux.registerContent, EW.ui.content_id, definition)
  if ok then EW.ui.definition = definition end
  EW.ui.registered = ok == true
  return ok, reason
end

function EW.ui.placeDefault()
  for target in pairs(EW.ui.instances) do
    if target._activeContent == EW.ui.content_id
        and (not EW.ui.instanceHealthy or EW.ui.instanceHealthy(target)) then
      if EW.ui.refreshMounted then EW.ui.refreshMounted(target, true) end
      return true, "already-placed"
    end
  end
  if not EW.ui.registered then
    local registered, reason = EW.ui.registerMuxContent()
    if not registered then return false, reason end
  end
  local placed, pane_or_reason, status = EW.ui.placeRegisteredContent(
    EW.ui.content_id, EW.ui.preferred_pane_start, EW.ui.preferred_pane_end)
  if placed then EW.ui.preferred_pane_id = pane_or_reason end
  return placed, pane_or_reason, status
end

function EW.ui.schedulePlacement(delay)
  if EW.ui_placement_timer then cancel_timer("ui_placement_timer") end
  if type(tempTimer) ~= "function" then return EW.ui.placeDefault() end
  EW.ui_placement_timer = tempTimer(tonumber(delay) or 0.25, function()
    EW.ui_placement_timer = nil
    local ok, reason = EW.ui.placeDefault()
    if ok then
      EW.ui.placement_attempt = 0
    else
      EW.ui.placement_attempt = EW.ui.placement_attempt + 1
    end
    local retryable = tostring(reason):find("not registered", 1, true)
      or tostring(reason):find("capability is unavailable", 1, true)
      or tostring(reason):find("no empty existing Mux pane", 1, true)
    if not ok and retryable and EW.ui.placement_attempt < EW.ui.placement_attempt_limit then
      EW.ui.schedulePlacement(0.5)
    end
  end)
  return true
end

function EW.ui.mount(_activate, _reapply)
  return EW.ui.placeDefault()
end

function EW.ui.install()
  return EW.ui.registerMuxContent()
end

function EW.ui.show()
  if not EW.ui.registered then
    local ok, reason = EW.ui.registerMuxContent()
    if not ok then notice("yellow", "Mux display unavailable: " .. tostring(reason)) return false end
  end
  local placed, pane_or_reason = EW.ui.placeDefault()
  if placed then
    notice("cyan", "Exchange Walker is available in " .. tostring(pane_or_reason) .. ".")
    return true
  end
  notice("yellow", "Exchange Walker is registered but was not auto-placed: " .. tostring(pane_or_reason)
    .. ". Select it from Muxlet Content Library.")
  return false
end

local function validate_complete_capture(exchange_data, production_data)
  if type(exchange_data) ~= "table" or type(production_data) ~= "table" then
    return nil, "Exchange or production capture is not a valid table."
  end
  local expected_count = finite_number(exchange_data._expected_count)
  if expected_count == nil or expected_count < 1
      or expected_count ~= math.floor(expected_count) then
    return nil, "Exchange summary count is unavailable; capture completeness cannot be proven."
  end
  if #exchange_data ~= expected_count then
    return nil, string.format(
      "Exchange capture is incomplete: parsed %d of %d summary rows.",
      #exchange_data, expected_count)
  end
  local production_by_name = {}
  for name, production in pairs(production_data) do
    if type(name) ~= "string" or name == "" or type(production) ~= "table" then
      return nil, "Production capture contains an invalid commodity row."
    end
    local key = normalized(name)
    if production_by_name[key] ~= nil then
      return nil, string.format("Production capture contains duplicate rows for %s.", name)
    end
    local produced = finite_number(production.production)
    local consumed = finite_number(production.consumption)
    if produced == nil or consumed == nil or produced < 0 or consumed < 0 then
      return nil, string.format("Production capture is invalid for %s.", name)
    end
    production_by_name[key] = { name = name, production = produced, consumption = consumed }
  end
  local exchange_names = {}
  for _, exchange in ipairs(exchange_data) do
    if type(exchange) ~= "table" or type(exchange.name) ~= "string" or exchange.name == "" then
      return nil, "Exchange capture contains an invalid commodity row."
    end
    local key = normalized(exchange.name)
    if exchange_names[key] then
      return nil, string.format("Exchange capture contains duplicate rows for %s.", exchange.name)
    end
    exchange_names[key] = true
    if production_by_name[key] == nil then
      return nil, string.format("Production capture is incomplete: missing %s.", exchange.name)
    end
    local current = finite_number(exchange.stock_current)
    local minimum = finite_number(exchange.stock_min)
    local maximum = finite_number(exchange.stock_max)
    local spread = finite_number(exchange.spread)
    -- Live exchanges can report negative current stock. That value is a real
    -- deficit, not an incomplete-capture sentinel. Only configured limits are
    -- constrained to the server's accepted non-negative ranges.
    if current == nil then
      return nil, string.format(
        "Exchange current stock capture is invalid for %s (%s).",
        exchange.name, tostring(exchange.stock_current))
    end
    if minimum == nil or minimum < 0 or minimum > 10000 then
      return nil, string.format(
        "Exchange minimum stock capture is invalid for %s (%s; expected 0..10000).",
        exchange.name, tostring(exchange.stock_min))
    end
    if maximum == nil or maximum < 0 or maximum > 20000 then
      return nil, string.format(
        "Exchange maximum stock capture is invalid for %s (%s; expected 0..20000).",
        exchange.name, tostring(exchange.stock_max))
    end
    if minimum > maximum then
      return nil, string.format(
        "Exchange stock limits are invalid for %s (minimum %s exceeds maximum %s).",
        exchange.name, tostring(exchange.stock_min), tostring(exchange.stock_max))
    end
    if spread == nil or spread < 6 or spread > 40 then
      return nil, string.format("Exchange spread capture is invalid for %s.", exchange.name)
    end
  end
  for key, production in pairs(production_by_name) do
    if not exchange_names[key] then
      return nil, string.format("Exchange capture is incomplete: missing %s.", production.name)
    end
  end
  return production_by_name, nil
end

local function make_plan(exchange_data, production_data, room_identity, target_planet)
  local production_by_name, capture_error = validate_complete_capture(exchange_data, production_data)
  if not production_by_name then return nil, capture_error end
  local rows, excluded = {}, {}
  for _, commodity in ipairs(EW.settings.excluded_commodities) do
    excluded[normalized(commodity)] = true
  end
  for _, exchange in ipairs(exchange_data) do
    if excluded[normalized(exchange.name)] then
      -- Excluded rows still participated in complete-capture validation above,
      -- but are deliberately omitted from every proposed mutation.
    else
    local production = production_by_name[normalized(exchange.name)]
    local produced, consumed = production.production, production.consumption
    local net = produced - consumed
    local current = math.floor(tonumber(exchange.stock_current))
    local old_min = math.floor(tonumber(exchange.stock_min))
    local old_max = math.floor(tonumber(exchange.stock_max))
    local old_spread = math.floor(tonumber(exchange.spread))
    local target_min, target_max, target_spread, policy
    if net < 0 then
      target_min, target_max = EW.settings.deficit_min, EW.settings.deficit_max
      target_spread, policy = EW.settings.deficit_spread, "deficit"
    elseif net == 0 then
      target_min, target_max = EW.settings.breakeven_min, EW.settings.breakeven_max
      target_spread, policy = EW.settings.breakeven_spread, "breakeven"
    elseif current < EW.settings.reserve_trigger then
      target_min = math.min(10000, math.max(0, current))
      target_max = math.min(20000, target_min + EW.settings.growth_buffer)
      target_spread, policy = EW.settings.surplus_spread, "surplus-growing"
    else
      target_min, target_max = EW.settings.reserve_min, EW.settings.reserve_max
      target_spread, policy = EW.settings.surplus_spread, "surplus-reserve"
    end
    rows[#rows + 1] = {
      commodity = exchange.name, production = produced, consumption = consumed, net = net,
      current = current, old_min = old_min, old_max = old_max,
      target_min = target_min, target_max = target_max,
      old_spread = old_spread, target_spread = target_spread, policy = policy,
    }
    end
  end
  table.sort(rows, function(left, right)
    if left.net == right.net then return normalized(left.commodity) < normalized(right.commodity) end
    return left.net > right.net
  end)
  local actions = {}
  for _, row in ipairs(rows) do
    local min_changed = row.target_min ~= row.old_min
    local max_changed = row.target_max ~= row.old_max
    local function add_limit(kind, value)
      actions[#actions + 1] = { kind = kind, commodity = row.commodity,
        value = value, planet = target_planet }
    end
    -- The server validates each mutation against the still-live opposite
    -- bound. Raise max before a higher min; lower min before a lower max.
    -- In every non-conflicting case prefer max first for a stable convention.
    if min_changed and max_changed and row.target_max < row.old_min then
      add_limit("min", row.target_min)
      add_limit("max", row.target_max)
    else
      if max_changed then add_limit("max", row.target_max) end
      if min_changed then add_limit("min", row.target_min) end
    end
    if row.target_spread ~= row.old_spread then
      actions[#actions + 1] = { kind = "spread", commodity = row.commodity,
        value = row.target_spread, planet = target_planet }
    end
  end
  return { created_at = os.time(), room_identity = target_planet and nil or room_identity,
    planet = target_planet or current_planet_name(), target_planet = target_planet,
    remote = target_planet ~= nil, rows = rows, actions = actions, applied = false }, nil
end

local function compact_name(value, width)
  local text = tostring(value or "")
  if #text > width then return text:sub(1, math.max(1, width - 1)) .. "~" end
  return text
end

local function display_plan(plan)
  local lines = {
    string.format("<green>EXCHANGE + PRODUCTION | %s<reset>", plan.planet),
    "<dim_grey>Production, stock, spread, and limits (old -> new)<reset>",
    string.format("<dim_grey>Policy: deficit %d%% %d/%d | even %d%% %d/%d | surplus %d%%<reset>",
      EW.settings.deficit_spread, EW.settings.deficit_min, EW.settings.deficit_max,
      EW.settings.breakeven_spread, EW.settings.breakeven_min, EW.settings.breakeven_max,
      EW.settings.surplus_spread),
    string.format("<dim_grey>Surplus growth: +%d until %d; reserve %d/%d | excluded %d<reset>",
      EW.settings.growth_buffer, EW.settings.reserve_trigger,
      EW.settings.reserve_min, EW.settings.reserve_max, #EW.settings.excluded_commodities),
  }
  for _, row in ipairs(plan.rows) do
    local color = row.net > 0 and "green" or "red"
    lines[#lines + 1] = string.format(
      "<%s>%-17s net %+d | stock %d<reset>",
      color, compact_name(row.commodity, 17), row.net, row.current)
    lines[#lines + 1] = string.format(
      "  prod/cons %d/%d | spread %d -> %d",
      row.production, row.consumption, row.old_spread, row.target_spread)
    lines[#lines + 1] = string.format(
      "  limits %d/%d -> %d/%d",
      row.old_min, row.old_max, row.target_min, row.target_max)
  end
  lines[#lines + 1] = string.format(
    "<cyan>%d commodities | %d reviewed setting changes | plan expires in %d seconds<reset>",
    #plan.rows, #plan.actions, EW.plan_max_age_seconds)
  EW.ui.replace(lines)
  if #plan.actions == 0 then
    notice("green", "Preview complete: no stockpile or spread changes are needed.")
  else
    notice("yellow", string.format(
      "Preview ready: %d reviewed changes for %s.", #plan.actions, plan.planet))
    notice("yellow", string.format(
      "Review Stockpiles; run 'ew apply' within %d seconds.", EW.plan_max_age_seconds))
  end
end

local function preview_failed(message)
  EW.f2ce.capture.cancel()
  EW.busy, EW.plan, EW.capture_room_identity, EW.capture_target = false, nil, nil, nil
  update_ui()
  notice("red", message)
  emit("preview.failed", { reason = message })
  if EW.operation_mode == "auto" and type(EW.autoFail) == "function" then EW.autoFail(message) end
  return false
end

function EW.status()
  local state = EW.enabled and "ON" or "OFF"
  local activity = EW.applying and "applying" or (EW.busy and "capturing" or "idle")
  local plan = EW.plan and string.format("%d pending change(s) for %s",
    #EW.plan.actions, EW.plan.planet) or "no preview plan"
  notice("cyan", string.format("v%s is %s; %s; %s.", EW.VERSION, state, activity, plan))
  return state_payload()
end

function EW.on()
  local ok, reason = EW.f2ce.core.check({ minimum_version = EW.MIN_F2CE_VERSION })
  if not ok then
    EW.enabled = false
    update_ui()
    notice("red", tostring(reason) .. "; Exchange Walker remains OFF.")
    return false
  end
  local context, why = EW.f2ce.enable()
  if not context then notice("red", tostring(why)); return false end
  EW.enabled = true
  update_ui()
  notice("green", "ON. Use `ew preview [planet]` or configure targets and `ew auto on`.")
  return true
end

function EW.cancel(reason)
  if EW.cancelView then EW.cancelView(reason) end
  local was_active = EW.busy or EW.applying
  cancel_timer("scheduler_timer")
  EW.scheduler.enabled, EW.scheduler.running = false, false
  cancel_timer("transition_timer")
  cancel_timer("apply_timer")
  cancel_timer("confirmation_timer")
  local capture_ok, capture_reason = EW.f2ce.capture.cancel()
  EW.busy, EW.applying = false, false
  EW.pending_confirmation, EW.apply_index = nil, nil
  EW.capture_room_identity, EW.capture_target, EW.operation_mode = nil, nil, "manual"
  update_ui()
  if not capture_ok then notice("yellow", tostring(capture_reason)) end
  if was_active then
    notice("yellow", reason or
      "Cancelled. Already-sent commands cannot be recalled; run a new preview to reconcile.")
  end
  return true
end

function EW.off(reason)
  EW.cancel(reason or "OFF. Capture stopped and unsent changes cancelled.")
  EW.enabled, EW.plan = false, nil
  EW.f2ce.disable(reason)
  update_ui()
  notice("red", "OFF. No capture or stockpile/spread operation will be started.")
  return true
end

function EW.toggle()
  if EW.enabled then return EW.off() end
  return EW.on()
end

function EW.preview(target_planet, automatic)
  if not EW.enabled then notice("red", "The walker is OFF. Use `ew on` first.") return false end
  if EW.busy or EW.applying then
    notice("yellow", "A capture or apply operation is already in progress.")
    return false
  end
  local ok, reason = EW.f2ce.core.check({ minimum_version = EW.MIN_F2CE_VERSION, gmcp = true })
  if not ok then return preview_failed(tostring(reason)) end
  local target
  if target_planet ~= nil and trimmed(target_planet) ~= "" then
    target = safe_planet(target_planet)
    if not target then return preview_failed("Remote target is not a safe planet name.") end
  end
  local room_identity = current_room_identity()
  if not target and not room_identity then return preview_failed("GMCP room identity is unavailable.") end
  EW.plan, EW.busy, EW.capture_room_identity = nil, true, target and nil or room_identity
  EW.capture_target, EW.operation_mode = target, automatic and "auto" or "manual"
  update_ui()
  notice("cyan", string.format("Gathering exchange and production data for %s through F2CE Tools...",
    target or current_planet_name()))
  local function location_changed()
    return not target and current_room_identity() ~= EW.capture_room_identity
  end
  local exchange_capture = target and EW.f2ce.po.captureExchange or EW.f2ce.capture.exchange
  local production_capture = target and EW.f2ce.po.captureProduction or EW.f2ce.capture.production
  local started, start_reason = exchange_capture(target, function(exchange_data)
    if not EW.enabled then return preview_failed("Capture stopped because the walker was switched OFF.") end
    if location_changed() then
      return preview_failed("Location changed during exchange capture; no plan was created.")
    end
    if type(exchange_data) ~= "table" or #exchange_data == 0 then
      return preview_failed("No live exchange rows were captured; no plan was created.")
    end
    EW.transition_timer = tempTimer(0.15, function()
      EW.transition_timer = nil
      if location_changed() then
        return preview_failed("Location changed before production capture; no plan was created.")
      end
      local production_started, production_reason = production_capture(target, function(production_data)
        EW.busy = false
        if not EW.enabled then
          EW.plan, EW.capture_room_identity, EW.capture_target = nil, nil, nil
          update_ui()
          notice("yellow", "Capture completed after OFF; results were discarded.")
          return
        end
        if location_changed() then
          return preview_failed("Location changed during production capture; no plan was created.")
        end
        if type(production_data) ~= "table" or next(production_data) == nil then
          return preview_failed("No live production rows were captured; no plan was created.")
        end
        local plan, capture_error = make_plan(exchange_data, production_data,
          EW.capture_room_identity, target)
        EW.capture_room_identity, EW.capture_target = nil, nil
        if not plan then
          return preview_failed(tostring(capture_error) .. " No plan was created; nothing can be applied.")
        end
        EW.plan = plan
        if EW.ui.setBoard then EW.ui.setBoard(plan.planet, exchange_data) end
        update_ui()
        display_plan(plan)
        emit("plan.ready", plan)
        if automatic then
          if #plan.actions == 0 then
            if type(EW.autoAdvance) == "function" then EW.autoAdvance() end
          else
            EW.apply(true)
          end
        end
      end)
      if not production_started then
        preview_failed("Production capture could not start: " .. tostring(production_reason))
      end
    end)
  end)
  if not started then return preview_failed("Exchange capture could not start: " .. tostring(start_reason)) end
  return true
end

local function stop_apply(message, color)
  cancel_timer("apply_timer")
  cancel_timer("confirmation_timer")
  EW.applying, EW.pending_confirmation, EW.apply_index = false, nil, nil
  EW.f2ce.capture.cancel()
  update_ui()
  notice(color or "red", message)
  emit("apply.failed", { reason = message, plan = EW.plan })
  if EW.operation_mode == "auto" and type(EW.autoFail) == "function" then EW.autoFail(message) end
  return false
end

local function apply_context_valid()
  if not EW.enabled then return false, "Apply stopped because Exchange Walker is OFF." end
  if not EW.plan then return false, "Apply stopped because the preview plan disappeared." end
  if EW.plan.remote then
    if not safe_planet(EW.plan.target_planet)
        or normalized(EW.plan.target_planet) ~= normalized(EW.plan.planet) then
      return false, "Apply stopped because the remote plan target is invalid."
    end
    return true
  end
  if EW.plan.room_identity ~= current_room_identity() then
    return false, "Apply stopped because the GMCP room identity changed."
  end
  local owned, owner, player = EW.f2ce.core.ownership()
  if not owned then
    return false, string.format(
      "Apply stopped because GMCP ownership is not confirmed (owner=%s, player=%s).",
      tostring(owner or "unknown"), tostring(player or "unknown"))
  end
  return true
end

local send_action
send_action = function(index)
  local valid, reason = apply_context_valid()
  if not valid then return stop_apply(reason) end
  local action = EW.plan.actions[index]
  if not action then
    EW.applying, EW.apply_index, EW.pending_confirmation = false, nil, nil
    EW.f2ce.capture.cancel()
    update_ui()
    notice("green", string.format(
      "Apply complete: %d/%d reviewed changes were sent once and confirmed.",
      #EW.plan.actions, #EW.plan.actions))
    emit("apply.completed", { plan = EW.plan })
    if EW.operation_mode == "auto" and type(EW.autoAdvance) == "function" then EW.autoAdvance() end
    return true
  end
  EW.apply_index = index
  EW.pending_confirmation = {
    key = normalized(action.commodity) .. ":" .. action.kind,
    value = action.value, action = action,
  }
  local dispatched, dispatch_reason = EW.f2ce.commands.stockpile(
    action.kind, action.commodity, action.value, action.planet)
  if not dispatched then
    return stop_apply("F2CE adapter blocked the reviewed setting change: " .. tostring(dispatch_reason))
  end
  emit("apply.command_sent", { index = index, action = action })
  EW.confirmation_timer = tempTimer(EW.confirmation_timeout_seconds, function()
    EW.confirmation_timer = nil
    stop_apply(string.format(
      "Timed out waiting for confirmation of %s %s=%d. Remaining changes were not sent; run a new preview.",
      action.commodity, action.kind, action.value))
  end)
  return true
end

function EW.apply(automatic)
  if not EW.enabled then notice("red", "The walker is OFF; nothing was sent.") return false end
  if automatic and not (EW.scheduler.enabled and EW.scheduler.running and EW.operation_mode == "auto") then
    notice("red", "Scheduled apply lacks active automation authority; nothing was sent.")
    return false
  end
  if EW.busy or EW.applying then
    notice("yellow", "A capture or apply operation is already in progress.") return false
  end
  if not EW.plan then notice("red", "No preview plan exists. Run `ew preview` first.") return false end
  if EW.plan.applied then
    notice("red", "This plan was already applied. Run a new preview; commands will not be replayed.")
    return false
  end
  if os.time() - EW.plan.created_at > EW.plan_max_age_seconds then
    EW.plan = nil
    update_ui()
    notice("red", "The preview expired. Run `ew preview` again before applying.")
    return false
  end
  local valid, reason = apply_context_valid()
  if not valid then notice("red", reason) return false end
  if #EW.plan.actions == 0 then notice("green", "The preview contains no changes; nothing was sent.") return true end
  EW.plan.applied, EW.applying = true, true
  update_ui()
  notice("yellow", string.format(
    "Applying %d reviewed changes to %s.", #EW.plan.actions, EW.plan.planet))
  notice("yellow", string.format(
    "Commands are sent once; progress is summarized every %d confirmations.",
    EW.apply_progress_interval))
  emit("apply.started", { plan = EW.plan })
  return send_action(1)
end

local function confirmation(kind)
  local commodity = matches and matches[2] or nil
  local planet = matches and matches[3] or nil
  local reported = matches and matches[4] or nil
  if not commodity or not planet or not reported or not EW.applying then return end
  local pending = EW.pending_confirmation
  if type(pending) ~= "table" then return end
  local key = normalized(commodity) .. ":" .. kind
  if key ~= pending.key then return end
  if normalized(planet) ~= normalized(EW.plan and EW.plan.planet) then return end
  local numeric = tonumber((tostring(reported):gsub(",", "")))
  if numeric ~= pending.value then
    return stop_apply(string.format(
      "%s %s confirmation was %s, expected %d. Remaining changes were not sent; run a new preview.",
      commodity, kind, tostring(reported), pending.value))
  end
  cancel_timer("confirmation_timer")
  local completed_index = EW.apply_index
  EW.pending_confirmation = nil
  local total = #EW.plan.actions
  if completed_index % EW.apply_progress_interval == 0 and completed_index < total then
    notice("cyan", string.format(
      "Apply progress: %d/%d changes confirmed.", completed_index, total))
  end
  emit("apply.confirmed", { index = completed_index, action = pending.action })
  EW.apply_timer = tempTimer(EW.command_spacing_seconds, function()
    EW.apply_timer = nil
    send_action((completed_index or 0) + 1)
  end)
end

schedule_next_cycle = function()
  cancel_timer("scheduler_timer")
  if not EW.scheduler.enabled or type(tempTimer) ~= "function" then return false end
  EW.scheduler_timer = tempTimer(EW.settings.interval_minutes * 60, function()
    EW.scheduler_timer = nil
    if EW.scheduler.enabled then EW.autoRunNow() end
  end)
  return EW.scheduler_timer ~= nil
end

function EW.autoStatus()
  local state = EW.scheduler.enabled and (EW.scheduler.running and "RUNNING" or "WAITING") or "OFF"
  notice("cyan", string.format(
    "Auto %s | every %d minutes | %d target(s) | %d cycle(s) complete | %d failure(s).",
    state, EW.settings.interval_minutes, #EW.settings.targets,
    EW.scheduler.completed, EW.scheduler.failures))
  return state_payload()
end

function EW.autoFail(reason)
  cancel_timer("scheduler_timer")
  EW.scheduler.enabled, EW.scheduler.running = false, false
  EW.scheduler.targets, EW.scheduler.index = {}, 0
  EW.scheduler.failures = EW.scheduler.failures + 1
  EW.operation_mode = "manual"
  update_ui()
  notice("red", "Scheduled management is OFF: " .. tostring(reason))
  return false
end

function EW.autoAdvance()
  if not (EW.enabled and EW.scheduler.enabled and EW.scheduler.running) then return false end
  EW.scheduler.index = EW.scheduler.index + 1
  local target = EW.scheduler.targets[EW.scheduler.index]
  if not target then
    EW.scheduler.running = false
    EW.scheduler.completed = EW.scheduler.completed + 1
    EW.operation_mode = "manual"
    update_ui()
    notice("green", string.format(
      "Scheduled cycle complete across %d remote exchange(s); next check in %d minutes.",
      #EW.scheduler.targets, EW.settings.interval_minutes))
    return schedule_next_cycle()
  end
  notice("cyan", string.format("Scheduled remote exchange %d/%d: %s.",
    EW.scheduler.index, #EW.scheduler.targets, target))
  return EW.preview(target, true)
end

function EW.autoRunNow()
  if not EW.enabled then notice("red", "Exchange Walker is OFF; no scheduled cycle started.") return false end
  if not EW.scheduler.enabled then
    notice("red", "Scheduled management is OFF. Use `ew auto on` first.") return false
  end
  if EW.busy or EW.applying or EW.scheduler.running then
    notice("yellow", "A capture, apply, or scheduled cycle is already active.") return false
  end
  local targets = copy_targets(EW.settings.targets)
  if #targets == 0 then
    return EW.autoFail("no remote target planets are configured")
  end
  cancel_timer("scheduler_timer")
  EW.scheduler.targets, EW.scheduler.index, EW.scheduler.running = targets, 0, true
  EW.operation_mode = "auto"
  update_ui()
  notice("yellow", string.format(
    "Scheduled cycle starting across %d configured remote exchange(s). Complete captures are applied automatically.",
    #targets))
  return EW.autoAdvance()
end

function EW.autoOn()
  if not EW.enabled then notice("red", "Arm Exchange Walker with `ew on` first.") return false end
  if #EW.settings.targets == 0 then
    notice("red", "Add at least one remote target before enabling scheduled management.") return false
  end
  EW.scheduler.enabled = true
  update_ui()
  notice("yellow", string.format(
    "Scheduled management ON. Complete reviewed changes will be applied every %d minutes.",
    EW.settings.interval_minutes))
  return EW.autoRunNow()
end

function EW.autoOff(reason)
  local was_active = EW.scheduler.enabled or EW.scheduler.running
  cancel_timer("scheduler_timer")
  EW.scheduler.enabled, EW.scheduler.running = false, false
  EW.scheduler.targets, EW.scheduler.index = {}, 0
  if EW.operation_mode == "auto" and (EW.busy or EW.applying) then
    EW.cancel(reason or "Scheduled management cancelled; unsent changes were discarded.")
  end
  EW.operation_mode = "manual"
  update_ui()
  if was_active then notice("red", reason or "Scheduled management OFF.") end
  return true
end

function EW.autoToggle()
  if EW.scheduler.enabled then return EW.autoOff() end
  return EW.autoOn()
end

function EW.settingsStatus()
  EW.ui.replace({
    "<cyan>EXCHANGE WALKER SETTINGS<reset>",
    string.format("Timer: %d minutes", EW.settings.interval_minutes),
    string.format("Deficit: spread %d | limits %d/%d",
      EW.settings.deficit_spread, EW.settings.deficit_min, EW.settings.deficit_max),
    string.format("Breakeven: spread %d | limits %d/%d",
      EW.settings.breakeven_spread, EW.settings.breakeven_min, EW.settings.breakeven_max),
    string.format("Surplus: spread %d | growth buffer %d | trigger %d | reserve %d/%d",
      EW.settings.surplus_spread,
      EW.settings.growth_buffer, EW.settings.reserve_trigger,
      EW.settings.reserve_min, EW.settings.reserve_max),
    "Targets: " .. (#EW.settings.targets > 0 and table.concat(EW.settings.targets, ", ") or "none"),
    "Excluded: " .. (#EW.settings.excluded_commodities > 0
      and table.concat(EW.settings.excluded_commodities, ", ") or "none"),
    "Edit preferences in Settings > F2CE-Tools > Exchange Walker.",
  })
  return state_payload()
end

local setting_aliases = {
  interval = "interval_minutes", ["surplus-spread"] = "surplus_spread",
  ["breakeven-spread"] = "breakeven_spread", ["deficit-spread"] = "deficit_spread",
  ["deficit-min"] = "deficit_min", ["deficit-max"] = "deficit_max",
  ["breakeven-min"] = "breakeven_min", ["breakeven-max"] = "breakeven_max",
  buffer = "growth_buffer",
  trigger = "reserve_trigger", ["reserve-min"] = "reserve_min",
  ["reserve-max"] = "reserve_max",
}

function EW.setSetting(name, value)
  local key = setting_aliases[normalized(name)]
  if not key then notice("red", "Unknown setting: " .. tostring(name)) return false end
  local numeric = tonumber(value)
  if numeric == nil then notice("red", "Setting value must be numeric.") return false end
  local ok, reason = EW.settings.configure({ [key] = numeric })
  if not ok then notice("red", "Setting was not saved: " .. tostring(reason)) return false end
  if EW.scheduler.enabled and not EW.scheduler.running then schedule_next_cycle() end
  update_ui()
  notice("green", string.format("%s set to %d.", key, EW.settings[key]))
  return true
end

function EW.addTarget(value)
  local target = safe_planet(value)
  if not target then notice("red", "Target is not a safe planet name.") return false end
  local targets = copy_targets(EW.settings.targets)
  targets[#targets + 1] = target
  local ok, reason = EW.settings.configure({ targets = targets })
  if not ok then notice("red", tostring(reason)) return false end
  update_ui()
  notice("green", "Remote target saved: " .. target .. ".")
  return true
end

function EW.removeTarget(value)
  local key = normalized(safe_planet(value))
  if key == "" then notice("red", "Target is not a safe planet name.") return false end
  local targets = {}
  for _, target in ipairs(EW.settings.targets) do
    if normalized(target) ~= key then targets[#targets + 1] = target end
  end
  local ok, reason = EW.settings.configure({ targets = targets })
  if not ok then notice("red", tostring(reason)) return false end
  update_ui()
  notice("green", "Remote target removed: " .. tostring(value) .. ".")
  return true
end

function EW.addExclusion(value)
  local commodity = safe_planet(value)
  if not commodity then notice("red", "Commodity is not a safe name.") return false end
  local exclusions = copy_exclusions(EW.settings.excluded_commodities)
  exclusions[#exclusions + 1] = commodity
  local ok, reason = EW.settings.configure({ excluded_commodities = exclusions })
  if not ok then notice("red", tostring(reason)) return false end
  update_ui()
  notice("green", "Commodity excluded: " .. commodity .. ".")
  return true
end

function EW.removeExclusion(value)
  local key = normalized(safe_planet(value))
  if key == "" then notice("red", "Commodity is not a safe name.") return false end
  local exclusions = {}
  for _, commodity in ipairs(EW.settings.excluded_commodities) do
    if normalized(commodity) ~= key then exclusions[#exclusions + 1] = commodity end
  end
  local ok, reason = EW.settings.configure({ excluded_commodities = exclusions })
  if not ok then notice("red", tostring(reason)) return false end
  update_ui()
  notice("green", "Commodity exclusion removed: " .. tostring(value) .. ".")
  return true
end

local function add_trigger(pattern, callback)
  if type(tempRegexTrigger) ~= "function" then return nil end
  local id = tempRegexTrigger(pattern, callback)
  if id then EW.runtime.trigger_ids[#EW.runtime.trigger_ids + 1] = id end
  return id
end

local function add_handler(event_name, callback)
  if type(registerAnonymousEventHandler) ~= "function" then return nil end
  local id = registerAnonymousEventHandler(event_name, callback)
  if id then EW.runtime.handler_ids[#EW.runtime.handler_ids + 1] = id end
  return id
end

local function api_status()
  local caps = EW.f2ce.core.capabilities()
  local capture = caps.profiles and caps.profiles.capture or { available = false }
  notice("cyan", string.format(
    "API %s | active adapter %s | F2CE %s | capture %s | public Mux registration %s.",
    EW.API_CONTRACT, tostring(caps.api_version), tostring(caps.f2ce_version or "missing"),
    capture.available and "available" or "missing",
    caps.display.registration and "available" or "missing"))
  return caps
end

local function install_runtime_hooks()
  add_trigger([[^\s*Min stock level for (\w+) on (.+) set to ([0-9][0-9,]*(?:\.[0-9]+)?) tons\.$]],
    function() confirmation("min") end)
  add_trigger([[^\s*Max stock level for (\w+) on (.+) set to ([0-9][0-9,]*(?:\.[0-9]+)?) tons\.$]],
    function() confirmation("max") end)
  add_trigger([[^\s*Price spread for (\w+) on (.+) set to ([0-9]+)%\.$]],
    function() confirmation("spread") end)
  if type(tempAlias) == "function" then
    EW.runtime.alias_id = tempAlias(
      [[^ew(?:\s+(.*))?\s*$]], function()
      local raw_command = trimmed(matches and matches[2] or "status")
      local command = normalized(raw_command)
      if command == "on" then EW.on()
      elseif command == "off" then EW.off()
      elseif command == "toggle" then EW.toggle()
      elseif command == "preview" then EW.preview()
      elseif command:match("^preview%s+.+") then EW.preview(raw_command:match("^%S+%s+(.+)$"))
      elseif command == "apply" then EW.apply()
      elseif command == "cancel" then EW.cancel()
      elseif command == "status" then EW.status()
      elseif command == "settings" then EW.settings.open()
      elseif command == "auto on" then EW.autoOn()
      elseif command == "auto off" then EW.autoOff()
      elseif command == "auto run" or command == "auto now" then EW.autoRunNow()
      elseif command == "auto status" then EW.autoStatus()
      elseif command:match("^set%s+[%w%-]+%s+%-?%d+$") then
        local name, value = raw_command:match("^%S+%s+(%S+)%s+(%-?%d+)$")
        EW.setSetting(name, value)
      elseif command:match("^target%s+add%s+.+") then EW.addTarget(raw_command:match("^%S+%s+%S+%s+(.+)$"))
      elseif command:match("^target%s+remove%s+.+") then EW.removeTarget(raw_command:match("^%S+%s+%S+%s+(.+)$"))
      elseif command == "target clear" then
        EW.settings.configure({ targets = {} })
        update_ui(); notice("green", "Remote targets cleared.")
      elseif command == "target list" then EW.settingsStatus()
      elseif command:match("^exclude%s+add%s+.+") then EW.addExclusion(raw_command:match("^%S+%s+%S+%s+(.+)$"))
      elseif command:match("^exclude%s+remove%s+.+") then EW.removeExclusion(raw_command:match("^%S+%s+%S+%s+(.+)$"))
      elseif command == "exclude clear" then
        EW.settings.configure({ excluded_commodities = {} })
        update_ui(); notice("green", "Commodity exclusions cleared.")
      elseif command == "exclude list" then EW.settingsStatus()
      elseif command == "display" then EW.ui.show()
      elseif command == "api" then api_status()
      else
        EW.ui.replace({
          "<cyan>EXCHANGE WALKER LIVE COMMANDS<reset>",
          "<yellow>ew on<reset>       Arm capture and explicit apply",
          "<yellow>ew off<reset>      Disable and cancel pending work",
          "<yellow>ew preview<reset>  Capture exchange + production and show a plan",
          "<yellow>ew preview PLANET<reset>  Preview one remote owned exchange",
          "<yellow>ew apply<reset>    Apply the latest unexpired preview once",
          "<yellow>ew target add/remove PLANET<reset>  Edit scheduled targets",
          "<yellow>ew exclude add/remove COMMODITY<reset>  Protect commodities from all changes",
          "<yellow>ew set interval 30<reset>  Set timer minutes (5-1440)",
          "<yellow>ew settings<reset> Show stock/spread/timer policy",
          "<yellow>ew auto on/off/run/status<reset>  Scheduled remote management",
          "<yellow>ew cancel<reset>   Cancel capture or unsent changes",
          "<yellow>ew display<reset>  Place/show the Exchange Walker Mux content",
          "<yellow>ew status<reset>   Show current state",
          "<yellow>ew api<reset>      Show F2CE adapter capabilities",
        })
        EW.ui.show()
      end
    end)
  end
  add_handler("sysDisconnectionEvent", function()
    EW.off("Disconnected. Reconnect requires explicit `ew on`.")
  end)
  add_handler("sysConnectionEvent", function()
    EW.off("Reconnect safety reset. Use `ew on` explicitly.")
  end)
  add_handler("sysUninstallPackage", function(_, package_name)
    local name = normalized(package_name)
    if name == "f2ce-tools" then
      EW.settings.remove()
      EW.shutdown()
    end
  end)
end

function EW.subscribe(event_name, callback)
  if type(event_name) ~= "string" or event_name == "" or type(callback) ~= "function" then
    return nil, "event name and callback are required"
  end
  EW.events.next_id = EW.events.next_id + 1
  EW.events.subscribers[event_name] = EW.events.subscribers[event_name] or {}
  EW.events.subscribers[event_name][EW.events.next_id] = callback
  return EW.events.next_id
end

function EW.unsubscribe(id)
  for _, listeners in pairs(EW.events.subscribers) do
    if listeners[id] then listeners[id] = nil return true end
  end
  return false
end

function EW.shutdown()
  EW.ui.shutting_down = true
  cancel_timer("scheduler_timer")
  cancel_timer("boot_timer")
  cancel_timer("ui_placement_timer")
  EW.cancel("Exchange Walker runtime shutdown; unsent work cancelled.")
  EW.enabled, EW.plan = false, nil
  for _, id in ipairs(EW.runtime.trigger_ids) do
    if type(killTrigger) == "function" then pcall(killTrigger, id) end
  end
  EW.runtime.trigger_ids = {}
  if EW.runtime.alias_id and type(killAlias) == "function" then pcall(killAlias, EW.runtime.alias_id) end
  EW.runtime.alias_id = nil
  for _, id in ipairs(EW.runtime.handler_ids) do
    if type(killAnonymousEventHandler) == "function" then pcall(killAnonymousEventHandler, id) end
  end
  EW.runtime.handler_ids = {}
  local targets = {}
  for target in pairs(EW.ui.instances) do targets[#targets + 1] = target end
  for _, target in ipairs(targets) do destroy_mux_content(target) end
  if EW.f2ce and type(EW.f2ce.shutdown) == "function" then EW.f2ce.shutdown() end
  update_ui()
end

EW.public = {
  contract = EW.API_CONTRACT, version = EW.VERSION,
  status = EW.status, on = EW.on, off = EW.off,
  preview = EW.preview, apply = EW.apply, cancel = EW.cancel,
  autoOn = EW.autoOn, autoOff = EW.autoOff, autoRunNow = EW.autoRunNow,
  autoStatus = EW.autoStatus, setSetting = EW.setSetting,
  addTarget = EW.addTarget, removeTarget = EW.removeTarget,
  addExclusion = EW.addExclusion, removeExclusion = EW.removeExclusion,
  show = EW.ui.show, subscribe = EW.subscribe, unsubscribe = EW.unsubscribe,
  capabilities = api_status,
}

-- Bootstrapped after all F2CE scripts and the native API are ready.
EW.installRuntime = install_runtime_hooks
EW.refresh = update_ui
EW.notice = notice
EW.policy.makePlan = make_plan
