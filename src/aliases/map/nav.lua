-- Navigation command
-- Usage: nav <destination>
-- Usage: nav info <destination>
-- Usage: nav info <origin> to <destination>
-- Usage: nav stop/pause/resume

local args = matches[2]

if not args or args == "" then
    f2t_show_registered_help("nav")
    return
end

if f2t_handle_help("nav", args) then
    return
end

local subcommand = string.lower(args):match("^(%S+)")

local function apiRequest()
    local navigation = F2CE and F2CE.API and F2CE.API.v1 and F2CE.API.v1.navigation
    return navigation, navigation and navigation._request
end

if subcommand == "stop" then
    local stop_rest = args:match("^stop%s+(.+)") or ""
    if f2t_handle_help("nav stop", stop_rest) then return end
    local navigation, request = apiRequest()
    if request and request.handle then
        navigation.cancel(request.handle, true, "cancelled_by_user")
        return
    end
    local active = F2T_SPEEDWALK_ACTIVE
        or (F2T_MAP_EXPLORE_STATE and F2T_MAP_EXPLORE_STATE.active)
        or (F2T_MAP_CIRCUIT_STATE and F2T_MAP_CIRCUIT_STATE.active)
        or (F2T_MAP_WHEREIS_CAPTURE and F2T_MAP_WHEREIS_CAPTURE.active)
    if not active then
        cecho("\n<yellow>[map]<reset> No active navigation to stop\n")
        return
    end
    if type(f2t_map_navigation_cancel) == "function" then
        f2t_map_navigation_cancel("Stopped by user")
    else
        f2t_map_speedwalk_stop()
    end

elseif subcommand == "pause" then
    local pause_rest = args:match("^pause%s+(.+)") or ""
    if f2t_handle_help("nav pause", pause_rest) then return end
    local navigation, request = apiRequest()
    if request and request.handle then
        local ok = navigation.pause(request.handle)
        if not ok then cecho("\n<yellow>[map]<reset> Navigation could not be paused\n") end
        return
    end
    if F2T_SPEEDWALK_ACTIVE then
        f2t_map_speedwalk_pause()
    elseif F2T_MAP_EXPLORE_STATE and F2T_MAP_EXPLORE_STATE.active then
        f2t_map_explore_pause()
    else
        cecho("\n<yellow>[map]<reset> No active navigation to pause\n")
        return
    end

elseif subcommand == "resume" then
    local resume_rest = args:match("^resume%s+(.+)") or ""
    if f2t_handle_help("nav resume", resume_rest) then return end
    local navigation, request = apiRequest()
    if request and request.handle then
        local ok = navigation.resume(request.handle)
        if not ok then cecho("\n<yellow>[map]<reset> Navigation could not be resumed\n") end
        return
    end
    if F2T_SPEEDWALK_ACTIVE then
        f2t_map_speedwalk_resume()
    elseif F2T_MAP_EXPLORE_STATE and F2T_MAP_EXPLORE_STATE.active
        and F2T_MAP_EXPLORE_STATE.paused then
        f2t_map_explore_resume()
    else
        cecho("\n<yellow>[map]<reset> No paused navigation to resume\n")
        return
    end

elseif subcommand == "info" then
    local info_rest = args:match("^info%s+(.+)$")

    if f2t_handle_help("nav info", info_rest or "") then return end

    if not info_rest or info_rest == "" then
        cecho("\n<red>[map]<reset> Usage: nav info <destination>\n")
        cecho("<red>[map]<reset>        nav info <origin> to <destination>\n")
        return
    end

    local origin, destination
    local before_to, after_to = info_rest:match("^(.-)%s+[Tt][Oo]%s+(.+)$")

    if before_to and after_to then
        origin = before_to
        destination = after_to
    else
        origin = nil
        destination = info_rest
    end

    f2t_map_show_route_info(origin, destination)

else
    f2t_map_navigate(args, {interactive = true, compensate_incomplete_map = true})
end
