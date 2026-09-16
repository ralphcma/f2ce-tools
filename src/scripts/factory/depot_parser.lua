-- A depot has no final text marker. The caller must supply ONLY the complete
-- block closed by the next owner-bound read response; silence is not success.
function f2t_depot_parse_display(lines, expected)
    if type(lines) ~= "table" or #lines > 180 then return nil, "invalid depot display" end
    local clean = {}
    for _, line in ipairs(lines) do
        if type(line) ~= "string" then return nil, "invalid depot line" end
        clean[#clean+1] = line:gsub("\27%[[%d;]*m", "")
    end
    local text = table.concat(clean, " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
    if #text > 32768 then return nil, "depot display exceeds bound" end
    local planet, capacity, workers, efficiency, rest = text:match(
        "^Location: (.-) Capacity: (%d+) cargo bays Workforce: (%d+) Efficiency: (%d+)%% (.+)$")
    capacity, workers, efficiency = tonumber(capacity), tonumber(workers), tonumber(efficiency)
    if not planet or planet:lower() ~= tostring(expected):lower() or capacity < 1 or capacity > 50
        or workers > 1000000 or efficiency > 100 then return nil, "invalid depot identity or limits" end
    local result = {planet=planet, capacity=capacity, workforce=workers, efficiency=efficiency,
        bays={}, inventory={}, used_bays=0, free_bays=capacity}
    local seen = {}
    if rest == "The depot is empty." then return result end
    while rest ~= "" do
        local bay, name, cost, origin, system, tail = rest:match(
            "^Bay #%s*(%d+) ([%a][%w]*) Cost ([%d,]+)ig/ton %(Origin (.-), (.-) system%)%s*(.*)$")
        bay = tonumber(bay)
        if not bay or bay < 1 or bay > capacity or seen[bay] or #result.bays >= capacity
            or #origin > 80 or #system > 80 or not origin:match("^[%w][%w%s'%.%-]*$")
            or not system:match("^[%w][%w%s'%.%-]*$") then
            return nil, "invalid, duplicate or incomplete depot bay"
        end
        if cost:find(",",1,true) then
            local first, groups = cost:match("^(%d+)(,.*)$")
            if not first or #first > 3 or groups:gsub(",%d%d%d", "") ~= "" then return nil, "invalid cargo cost" end
        end
        cost = tonumber((cost:gsub(",", "")))
        if not cost or cost > 1000000000 then return nil, "invalid cargo cost" end
        seen[bay] = true
        -- Cargo has no partial-quantity field: each stored Cargo is one 75t bay.
        result.bays[#result.bays+1] = {number=bay, commodity=name, tons=75, cost_per_ton=cost,
            origin=origin, system=system}
        local key = name:lower()
        result.inventory[key] = (result.inventory[key] or 0) + 75
        rest = tail
    end
    result.used_bays = #result.bays
    result.free_bays = capacity - result.used_bays
    return result
end
