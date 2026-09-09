-- SPDX-License-Identifier: GPL-2.0-only
-- Remote exchange board using the same sortable table system as Exchange.
local EW = F2T_EXCHANGE_WALKER
local view_id, view_api, view_session = "f2ce.exchange_walker_view", nil, nil
local board = { rows = {}, planet = nil, captured_at = nil, message = "Enter a planet below, then Refresh." }
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
    return tostring(value or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key, item in pairs(value) do result[key] = copy(item) end; return result
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
    { key = "name", label = "Commodity", scrollbox_pct = 26, default_sort = "asc" },
    { key = "spread", label = "Spread", scrollbox_pct = 10 },
    { key = "stock_current", label = "Current", scrollbox_pct = 14 },
    { key = "stock_min", label = "Min", scrollbox_pct = 12 },
    { key = "stock_max", label = "Max", scrollbox_pct = 12 },
    { key = "efficiency", label = "Efficiency", scrollbox_pct = 14 },
    { key = "net", label = "Net", scrollbox_pct = 12 },
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
    column.render_label = function(value, row, cell)
        local number = tonumber(value)
        local color = key == "name" and "#ce91e8" or "#d8d8d8"
        local text = tostring(value or "—")
        if key == "spread" or key == "efficiency" then text = text .. "%" end
        if key == "net" and number and number > 0 then text = "+" .. text end
        if key == "net" or key == "stock_current" then
            color = number and (number > 0 and "#65dd75" or (number < 0 and "#ff7373" or "#e7cc70")) or color
        end
        local proposed = proposal(row, key)
        local changed = proposed ~= nil and proposed ~= number
        if changed then color = "#65dbff" end
        cell:echo(string.format("<div align='%s' style='font-family:Consolas,monospace;font-size:9pt;color:%s;'>%s</div>",
            key == "name" and "left" or "right", color, escape(text)))
        cell:setToolTip(changed and string.format("%s: observed %s → proposed %s. Apply requires an explicit reviewed plan.", row.name, tostring(value), tostring(proposed)) or tostring(value))
        cell:setClickCallback(function() end) -- informational cells never trade
    end
end
EW.ui.boardColumns = columns
local function label(parent, name, x, y, width, height, text, action)
    local widget = Geyser.Label:new({ name = name, x = x, y = y, width = width, height = height }, parent)
    widget:setStyleSheet("background-color:#171b29;color:#ddd;border:1px solid #353c50;font-family:Consolas;font-size:9pt;")
    widget:echo(text)
    if action then widget:setClickCallback(action) end
    return widget
end
function EW.ui.resizeTable(target)
    local instance = EW.ui.instances[target]
    if not instance or not instance.table_id then return end
    local width = math.max(100, target.content:get_width() - 17)
    instance.body:resize(width, instance.body:get_height())
    local x = 0
    for index, column in ipairs(columns) do
        local cell_width = index == #columns and width - x or math.floor(width * column.scrollbox_pct / 100)
        instance.headers[index]:move(x, 0); instance.headers[index]:resize(cell_width, 22); x = x + cell_width
    end
    f2tTableOnResize(instance.table_id, width)
end
function EW.ui.updateTable()
    for target, instance in pairs(EW.ui.instances) do
        if instance.table_id then
            local rank = EW.rankAllowed()
            instance.title:echo(escape(rank and ((board.planet or "Exchange Walker") .. " | " .. (board.captured_at and os.date("%H:%M:%S", board.captured_at) or "no capture")) or "Founder rank required"))
            local message = EW.plan and EW.plan.planet == board.planet and not EW.plan.applied
                and (#EW.plan.actions .. " reviewed changes. Cyan cells: hover to compare observed → proposed.") or board.message
            instance.status:echo(escape(message))
            f2tTableSetData(instance.table_id, rank and copy(board.rows) or {})
            if Mux.reassertHidden then Mux.reassertHidden(target.content) end
        end
    end
end
function EW.ui.buildTable(target)
    assert(Geyser.ScrollBox and Geyser.CommandLine and f2tTableCreate, "native exchange table UI is not ready")
    if target.contentBg then target.contentBg:hide() end
    EW.ui.instance_counter = EW.ui.instance_counter + 1
    local id = "ew_board_" .. EW.ui.instance_counter
    local instance = { target = target, table_id = id, controls = {}, headers = {} }
    EW.ui.instances[target] = instance
    EW.ui.registered_target = target
    instance.title = label(target.content, id .. "title", 0, 0, "100%", 22, "Exchange Walker")
    instance.header = label(target.content, id .. "header", 0, 22, "100%", 22, "")
    instance.scroll = Geyser.ScrollBox:new({ name = id .. "scroll", x = 0, y = 44, width = "100%", height = "100%-140px" }, target.content)
    instance.body = label(instance.scroll, id .. "body", 0, 0, "100%", 1000, "")
    f2tTableCreate(id, columns)
    f2tTableSetScrollbox(id, instance.body, math.max(100, target.content:get_width() - 17), 20, instance.scroll)
    local header_map = {}
    for index, column in ipairs(columns) do
        local key = column.key
        local header = label(instance.header, id .. "col" .. index, 0, 0, 1, 22, column.label,
            function() f2tTableToggleSort(id, key) end)
        header:setToolTip("Sort by " .. column.label)
        instance.headers[index], header_map[key] = header, header
    end
    f2tTableSetColHdrs(id, header_map)
    instance.status = label(target.content, id .. "status", 0, "100%-94px", "100%", 22, "")
    local input = Geyser.CommandLine:new({ name = id .. "planet", x = 0, y = "100%-70px", width = "60%", height = 30 }, target.content)
    input:print(board.planet or EW.settings.targets[1] or "")
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
        instance.controls[button[1]] = label(target.content, id .. button[1], ((index - 1) * 100 / 6) .. "%", "100%-36px", (100 / 6) .. "%", 32, button[2], function()
            if action then EW[action]()
            elseif button[1] == "settings" then EW.settings.open()
            else board.rows, board.planet, board.captured_at = {}, nil, nil; EW.ui.clear(); EW.ui.updateTable() end
        end)
    end
    -- Keep operational messages in one status line, not mixed into data rows.
    instance.console = { cecho = function(_, text)
        board.message = tostring(text):gsub("<[^>]+>", ""):gsub("\n", " "); instance.status:echo(escape(board.message))
    end, clear = function() end }
    EW.ui.resizeTable(target); EW.ui.updateTable(); EW.refresh()
end
function EW.ui.destroyTable(target)
    local instance = EW.ui.instances[target]
    if not instance or not instance.table_id then return end
    f2tTableDestroy(instance.table_id)
    for _, header in ipairs(instance.headers) do header:hide(); if header.delete then header:delete() end end
    for _, key in ipairs({ "title", "header", "scroll", "body", "status", "input" }) do
        local widget = instance[key]; if widget then widget:hide(); if widget.delete then widget:delete() end end
    end
end
