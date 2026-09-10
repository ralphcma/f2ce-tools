-- SPDX-License-Identifier: GPL-2.0-only
-- Muxlet owns panes/workspaces. Preserve the historic content ID so existing
-- saved layouts keep working; register only through F2CE's normal lifecycle.
local function walker() return F2T_EXCHANGE_WALKER end

local function instance_healthy(ew, target)
    if type(ew.ui.instanceHealthy) == "function" then
        return ew.ui.instanceHealthy(target) == true
    end
    return ew.ui.instances[target] ~= nil
end

local function ensure_applied(ew, target, content_id)
    if target._activeContent ~= content_id or not instance_healthy(ew, target) then
        Mux._applyContent(target, content_id, true)
    end
    if target._activeContent ~= content_id or not instance_healthy(ew, target) then
        return false
    end
    if ew.ui.refreshMounted then ew.ui.refreshMounted(target, true) end
    return true
end

local function has_founder_rule(tab)
    for _, rule in ipairs(tab.rules or {}) do
        if rule.id == "ew_founder" and rule.enabled ~= false
            and rule.cond and rule.cond.ref == "ExchangeWalkerFounder"
            and rule.act == "mux.showSelf" and rule.actElse == "mux.hideSelf" then
            return true
        end
    end
    return false
end

-- Tabs exported with the native workspace are deliberately locked in the same
-- way as Who, Events, and Exchange. Older Walker releases appended a normal
-- user tab instead (all four capabilities defaulted to true), then mutated its
-- rules table after construction without registering the rule with Muxlet.
-- That malformed saved object is the common factor in the persistent black-tab
-- reports: replacing only its content slot cannot repair its lifecycle.
local function is_native_tab(tab)
    return tab
        and tab.renamable == false
        and tab.closeable == false
        and tab.movable ~= false
        and tab.contentable == false
        and tab.propertiesButton == false
        and tab.nameAlign == "center"
        and has_founder_rule(tab)
end

