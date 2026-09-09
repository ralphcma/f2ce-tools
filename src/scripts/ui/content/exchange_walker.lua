-- SPDX-License-Identifier: GPL-2.0-only
-- Muxlet owns panes/workspaces. Preserve the historic content ID so existing
-- saved layouts keep working; register only through F2CE's normal lifecycle.
local function walker() return F2T_EXCHANGE_WALKER end

local function place(content_id, first, last)
    local ew = walker()
    if not (ew and Mux and Mux.getPane and Mux._applyContent) then
        return false, "Mux safe placement capability is unavailable"
    end
    -- Existing placement wins, even outside the preferred range. Do not switch
    -- tabs, move windows, or replace the map/Galaxy/another package's content.
    for index = 1, 99 do
        local pane = Mux.getPane("pane_" .. index)
        if pane then
            if pane._activeContent == content_id then
                if not ew.ui.instances[pane] then Mux._applyContent(pane, content_id, true) end
                return true, pane.id or ("pane_" .. index), "existing"
            end
            for _, tabs in ipairs({ pane._tabs or {}, pane._hiddenTabs or {} }) do
                for _, tab in ipairs(tabs) do
                    if tab._activeContent == content_id then return true, pane.id, "existing-tab" end
                end
            end
        end
    end
    for index = first, last do
        local id = "pane_" .. index
        local pane = Mux.getPane(id)
        if pane and not pane._activeContent and not next(pane._tabs or {})
            and not next(pane._hiddenTabs or {}) then
            Mux._applyContent(pane, content_id, true)
            if pane._activeContent == content_id then return true, id, "placed" end
            return false, "Muxlet did not confirm content placement"
        end
    end
    return false, "no empty existing Mux pane at or above pane_15"
end

function f2tRegisterExchangeWalker()
    local ew = walker()
    if not ew then return end
    ew.ui.placeRegisteredContent = place
    if not ew.bootstrap() then return end
    local ok, why = ew.ui.registerMuxContent()
    if not ok then error("Exchange Walker content: " .. tostring(why)) end
    ew.ui.schedulePlacement(0.25)
end

if walker() then walker().ui.placeRegisteredContent = place end

F2T_CONTENT_REGISTRARS = F2T_CONTENT_REGISTRARS or {}
-- Preserve list order but replace our stale closure after a script-only reload.
local old = F2T_EXCHANGE_WALKER_REGISTRAR
for index = #F2T_CONTENT_REGISTRARS, 1, -1 do
    if F2T_CONTENT_REGISTRARS[index] == old then table.remove(F2T_CONTENT_REGISTRARS, index) end
end
F2T_EXCHANGE_WALKER_REGISTRAR = f2tRegisterExchangeWalker
table.insert(F2T_CONTENT_REGISTRARS, f2tRegisterExchangeWalker)
