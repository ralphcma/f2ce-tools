local repo = arg[1] or "."

local function assert_equal(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
    end
end

local Widget = {}
Widget.__index = Widget

function Widget:new(options)
    options = options or {}
    return setmetatable({
        name = options.name,
        width = options.width or 500,
        height = options.height or 300,
        hidden = false,
    }, self)
end

function Widget:setStyleSheet(style) self.style = style end
function Widget:echo(value) self.value = value end
function Widget:setClickCallback(callback) self.callback = callback end
function Widget:hide() self.hidden = true end
function Widget:show() self.hidden = false end
function Widget:move(x, y) self.x, self.y = x, y end
function Widget:resize(width, height) self.width, self.height = width, height end
function Widget:get_width() return self.width end
function Widget:get_height() return self.height end

local Label = setmetatable({}, { __index = Widget })
Label.__index = Label
function Label:new(options) return setmetatable(Widget:new(options), self) end

Geyser = { Label = Label }
Mux = { reassertHidden = function() end }
function f2t_ui_pt(size) return size end

dofile(repo .. "/src/scripts/ui/table_system.lua")

local renders = {}
local function render(value, row, cell)
    renders[row.name] = (renders[row.name] or 0) + 1
    cell:echo(value)
end

local columns = {
    {
        key = "name", label = "Name", sortable = true, default_sort = "asc",
        scrollbox_pct = 50, render_label = render,
    },
    {
        key = "location", label = "Location", sortable = true,
        scrollbox_pct = 50, render_label = render,
    },
}
local alice = { name = "Alice", location = "Earth" }
local bob = { name = "Bob", location = "Mars" }
local content = Widget:new({ width = 500, height = 300 })
local scroll = Widget:new({ width = 500, height = 300 })

f2tTableCreate("test", columns)
f2tTableSetScrollbox("test", content, 500, 20, scroll)
f2tTableSetData("test", { alice, bob })
assert_equal(renders.Alice, 2, "initial render paints Alice cells")
assert_equal(renders.Bob, 2, "initial render paints Bob cells")

renders = {}
alice.location = "Sol Space"
assert_equal(f2tTableRefreshRow("test", alice), true, "stable sort position refreshes in place")
assert_equal(renders.Alice, 2, "row refresh paints only Alice cells")
assert_equal(renders.Bob, nil, "row refresh does not paint Bob cells")

renders = {}
alice.name = "Zulu"
assert_equal(f2tTableRefreshRow("test", alice), false, "sort movement requests full fallback")
assert_equal(next(renders), nil, "sort fallback does not partially repaint")

f2tTableSetData("test", { alice, bob })
assert_equal(renders.Zulu, 2, "full fallback repaints renamed row")
assert_equal(renders.Bob, 2, "full fallback repaints other rows")
assert_equal(f2tTableRefreshRow("test", { name = "Unknown" }), false,
    "unknown row requests full fallback")

-- Native Exchange Walker extends this shared table with per-column header
-- styles and a dynamic viewport floor. The Who integration must retain both.
columns[1].header_css = "walker-name-idle"
columns[1].header_active_css = "walker-name-active"
columns[2].header_css = "walker-location-idle"
columns[2].header_active_css = "walker-location-active"
local headers = {name=Widget:new(), location=Widget:new()}
f2tTableSetColHdrs("test", headers)
f2tTableUpdateScrollboxHeader("test", headers)
assert_equal(headers.name.style, "walker-name-active", "custom sorted header styling survives")
assert_equal(headers.location.style, "walker-location-idle", "custom inactive header styling survives")
f2tTableToggleSort("test", "location")
assert_equal(headers.name.style, "walker-name-idle", "old sorted header returns to its own idle style")
assert_equal(headers.location.style, "walker-location-active", "new sorted header uses its own active style")
scroll.height = 600
f2tTableSetData("test", {alice,bob})
assert_equal(content.height, 600, "growing viewport updates content height")
scroll.height = 120
f2tTableSetData("test", {alice,bob})
assert_equal(content.height, 120, "shrinking viewport removes stale empty space")

print("table system row refresh: ok")
