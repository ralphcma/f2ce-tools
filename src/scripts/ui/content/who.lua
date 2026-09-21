-- Reads from F2T_PLAYER_DB (player_db.lua), kept current by the always-on
-- GMCP handler. Applies keyed row changes from f2tPlayerDbUpdated when safe,
-- with a full refresh fallback for membership/order changes and legacy events.
--
-- Layout per pane:
--   H_HDR px  - header strip: online count + Online/All toggle button
--   H_COL px  - sortable column header bar (Rank | Name | Location)
--   remainder - ScrollBox driven by the table system (f2t_table_system.lua)

local H_HDR     = 24    -- header strip height (px)
local H_COL     = 20    -- column header bar height (px)
local WHO_ROW_H = 22    -- row height (px)
local SB_W      = 17    -- scrollbar pixel allowance

local RC_DEFAULT = "#c8c8c8"
local RC_OFFLINE = "#888888"
local RC_STAFF   = "#6b8e23"   -- Plutocrat with a staff role

local CELL_FONT = "font-size:"..f2t_ui_pt(12)..";font-family:Consolas,Monaco,monospace;"

local _COL_HDR_CSS = [[
    QLabel {
        background-color: transparent; border: none;
        color: rgba(160,160,185,220);
        font-size: 10pt; font-weight: bold;
        font-family: "Consolas","Monaco",monospace;
        padding: 0 4px;
    }
    QLabel::hover { color: white; }
]]

-- Per-pane state, keyed by target._gid
local instances = {}

local function rankColor(row)
    if row.is_online == false then return RC_OFFLINE end
    if row.rank == "Plutocrat" and (row.staff or "") ~= "" then return RC_STAFF end
    return f2t_rank_color_hex(row.rank) or RC_DEFAULT
end

