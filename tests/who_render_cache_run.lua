local repo = arg[1] or "."

local captured_def = nil
local captured_columns = nil
local event_handlers = {}
local timers = {}
local set_data_count = 0
local refresh_row_count = 0
local refresh_row_result = true

local function assert_equal(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
    end
end

local Widget = {}
Widget.__index = Widget

function Widget:new()
    return setmetatable({
        echo_count = 0,
        tooltip_count = 0,
        callback_count = 0,
        width = 500,
        height = 300,
    }, self)
end

function Widget:echo() self.echo_count = self.echo_count + 1 end
function Widget:setToolTip() self.tooltip_count = self.tooltip_count + 1 end
function Widget:setClickCallback() self.callback_count = self.callback_count + 1 end
function Widget:setStyleSheet(style) self.style = style end
function Widget:hide() self.hidden = true end
function Widget:show() self.hidden = false end
function Widget:resize(width, height)
    self.width = width or self.width
    self.height = height or self.height
end
function Widget:move(x, y)
    self.x = x
    self.y = y
end
function Widget:get_width() return self.width end
function Widget:get_height() return self.height end

local Label = setmetatable({}, { __index = Widget })
Label.__index = Label
function Label:new() return setmetatable(Widget:new(), self) end

local ScrollBox = setmetatable({}, { __index = Widget })
ScrollBox.__index = ScrollBox
function ScrollBox:new() return setmetatable(Widget:new(), self) end

Geyser = { Label = Label, ScrollBox = ScrollBox }
Mux = {
    registerContent = function(_, def) captured_def = def end,
}
F2T_CONTENT_REGISTRARS = {}
F2T_PLAYER_DB = {}

function f2t_ui_pt(size) return size end
function f2t_rank_color_hex() return "#abcdef" end
function f2t_player_db_get_offline() return {} end
function f2t_player_db_last_seen_str() return "1m ago" end
function f2t_debug_log() end
function registerAnonymousEventHandler(name, callback)
    event_handlers[name] = callback
    return 1
end
function tempTimer(delay, callback)
    timers[#timers + 1] = { delay = delay, callback = callback }
    return #timers
end
function expandAlias() end
function f2tTableCreate(_, columns) captured_columns = columns end
function f2tTableSetScrollbox() end
function f2tTableSetColHdrs() end
function f2tTableSetData() set_data_count = set_data_count + 1 end
function f2tTableRefreshRow(_, row)
    refresh_row_count = refresh_row_count + 1
    assert_equal(row, F2T_PLAYER_DB.alice, "incremental refresh receives changed row")
    return refresh_row_result
end
function f2tTableToggleSort() end
function f2tTableDestroy() end
function f2tTableOnResize() end

dofile(repo .. "/src/scripts/ui/content/who.lua")
F2T_CONTENT_REGISTRARS[1]()

local target = {
    _gid = "test",
    content = Widget:new(),
    contentBg = Widget:new(),
}
captured_def.apply(target)

local rank_cell = Widget:new()
local name_cell = Widget:new()
local location_cell = Widget:new()
local row = {
    name = "Alice",
    rank = "Trader",
    rank_order = 5,
    location = "Sol Space",
    staff = "",
    is_online = true,
}

captured_columns[1].render_label(row.rank, row, rank_cell)
captured_columns[2].render_label(row.name, row, name_cell)
captured_columns[3].render_label(row.location, row, location_cell)
assert_equal(rank_cell.echo_count, 1, "first rank render")
assert_equal(name_cell.echo_count, 1, "first name render")
assert_equal(location_cell.echo_count, 1, "first location render")

captured_columns[1].render_label(row.rank, row, rank_cell)
captured_columns[2].render_label(row.name, row, name_cell)
captured_columns[3].render_label(row.location, row, location_cell)
assert_equal(rank_cell.echo_count, 1, "unchanged rank is not rewritten")
assert_equal(name_cell.echo_count, 1, "unchanged name is not rewritten")
assert_equal(location_cell.echo_count, 1, "unchanged location is not rewritten")
assert_equal(location_cell.callback_count, 1, "unchanged callback is not replaced")

row.location = "Earth"
captured_columns[1].render_label(row.rank, row, rank_cell)
captured_columns[2].render_label(row.name, row, name_cell)
captured_columns[3].render_label(row.location, row, location_cell)
assert_equal(rank_cell.echo_count, 1, "location change leaves rank alone")
assert_equal(name_cell.echo_count, 1, "location change leaves name alone")
assert_equal(location_cell.echo_count, 2, "location change rewrites location")

row.location = ""
captured_columns[3].render_label(row.location, row, location_cell)
captured_columns[3].render_label(row.location, row, location_cell)
assert_equal(location_cell.echo_count, 3, "blank location clears exactly once")
assert_equal(location_cell.callback_count, 3, "blank location clears callback exactly once")

local replacement = {
    name = "Bob",
    rank = "Trader",
    rank_order = 5,
    location = "Earth",
    staff = "",
    is_online = true,
}
captured_columns[2].render_label(replacement.name, replacement, name_cell)
assert_equal(name_cell.echo_count, 2, "row replacement rewrites cell")
assert_equal(name_cell.callback_count, 2, "row replacement refreshes callback")

local function run_refresh_timer()
    local timer = table.remove(timers, 1)
    assert_equal(timer.delay, 0.2, "Who refresh remains coalesced")
    timer.callback()
end

local function reset_refresh_counts()
    set_data_count = 0
    refresh_row_count = 0
    refresh_row_result = true
end

row.location = "Sol Space"
row.is_online = true
F2T_PLAYER_DB.alice = row
reset_refresh_counts()
event_handlers.f2tPlayerDbUpdated("f2tPlayerDbUpdated", {
    version = 1,
    full = false,
    players = {
        alice = {
            key = "alice", existed = true, was_online = true,
            fields = { location = true },
        },
    },
})
run_refresh_timer()
assert_equal(refresh_row_count, 1, "delta refreshes one existing row")
assert_equal(set_data_count, 0, "delta avoids a full table refresh")

reset_refresh_counts()
event_handlers.f2tPlayerDbUpdated("f2tPlayerDbUpdated", {
    version = 1, full = false,
    players = { alice = { existed = true, was_online = true, fields = { location = true } } },
})
event_handlers.f2tPlayerDbUpdated("f2tPlayerDbUpdated", {
    version = 1, full = false,
    players = { alice = { existed = true, was_online = true, fields = { company = true } } },
})
assert_equal(#timers, 1, "multiple deltas share one refresh timer")
run_refresh_timer()
assert_equal(refresh_row_count, 1, "coalesced player deltas refresh one row")

reset_refresh_counts()
row.is_online = false
event_handlers.f2tPlayerDbUpdated("f2tPlayerDbUpdated", {
    version = 1, full = false,
    players = { alice = { existed = true, was_online = true, fields = { is_online = true } } },
})
run_refresh_timer()
assert_equal(refresh_row_count, 0, "membership change skips row-only refresh")
assert_equal(set_data_count, 1, "membership change rebuilds the table")

reset_refresh_counts()
row.is_online = true
event_handlers.f2tPlayerDbUpdated("f2tPlayerDbUpdated")
run_refresh_timer()
assert_equal(set_data_count, 1, "legacy event rebuilds the table")

reset_refresh_counts()
refresh_row_result = false
event_handlers.f2tPlayerDbUpdated("f2tPlayerDbUpdated", {
    version = 1, full = false,
    players = { alice = { existed = true, was_online = true, fields = { name = true } } },
})
run_refresh_timer()
assert_equal(refresh_row_count, 1, "row refresh is attempted before sort fallback")
assert_equal(set_data_count, 1, "sort fallback rebuilds the table")

for _, malformed in ipairs({
    {version=2, full=false, players={}},
    {version=1, full=false},
    {version=1, full=false, players="bad"},
    {version=1, full=false, players={alice=false}},
    {version=1, full=false, players={alice={existed=true, was_online=true, fields="bad"}}},
    {version=1, full=false, players={alice={existed=true, fields={name=true}}}},
    {version=1, full=false, players={alice={key="bob", existed=true, was_online=true, fields={name=true}}}},
    {version=1, full=false, players={alice={existed=true, was_online=true, fields={name="bad"}}}},
}) do
    reset_refresh_counts()
    event_handlers.f2tPlayerDbUpdated("f2tPlayerDbUpdated", malformed)
    assert_equal(#timers, 1, "malformed payload schedules its safe fallback")
    run_refresh_timer()
    assert_equal(set_data_count, 1, "malformed payload rebuilds from the authoritative DB")
    assert_equal(refresh_row_count, 0, "malformed payload cannot partially repaint rows")
end

reset_refresh_counts()
event_handlers.f2tPlayerDbUpdated("f2tPlayerDbUpdated", {
    version=1, full=false,
    players={alice={existed=true, was_online=true, fields={location=true}}},
})
event_handlers.f2tPlayerDbUpdated("f2tPlayerDbUpdated", {version=1, full=false, players={alice=3}})
assert_equal(#timers, 1, "malformed delta shares an existing pending timer")
run_refresh_timer()
assert_equal(set_data_count, 1, "malformed coalesced delta promotes the whole batch to full refresh")
assert_equal(refresh_row_count, 0, "previous partial delta is not painted ahead of fallback")

print("who render cache: ok")
