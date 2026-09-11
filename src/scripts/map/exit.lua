-- f2ce-tools map — exit handling (ported from map_exit.lua)

local DIR_EXPANSION_MAP = {
    n="north",s="south",e="east",w="west",
    ne="northeast",nw="northwest",se="southeast",sw="southwest",
    u="up",d="down",
}

local function get_existing_exit(room_id, direction)
    local exits = getRoomExits(room_id)
    local existing = exits[direction]
    if not existing then
        local expanded = DIR_EXPANSION_MAP[direction]
        if expanded then existing = exits[expanded] end
    end
    return existing
end

local function has_stub_in_direction(room_id, direction)
    local stubs = getExitStubs(room_id)
    local direction_num = f2t_map_direction_to_number(direction)
    for _, stub_dir_num in pairs(stubs) do
        if stub_dir_num == direction_num then return true end
    end
    return false
end

local function existing_exit_matches_hash(room_id, direction, expected_hash)
    local destination = get_existing_exit(room_id, direction)
    if not destination then return nil, false end
    return destination, f2t_map_generate_hash_from_room(destination) == expected_hash
end

function f2t_map_process_exits(current_room_id, gmcp_exits, gmcp_room_data)
    if not current_room_id or not roomExists(current_room_id) then return end
    if not gmcp_exits then return end

    local current_exits = getRoomExits(current_room_id)
    local seen_directions = {}

    for direction, fed2_num in pairs(gmcp_exits) do
        seen_directions[direction] = true
        local dest_hash = string.format("%s.%s.%d", gmcp_room_data.system, gmcp_room_data.area, fed2_num)
        local dest_room_id = f2t_map_get_room_by_hash(dest_hash)

        -- A rebuilt system can reuse a direction for a newly-numbered room.
        -- In that case an imported map may still have (for example) `up`
        -- connected to the old orbit while live GMCP says `up:101`. Leaving
        -- that stale edge in place prevents exploration from creating a stub
        -- and the new orbit is never visited. Trust the live destination:
        -- retain an exact userdata/hash match if Mudlet's hash index missed
        -- it, otherwise remove the stale edge so it can be rediscovered.
        if not dest_room_id then
            local existing, matches = existing_exit_matches_hash(current_room_id, direction, dest_hash)
            if matches then
                dest_room_id = existing
            elseif existing then
                setExit(current_room_id, -1, f2t_map_direction_to_number(direction))
            end
        end

        if dest_room_id then
            local existing_exit = get_existing_exit(current_room_id, direction)
            if existing_exit ~= dest_room_id then
                local opposite_dir = f2t_map_get_opposite_direction(direction)
                if opposite_dir then
                    local dest_existing_exit = get_existing_exit(dest_room_id, opposite_dir)
                    if not dest_existing_exit or dest_existing_exit ~= current_room_id then
                        local dest_has_stub = has_stub_in_direction(dest_room_id, opposite_dir)
                        local dest_should_have_exit = false
                        local dest_exits_data = getRoomUserData(dest_room_id, "fed2_exits")
                        if dest_exits_data then
                            local our_fed2_num = gmcp_room_data.num
                            for dir_num_pair in string.gmatch(dest_exits_data, "[^,]+") do
                                local dir, num = string.match(dir_num_pair, "([^:]+):(%d+)")
                                if dir == opposite_dir and num and tonumber(num) == our_fed2_num then
                                    dest_should_have_exit = true; break
                                end
                            end
                        end
                        if dest_has_stub then
                            local odn = f2t_map_direction_to_number(opposite_dir)
                            setExitStub(dest_room_id, odn, false)
                            setExit(dest_room_id, current_room_id, odn)
                        elseif dest_should_have_exit then
                            local odn = f2t_map_direction_to_number(opposite_dir)
                            setExit(dest_room_id, current_room_id, odn)
                        end
                    end
                end

                local dir_num = f2t_map_direction_to_number(direction)
                if has_stub_in_direction(current_room_id, direction) then
                    local success = connectExitStub(current_room_id, dir_num, dest_room_id)
                    if not success then
                        setExit(current_room_id, dest_room_id, dir_num)
                        setExitStub(current_room_id, dir_num, false)
                    end
                else
                    setExit(current_room_id, dest_room_id, dir_num)
                end
            end
        else
            if not has_stub_in_direction(current_room_id, direction) then
                setExitStub(current_room_id, f2t_map_direction_to_number(direction), true)
            end
        end
    end

    for direction in pairs(current_exits) do
        local normalized_dir = f2t_map_normalize_direction(direction)
        if not seen_directions[direction] and not seen_directions[normalized_dir] then
            setExit(current_room_id, -1, f2t_map_direction_to_number(direction))
        end
    end
