-- SPDX-License-Identifier: GPL-2.0-only
-- All Walker preferences live in the existing Muxlet Settings window.
local EW = F2T_EXCHANGE_WALKER
local settings = EW.settings
local fields = {
    { "interval_minutes", "ew_general", "Review interval (minutes)", 5, 1440 },
    { "targets", "ew_general", "Owned exchange targets (comma-separated)" },
    { "excluded_commodities", "ew_general", "Excluded commodities (comma-separated)" },
    { "deficit_spread", "ew_deficit", "Deficit spread (6-40%)", 6, 40 },
    { "deficit_min", "ew_deficit", "Deficit minimum stock (0-10,000)", 0, 10000 },
    { "deficit_max", "ew_deficit", "Deficit maximum stock (0-20,000)", 0, 20000 },
    { "breakeven_spread", "ew_breakeven", "Breakeven spread (6-40%)", 6, 40 },
    { "breakeven_min", "ew_breakeven", "Breakeven minimum stock (0-10,000)", 0, 10000 },
    { "breakeven_max", "ew_breakeven", "Breakeven maximum stock (0-20,000)", 0, 20000 },
    { "surplus_spread", "ew_surplus", "Surplus spread (6-40%)", 6, 40 },
    { "growth_buffer", "ew_surplus", "Surplus stock growth buffer (0-10,000)", 0, 10000 },
    { "reserve_trigger", "ew_reserve", "Switch to reserve policy at stock (0-10,000)", 0, 10000 },
    { "reserve_min", "ew_reserve", "Reserve minimum stock (0-10,000)", 0, 10000 },
    { "reserve_max", "ew_reserve", "Reserve maximum stock (0-20,000)", 0, 20000 },
}
local defaults, by_key = {}, {}
local writing, loaded = false, false
for _, field in ipairs(fields) do
    local key = field[1]
    defaults[key] = type(settings[key]) == "table" and {} or settings[key]
    by_key[key] = field
end

