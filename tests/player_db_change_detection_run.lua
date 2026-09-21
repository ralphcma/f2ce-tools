local repo = arg[1] or "."

local events = {}
local timers = {}
local load_fixture = nil

local function copy_table(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = copy_table(v) end
    return result
end

local function assert_equal(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
    end
end

local function event_count(name)
    local count = 0
    for _, event in ipairs(events) do
        if event.name == name then count = count + 1 end
    end
    return count
end

local function last_event_payload(name)
    for index = #events, 1, -1 do
        if events[index].name == name then return events[index].args[1] end
    end
    return nil
end

function f2t_get_char_persistent_dir() return repo .. "/tests/tmp" end
function f2t_get_rank_level(rank) return rank == "Trader" and 5 or 0 end
function f2t_debug_log() end
function registerAnonymousEventHandler() return 1 end
function killTimer() end
function raiseEvent(name, ...)
    events[#events + 1] = { name = name, args = { ... } }
end
function tempTimer(delay, callback)
    timers[#timers + 1] = { delay = delay, callback = callback }
    return #timers
end

lfs = { mkdir = function() return true end }
rawset(table, "save", function() return true end)
rawset(table, "load", function(_, target)
    for k, v in pairs(load_fixture or {}) do target[k] = copy_table(v) end
    return true
end)

F2T_CHAR_NAME = nil
gmcp = nil
dofile(repo .. "/src/scripts/player_db.lua")

local function player(name, location, titles)
    return {
        name = name,
        rank = "Trader",
        location = location,
        company = "",
        system = "Sol",
        cartel = "",
        syndicate = "",
        ship_class = "",
        staff_role = "",
        titles = titles or { "Founder" },
    }
end

gmcp = { players = { online = { Alice = player("Alice", "Earth") } } }
assert_equal(f2t_player_db_feed_from_gmcp(), true, "new delta reports a change")
assert_equal(event_count("f2tPlayerDbUpdated"), 1, "new delta raises one update")
local alice_entry = F2T_PLAYER_DB.alice
assert_equal(f2t_player_db_feed_from_gmcp(), false, "identical delta is ignored")
assert_equal(event_count("f2tPlayerDbUpdated"), 1, "identical delta raises no update")
assert_equal(F2T_PLAYER_DB.alice, alice_entry, "identical delta preserves entry identity")

gmcp.players.online.Alice.location = "Sol Space"
assert_equal(f2t_player_db_feed_from_gmcp(), true, "location delta reports a change")
assert_equal(event_count("f2tPlayerDbUpdated"), 2, "location delta raises an update")
assert_equal(F2T_PLAYER_DB.alice, alice_entry, "changed delta preserves entry identity")
local location_change = last_event_payload("f2tPlayerDbUpdated")
assert_equal(location_change.version, 1, "change metadata is versioned")
assert_equal(location_change.full, false, "delta metadata is incremental")
assert_equal(location_change.players.alice.existed, true, "delta records existing row")
assert_equal(location_change.players.alice.was_online, true, "delta records old visibility")
assert_equal(location_change.players.alice.fields.location, true, "delta identifies changed field")

gmcp.players.online.Alice.titles = { "Founder" }
assert_equal(f2t_player_db_feed_from_gmcp(), false, "equal title values are ignored")
gmcp.players.online.Alice.titles = { "Founder", "Navigator" }
assert_equal(f2t_player_db_feed_from_gmcp(), true, "title delta reports a change")
gmcp.players.online.Alice.staff_role = "Navigator"
assert_equal(f2t_player_db_feed_from_gmcp(), true, "staff delta reports a change")
gmcp.players.online.Alice.staff_role = ""
assert_equal(f2t_player_db_feed_from_gmcp(), true, "cleared staff role reports a change")

gmcp.players.online.Bob = player("Bob", "Mars")
assert_equal(f2t_player_db_feed_from_gmcp(), true, "second player reports a change")

gmcp.players = {
    count = 2,
    online = {
        Alice = player("Alice", "Sol Space", { "Founder", "Navigator" }),
        Bob = player("Bob", "Mars"),
    },
}
local updates_before_roster = event_count("f2tPlayerDbUpdated")
assert_equal(f2t_player_db_feed_from_gmcp(), false, "identical full roster is ignored")
assert_equal(event_count("f2tPlayerDbUpdated"), updates_before_roster,
    "identical full roster raises no update")

gmcp.players = {
    count = 1,
    online = { Alice = player("Alice", "Sol Space", { "Founder", "Navigator" }) },
}
assert_equal(f2t_player_db_feed_from_gmcp(), true, "missing roster player reports a change")
assert_equal(F2T_PLAYER_DB.bob.is_online, false, "missing roster player is marked offline")
local roster_change = last_event_payload("f2tPlayerDbUpdated")
assert_equal(roster_change.players.bob.fields.is_online, true,
    "authoritative omission reports online-state change")
assert_equal(f2t_player_db_feed_from_gmcp(), false, "repeated reduced roster is ignored")

load_fixture = copy_table(F2T_PLAYER_DB)
local updates_before_reload = event_count("f2tPlayerDbUpdated")
f2t_player_db_reload()
assert_equal(event_count("f2tPlayerDbUpdated"), updates_before_reload + 1,
    "character reload forces exactly one consumer refresh")
assert_equal(last_event_payload("f2tPlayerDbUpdated").full, true,
    "character reload requests a full consumer refresh")
assert_equal(event_count("f2tPlayerDbReloaded"), 1, "character reload event is preserved")

local save_timer_count = 0
for _, timer in ipairs(timers) do
    if timer.delay == 30 then save_timer_count = save_timer_count + 1 end
end
assert_equal(save_timer_count, 1, "database saves remain debounced")

print("player_db change detection: ok")