local function buildTableData(showAll)
    local rows = {}
    for _, e in pairs(F2T_PLAYER_DB or {}) do
        if e.is_online then rows[#rows + 1] = e end
    end
    if showAll then
        for _, e in ipairs(f2t_player_db_get_offline()) do
            rows[#rows + 1] = e
        end
    end
    return rows
end

local function onlineCount()
    local n = 0
    for _, e in pairs(F2T_PLAYER_DB or {}) do
        if e.is_online then n = n + 1 end
    end
    return n
end

-- Rendering a table cell crosses from Lua into Geyser (and, on the web client,
-- into JavaScript/React). A single-player GMCP delta still walks the sorted
-- table, but unchanged cells should not repeat their HTML, tooltip, and callback
-- writes. The row reference is stable in player_db.lua, so callbacks continue to
-- see current data without being replaced when another field changes.
local function renderCellIfChanged(cell, row, signature, render)
    if cell._f2tWhoRow == row and cell._f2tWhoSignature == signature then return end
    render()
    cell._f2tWhoRow = row
    cell._f2tWhoSignature = signature
end

local function refreshHeader(inst)
    local count = onlineCount()
    if inst.hdrCount and inst.onlineCount ~= count then
        inst.hdrCount:echo(string.format("  👥  Online: %d", count))
        inst.onlineCount = count
    end
end

local function refreshInstance(gid)
    local inst = instances[gid]
    if not inst then return end
    refreshHeader(inst)
    f2tTableSetData(inst.tableId, buildTableData(inst.showAll))
end

local function refreshInstanceChanges(gid, changes)
    local inst = instances[gid]
    if not inst then return end
    refreshHeader(inst)
    for key, change in pairs(changes.players or {}) do
        local row = F2T_PLAYER_DB and F2T_PLAYER_DB[key] or nil
        local wasVisible = change.existed and (inst.showAll or change.was_online) or false
        local isVisible = row ~= nil and (inst.showAll or row.is_online) or false
        if wasVisible ~= isVisible then
            refreshInstance(gid)
            return
        end
        if isVisible then
            local ok, refreshed = false, false
            if f2tTableRefreshRow then
                ok, refreshed = pcall(f2tTableRefreshRow, inst.tableId, row)
            end
            if not ok or not refreshed then
                refreshInstance(gid)
                return
            end
        end
    end
end

local function refreshAll()
    for gid in pairs(instances) do
        pcall(refreshInstance, gid)
    end
    if f2tPlayerCardsRefreshAll then f2tPlayerCardsRefreshAll() end
end

local function refreshChanged(changes)
    for gid in pairs(instances) do
        pcall(refreshInstanceChanges, gid, changes)
    end
    if f2tPlayerCardsRefreshAll then f2tPlayerCardsRefreshAll() end
end

-- Column definitions.
local function buildCols()
    return {
        {
            key           = "rank",
            label         = "Rank",
            sortable      = true,
            sort_value    = function(row) return row.rank_order or 0 end,
            scrollbox_pct = 30,
            render_label  = function(v, row, cell)
                local rc = rankColor(row)
                local tooltip = (row.is_online == false and row.last_seen)
                    and ("Last seen " .. f2t_player_db_last_seen_str(row.last_seen)) or ""
                local signature = table.concat({ tostring(v or ""), rc, tooltip }, "\31")
                renderCellIfChanged(cell, row, signature, function()
                    cell:echo(string.format(
                        "<span style='%scolor:%s;'>%s</span>",
                        CELL_FONT, rc, v or ""))
                    cell:setToolTip(tooltip)
                    cell:setClickCallback(function()
                        if f2tPlayerCardShowOrRaise then f2tPlayerCardShowOrRaise(row) end
                    end)
                end)
            end,
        },
        {
            key           = "name",
            label         = "Name",
            sortable      = true,
            default_sort  = "asc",
            scrollbox_pct = 38,
            render_label  = function(v, row, cell)
                local rc      = rankColor(row)
                local staffSfx = (row.staff and row.staff ~= "")
                    and string.format("<span style='%scolor:#ffff55;'> [%s]</span>",
                        CELL_FONT, row.staff:sub(1, 3))
                    or ""
                local signature = table.concat({ tostring(v or ""), rc, staffSfx }, "\31")
                renderCellIfChanged(cell, row, signature, function()
                    cell:echo(string.format(
                        "<span style='%scolor:%s;'><b>%s</b></span>%s",
                        CELL_FONT, rc, v or "", staffSfx))
                    cell:setToolTip("Click to view player card")
                    cell:setClickCallback(function()
                        if f2tPlayerCardShowOrRaise then f2tPlayerCardShowOrRaise(row) end
                    end)
                end)
            end,
        },
        {
            key           = "location",
            label         = "Location",
            sortable      = true,
            scrollbox_pct = 32,
            render_label  = function(v, row, cell)
                v = v or ""
                local lcc    = (row.is_online == false) and RC_OFFLINE or "#00cccc"
                local locSys = v ~= "" and v:match("^(.+) Space$") or nil
                local dest = locSys or v
                local tooltip = ""
                if row.is_online == false and row.last_seen then
                    tooltip = f2t_player_db_last_seen_str(row.last_seen) ..
                        " — navigate to " .. dest
                elseif v ~= "" then
                    tooltip = "Navigate to " .. dest
                end
                local signature = table.concat({ v, lcc, tooltip }, "\31")
                renderCellIfChanged(cell, row, signature, function()
                    if v == "" then
                        cell:echo("")
                        cell:setToolTip("")
                        cell:setClickCallback(function() end)
                        return
                    end
                    cell:echo(string.format(
                        "<span style='%scolor:%s;'>%s</span>",
                        CELL_FONT, lcc, v))
                    cell:setToolTip(tooltip)
                    cell:setClickCallback(function()
                        if locSys then expandAlias("nav " .. locSys .. " link")
                        else            expandAlias("nav " .. v) end
                    end)
                end)
            end,
        },
    }
end

local function buildContent(target)
    local gid = target._gid

    if target.contentBg then
        target.contentBg:echo("")
        target.contentBg:setStyleSheet("background-color: rgba(0,0,0,0); border: none;")
        target.contentBg:hide()
    end

    -- Re-show if already built (e.g. apply called without prior remove)
    if instances[gid] then
        refreshInstance(gid)
        return
    end

    local wc = 0
    local function wid()
        wc = wc + 1
        return string.format("%s_who_%d", gid, wc)
    end

    -- ── Header strip (count + toggle) ────────────────────────────────────────
    local hdrStrip = Geyser.Label:new({
        name = wid(), x = 0, y = 0, width = "100%", height = H_HDR,
    }, target.content)
    hdrStrip:setStyleSheet([[
        background-color: rgba(15, 18, 30, 200);
        border: none;
        border-bottom: 1px solid rgba(70, 75, 110, 150);
    ]])

    local hdrCount = Geyser.Label:new({
        name = wid(), x = 0, y = 0, width = "-80", height = H_HDR,
    }, hdrStrip)
    hdrCount:setStyleSheet([[
        background: transparent; border: none;
        color: rgba(140, 150, 195, 255);
        font-size: 10px; font-family: "Consolas","Monaco",monospace;
        padding: 0 6px;
    ]])
    hdrCount:echo("  👥  Online: —")

    local toggleBtn = Geyser.Label:new({
        name = wid(), x = "-76", y = 2, width = 72, height = H_HDR - 4,
    }, hdrStrip)
    toggleBtn:setStyleSheet([[
        QLabel {
            background-color: rgba(28,32,50,210);
            color: rgba(150,165,205,255);
            border: 1px solid rgba(72,85,128,180);
            border-radius: 3px;
            font-size: 9px; font-family: "Consolas","Monaco",monospace;
            qproperty-alignment: AlignCenter;
        }
        QLabel::hover {
            background-color: rgba(42,48,78,230);
            color: rgba(200,215,255,255);
        }
    ]])
    toggleBtn:echo("<center>Online</center>")
    toggleBtn:setToolTip("Showing online only — click to show all known players")

    -- ── Column header bar ─────────────────────────────────────────────────────
    local colBar = Geyser.Label:new({
        name = wid(), x = 0, y = H_HDR, width = "100%", height = H_COL,
    }, target.content)
    colBar:setStyleSheet([[
        background-color: rgba(18, 20, 35, 200);
        border: none;
        border-bottom: 1px solid rgba(60, 65, 100, 180);
    ]])

    -- ── ScrollBox ─────────────────────────────────────────────────────────────
    local scrollTop = H_HDR + H_COL
    local scroll = Geyser.ScrollBox:new({
        name   = wid(),
        x = 0, y = scrollTop,
        width  = "100%",
        height = "100%-" .. scrollTop .. "px",
    }, target.content)

    local contentW = math.max(100, target.content:get_width() - SB_W)
    local contentLabel = Geyser.Label:new({
        name = wid(), x = 0, y = 0, width = contentW, height = 1000,
    }, scroll)
    contentLabel:setStyleSheet("background-color: rgba(18, 18, 26, 255); border: none;")

    -- ── Table system ──────────────────────────────────────────────────────────
    local tableId = "who_" .. gid
    local cols    = buildCols()
    f2tTableCreate(tableId, cols)
    f2tTableSetScrollbox(tableId, contentLabel, contentW, WHO_ROW_H, scroll)

    -- Column header labels (sortable, click to toggle sort)
    local colHdrs = {}
    local xPct    = 0
    for _, col in ipairs(cols) do
        local lbl = Geyser.Label:new({
            name  = wid(),
            x = xPct .. "%", y = 0,
            width = col.scrollbox_pct .. "%", height = "100%",
        }, colBar)
        lbl:setStyleSheet(_COL_HDR_CSS)
        lbl:echo(col.label)
        if col.sortable then
            local tid, key = tableId, col.key
            lbl:setClickCallback(function() f2tTableToggleSort(tid, key) end)
            lbl:setToolTip("Sort by " .. col.label)
        end
        colHdrs[col.key] = lbl
        xPct = xPct + col.scrollbox_pct
    end
    f2tTableSetColHdrs(tableId, colHdrs)

    -- ── Per-instance state ────────────────────────────────────────────────────
    instances[gid] = {
        tableId      = tableId,
        colHdrs      = colHdrs,
        showAll      = false,
        toggleBtn    = toggleBtn,
        hdrCount     = hdrCount,
        scroll       = scroll,
        contentLabel = contentLabel,
        contentW     = contentW,
    }

    -- Toggle click: switch Online ↔ All, update button label and table data
    toggleBtn:setClickCallback(function()
        local inst = instances[gid]
        if not inst then return end
        inst.showAll = not inst.showAll
        if inst.showAll then
            toggleBtn:echo("<center>All</center>")
            toggleBtn:setToolTip("Showing all known players — click for Online only")
        else
            toggleBtn:echo("<center>Online</center>")
            toggleBtn:setToolTip("Showing online only — click for All known players")
        end
        f2tTableSetData(inst.tableId, buildTableData(inst.showAll))
    end)

    refreshInstance(gid)
end

local function buildWhoDef()
    return {
        name        = "Who",
        description = "Online player list from gmcp.players.",
        group       = "F2CE Tools",
        internal    = false,
        singleton   = false,
        apply = function(target)
            local ok, err = pcall(buildContent, target)
            if not ok then
                f2t_debug_log("[who] apply error: %s", tostring(err))
            end
        end,
        remove = function(target)
            local inst = instances[target._gid]
            if inst then
                f2tTableDestroy(inst.tableId)
                instances[target._gid] = nil
            end
        end,
        resize = function(target)
            local inst = instances[target._gid]
            if not inst then return end
            local newCw = math.max(100, target.content:get_width() - SB_W)
            f2t_debug_log("[who] resize gid=%s content.w=%s scroll.w=%s scroll.h=%s oldCw=%s newCw=%s",
                tostring(target._gid), tostring(target.content:get_width()),
                tostring(inst.scroll and inst.scroll:get_width()),
                tostring(inst.scroll and inst.scroll:get_height()),
                tostring(inst.contentW), tostring(newCw))
            if newCw ~= inst.contentW then
                inst.contentW = newCw
                inst.contentLabel:resize(newCw, inst.contentLabel:get_height())
                f2tTableOnResize(inst.tableId, newCw)
            end
        end,
        serialize = function(_t) return {} end,
        restore   = function(_t, _d) end,
        onReveal  = function(target) refreshInstance(target._gid) end,
    }
end

function f2tRegisterWho()
    if not (Mux and Mux.registerContent) then
        if f2t_debug_log then f2t_debug_log("[who] Muxlet content API unavailable; skipping") end
        return
    end
    Mux.registerContent("fed2_who", buildWhoDef())
    if f2t_debug_log then f2t_debug_log("[who] registered fed2_who content") end
end

F2T_CONTENT_REGISTRARS = F2T_CONTENT_REGISTRARS or {}
table.insert(F2T_CONTENT_REGISTRARS, f2tRegisterWho)

-- Coalesce repaints: gmcp.players deltas can arrive several times a second with
-- many players online. One repaint per 0.2s window keeps the list effectively
-- realtime at a fraction of the render cost.
local _refreshTimer = nil
local _pendingChanges = { version = 1, full = false, players = {} }

-- Other consumers can raise legacy or malformed events. Validate the whole
-- batch before merging it so a bad nested value cannot lose a scheduled paint.
local function validChanges(changes)
    if type(changes) ~= "table" or changes.version ~= 1 or changes.full ~= false
        or type(changes.players) ~= "table" then return false end
    for key, change in pairs(changes.players) do
        if type(key) ~= "string" or key == "" or type(change) ~= "table"
            or (change.key ~= nil and change.key ~= key)
            or type(change.existed) ~= "boolean" or type(change.was_online) ~= "boolean"
            or type(change.fields) ~= "table" then return false end
        for field, changed in pairs(change.fields) do
            if type(field) ~= "string" or changed ~= true then return false end
        end
    end
    return true
end

local function mergePendingChanges(changes)
    if not validChanges(changes) then
        _pendingChanges = { version = 1, full = true, players = {} }
        return
    end
    if _pendingChanges.full then return end
    for key, change in pairs(changes.players or {}) do
        local pending = _pendingChanges.players[key]
        if not pending then
            pending = {
                key        = key,
                existed    = change.existed,
                was_online = change.was_online,
                fields     = {},
            }
            _pendingChanges.players[key] = pending
        end
        for field in pairs(change.fields or {}) do pending.fields[field] = true end
    end
end

registerAnonymousEventHandler("f2tPlayerDbUpdated", function(event_or_changes, event_changes)
    local changes = type(event_changes) == "table" and event_changes
        or (type(event_or_changes) == "table" and event_or_changes or nil)
    mergePendingChanges(changes)
    if _refreshTimer then return end
    _refreshTimer = tempTimer(0.2, function()
        _refreshTimer = nil
        local pending = _pendingChanges
        _pendingChanges = { version = 1, full = false, players = {} }
        if pending.full then refreshAll() else refreshChanged(pending) end
    end)
end)

if f2t_debug_log then f2t_debug_log("[who] module loaded") end