local function list(value)
    if type(value) == "table" then
        local result = {}
        for key, item in pairs(value) do
            if type(key) ~= "number" or key < 1 or key ~= math.floor(key)
                or type(item) ~= "string" or item:find("[%c;|]") or not EW.policy.safePlanet(item) then
                return nil, "Invalid name in list"
            end
            result[key] = item
        end
        return result
    end
    if type(value) ~= "string" then return nil, "Enter a comma-separated list" end
    local result = {}
    for item in value:gmatch("[^,]+") do
        if item:find("[%c;|]") or not EW.policy.safePlanet(item) then return nil, "Invalid name in list" end
        result[#result + 1] = item
    end
    return result
end

local function decode(key, value)
    if type(defaults[key]) == "table" then return list(value) end
    return tonumber(value)
end

local function read_config()
    local values = {}
    for _, field in ipairs(fields) do
        local value = f2t_settings_get(field[2], field[1])
        if value == nil then value = defaults[field[1]] end
        local decoded, why = decode(field[1], value)
        if decoded == nil then return nil, why or ("Invalid " .. field[1]) end
        values[field[1]] = decoded
    end
    return EW.policy.validate(values)
end

local function apply_runtime(values)
    for key, value in pairs(values) do settings[key] = value end
    EW.settings_error = nil
end

local function invalidate()
    EW.plan = nil
    if EW.cancel then EW.cancel("Exchange Walker settings changed; run a new preview or explicitly restart the timer.") end
    if EW.refresh then EW.refresh() end
end

for _, field in ipairs(fields) do
    local key, ns = field[1], field[2]
    local default = type(defaults[key]) == "table" and "" or defaults[key]
    f2t_settings_register(ns, key, {
        tab = "F2CE-Tools/Exchange Walker", label = field[3], default = default,
        min = field[4], max = field[5],
        description = key == "interval_minutes"
            and "Default 30 minutes. Saving a preference never arms scheduled automation. Use AUTO ON explicitly."
            or key == "targets"
                and "Comma-separated planet names, e.g. Tempest, Amsterdam, Holland, Denmark. Click Apply beside this field to save for this profile. Saving stops the timer; use AUTO ON explicitly."
            or key:find("spread", 1, true)
                and "Game range: 6-40%. Saved per profile; changes invalidate previews and stop the running timer."
            or key:find("_min", 1, true)
                and "Game range: 0-10,000 tons. The minimum must not exceed its corresponding maximum."
            or key:find("_max", 1, true)
                and "Game range: 0-20,000 tons. The maximum must not be below its corresponding minimum."
            or "Saved per profile. Changes invalidate previews and stop the running timer. Limits are in tons.",
        validator = function(value)
            local decoded, why = decode(key, value)
            if decoded == nil then return false, why or "Enter a number" end
            local candidate = writing and writing or select(1, read_config())
            if not candidate then
                candidate = {}
                for name, fallback in pairs(defaults) do candidate[name] = fallback end
            else
                local copy = {}; for name, item in pairs(candidate) do copy[name] = item end; candidate = copy
            end
            candidate[key] = decoded
            local valid, reason = EW.policy.validate(candidate)
            return valid ~= nil, reason
        end,
    })
    f2t_settings_on_change(ns, key, function()
        if writing then return end
        local values, why = read_config()
        if values then apply_runtime(values)
        else
            EW.settings_error = "Invalid saved exchange policy: " .. tostring(why)
            if EW.notice then EW.notice("red", EW.settings_error) end
        end
        invalidate()
    end)
end

local function persist(values)
    -- Validate the entire candidate before writing any field. Every Muxlet
    -- validator sees this same candidate, including crossing min/max edits.
    writing = values
    for _, field in ipairs(fields) do
        local value = values[field[1]]
        if type(value) == "table" then value = table.concat(value, ", ") end
        local called, ok, why = pcall(f2t_settings_set, field[2], field[1], value)
        if not called or not ok then writing = false; return false, called and why or tostring(ok) end
    end
    writing = false
    return true
end

function settings.configure(changes, save)
    local candidate = {}
    for key in pairs(defaults) do candidate[key] = changes[key] ~= nil and changes[key] or settings[key] end
    for _, key in ipairs({ "targets", "excluded_commodities" }) do
        local value, why = list(candidate[key])
        if not value then return false, why end
        candidate[key] = value
    end
    local clean, why = EW.policy.validate(candidate)
    if not clean then return false, why end
    local previous = {}; for key in pairs(defaults) do previous[key] = settings[key] end
    if save ~= false then
        local ok, reason = persist(clean)
        if not ok then
            persist(previous)
            invalidate()
            EW.settings_error = "Unable to persist exchange policy: " .. tostring(reason)
            return false, reason
        end
    end
    apply_runtime(clean)
    invalidate()
    return true
end

function settings.save()
    return settings.configure({}, true)
end

function settings.setTargetsCsv(value, save)
    local targets, why = list(value)
    if not targets then return false, why end
    return settings.configure({ targets = targets }, save)
end

function settings.setExclusionsCsv(value, save)
    local exclusions, why = list(value)
    if not exclusions then return false, why end
    return settings.configure({ excluded_commodities = exclusions }, save)
end

function settings.load()
    if not (Mux and Mux.settings) then return false, "Muxlet Settings is not ready" end
    f2t_settings_flush_registrations()
    local current, why = read_config()
    if not current then return false, why end
    if loaded then apply_runtime(current); return true end
    -- Preserve native settings when already present. Never migrate saved ON
    -- state, callbacks, timers, plans, or another package's implementation.
    local saved = false
    for _, field in ipairs(fields) do
        local namespace = f2t_settings[field[2]]
        if namespace and namespace[field[1]] ~= nil then saved = true; break end
    end
    if not saved and type(getMudletHomeDir) == "function" then
        local file = io.open(getMudletHomeDir() .. "/exchange-walker-live-settings.ini", "r")
        if file then
            local candidate, schema, parse_error = {}, 1, nil
            for key, value in pairs(defaults) do candidate[key] = value end
            for text in file:lines() do
                local key, value = text:match("^([%w_]+)=(.*)$")
                if key == "schema" then
                    schema = tonumber(value)
                    if schema ~= 1 and schema ~= 2 then parse_error = "Unsupported legacy settings schema" end
                elseif key == "targets" or key == "excluded_commodities" then
                    candidate[key] = value:gsub("|", ",")
                elseif key and (defaults[key] ~= nil or key == "positive_spread" or key == "nonpositive_spread") then
                    candidate[key] = tonumber(value)
                    if candidate[key] == nil then parse_error = "Invalid legacy numeric setting: " .. key end
                end
            end
            file:close()
            if parse_error then return false, parse_error .. "; original file preserved" end
            if schema < 2 then
                candidate.surplus_spread = candidate.positive_spread or defaults.surplus_spread
                candidate.deficit_spread = candidate.nonpositive_spread or defaults.deficit_spread
                candidate.breakeven_spread = candidate.nonpositive_spread or defaults.breakeven_spread
            end
            local ok, reason = settings.configure(candidate)
            if not ok then return false, "Legacy settings were not migrated: " .. tostring(reason) end
            loaded = true
            return true, "migrated; original INI preserved"
        end
    end
    apply_runtime(current)
    loaded = true
    return true
end

function settings.remove()
    writing = defaults
    for _, field in ipairs(fields) do f2t_settings_clear(field[2], field[1]) end
    writing, loaded = false, false
    apply_runtime(defaults)
    invalidate()
    -- The old standalone INI is an untouched migration backup, not ours to delete.
    return true
end

function settings.open()
    if Mux and Mux.settings and Mux.settings.showTab then
        if (not Mux._settings_ui or not Mux._settings_ui.visible) and Mux.settings.toggle then
            Mux.settings.toggle()
        end
        Mux.settings.showTab("ew_general")
        return true
    end
    EW.notice("yellow", "Open Muxlet Settings > F2CE-Tools > Exchange Walker when Muxlet is ready.")
    return false
end

settings.fields = fields