local function apply_native_tab_settings(tab)
    tab.name = "Exchange Walker"
    tab.renamable = false
    tab.closeable = false
    tab.movable = true
    tab.contentable = false
    tab.propertiesButton = false
    tab.nameAlign = "center"
    tab.rules = tab.rules or {}
    if not has_founder_rule(tab) then
        local rule = { id = "ew_founder", enabled = true,
            cond = { ref = "ExchangeWalkerFounder" },
            act = "mux.showSelf", actElse = "mux.hideSelf" }
        -- _addRule is the native path: it registers the tab as a reactive rule
        -- subject, wires the GMCP event, and evaluates the current rank. Directly
        -- appending to tab.rules (the old behavior) does none of those things.
        if type(Mux._addRule) == "function" then
            Mux._addRule(tab, rule)
        elseif type(Mux._migrateLegacyRules) == "function" then
            Mux._migrateLegacyRules(tab, { rules = { rule } })
        else
            tab.rules[#tab.rules + 1] = rule
        end
    end
end

local function visible_tab_index(host, target)
    for index, tab in ipairs(host._tabs or {}) do
        if tab == target then return index end
    end
end

local function rebuild_named_tab(ew, host, old_tab, content_id)
    if type(host.removeTab) ~= "function" or type(host.addTab) ~= "function" then
        return nil, "Muxlet cannot replace the malformed Exchange Walker tab"
    end
    local was_active = host._activeTabId == old_tab.id
    local position = visible_tab_index(host, old_tab)
    if not position and old_tab._conditionHidden and type(old_tab._conditionShow) == "function" then
        pcall(old_tab._conditionShow, old_tab)
        position = visible_tab_index(host, old_tab)
    end
    if not position then
        return nil, "Muxlet could not expose the malformed Exchange Walker tab for replacement"
    end

    -- removeTab tears down tab bookkeeping and rules, but not active content.
    -- Use Muxlet's content remover first so its slot and every descendant Geyser
    -- widget are destroyed before the tab object itself leaves the workspace.
    if type(Mux._removeContent) == "function" then Mux._removeContent(old_tab) end
    old_tab.closeable = true
    host:removeTab(old_tab.id)
    if visible_tab_index(host, old_tab) then
        return nil, "Muxlet did not remove the malformed Exchange Walker tab"
    end

    local tab = host:addTab("Exchange Walker", position)
    if not tab then return nil, "Muxlet could not recreate the Exchange Walker tab" end
    apply_native_tab_settings(tab)
    if not ensure_applied(ew, tab, content_id) then
        return nil, "Muxlet did not build the recreated Exchange Walker tab"
    end
    if was_active then
        if type(host.activateTab) == "function" then host:activateTab(tab.id)
        elseif type(host._activateTabObj) == "function" then host:_activateTabObj(tab) end
    end
    return tab
end

local function place(content_id, first, last)
    local ew = walker()
    if not (ew and Mux and Mux.getPane and Mux._applyContent) then
        return false, "Mux safe placement capability is unavailable"
    end
    local eligible = ew.rankAllowed and ew.rankAllowed()
    local host, existing_tab, named_tab
    for index = 1, 99 do
        local pane = Mux.getPane("pane_" .. index)
        if pane then
            local who, exchange, pane_named_tab = false, false, nil
            for _, tabs in ipairs({ pane._tabs or {}, pane._hiddenTabs or {} }) do
                for _, tab in ipairs(tabs) do
                    who = who or tab._activeContent == "fed2_who"
                    exchange = exchange or tab._activeContent == "fed2_exchange"
                    local tab_name = tostring(tab.name or tab.id or "")
                    if tab_name == "Exchange Walker" then pane_named_tab = pane_named_tab or tab end
                    if tab._activeContent == content_id then
                        existing_tab = existing_tab or tab
                        if Mux.runAction then Mux.runAction(eligible and "mux.showSelf" or "mux.hideSelf", { tab = tab, pane = pane }) end
                    end
                end
            end
            if who and exchange then
                host = host or pane
                named_tab = named_tab or pane_named_tab
                if pane_named_tab and Mux.runAction then
                    Mux.runAction(eligible and "mux.showSelf" or "mux.hideSelf", { tab = pane_named_tab, pane = pane })
                end
            end
            if not eligible and pane._activeContent == content_id and Mux.runAction then
                Mux.runAction("mux.hideSelf", { pane = pane })
            end
        end
    end
    -- Older workspace saves can retain a tab named Exchange Walker while its
    -- content ID points at another F2CE view (observed live as `fed2_cargo`).
    -- Prefer and repair that intended tab instead of silently mounting Walker
    -- in a different pane and leaving the selected named tab black.
    existing_tab = named_tab or existing_tab
    if not eligible then return false, "Founder rank or higher is required" end
    if existing_tab then
        if named_tab and host and not is_native_tab(named_tab) then
            local rebuilt, reason = rebuild_named_tab(ew, host, named_tab, content_id)
            if not rebuilt then return false, reason end
            return true, host.id, "rebuilt-tab"
        end
        -- A package/script reload destroys the prior Walker's Geyser widgets,
        -- but Muxlet deliberately keeps the saved tab and its content ID. The
        -- ID alone therefore does not prove that the newly loaded Walker has a
        -- live board instance. Reapply into the existing tab when the instance
        -- is missing; otherwise a hot update leaves a valid-looking, black tab
        -- until the entire Mudlet profile is restarted.
        if not ensure_applied(ew, existing_tab, content_id) then
            return false, "Muxlet did not rebuild the existing Exchange Walker tab"
        end
        return true, existing_tab.pane and existing_tab.pane.id, "existing-tab"
    end
    -- Existing placement wins, even outside the preferred range. Do not switch
    -- tabs, move windows, or replace the map/Galaxy/another package's content.
    for index = 1, 99 do
        local pane = Mux.getPane("pane_" .. index)
        if pane then
            if pane._activeContent == content_id then
                if not ensure_applied(ew, pane, content_id) then
                    return false, "Muxlet did not rebuild the existing Exchange Walker pane"
                end
                return true, pane.id or ("pane_" .. index), "existing"
            end
            for _, tabs in ipairs({ pane._tabs or {}, pane._hiddenTabs or {} }) do
                for _, tab in ipairs(tabs) do
                    if tab._activeContent == content_id then return true, pane.id, "existing-tab" end
                end
            end
        end
    end
    if host and type(host.addTab) == "function" then
        local tab = host:addTab("Exchange Walker")
        if not tab then return false, "Muxlet could not create the Exchange Walker tab" end
        apply_native_tab_settings(tab)
        if not ensure_applied(ew, tab, content_id) then
            return false, "Muxlet did not build the new Exchange Walker tab"
        end
        return true, host.id, "added-tab"
    end
    for index = first, last do
        local id = "pane_" .. index
        local pane = Mux.getPane(id)
        if pane and not pane._activeContent and not next(pane._tabs or {})
            and not next(pane._hiddenTabs or {}) then
            if ensure_applied(ew, pane, content_id) then return true, id, "placed" end
            return false, "Muxlet did not confirm content placement"
        end
    end
    return false, "no empty existing Mux pane at or above pane_15"
end

function f2tRegisterExchangeWalker()
    local ew = walker()
    if not ew then return end
    if Mux and Mux.createDeclarativeCondition then
        Mux.createDeclarativeCondition({ id = "ExchangeWalkerFounder", label = "Founder or higher",
            cond = { type = "gmcp_contains", path = "gmcp.char.vitals.rank",
                values = "Founder,Engineer,Mogul,Technocrat,Gengineer,Magnate,Plutocrat,Syndicrat" } }, true)
    end
    ew.ui.placeRegisteredContent = place
    if not ew.bootstrap() then return end
    local ok, why = ew.ui.registerMuxContent()
    if not ok then error("Exchange Walker content: " .. tostring(why)) end
    ew.ui.schedulePlacement(0.25)
end

if walker() then walker().ui.placeRegisteredContent = place end

if walker() and type(registerAnonymousEventHandler) == "function" then
    local ew = walker()
    ew.runtime.handler_ids[#ew.runtime.handler_ids + 1] = registerAnonymousEventHandler("gmcp.char.vitals", function()
        if F2T_EXCHANGE_WALKER ~= ew then return end
        if not ew.rankAllowed() then
            if ew.enabled or ew.busy or ew.applying or ew.scheduler.enabled then ew.off() end
            local current = F2CE and F2CE.API and F2CE.API.v1
            if current then current.modules.disable("f2ce.exchange_walker_view", "rank_gate") end
        end
        if ew.ui.definition then ew.ui.definition.internal = not ew.rankAllowed() end
        place(ew.ui.content_id, ew.ui.preferred_pane_start, ew.ui.preferred_pane_end)
        if ew.ui.updateTable then ew.ui.updateTable() end
    end)
end

F2T_CONTENT_REGISTRARS = F2T_CONTENT_REGISTRARS or {}
-- Preserve list order but replace our stale closure after a script-only reload.
local old = F2T_EXCHANGE_WALKER_REGISTRAR
for index = #F2T_CONTENT_REGISTRARS, 1, -1 do
    if F2T_CONTENT_REGISTRARS[index] == old then table.remove(F2T_CONTENT_REGISTRARS, index) end
end
F2T_EXCHANGE_WALKER_REGISTRAR = f2tRegisterExchangeWalker
table.insert(F2T_CONTENT_REGISTRARS, f2tRegisterExchangeWalker)
