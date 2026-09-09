-- SPDX-License-Identifier: GPL-2.0-only
-- F2CE package lifecycle only. No standalone loader, dependency bootstrap,
-- navigation, capture, setting mutation, or scheduler start occurs on load.
local EW = F2T_EXCHANGE_WALKER

function EW.bootstrap()
    if F2T_EXCHANGE_WALKER ~= EW or EW.ui.shutting_down then return false end
    if Mux and Mux.settings then
        local loaded, why = EW.settings.load()
        EW.settings_error = not loaded and tostring(why) or nil
    end
    if EW.isBlocked() then
        if not EW.conflict_noticed then
            EW.conflict_noticed = true
            EW.notice("yellow", "Native module is OFF: standalone exchange-walker-live is installed. Settings migration is available; remove the standalone package to use the native module.")
        end
        return false
    end
    local ok, why = EW.f2ce.register()
    if not ok then
        EW.bootstrap_error = why
        return false
    end
    EW.bootstrap_error = nil
    if not EW.runtime_installed then
        EW.installRuntime()
        EW.runtime_installed = true
        ExchangeWalkerLive = EW -- compatibility discovery; native implementation
        EW.notice("cyan", "Native Exchange Walker loaded OFF. Settings: F2CE-Tools / Exchange Walker. Use ew on, ew preview, then ew apply; timer requires ew auto on.")
    end
    return true
end

local function defer_boot()
    if EW.boot_timer then killTimer(EW.boot_timer) end
    EW.boot_timer = tempTimer(0, function()
        EW.boot_timer = nil
        if not EW.bootstrap() and EW.bootstrap_error then
            EW.notice("yellow", tostring(EW.bootstrap_error) .. "; native Walker remains OFF.")
        elseif EW.runtime_installed and Mux and Mux._ready and type(f2tRegisterExchangeWalker) == "function" then
            f2tRegisterExchangeWalker()
        end
    end)
end

if type(registerAnonymousEventHandler) == "function" then
    EW.runtime.handler_ids[#EW.runtime.handler_ids + 1] = registerAnonymousEventHandler("sysUninstallPackage", function(_, name)
        if tostring(name):lower() == "exchange-walker-live" then defer_boot() end
    end)
end
if type(tempTimer) == "function" then defer_boot() end
