-- SPDX-License-Identifier: GPL-2.0-only
-- Remote exchange board using the same sortable table system as Exchange.
local EW = F2T_EXCHANGE_WALKER
local view_id, view_api, view_session = "f2ce.exchange_walker_view", nil, nil
local board = { rows = {}, planet = nil, captured_at = nil, message = "Refresh reads an exchange while OFF. ON → Preview → Apply changes it." }
EW.board = board
local function api() return F2CE and F2CE.API and F2CE.API.v1 end
function EW.rankAllowed()
    local current = api()
    return current and current.character and current.character.hasRank("Founder") or false
end
function EW.cancelView(reason)
    if view_session then view_session:release(reason or "view_cancelled"); view_session = nil end
    if view_api then view_api.modules.disable(view_id, reason or "view_cancelled") end
end
local function escape(value)
    -- gsub also returns a replacement count. Never pass it to Label:echo as
    -- the optional color argument (Geyser.Color.parse cannot parse a number).
    return (tostring(value or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key, item in pairs(value) do result[key] = copy(item) end; return result
end
local function set_tooltip(widget, text)
    -- Geyser.CommandLine in Mudlet 5.0.1 has no setToolTip method. Tooltips
    -- are enhancement-only: an unsupported widget must never abort the board
    -- constructor and strand every control created after it.
    if widget and type(widget.setToolTip) == "function" then
        return pcall(widget.setToolTip, widget, text)
    end
    return false
end
function EW.ui.setBoard(planet, rows)
    if type(rows) ~= "table" or not tonumber(rows._expected_count) or #rows ~= tonumber(rows._expected_count) then return false end
    local seen = {}
    for _, row in ipairs(rows) do
        if type(row.name) ~= "string" or seen[row.name:lower()] then return false end
        seen[row.name:lower()] = true
        for _, key in ipairs({ "spread", "stock_current", "stock_min", "stock_max", "efficiency", "net" }) do
            local number = tonumber(row[key])
            if not number or number ~= number or math.abs(number) == math.huge then return false end
        end
    end
    board.planet, board.rows, board.captured_at = planet, copy(rows), os.time()
    board.message = string.format("%d commodities captured. Values are from the last complete response.", #rows)
    EW.ui.updateTable()
    return true
end
function EW.inspect(planet)
    if not EW.rankAllowed() then return false, "Founder rank or higher is required" end
    if EW.isBlocked() or EW.busy or EW.applying or view_session then return false, "Exchange Walker is busy or blocked" end
    planet = EW.policy.safePlanet(planet)
    if not planet then return false, "Enter a valid planet name" end
    local current = api()
    if view_api ~= current or not current.modules.status(view_id) then
        local registered, why = current.modules.register({ id = view_id, version = EW.VERSION,
            requires = { api = ">=1.1.0", capabilities = { "exchange.capture" } },
            disable = function() if view_session then view_session:release("view_disabled"); view_session = nil end end,
        })
        if not registered then return false, tostring(why) end
        view_api = current
    end
    local context, why = current.modules.enable(view_id)
    if not context then return false, tostring(why) end
    view_session, why = current.exchange.acquire(context, { reason = "explicit remote exchange board refresh" })
    if not view_session then current.modules.disable(view_id); return false, tostring(why) end
    board.message = "Capturing " .. planet .. "..."; EW.ui.updateTable()
    local session = view_session
    local started, reason = session:capture("exchange", planet, function(rows, failure)
        session:release("board_capture_complete"); view_session = nil
        current.modules.disable(view_id, "read_complete")
        if not EW.rankAllowed() then return end
        if failure or not EW.ui.setBoard(planet, rows) then
            board.message = "Capture incomplete; previous table retained. " .. tostring(failure or "No validated summary.")
            EW.ui.updateTable()
        end
    end)
    if not started then session:release("capture_failed"); view_session = nil; current.modules.disable(view_id); return false, tostring(reason) end
    return true
end

local columns = {
    { key = "name", label = "Commodity", scrollbox_pct = 28, default_sort = "asc" },
    { key = "spread", label = "Spread", scrollbox_pct = 9.5 },
    { key = "stock_current", label = "Current", scrollbox_pct = 12.5 },
    { key = "stock_min", label = "Min", scrollbox_pct = 12.5 },
    { key = "stock_max", label = "Max", scrollbox_pct = 12.5 },
    { key = "efficiency", label = "Efficiency", compact = "Eff.%", scrollbox_pct = 12 },
    { key = "net", label = "Net", scrollbox_pct = 13 },
}
local function proposal(row, key)
    if not EW.plan or EW.plan.planet ~= board.planet or EW.plan.applied then return nil end
    local field = ({ spread = "target_spread", stock_min = "target_min", stock_max = "target_max" })[key]
    if not field then return nil end
    for _, candidate in ipairs(EW.plan.rows) do if candidate.commodity == row.name then return candidate[field] end end
end
for _, column in ipairs(columns) do
    local key = column.key
    column.sortable = true
    column.render_label = function(value, row, cell, definition)
        local number = tonumber(value)
        local color = key == "name" and "#ce91e8" or "#d8d8d8"
        local text = tostring(value or "—")
        local font = definition and definition.font_pt or 9
        if key == "name" then
            local limit = math.max(4, math.floor((cell:get_width() - 6) / (font * 0.81)))
            if #text > limit then text = text:sub(1, limit - 1) .. "~" end
        end
        if key == "spread" or key == "efficiency" then text = text .. "%" end
        if key == "net" and number and number > 0 then text = "+" .. text end
        if key == "net" or key == "stock_current" then
            color = number and (number > 0 and "#65dd75" or (number < 0 and "#ff7373" or "#e7cc70")) or color
        end
        local proposed = proposal(row, key)
        local changed = proposed ~= nil and proposed ~= number
        if changed then color = "#65dbff" end
        -- This board supplies its colors in HTML/CSS. Explicitly bypass
        -- Geyser.Label:echo's color parser so a bad inherited/multiple-return
        -- color can never abort the entire Mux content apply.
        cell:echo(string.format("<div align='%s' style='white-space:nowrap;font-family:Consolas,monospace;font-size:%dpt;color:%s;'>%s</div>",
            key == "name" and "left" or "right", font, color, escape(text)), "nocolor")
        set_tooltip(cell, changed and string.format("%s: observed %s -> proposed %s. Apply requires an explicit reviewed plan.", row.name, tostring(value), tostring(proposed)) or tostring(value))
        cell:setClickCallback(function() end) -- informational cells never trade
    end
end
EW.ui.boardColumns = columns
local required_widgets = { "background", "title", "header", "scroll", "body", "empty",
    "status", "input", "planet_label" }
local required_controls = { "refresh", "preview", "toggle", "apply", "auto", "cancel", "settings", "clear" }
local function live_widget(widget)
    return type(widget) == "table" and widget.deleted ~= true
end
function EW.ui.instanceHealthy(target)
    local instance = EW.ui.instances[target]
    if type(instance) ~= "table" or not instance.table_id then return false end
    for _, key in ipairs(required_widgets) do
        if not live_widget(instance[key]) then return false end
    end
    if type(instance.headers) ~= "table" or #instance.headers ~= #columns
        or type(instance.controls) ~= "table" then return false end
    for _, key in ipairs(required_controls) do
        if not live_widget(instance.controls[key]) then return false end
    end
    return true
end
local function target_dimensions(target)
    local content = target and target.content
    local width = content and tonumber(content:get_width()) or 0
    local height = content and tonumber(content:get_height()) or 0
    -- Muxlet restores every saved tab before activating the selected one. An
    -- inactive tab can therefore report 0x0 even though its host viewport has
    -- final geometry. Build against that viewport so the first reveal is not a
    -- correctly registered but visually empty black surface.
    local host = target and target.pane
    local viewport = host and (host._tabViewport or host.content)
    if viewport then
        if width <= 1 then width = tonumber(viewport:get_width()) or width end
        if height <= 1 then height = tonumber(viewport:get_height()) or height end
    end
    return math.max(1, width), math.max(1, height)
end
local function target_is_active(target)
    local current = target
    while current do
        if current._conditionHidden then return false end
        local host = current.pane
        if not host then return true end
        if host._activeTabId ~= current.id then return false end
        current = host
    end
    return true
end
local function restore_paint_order(instance)
    -- Geyser.Container:show() reveals children through pairs(windowList), whose
    -- traversal order is undefined. On a board first constructed in a hidden
    -- tab, that can leave this full-pane black label above every useful widget
    -- when the tab is revealed. A directly mounted pane is built visible and
    -- therefore does not expose the defect. Pin the background beneath its
    -- siblings, then raise the visible board layers in their intended order.
    if instance.background and type(instance.background.lower) == "function" then
        pcall(instance.background.lower, instance.background)
    end
    local foreground = { instance.title, instance.header }
    for _, widget in ipairs(foreground) do
        if widget and type(widget.raise) == "function" then pcall(widget.raise, widget) end
    end
    -- Column headings are direct children of the Mux content slot. Keeping
    -- them out of the decorative header Label avoids the Mudlet 5.0.1 nested
    -- Label visibility bug that can leave an otherwise populated table with
    -- no headings after a hidden tab is revealed.
    for _, widget in ipairs(instance.headers or {}) do
        if widget and type(widget.raise) == "function" then pcall(widget.raise, widget) end
    end
    for _, widget in ipairs({ instance.scroll, instance.status, instance.planet_label, instance.input }) do
        if widget and type(widget.raise) == "function" then pcall(widget.raise, widget) end
    end
    for _, key in ipairs({ "refresh", "preview", "toggle", "apply", "auto", "cancel", "settings", "clear" }) do
        local widget = instance.controls and instance.controls[key]
        if widget and type(widget.raise) == "function" then pcall(widget.raise, widget) end
    end
end
local function reveal_active(target, instance)
    if not target_is_active(target) then return end
    -- Muxlet/Geyser keep explicit and inherited visibility separately. Clear
    -- both on the tab container and framework-owned content slot. Container
    -- show(true) then clears inherited hiding recursively while preserving any
    -- deliberate explicit hide on state-dependent children such as `empty`.
    for _, container in ipairs({ target.content, target._contentSlot }) do
        if container and type(container.show) == "function" then
            pcall(container.show, container, false)
            pcall(container.show, container, true)
        end
    end
    restore_paint_order(instance)
end
local function label(parent, name, x, y, width, height, text, action)
    local widget = Geyser.Label:new({ name = name, x = x, y = y, width = width, height = height, fgColor = "#d8d8d8" }, parent)
    widget:setStyleSheet("background-color:#171b29;color:#ddd;border:1px solid #353c50;font-family:Consolas;font-size:9pt;")
    -- All board text is CSS-colored. `nocolor` avoids Mudlet 5.0.1's
    -- Geyser.Color.parse path and becomes the safe inherited color for later
    -- one-argument echoes from the shared table header renderer.
    widget:echo(text, "nocolor")
    if action then widget:setClickCallback(action) end
    return widget
end
local function set_style(widget, css)
    if widget and type(widget.setStyleSheet) == "function" then pcall(widget.setStyleSheet, widget, css) end
end
local function button_css(background, border)
    return "QLabel { background-color:" .. background .. ";color:#f3f6fb;border:1px solid " .. border
        .. ";border-radius:3px;padding:2px;font-family:Consolas;font-size:9pt;font-weight:bold;}"
        .. " QLabel:hover { background-color:#33415c;border-color:#91b8ff;color:white;}"
end
function EW.ui.resizeTable(target)
    local instance = EW.ui.instances[target]
    if not instance or not instance.table_id then return end
    local pane_width, pane_height = target_dimensions(target)
    local width = math.max(1, pane_width - 17)
    local footer_y = math.max(44, pane_height - 142)
    local function place(widget, x, y, w, h)
        -- Keep laying out the remaining footer if a future Geyser primitive
        -- lacks one of the ordinary Container methods. A single decorative or
        -- input widget must not make every later action disappear.
        if not widget then return false end
        local moved = type(widget.move) == "function" and pcall(widget.move, widget, x, y)
        local resized = type(widget.resize) == "function" and pcall(widget.resize, widget, w, h)
        return moved and resized or false
    end
    place(instance.background, 0, 0, pane_width, pane_height)
    place(instance.title, 0, 0, pane_width, 22)
    place(instance.header, 0, 22, pane_width, 22)
    place(instance.scroll, 0, 44, pane_width, math.max(0, footer_y - 48))
    place(instance.status, 2, footer_y, math.max(1, pane_width - 4), 38)
    local input_end, refresh_end = math.floor(pane_width * 0.60), math.floor(pane_width * 0.80)
    place(instance.planet_label, 2, footer_y + 40, 56, 30)
    place(instance.input, 60, footer_y + 40, math.max(1, input_end - 62), 30)
    place(instance.controls.refresh, input_end + 2, footer_y + 40, math.max(1, refresh_end - input_end - 4), 30)
    place(instance.controls.preview, refresh_end + 2, footer_y + 40, math.max(1, pane_width - refresh_end - 4), 30)
    for index, key in ipairs({ "toggle", "apply", "auto", "cancel", "settings", "clear" }) do
        local col = (index - 1) % 3
        local left, right = math.floor(pane_width * col / 3), math.floor(pane_width * (col + 1) / 3)
        place(instance.controls[key], left + 2, footer_y + 74 + math.floor((index - 1) / 3) * 32,
            math.max(1, right - left - 4), 30)
    end
    place(instance.empty, 8, 12, math.max(1, width - 16), 90)
    instance.body:resize(width, instance.body:get_height())
    local x = 0
    for index, column in ipairs(instance.columns) do
        local compact = width < 700
        column.label = compact and (columns[index].compact or columns[index].label) or columns[index].label
        column.font_pt = compact and 8 or 9
        column.header_css = "background-color:transparent;border:none;padding:0 2px;color:#d8d8d8;font-family:Consolas;font-size:" .. column.font_pt .. "pt;"
        column.header_active_css = column.header_css .. "color:#65dd75;"
        local cell_width = index == #instance.columns and width - x or math.floor(width * column.scrollbox_pct / 100)
        instance.headers[index]:move(x, 22); instance.headers[index]:resize(cell_width, 22); x = x + cell_width
    end
    f2tTableOnResize(instance.table_id, width)
end
function EW.ui.refreshMounted(target, settle)
    if not EW.ui.instanceHealthy(target) then return false end
    reveal_active(target, EW.ui.instances[target])
    return EW.ui.reflowTable(target, settle == true)
end
function EW.ui.reflowTable(target, settle)
    local instance = EW.ui.instances[target]
    if not instance or not instance.table_id then return false end
    local function reflow()
        if F2T_EXCHANGE_WALKER ~= EW or EW.ui.instances[target] ~= instance then return end
        EW.ui.resizeTable(target)
        EW.ui.updateTable()
        reveal_active(target, instance)
    end
    reflow()
    if settle and type(tempTimer) == "function" then
        for _, timer_id in ipairs(instance.reflow_timer_ids or {}) do
            if type(killTimer) == "function" then pcall(killTimer, timer_id) end
        end
        instance.reflow_timer_ids = {}
        -- Hidden Mux tabs can report 0x0 while content is first applied. The
        -- tab switch updates Qt geometry asynchronously, so re-read it on the
        -- next event-loop turn as well as immediately above.
        local timer_id = tempTimer(0, function()
            instance.reflow_timer_ids = {}
            reflow()
        end)
        if timer_id then instance.reflow_timer_ids[1] = timer_id end
    end
    return true
end
local function update_status(instance, message)
    local state = (EW.enabled and "ON" or "OFF") .. " | " .. (EW.scheduler.enabled and "AUTO ON" or "AUTO OFF")
        .. " | " .. #EW.settings.targets .. " targets | every " .. EW.settings.interval_minutes .. "m"
    -- Keep the footer compact; the complete diagnostic is available on hover.
    local limit = math.max(20, math.floor(instance.status:get_width() / 6.5))
    local detail = #message > limit and message:sub(1, limit - 3) .. "..." or message
    local state_color = EW.enabled and "#65dd75" or "#ff8b8b"
    instance.status:echo("<div style='font-family:Consolas;font-size:8pt;padding:2px 5px;'>"
        .. "<span style='color:" .. state_color .. ";font-weight:bold;'>" .. escape(state) .. "</span><br>"
        .. "<span style='color:#aeb8cc;'>" .. escape(detail) .. "</span></div>")
    set_tooltip(instance.status, message .. "\nTargets: " .. (#EW.settings.targets > 0 and table.concat(EW.settings.targets, ", ") or "none; set these in Settings"))
end
function EW.ui.updateTable()
    for target, instance in pairs(EW.ui.instances) do
        if instance.table_id then
            local rank = EW.rankAllowed()
            instance.title:echo(escape(rank and ((board.planet or "Exchange Walker") .. " | " .. (board.captured_at and os.date("%H:%M:%S", board.captured_at) or "no capture")) or "Founder rank required"))
            local message = EW.plan and EW.plan.planet == board.planet and not EW.plan.applied
                and ("Preview ready: " .. #EW.plan.actions .. " changes. Cyan cells show observed vs proposed values.") or board.message
            update_status(instance, message)
            instance.controls.toggle:echo("<center><b>" .. (EW.enabled and "TURN OFF" or "TURN ON") .. "</b></center>", "nocolor")
            instance.controls.auto:echo("<center><b>" .. (EW.scheduler.enabled and "AUTO OFF" or "AUTO ON") .. "</b></center>", "nocolor")
            set_style(instance.controls.toggle, button_css(EW.enabled and "#7f1d2d" or "#17613a", EW.enabled and "#e06070" or "#4cc77c"))
            set_style(instance.controls.auto, button_css(EW.scheduler.enabled and "#7f1d2d" or "#285d70", EW.scheduler.enabled and "#e06070" or "#58b9d1"))
            if instance.input:getText() == "" and EW.settings.targets[1] then instance.input:print(EW.settings.targets[1]) end
            f2tTableSetData(instance.table_id, rank and copy(board.rows) or {})
            if not rank or #board.rows == 0 then
                instance.empty:echo(not rank and "Founder rank or higher is required." or board.captured_at
                    and "This exchange returned no commodities." or "<b>No exchange loaded</b><br>Type a planet below, then choose Refresh to inspect or Preview to plan.<br>Automation targets and schedules are configured in Settings.")
                instance.empty:show()
            else instance.empty:hide() end
            if Mux.reassertHidden then Mux.reassertHidden(target.content) end
        end
    end
end
function EW.ui.buildTable(target)
    assert(Geyser.ScrollBox and Geyser.CommandLine and f2tTableCreate, "native exchange table UI is not ready")
    if target.contentBg then target.contentBg:hide() end
    EW.ui.instance_counter = EW.ui.instance_counter + 1
    local id = "ew_board_" .. EW.ui.instance_counter
    local instance = { target = target, table_id = id, controls = {}, headers = {}, columns = copy(columns) }
    EW.ui.instances[target] = instance
    EW.ui.registered_target = target
    instance.background = label(target.content, id .. "background", 0, 0, "100%", "100%", "")
    set_style(instance.background, "background-color:#0d111b;border:none;")
    instance.title = label(target.content, id .. "title", 0, 0, "100%", 22, "Exchange Walker")
    set_style(instance.title, "background-color:#131a29;color:#eef4ff;border:none;border-bottom:1px solid #40506d;padding:2px 6px;font-family:Consolas;font-size:9pt;font-weight:bold;")
    instance.header = label(target.content, id .. "header", 0, 22, "100%", 22, "")
    instance.scroll = Geyser.ScrollBox:new({ name = id .. "scroll", x = 0, y = 44, width = "100%", height = "100%-140px" }, target.content)
    instance.body = label(instance.scroll, id .. "body", 0, 0, "100%", 1000, "")
    instance.empty = label(instance.body, id .. "empty", 8, 12, "100%-16px", 90, "")
    instance.empty:setStyleSheet("background-color:transparent;border:none;color:#aaa;font-family:Consolas;font-size:9pt;")
    f2tTableCreate(id, instance.columns)
    f2tTableSetScrollbox(id, instance.body, math.max(100, target.content:get_width() - 17), 20, instance.scroll)
    local header_map = {}
    for index, column in ipairs(columns) do
        local key = column.key
        local header = label(target.content, id .. "col" .. index, 0, 22, 1, 22, column.label,
            function() f2tTableToggleSort(id, key) end)
        set_tooltip(header, "Sort by " .. column.label)
        instance.headers[index], header_map[key] = header, header
    end
    f2tTableSetColHdrs(id, header_map)
    instance.status = label(target.content, id .. "status", 0, "100%-94px", "100%", 22, "")
    set_style(instance.status, "background-color:#111827;color:#aeb8cc;border:1px solid #33415c;border-radius:3px;")
    instance.planet_label = label(target.content, id .. "planet_label", 0, 0, 56, 30, "<center>Inspect</center>")
    set_style(instance.planet_label, "background-color:#182235;color:#b9c9e6;border:1px solid #3d4d68;border-radius:3px;font-family:Consolas;font-size:8pt;font-weight:bold;")
    set_tooltip(instance.planet_label, "One-off planet to inspect. This does not change the scheduled target list.")
    local input = Geyser.CommandLine:new({ name = id .. "planet", x = 0, y = "100%-70px", width = "60%", height = 30 }, target.content)
    set_style(input, "background-color:#090d16;color:#f0f5ff;border:1px solid #58719a;border-radius:3px;padding:2px 6px;font-family:Consolas;font-size:9pt;")
    set_tooltip(input, "Type a planet name. Press Enter or Refresh for a read-only exchange scan; Preview calculates proposed settings without applying them.")
    local current = api() and api().data.get("room")
    local vitals = api() and api().data.get("vitals")
    local owned = current and vitals and current.owner == vitals.name and EW.policy.safePlanet(current.area)
    input:print(board.planet or EW.settings.targets[1] or owned or "")
    instance.input = input
    local function refresh()
        local ok, reason = EW.inspect(input:getText())
        if not ok then board.message = tostring(reason); EW.ui.updateTable() end
    end
    input:setAction(refresh)
    instance.controls.refresh = label(target.content, id .. "refresh", "60%", "100%-70px", "20%", 30, "Refresh", refresh)
    instance.controls.preview = label(target.content, id .. "preview", "80%", "100%-70px", "20%", 30, "Preview", function() EW.preview(input:getText()) end)
    local buttons = { {"toggle", "ON / OFF", "toggle"}, {"apply", "Apply", "apply"}, {"auto", "Auto", "autoToggle"},
        {"cancel", "Cancel", "cancel"}, {"settings", "Settings"}, {"clear", "Clear"} }
    for index, button in ipairs(buttons) do
        local action = button[3]
        instance.controls[button[1]] = label(target.content, id .. button[1], 0, 0, 1, 28, "<center>" .. button[2] .. "</center>", function()
            if action then EW[action]()
            elseif button[1] == "settings" then EW.settings.open()
            else board.rows, board.planet, board.captured_at = {}, nil, nil; board.message = "Choose a planet below and Refresh."; EW.ui.clear(); EW.ui.updateTable() end
        end)
    end
    local palette = {
        refresh={"#234f82", "#5c91cf"}, preview={"#503f78", "#8f77c9"}, apply={"#75501f", "#d49a4c"},
        cancel={"#6f2630", "#cf6572"}, settings={"#39445a", "#70809f"}, clear={"#303849", "#65728b"},
    }
    for key, colors in pairs(palette) do set_style(instance.controls[key], button_css(colors[1], colors[2])) end
    set_tooltip(instance.controls.refresh, "Read-only: capture and display the selected planet's remote exchange.")
    set_tooltip(instance.controls.preview, "Calculate proposed spread and stock changes for the selected planet. Sends no setting commands.")
    set_tooltip(instance.controls.apply, "Apply the current reviewed and unexpired preview plan.")
    set_tooltip(instance.controls.cancel, "Cancel the current capture or discard unsent planned actions.")
    set_tooltip(instance.controls.settings, "Open Exchange Walker targets, schedule, spreads, reserves, and commodity exclusions.")
    set_tooltip(instance.controls.clear, "Clear the displayed exchange table and preview from this board.")
    -- Keep operational messages in one status line, not mixed into data rows.
    instance.console = { cecho = function(_, text)
        board.message = tostring(text):gsub("<[^>]+>", ""):gsub("\n", " "); update_status(instance, board.message)
    end, clear = function() end }
    EW.ui.reflowTable(target, true); EW.refresh()
    restore_paint_order(instance)
end
function EW.ui.destroyTable(target)
    local instance = EW.ui.instances[target]
    if not instance or not instance.table_id then return end
    for _, timer_id in ipairs(instance.reflow_timer_ids or {}) do
        if type(killTimer) == "function" then pcall(killTimer, timer_id) end
    end
    instance.reflow_timer_ids = {}
    f2tTableDestroy(instance.table_id)
    for _, header in ipairs(instance.headers) do header:hide(); if header.delete then header:delete() end end
    for _, key in ipairs({ "empty", "title", "header", "body", "scroll", "status", "input", "planet_label", "background" }) do
        local widget = instance[key]; if widget then widget:hide(); if widget.delete then widget:delete() end end
    end
end
