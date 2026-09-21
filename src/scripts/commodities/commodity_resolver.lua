-- Commodity name resolver
-- Handles both full names and short names (e.g., "petros" -> "Petrochemicals")

-- Cache for commodity data (loaded on first use)
local commodity_cache = nil

-- Load commodity data from JSON file
local function load_commodities()
    if commodity_cache then
        return commodity_cache
    end

    -- Note: @PKGNAME@ substitution only works in XML, use actual package name
    local filePath = getMudletHomeDir() .. "/f2ce-tools/commodities.json"
    local file = io.open(filePath, "r")

    if not file then
        f2t_debug_log("[commodities] ERROR: Could not open commodities.json")
        return nil
    end

    local jsonString = file:read("*all")
    file:close()

    local data = yajl.to_value(jsonString)
    if not data or not data.groups then
        f2t_debug_log("[commodities] ERROR: Invalid commodities.json format")
        return nil
    end

    -- Build lookup tables
    -- name_to_canonical: lowercase name -> canonical (properly cased) name
    -- short_to_canonical: lowercase short name -> canonical name
    local name_to_canonical = {}
    local short_to_canonical = {}
    local base_prices = {}

    for _, group in ipairs(data.groups) do
        for _, commodity in ipairs(group.commodities) do
            local canonical = commodity.name
            local lower_name = string.lower(canonical)

            name_to_canonical[lower_name] = canonical
            base_prices[canonical] = commodity.basePrice

            if commodity.shortName then
                local lower_short = string.lower(commodity.shortName)
                short_to_canonical[lower_short] = canonical
            end
        end
    end

    commodity_cache = {
        name_to_canonical = name_to_canonical,
        short_to_canonical = short_to_canonical,
        base_prices = base_prices
    }

    f2t_debug_log("[commodities] Loaded %d commodities with %d short names",
        f2t_table_count_keys(name_to_canonical),
        f2t_table_count_keys(short_to_canonical))

    return commodity_cache
end

-- Resolve a commodity input to its canonical (properly cased) name
-- Returns: canonical_name, was_short_name
-- Returns nil if commodity is not recognized
function f2t_resolve_commodity(input)
    if not input or input == "" then
        return nil, false
    end

    local cache = load_commodities()
    if not cache then
        -- Fallback: just return the input as-is
        return input, false
    end

    local lower_input = string.lower(input)

    -- Check if it's a short name first
    if cache.short_to_canonical[lower_input] then
        return cache.short_to_canonical[lower_input], true
    end

    -- Check if it's a full name
    if cache.name_to_canonical[lower_input] then
        return cache.name_to_canonical[lower_input], false
    end

    -- Not recognized - return the input as-is (let the game handle errors)
    return input, false
end

-- Get all valid commodity names (for validation/autocomplete)
function f2t_get_all_commodities()
    local cache = load_commodities()
    if not cache then
        return {}
    end

    local commodities = {}
    for _, canonical in pairs(cache.name_to_canonical) do
        table.insert(commodities, canonical)
    end

    table.sort(commodities)
    return commodities
end

-- Fixed game base prices, not live quotes or estimated hauling profits.
-- Ties use canonical name order so selection is stable across reloads.
function f2t_get_highest_base_commodities(limit)
    local cache = load_commodities()
    if not cache then return nil, "Commodity base-price catalog unavailable" end
    local names = f2t_get_all_commodities()
    for _, name in ipairs(names) do
        local price = cache.base_prices[name]
        if type(price) ~= "number" or price <= 0 or price >= math.huge or price ~= price then
            return nil, "Invalid commodity base price: " .. name
        end
    end
    if #names < limit then return nil, "Incomplete commodity base-price catalog" end
    table.sort(names, function(a, b)
        if cache.base_prices[a] == cache.base_prices[b] then return a < b end
        return cache.base_prices[a] > cache.base_prices[b]
    end)
    local selected = {}
    for i = 1, limit do selected[i] = names[i] end
    return selected
end

-- Check if a commodity name is valid (full name or short name)
function f2t_is_valid_commodity(input)
    if not input or input == "" then
        return false
    end

    local cache = load_commodities()
    if not cache then
        return true  -- Can't validate, assume valid
    end

    local lower_input = string.lower(input)
    return cache.name_to_canonical[lower_input] ~= nil or cache.short_to_canonical[lower_input] ~= nil
end

f2t_debug_log("[shared] Commodity resolver loaded")
