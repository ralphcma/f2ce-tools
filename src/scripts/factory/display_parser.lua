-- Pure, strict reader shared by native consumers. A quiet interval is not a
-- complete display. No missing value is silently converted to zero.
function f2t_factory_parse_display(lines, expected)
    if type(lines) ~= "table" then return nil, "factory display is unavailable" end
    local clean = {}
    for _, value in ipairs(lines) do
        if type(value) ~= "string" then return nil, "invalid display line" end
        clean[#clean + 1] = value:gsub("\27%[[%d;]*m", "")
    end
    local text = table.concat(clean, " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
    if #text > 16384 then return nil, "factory display exceeds bound" end
    local money = "([%+%-]?[%d,]+)ig"
    local pattern = "^(.-): ([%w]+) Production Facility #(%d+) Location: (.-) Status: (%a+) Finance: "
        .. "Working Capital: " .. money .. " Top Up Level: " .. money
        .. " Income: " .. money .. " Expenditure: " .. money
        .. " Profit last company accounting period: " .. money
        .. " Structure: Efficiency: (%d+)/(%d+) Storage: (%d+)/(%d+) tons available"
        .. " Workers: Required: (%d+) Hired: (%d+) Wages: " .. money
        .. " Inputs: (.-) Output: Stored: (.-) Dispose of ([%w]+) to (%a+) where possible"
        .. " Next batch is (%d+)%% complete$"
    local owner, commodity, number, location, status, cash, topup, income, expenditure, profit,
        efficiency, maximum, free, storage, required, hired, wages, input_text, stored_text,
        disposed, disposal, progress = text:match(pattern)
    if not owner then return nil, "incomplete or malformed factory display" end
    local function amount(value)
        local bare = value:gsub("^[%+%-]", "")
        if bare:find(",", 1, true) then
            local first, rest = bare:match("^(%d+)(,.*)$")
            if not first or #first > 3 or rest:gsub(",%d%d%d", "") ~= "" then return nil end
        end
        local n = tonumber((value:gsub(",", "")))
        if not n or math.abs(n) > 9007199254740991 then return nil end
        return n
    end
    local record = { owner = owner, commodity = commodity, number = tonumber(number), location = location,
        status = status, efficiency = tonumber(efficiency), efficiency_max = tonumber(maximum),
        storage_available = tonumber(free), storage_max = tonumber(storage), workers_required = tonumber(required),
        workers_hired = tonumber(hired), batch_completion = tonumber(progress), disposal = disposal,
        inputs = {}, inputs_met = true }
    for field, value in pairs({working_capital=cash, top_up_level=topup, income=income,
        expenditure=expenditure, profit=profit, wages=wages}) do
        record[field] = amount(value)
        if record[field] == nil then return nil, "invalid " .. field end
    end
    if owner == "" or location == "" or record.number ~= tonumber(expected)
        or record.number < 1 or record.number > 15 or disposed ~= commodity
        or (status ~= "Running" and status ~= "Mothballed")
        or (disposal ~= "exchange" and disposal ~= "depot")
        or record.efficiency_max <= 0 or record.efficiency > record.efficiency_max
        or record.storage_available > record.storage_max or record.batch_completion > 100 then
        return nil, "inconsistent factory identity or limits"
    end
    if stored_text == "None" then record.stored = 0 else
        local n, name = stored_text:match("^(%d+) tons of ([%w]+)$")
        if not n or name ~= commodity then return nil, "invalid stored output" end
        record.stored = tonumber(n)
    end
    if record.stored + record.storage_available ~= record.storage_max then return nil, "inconsistent output storage" end
    if input_text ~= "None" then
        local seen, remainder = {}, input_text
        while remainder ~= "" do
            local name, needed, available, tail = remainder:match("^([%w]+) Required: (%d+) Available: (%d+)%s*(.*)$")
            if not name or seen[name:lower()] or #record.inputs >= 6 then return nil, "invalid or duplicate factory input" end
            needed, available = tonumber(needed), tonumber(available)
            if needed <= 0 then return nil, "invalid input requirement" end
            seen[name:lower()] = true
            record.inputs[#record.inputs + 1] = {commodity=name, required=needed, available=available,
                shortfall=math.max(0, needed-available)}
            if available < needed then record.inputs_met = false end
            remainder = tail
        end
        if #record.inputs == 0 then return nil, "missing input declaration" end
    end
    -- Keep the reported accounting profit separate from the current counters.
    record.current_net = record.income - record.expenditure
    return record
end