end

function f2t_map_resolve_stub_exit(prev_room_id, current_room_id, direction)
    if not prev_room_id or not current_room_id or not direction then return end
    if not roomExists(prev_room_id) or not roomExists(current_room_id) then return end
    local dir_num = f2t_map_direction_to_number(direction)
    if not dir_num then return end
    local stubs = getExitStubs(prev_room_id)
    if not stubs then return end
    local has_stub = false
    for _, stub_dir_num in pairs(stubs) do
        if stub_dir_num == dir_num then has_stub = true; break end
    end
    if not has_stub then return end
    setExit(prev_room_id, current_room_id, dir_num)
    setExitStub(prev_room_id, dir_num, false)
end

function f2t_map_connect_incoming_stubs(room_id, fed2_num)
    if not room_id or not fed2_num then return end
    local area_id = getRoomArea(room_id)
    if not area_id then return end
    local fed2_num_str = tostring(fed2_num)
    for _, other_room_id in ipairs(f2t_map_area_room_list(area_id)) do
        if other_room_id ~= room_id then
            local stubs = getExitStubs(other_room_id)
            if stubs and next(stubs) ~= nil then
                local exits_data = getRoomUserData(other_room_id, "fed2_exits")
                if exits_data and exits_data ~= "" then
                    for dir_num_pair in string.gmatch(exits_data, "[^,]+") do
                        local dir, num = string.match(dir_num_pair, "([^:]+):(%d+)")
                        if dir and num == fed2_num_str then
                            local dir_num = f2t_map_direction_to_number(dir)
                            if dir_num then
                                local has_stub = false
                                for _, stub_dir in pairs(stubs) do
                                    if stub_dir == dir_num then has_stub = true; break end
                                end
                                if has_stub then
                                    setExit(other_room_id, room_id, dir_num)
                                    setExitStub(other_room_id, dir_num, false)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Import can restore a stub after its destination room because both are
-- created before exits are wired.  The live mapper only called the incoming
-- stub resolver when a room was newly discovered, leaving such fully-known
-- pairs disconnected until somebody physically revisited the source room.
function f2t_map_reconcile_cached_exits()
    local repaired = 0
    for room_id in pairs(getRooms() or {}) do
        room_id = tonumber(room_id)
        if room_id and roomExists(room_id) then
            local exits_data = getRoomUserData(room_id, "fed2_exits")
            local system = getRoomUserData(room_id, "fed2_system")
            local area = getRoomUserData(room_id, "fed2_area")
            if exits_data and exits_data ~= "" and system and system ~= "" and area and area ~= "" then
                for pair in string.gmatch(exits_data, "[^,]+") do
                    local direction, fed2_num = string.match(pair, "([^:]+):(%d+)")
                    local direction_number = direction and f2t_map_direction_to_number(direction)
                    local destination = fed2_num and f2t_map_get_room_by_hash(
                        string.format("%s.%s.%s", system, area, fed2_num))
                    if direction_number then
                        local existing = get_existing_exit(room_id, direction)
                        if destination then
                            if tonumber(existing) ~= tonumber(destination) then
                                setExit(room_id, destination, direction_number)
                                repaired = repaired + 1
                            end
                            if has_stub_in_direction(room_id, direction) then
                                setExitStub(room_id, direction_number, false)
                            end
                        else
                            local expected_hash = string.format("%s.%s.%s", system, area, fed2_num)
                            local _, matches = existing_exit_matches_hash(room_id, direction, expected_hash)
                            if existing and not matches then
                                setExit(room_id, -1, direction_number)
                                existing = nil
                                repaired = repaired + 1
                            end
                            if not existing and not has_stub_in_direction(room_id, direction) then
                                setExitStub(room_id, direction_number, true)
                                repaired = repaired + 1
                            end
                        end
                    end
                end
            end
        end
    end
    return repaired
