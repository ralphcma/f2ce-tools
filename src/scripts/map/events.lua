-- f2ce-tools map — GMCP event handler registration (ported from map_events.lua)

local success, handler_id = pcall(registerAnonymousEventHandler, "gmcp.room.info", "f2t_map_handle_gmcp_room")

if success and handler_id then
    f2t_debug_log("[map] Registered GMCP event handler for gmcp.room.info (ID: %s)", tostring(handler_id))
else
    f2t_debug_log("[map] WARNING: Failed to register GMCP event handler: %s", tostring(handler_id))
end

-- Startup topology sync
--
-- Once per login, re-ground the jump model (cartel->syndicate groupings and
-- syndicate beacon builds) with a single "display cartels" / "display
-- syndicates" pass, so speedwalk jump planning is correct from the first
-- jump even though galaxy politics drift between sessions.
--
-- Minimal is a UI choice, not a map-disable switch, so this is allowed there
-- while mapping and topology auto-sync remain enabled. "map off" and the
-- topology_auto_sync setting are the explicit command-production gates.
--
-- Gated to fire once per connection, keyed off gmcp.char.vitals with a flag
-- that re-arms on disconnect. The sync is deferred a few seconds so its
-- commands never land mid-login. Every command-producing edge is rechecked
-- when the timer fires: disconnecting or disabling mapping/auto-sync while it
-- waits must result in zero commands.
local topology_startup_synced = false
local topology_startup_timer_id = nil

local function f2t_map_startup_topology_ready()
    if F2T_MAP_ENABLED ~= true then return false, "mapping disabled" end
    if type(f2t_settings_get) ~= "function"
        or not f2t_settings_get("map", "topology_auto_sync") then
        return false, "topology auto-sync disabled"
    end

    local connected = F2T_CONNECTED
    if type(f2t_check_connection) == "function" then
        connected = f2t_check_connection()
    end
    if not connected then return false, "disconnected" end

    local name = gmcp and gmcp.char and gmcp.char.vitals and gmcp.char.vitals.name
    if not name or name == "" then return false, "not logged in" end
    return true
end

local function f2t_map_startup_topology_cancel_timer()
    if not topology_startup_timer_id then return end
    if type(killTimer) == "function" then
        pcall(killTimer, topology_startup_timer_id)
    end
    topology_startup_timer_id = nil
end

local f2t_map_startup_topology_sync
f2t_map_startup_topology_sync = function(delay)
    if topology_startup_synced or topology_startup_timer_id then return end
    local ready = f2t_map_startup_topology_ready()
    if not ready then return end

    topology_startup_synced = true
    if type(delay) ~= "number" then delay = 3 end
    topology_startup_timer_id = tempTimer(delay, function()
        topology_startup_timer_id = nil

        local still_ready, reason = f2t_map_startup_topology_ready()
        if not still_ready then
            -- Let a later vitals update retry if the user re-enables the map or
            -- topology auto-sync during this same connection.
            topology_startup_synced = false
            f2t_debug_log("[map/topology] Startup sync skipped: %s", tostring(reason))
            return
        end

        if type(f2t_map_topology_sync) == "function" then
            local started, start_reason = f2t_map_topology_sync(nil, { silent = true, automatic = true })
            if not started and start_reason == "native busy" then
                topology_startup_synced = false
                f2t_map_startup_topology_sync(0.5)
            end
        end
    end)
    if not topology_startup_timer_id then topology_startup_synced = false end
end

registerAnonymousEventHandler("gmcp.char.vitals", f2t_map_startup_topology_sync)

-- gmcp.char.vitals may already have fired before this script (re)loaded — e.g.
-- a dev-mode rebuild while connected. gmcp.char survives that, so check now too.
f2t_map_startup_topology_sync()

-- Re-arm so the next login after a reconnect syncs once again.
registerAnonymousEventHandler("sysDisconnectionEvent", function()
    f2t_map_startup_topology_cancel_timer()
    if F2T_MAP_TOPOLOGY_CAPTURE and F2T_MAP_TOPOLOGY_CAPTURE.active
        and type(f2t_map_topology_capture_cancel) == "function" then
        f2t_map_topology_capture_cancel("disconnected")
    end
    topology_startup_synced = false
end)
