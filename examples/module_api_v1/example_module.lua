-- Minimal independent module using only F2CE.API.v1.

local API = assert(F2CE and F2CE.API and F2CE.API.v1, "F2CE.API.v1 is required")

local spec = {
    id = "example.market.runner",
    version = "1.0.0",
    auto_enable = true,
    requires = {
        api = ">=1.0.0",
        f2ce = ">=3.2.5",
        capabilities = { "navigation", "gmcp.snapshots", "map.queries" },
    },
}

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

    context:alias("^example market$", function()
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
                -- A module can opt into F2CE's supported customs auto-resume.
                if result.interruption_reason == "customs" then return { auto_resume = true } end
            end,
        })
        if not request then lease:release("start_failed"); print("[example] " .. tostring(request_error)) end
    end)
end

function spec.disable(context, reason)
    print("[example] disabled: " .. tostring(reason))
    -- No manual resource deletion is needed. The scoped context owns the alias,
    -- event subscriptions, navigation handles, and every cleanup token.
end

function spec.unload(context, reason)
    print("[example] unloaded: " .. tostring(reason))
end

local context, err = API.modules.reload(spec)
if not context then error(tostring(err)) end