end

local function room_is_isolated(room_id)
    if not room_id or not roomExists(room_id) then return false end
    return next(getRoomExits(room_id) or {}) == nil
        and next(getSpecialExits(room_id) or {}) == nil
end

local function is_synthetic_board_room(room_id)
    if not room_id or not roomExists(room_id) then return false end
    if getRoomUserData(room_id, "fed2_synthetic_board") == "true" then return true end
    return string.match(getRoomName(room_id) or "", "%s%(via board%)$") ~= nil
end

-- A learned board transition is only reusable when it connects the orbit and
-- shuttlepad of the same planet. Keeping this narrow prevents an imported
-- hint from ever becoming a cross-planet shortcut.
function f2t_map_board_pair_valid(from_room, to_room)
    if not from_room or not to_room or not roomExists(from_room) or not roomExists(to_room) then
        return false
    end
    local from_planet = getRoomUserData(from_room, "fed2_planet")
    local to_planet = getRoomUserData(to_room, "fed2_planet")
    if not from_planet or not to_planet or from_planet == "" or to_planet == ""
        or string.lower(from_planet) ~= string.lower(to_planet) then
        return false
    end
    local from_orbit = getRoomUserData(from_room, "fed2_flag_orbit") == "true"
    local from_pad = getRoomUserData(from_room, "fed2_flag_shuttlepad") == "true"
    local to_orbit = getRoomUserData(to_room, "fed2_flag_orbit") == "true"
    local to_pad = getRoomUserData(to_room, "fed2_flag_shuttlepad") == "true"
    return (from_orbit and to_pad) or (from_pad and to_orbit)
end

function f2t_map_remember_board_pair(from_room, to_room)
    if not f2t_map_board_pair_valid(from_room, to_room) then return false end
    local hash = f2t_map_generate_hash_from_room(to_room)
    if not hash then return false end
    setRoomUserData(from_room, "fed2_board_actual_hash", hash)
    return true
end

