-- Minimal independent module using only F2CE.API.v1.

local API = assert(F2CE and F2CE.API and F2CE.API.v1, "F2CE.API.v1 is required")

local spec = {
    id = "example.market.runner",
    version = "1.0.0",
    auto_enable = true,
    requires = {
        api = ">=1.0.0",
        f2ce = ">=3.3.0",
        capabilities = { "navigation", "gmcp.snapshots", "map.queries" },
    },
}

local function startMarketTrip(context)
    local lease, lease_error = API.navigation.acquire(context, { purpose = "example market trip" })
    if not lease then print("[example] " .. tostring(lease_error)); return end

    local request, request_error = lease:request("Sol exchange", {
        suppress_hint = true,
        on_complete = function(result)
            print("[example] arrived: " .. tostring(result.destination))
        end,
        on_failure = function(result)
            print("[example] failed: " .. tostring(result.reason))
        end,
        on_interrupt = function(result)
            if result.interruption_reason == "customs" then return { auto_resume = true } end
        end,
    })
    if not request then lease:release("start_failed"); print("[example] " .. tostring(request_error)) end
end

function spec.initialize(context)
    context:on("data.room", function(event)
        if event.available then
            local room = event.value -- copied snapshot; safe for the module to mutate
            if room and room.name then print("[example] room: " .. tostring(room.name)) end
        end
    end)

    context:on("navigation.interrupted", function(event)
        print("[example] navigation interrupted: " .. tostring(event.interruption_reason))
    end)

    -- Host resources stay with their native owner. This alias uses Mudlet
    -- directly and gives the scoped context only its cleanup token.
    local alias_id = tempAlias("^example market$", function() startMarketTrip(context) end)
    context:own("mudlet_alias", alias_id, function(id) killAlias(id) end)
end

function spec.disable(context, reason)
    print("[example] disabled: " .. tostring(reason))
    -- Muxlet owns any visual content registered by this package. The F2CE
    -- context owns only F2CE service subscriptions/leases and explicit cleanup.
end

function spec.unload(context, reason)
    print("[example] unloaded: " .. tostring(reason))
end

local context, err = API.modules.reload(spec)
if not context then error(tostring(err)) end
