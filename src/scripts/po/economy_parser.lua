-- Parse exchange/production records in one-line or wrapped server output.
-- Each commodity starts a new record; never borrow fields from the next row.
local function records(buffer, field)
    local result, pending = {}, nil
    for _, value in ipairs(type(buffer) == "table" and buffer or {}) do
        local text = tostring(value)
        if text:match("^%s*[%w][^:]*:%s*" .. field .. "%s+") then
            if pending then result[#result + 1] = pending end
            pending = text
        elseif pending then
            pending = pending .. " " .. text
        end
    end
    if pending then result[#result + 1] = pending end
    return result
end

function f2t_po_parse_exchange_buffer(buffer, summary)
    local results = {}
    for _, text in ipairs(records(buffer, "value")) do
        local name, value, spread, current, minimum, maximum, efficiency, net = text:match(
            "^%s*(.-):%s+value%s+(%d+)ig/ton%s+Spread:%s+(%d+)%%%s+Stock:%s+current%s+" ..
            "(%-?%d+)/min%s+(%-?%d+)/max%s+(%-?%d+)%s+Efficiency:%s*(%d+)%%%s+Net:%s*(%-?%d+)")
        if name then
            results[#results + 1] = { name = name, value = tonumber(value), spread = tonumber(spread),
                stock_current = tonumber(current), stock_min = tonumber(minimum),
                stock_max = tonumber(maximum), efficiency = tonumber(efficiency), net = tonumber(net) }
        end
    end
    results._expected_count = tonumber(tostring(summary or ""):match("^%s*(%d+)%s+commodities,"))
    return results
end

function f2t_po_parse_production_buffer(buffer)
    local results, seen = {}, {}
    for _, text in ipairs(records(buffer, "production")) do
        local name, production, consumption = text:match(
            "^%s*(.-):%s+production%s+(%d+),%s+consumption%s+(%d+)")
        if name then
            local key = name:lower()
            if seen[key] then return {} end -- duplicate capture must not overwrite evidence
            seen[key] = true
            results[name] = { production = tonumber(production), consumption = tonumber(consumption) }
        end
    end
    return results
end

--- Merge exchange and production data with base prices from commodities.json
--- @param exchange_data table Array from f2t_po_parse_exchange_buffer
--- @param production_data table Table from f2t_po_parse_production_buffer
--- @return table Array of merged commodity records
function f2t_po_merge_economy_data(exchange_data, production_data)
    local merged = {}

    for _, ex in ipairs(exchange_data) do
        local record = {
            name = ex.name,
            value = ex.value,
            spread = ex.spread,
            stock_current = ex.stock_current,
            stock_min = ex.stock_min,
            stock_max = ex.stock_max,
            efficiency = ex.efficiency,
            net = ex.net,
            production = 0,
            consumption = 0,
            base_price = 0,
            diff = 0,
            group = "Unknown"
        }

        -- Merge production data
        local prod = production_data[ex.name]
        if prod then
            record.production = prod.production
            record.consumption = prod.consumption
        end

        -- Look up base price and group from commodities.json
        local info = f2t_po_get_commodity_info(ex.name)
        if info then
            record.base_price = info.base_price
            record.diff = ex.value - info.base_price
            record.group = info.group
        end

        table.insert(merged, record)
    end

    f2t_debug_log("[po] Merged %d commodity records", #merged)
    return merged
end

f2t_debug_log("[po] Economy parser loaded")