-- Older map exports can contain a synthetic "Planet (via board)" room made
-- from a legacy GMCP board hash even though the real, flagged landing pad is
-- already mapped.  Repoint only the provably-safe shape: one unique real pad,
-- a recognisably synthetic board destination in that area, and an otherwise isolated
-- synthetic room.  Ambiguous/dynamic board arrangements are left untouched
-- and can still be corrected from a live transition by speedwalk.lua.
function f2t_map_reconcile_board_exits()
    local repaired = 0
    for orbit_id in pairs(getRooms() or {}) do
        orbit_id = tonumber(orbit_id)
        if orbit_id and roomExists(orbit_id)
            and getRoomUserData(orbit_id, "fed2_flag_orbit") == "true" then
            local planet = getRoomUserData(orbit_id, "fed2_planet")
            local area_id = planet and planet ~= "" and f2t_map_get_area_id(planet)
            if area_id then
                local pads = {}
                for _, room_id in ipairs(f2t_map_area_room_list(area_id)) do
                    if getRoomUserData(room_id, "fed2_flag_shuttlepad") == "true"
                        and not is_synthetic_board_room(room_id) then
                        pads[#pads + 1] = room_id
                    end
                end
                if #pads == 1 then
                    local pad_id = pads[1]
                    local board_destination = tonumber((getSpecialExitsSwap(orbit_id) or {}).board)
                    if board_destination and board_destination ~= pad_id
                        and roomExists(board_destination)
                        and getRoomArea(board_destination) == area_id
                        and is_synthetic_board_room(board_destination)
                        and room_is_isolated(board_destination) then
                        removeSpecialExit(orbit_id, "board")
                        addSpecialExit(orbit_id, pad_id, "board")
                        f2t_map_remember_board_pair(orbit_id, pad_id)
                        local reverse = tonumber((getSpecialExitsSwap(pad_id) or {}).board)
                        if not reverse then
                            addSpecialExit(pad_id, orbit_id, "board")
                            reverse = orbit_id
                        end
                        if reverse == orbit_id then f2t_map_remember_board_pair(pad_id, orbit_id) end
                        repaired = repaired + 1
                    end
                end
            end
        end
    end
    return repaired
end

function f2t_map_reconcile_cached_routes()
    local exits = f2t_map_reconcile_cached_exits()
    local boards = f2t_map_reconcile_board_exits()
    if exits > 0 or boards > 0 then
        f2t_debug_log("[map] Reconciled imported routes: %d regular exit(s), %d board pair(s)",
            exits, boards)
    end
    return exits, boards
end

function f2t_map_process_special_exits(current_room_id, gmcp_room_data)
    if not current_room_id or not roomExists(current_room_id) or not gmcp_room_data then return end
    if gmcp_room_data.flags then
        f2t_map_process_link_room(current_room_id, gmcp_room_data)
    end
    if gmcp_room_data.board or gmcp_room_data.orbit then
        local board_hash = gmcp_room_data.board or gmcp_room_data.orbit
        -- Once a live transition has disproved a legacy board hash, retain
        -- the learned real endpoint. Otherwise revisiting the orbit restores
        -- the bad synthetic edge on every GMCP room update.
        local learned_hash = getRoomUserData(current_room_id, "fed2_board_actual_hash")
        local learned_room = learned_hash and learned_hash ~= ""
            and f2t_map_get_room_by_hash(learned_hash) or nil
        if learned_room and not f2t_map_board_pair_valid(current_room_id, learned_room) then
            setRoomUserData(current_room_id, "fed2_board_actual_hash", "")
            learned_room = nil
        end
        local dest_room_id = learned_room or f2t_map_get_room_by_hash(board_hash)
        if not dest_room_id then
            local parts = {}
            for part in string.gmatch(board_hash, "[^.]+") do table.insert(parts, part) end
            if #parts == 3 then
                local dest_system = parts[1]
                local dest_area   = parts[2]
                local dest_num    = tonumber(parts[3])
                if dest_system and dest_area and dest_num then
                    -- Landing from orbit always sets you down on the planet's
                    -- landing pad, so this stub is that room. Flagging it now
                    -- is what lets "nav <planet>" resolve and reach it without
                    -- anyone having walked the surface first.
                    local dest_data = {system=dest_system, area=dest_area, num=dest_num,
                                       name=string.format("%s (via board)", dest_area),
                                       flags={"shuttlepad"}}
                    local dest_area_id = f2t_map_get_or_create_area(dest_area, {system=dest_system})
                    if dest_area_id then
                        dest_room_id = f2t_map_create_room(dest_data, dest_area_id)
                        if dest_room_id then
                            setRoomUserData(dest_room_id, "fed2_synthetic_board", "true")
                            local x, y, z = f2t_map_calculate_coords_from_room_num(dest_num)
                            f2t_map_set_room_coords(dest_room_id, x, y, z)
                            centerview(current_room_id)
                        end
                    end
                end
            end
        end
        if dest_room_id then
            removeSpecialExit(current_room_id, "board")
            addSpecialExit(current_room_id, dest_room_id, "board")
        end
    end
end

