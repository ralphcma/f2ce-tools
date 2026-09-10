-- Offline native integration tests. No real profile, network, or game I/O.
local root = arg[1] or "."
local passed, failed = 0, 0
local function eq(a, b, why) assert(a == b, (why or "values differ") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end

local function environment(options)
    options = options or {}
    local e = { sent = {}, timers = {}, handlers = {}, triggers = {}, aliases = {}, messages = {},
        now = 0, serial = 0, deleted = 0, files = options.files or {}, packages = options.packages or {} }
    setmetatable(e, { __index = _G }); e._G = e
    e.F2CE, e.F2T_VERSION = false, "3.3.0"
    e.gmcp = { room = { info = { id = 7, mapId = 3, area = "Tempest", owner = "TestOwner" } },
        char = { vitals = { name = "TestOwner", stamina = 100, rank = options.rank or "Founder" } } }
    e.os = { time = function() return math.floor(e.now) end, clock = os.clock, date = os.date }
    e.io = { open = function(path, mode)
        assert(mode == "r", "unexpected profile write: " .. path)
        local source = e.files[path]
        if not source then return nil end
        return { close = function() end, lines = function()
            return source:gmatch("[^\r\n]+")
        end }
    end }
    function e.getMudletHomeDir() return "/mock-profile" end
    function e.getPackages() return e.packages end
    function e.getPackageInfo() return { version = e.F2T_VERSION } end
    function e.send(command) e.sent[#e.sent + 1] = command end
    function e.cecho(message) e.messages[#e.messages + 1] = message end
    function e.deleteLine() e.deleted = e.deleted + 1 end
    function e.f2t_debug_log() end
    function e.f2t_table_count_keys(t) return count(t) end
    local function id() e.serial = e.serial + 1; return e.serial end
    function e.tempTimer(delay, fn) local key = id(); e.timers[key] = { at = e.now + delay, fn = fn }; return key end
    function e.killTimer(key) e.timers[key] = nil end
    function e.tempRegexTrigger(pattern, fn) local key = id(); e.triggers[key] = { pattern = pattern, fn = fn }; return key end
    function e.killTrigger(key) e.triggers[key] = nil end
    function e.tempAlias(pattern, fn) local key = id(); e.aliases[key] = { pattern = pattern, fn = fn }; return key end
    function e.killAlias(key) e.aliases[key] = nil end
    function e.registerAnonymousEventHandler(name, fn) local key = id(); e.handlers[key] = { name = name, fn = fn }; return key end
    function e.killAnonymousEventHandler(key) e.handlers[key] = nil end
    function e.event(name, ...)
        local handlers = {}; for key, item in pairs(e.handlers) do handlers[key] = item end
        for key, item in pairs(handlers) do if e.handlers[key] and item.name == name then item.fn(name, ...) end end
    end
    function e.advance(seconds)
        local until_time = e.now + seconds
        for _ = 1, 1000 do
            local key, at
            for candidate, item in pairs(e.timers) do
                if item.at <= until_time and (not at or item.at < at or item.at == at and candidate < key) then
                    key, at = candidate, item.at
                end
            end
            if not key then e.now = until_time; return end
            local fn = e.timers[key].fn; e.timers[key] = nil; e.now = at; fn()
        end
        error("timer loop")
    end
    function e.load(path)
        local fn = assert(loadfile(root .. "/" .. path)); setfenv(fn, e); return fn()
    end
    e.widgets = {}
    local function widget(spec, parent)
        local w = { name = spec.name, spec = spec, parent = parent, history = {} }
        if spec.name then e.widgets[spec.name] = w end
        function w:echo(text, color)
            -- Geyser Label:echo treats a second argument as a color. A bare
            -- gsub return leaks its numeric replacement count into this slot.
            assert(color == nil or type(color) == "string" or type(color) == "table", "invalid Geyser echo color")
            self.text, self.echo_color = text, color or self.echo_color
        end
        function w:cecho(text) self.history[#self.history + 1] = text end
        function w:setStyleSheet(css) self.css = css end
        function w:setClickCallback(fn) self.click = fn end
        function w:setToolTip(text) self.tooltip = text end
        function w:get_width() return tonumber(self.spec.width) or 800 end
        function w:get_height() return tonumber(self.spec.height) or 500 end
        function w:move(x, y) self.spec.x, self.spec.y = x, y end
        function w:resize(width, height) self.spec.width, self.spec.height = width, height end
        function w:print(text) self.text = text end
        function w:getText() return self.text end
        function w:setAction(fn) self.action = fn end
        function w:setColor() end
        function w:enableAutoWrap() end
        function w:show() self.hidden = false end
        function w:hide() self.hidden = true end
        function w:clear() self.history = {} end
        function w:delete() self.deleted = true end
        return w
    end
    e.Geyser = { Label = { new = function(_, spec, parent) return widget(spec, parent) end },
        MiniConsole = { new = function(_, spec, parent) return widget(spec, parent) end },
        ScrollBox = { new = function(_, spec, parent) return widget(spec, parent) end },
        CommandLine = { new = function(_, spec, parent) return widget(spec, parent) end } }
    function e.f2t_ui_pt(value) return value .. "pt" end
    function e.makeMux()
        local mux = { _ready = true, _content = {}, panes = {}, registrations = 0, applied = {},
            _settings_ui = { visible = false }, settings = { _data = options.data or {}, _registry = {}, _change = {} } }
        e.Mux = mux
        local settings = mux.settings
        function settings.register(ns, key, cfg)
            settings._registry[ns] = settings._registry[ns] or {}; settings._registry[ns][key] = cfg
        end
        function settings.get(ns, key)
            local value = settings._data[ns] and settings._data[ns][key]
            if value ~= nil then return value end
            local cfg = settings._registry[ns] and settings._registry[ns][key]
            if cfg then return cfg.default end
        end
        function settings.set(ns, key, value)
            local cfg = settings._registry[ns] and settings._registry[ns][key]
            if not cfg then return false, "unknown setting" end
            if type(cfg.default) == "number" and type(value) == "string" then value = tonumber(value) end
            if cfg.validator then local ok, why = cfg.validator(value); if not ok then return false, why end end
            settings._data[ns] = settings._data[ns] or {}; settings._data[ns][key] = value
            settings.save()
            local cb = settings._change[ns .. "." .. key]; if cb then cb(value) end
            return true
        end
        function settings.clear(ns, key) if settings._data[ns] then settings._data[ns][key] = nil end end
        function settings.save() settings.saved = (settings.saved or 0) + 1 end
        function settings.onChange(ns, key, fn) settings._change[ns .. "." .. key] = fn end
        function settings.toggle() mux._settings_ui.visible = not mux._settings_ui.visible end
        function settings.showTab(ns) settings.shown = ns end
        function mux.registerContent(key, def) mux.registrations = mux.registrations + 1; mux._content[key] = def end
        function mux.getPane(key) return mux.panes[key] end
        function mux.createDeclarativeCondition(rule) mux.condition = rule end
        function mux.runAction(action, ctx)
            local target = ctx.tab or ctx.pane
            target.hidden = action == "mux.hideSelf"
        end
        function mux._applyContent(target, key)
            mux.applied[#mux.applied + 1] = target.id
            local old = mux._content[target._activeContent]
            if old and old.remove then old.remove(target) end
            mux._content[key].apply(target); target._activeContent = key
        end
        for _, index in ipairs({1, 7, 15, 16}) do
            mux.panes["pane_" .. index] = { id = "pane_" .. index, content = widget({}), contentBg = widget({}) }
        end
        if options.tabHost then
            local pane = { id = "pane_2", _tabs = {}, _hiddenTabs = {}, active = "who", _activeTabId = "who",
                _tabViewport = widget({ width = 417, height = 828 }) }
            function pane:addTab(name)
                local geometry = options.zeroSizedTab and { width = 0, height = 0 } or {}
                local tab = { id = name, pane = self, content = widget(geometry), contentBg = widget({}) }
                self._tabs[#self._tabs + 1] = tab; return tab
            end
            for _, name in ipairs({ "who", "events", "exchange" }) do
                pane:addTab(name)._activeContent = "fed2_" .. name
            end
            if options.staleNamedTab then
                local stale = pane:addTab("stale-exchange-walker")
                stale.name = "Exchange Walker"
                stale._activeContent = "fed2_cargo"
            end
            mux.panes.pane_2 = pane
        end
        mux.panes.pane_1._activeContent = "nativeMap"
        mux.panes.pane_7._activeContent = "fed2_galaxy"
        mux.panes.pane_15._activeContent = "foreign_content"
        return mux
    end
    if not options.lateMux then e.makeMux() else e.Mux = false end
    e.load("src/scripts/settings.lua")
    e.load("src/scripts/rank.lua")
    e.load("src/scripts/ui/table_system.lua")
    e.load("src/scripts/api/v1.lua")
    e.load("src/scripts/api/exchange.lua")
    e.load("src/scripts/api/adapter.lua")
    function e.loadWalker()
        for _, name in ipairs({"controller", "settings", "bridge", "board", "bootstrap"}) do
            e.load("src/scripts/exchange_walker/" .. name .. ".lua")
        end
        e.load("src/scripts/ui/content/exchange_walker.lua")
    end
    e.loadWalker()
    -- Native package order puts the API and Walker before PO; all deferred
    -- initialization must wait until the later provider scripts have loaded.
    e.load("src/scripts/po/init.lua")
    e.load("src/scripts/po/economy_parser.lua")
    e.load("src/scripts/po/economy_capture.lua")
    e.advance(0)
    function e.finishCapture(kind, planet, lines, summary)
        eq(e.f2t_po.phase, "capturing_" .. kind)
        e.line = planet .. (kind == "exchange" and " exchange - all products:" or " exchange - production and consumption:")
        e.load("src/triggers/po/" .. kind .. "_header.lua")
        for _, line in ipairs(lines) do e.line = line; e.load("src/triggers/po/capture_line.lua") end
        if kind == "exchange" then e.line = summary; e.load("src/triggers/po/exchange_summary.lua") else e.advance(0.5) end
    end
    return e
end

local function sample(e, remote)
    local ew = e.F2T_EXCHANGE_WALKER
    assert(ew.on()); assert(ew.preview(remote))
    e.finishCapture("exchange", remote or "Tempest", {
        "Alloys: value 137ig/ton Spread: 20% Stock: current 800/min 100/max 800 Efficiency:",
        "105% Net: 44",
        "NanoFabrics: value 900ig/ton Spread: 6% Stock: current -525/min 0/max 0 Efficiency: 100% Net: -11",
    }, "2 commodities, 1 deficits, 1 surpluses")
    e.advance(0.15)
    e.finishCapture("production", remote or "Tempest", {
        "Alloys: production 45, consumption 1 (44), efficiency 105%",
        "NanoFabrics: production 3, consumption 14 (-11), efficiency 100%",
    })
    assert(ew.plan, "preview should be complete")
    return ew
end

local tests = {}
function tests.defaults_and_late_mux()
    local e = environment({ lateMux = true })
    eq(#e.sent, 0); eq(e.F2T_EXCHANGE_WALKER.enabled, false)
    e.f2t_settings_register("test", "false_default", { default = false })
    eq(e.f2t_settings_get("test", "false_default"), false)
    e.makeMux(); e.f2tRegisterExchangeWalker(); e.advance(0.25)
    local ew = e.F2T_EXCHANGE_WALKER
    for _, field in ipairs(ew.settings.fields) do
        assert(e.Mux.settings.get(field[2], field[1]) ~= nil, field[1] .. " is blank")
        assert(type(e.Mux.settings._registry[field[2]][field[1]].validator) == "function")
    end
    eq(ew.settings.interval_minutes, 30); eq(ew.settings.reserve_min, 10000); eq(ew.settings.reserve_max, 20000)
    eq(ew.settings.surplus_spread, 40); eq(ew.settings.deficit_spread, 6); eq(#e.sent, 0)
    ew.settings.open(); assert(e.Mux._settings_ui.visible); eq(e.Mux.settings.shown, "ew_general")
end
function tests.policy_validation_and_invalidation()
    local e = environment(); local ew = sample(e)
    assert(not ew.settings.configure({ deficit_min = 3000, deficit_max = 1000 }))
    assert(ew.plan, "invalid input must not change the current plan")
    assert(ew.settings.configure({ deficit_min = 3000, deficit_max = 5000 }))
    eq(ew.plan, nil); eq(ew.settings.deficit_min, 3000)
    assert(not e.Mux.settings.set("ew_deficit", "deficit_max", 2000))
    assert(not ew.settings.setTargetsCsv("Tempest; quit"))
    assert(not ew.settings.setExclusionsCsv("Alloys\nquit"))
    assert(not e.Mux.settings.set("ew_general", "interval_minutes", 0))
    assert(ew.settings.configure({ targets = {"Tempest"}, excluded_commodities = {"nanofabrics"} }))
    local plan = assert(ew.policy.makePlan({
        { name = "NanoFabrics", stock_current = -1, stock_min = 0, stock_max = 0, spread = 6 }, _expected_count = 1,
    }, { NanoFabrics = { production = 1, consumption = 2 } }, "room", "Tempest"))
    eq(#plan.rows, 0); eq(#plan.actions, 0)
end
function tests.settings_ui_targets_reach_runtime_and_remain_profile_local()
    local e = environment({tabHost=true}); e.advance(0.25)
    local ew = e.F2T_EXCHANGE_WALKER
    assert(e.Mux.settings.set("ew_general", "targets", "tempest, amsterdam, holland, denmark"))
    eq(table.concat(ew.settings.targets, ","), "amsterdam,denmark,holland,tempest")
    eq(#e.sent, 0); eq(ew.scheduler.enabled, false); eq(ew.plan, nil)
    local other = environment({tabHost=true}); other.advance(0.25)
    eq(#other.F2T_EXCHANGE_WALKER.settings.targets, 0)
    local reloaded = environment({data=e.Mux.settings._data})
    eq(table.concat(reloaded.F2T_EXCHANGE_WALKER.settings.targets, ","), "amsterdam,denmark,holland,tempest")
    eq(reloaded.F2T_EXCHANGE_WALKER.scheduler.enabled, false); eq(#reloaded.sent, 0)
    assert(ew.on()); assert(ew.autoOn())
    eq(#ew.scheduler.targets, 4); eq(e.sent[1], "display exchange amsterdam")
    ew.cancel()
end
function tests.settings_remain_consistent_when_board_render_fails()
    local e = environment(); local ew = sample(e, "Tempest")
    ew.ui.updateTable = function() error("simulated display-only failure") end
    assert(e.Mux.settings.set("ew_general", "targets", "Tempest, Denmark"))
    eq(table.concat(ew.settings.targets, ","), "Denmark,Tempest")
    eq(ew.plan, nil); eq(ew.busy, false); eq(ew.scheduler.enabled, false)
    eq(#e.sent, 2)
end
function tests.complete_capture_and_confirmed_commands()
    local e = environment(); local ew = sample(e, "Tempest")
    eq(e.sent[1], "display exchange Tempest"); eq(e.sent[2], "display production all Tempest")
    eq(#ew.plan.rows, 2); eq(#ew.plan.actions, 3)
    eq(ew.plan.rows[1].target_min, 800); eq(ew.plan.rows[1].target_max, 1800)
    assert(ew.apply()); eq(#e.sent, 3); eq(e.sent[3], "set stockpile max 1800 Alloys Tempest")
    -- Wrong planet/commodity must not advance the command sequence.
    e.matches = { "", "Alloys", "Elsewhere", "1800" }
    for _, trigger in pairs(e.triggers) do if trigger.pattern:find("Max stock", 1, true) then trigger.fn() end end
    e.advance(0.21); eq(#e.sent, 3)
    while ew.pending_confirmation do
        local action = ew.pending_confirmation.action
        e.matches = { "", action.commodity, "Tempest", tostring(action.value) }
        for _, trigger in pairs(e.triggers) do
            local needle = action.kind == "min" and "Min stock" or action.kind == "max" and "Max stock" or "Price spread"
            if trigger.pattern:find(needle, 1, true) then trigger.fn() end
        end
        e.advance(0.2)
    end
    eq(#e.sent, 5); eq(ew.applying, false); eq(e.F2CE.API.v1.commands._lease, nil)
    assert(not ew.apply(), "applied plan must not replay")
end
function tests.incomplete_and_wrong_target_capture()
    for _, wrong in ipairs({false, true}) do
        local e = environment(); local ew = e.F2T_EXCHANGE_WALKER
        ew.on(); assert(ew.preview("Tempest"))
        e.finishCapture("exchange", wrong and "Other" or "Tempest", {
            "Alloys: value 137ig/ton Spread: 40% Stock: current 800/min 800/max 1800 Efficiency: 100% Net: 1",
        }, "67 commodities, 0 deficits, 67 surpluses")
        e.advance(0.15)
        if not wrong then e.finishCapture("production", "Tempest", { "Alloys: production 2, consumption 1" }) end
        eq(ew.plan, nil); assert(not ew.apply()); assert(#e.sent <= 2)
        eq(e.F2CE.API.v1.commands._lease, nil)
    end
end
function tests.cancel_and_reconnect_revoke_authority()
    local e = environment(); local ew = e.F2T_EXCHANGE_WALKER; ew.on(); ew.preview("Tempest")
    local late = e.f2t_po.callback
    e.event("sysDisconnectionEvent")
    eq(ew.enabled, false); eq(e.f2t_po.phase, "idle"); eq(e.F2CE.API.v1.commands._lease, nil)
    eq(e.F2CE.API.v1.modules.status("f2ce.exchange_walker").state, "registered")
    late({ _expected_count = 0 }, nil, { planet = "Tempest" }); e.advance(20); eq(#e.sent, 1)
    assert(not ew.apply()); assert(not ew.preview("Tempest"))
end
function tests.foreign_capture_is_never_cancelled()
    local e = environment(); local ew = e.F2T_EXCHANGE_WALKER; ew.on(); ew.preview("Tempest")
    local foreign = function() end; e.f2t_po.callback = foreign
    ew.off(); eq(e.f2t_po.callback, foreign); eq(e.f2t_po.phase, "capturing_exchange")
end
function tests.mux_isolation_reload_and_uninstall()
    local e = environment(); e.advance(0.25); local ew = e.F2T_EXCHANGE_WALKER
    eq(e.Mux.panes.pane_1._activeContent, "nativeMap"); eq(e.Mux.panes.pane_7._activeContent, "fed2_galaxy")
    eq(e.Mux.panes.pane_15._activeContent, "foreign_content"); eq(e.Mux.panes.pane_16._activeContent, "exchange_walker_live")
    local registrations = e.Mux.registrations; e.f2tRegisterExchangeWalker(); e.advance(0.25)
    eq(e.Mux.registrations, registrations, "idempotent content registration")
    eq(count(e.aliases), 1); eq(count(e.triggers), 3)
    assert(ew.settings.configure({ interval_minutes = 45, targets = {"Tempest"} }))
    e.loadWalker(); e.advance(0.25); ew = e.F2T_EXCHANGE_WALKER
    eq(ew.settings.interval_minutes, 45); eq(ew.enabled, false)
    eq(count(e.aliases), 1); eq(count(e.triggers), 3)
    e.event("sysUninstallPackage", "f2ce-tools")
    eq(count(e.aliases), 0); eq(count(e.triggers), 0)
    eq(e.Mux.settings._data.ew_general.interval_minutes, nil)
    eq(e.Mux.panes.pane_1._activeContent, "nativeMap")
end
function tests.legacy_settings_migration_without_arming()
    local path = "/mock-profile/exchange-walker-live-settings.ini"
    local source = "schema=2\ninterval_minutes=45\nsurplus_spread=35\ntargets=Tempest|Denmark\nexcluded_commodities=Gold|Alloys\n"
    local e = environment({ files = { [path] = source }, packages = {"exchange-walker-live"} })
    local ew = e.F2T_EXCHANGE_WALKER
    eq(ew.settings.interval_minutes, 45); eq(ew.settings.surplus_spread, 35); eq(#ew.settings.targets, 2)
    eq(#ew.settings.excluded_commodities, 2); eq(e.files[path], source)
    eq(ew.enabled, false); eq(ew.scheduler.enabled, false); eq(count(e.aliases), 0); eq(#e.sent, 0)
    assert(not ew.on()); e.packages = {}; e.event("sysUninstallPackage", "exchange-walker-live"); e.advance(0)
    eq(count(e.aliases), 1); eq(ew.enabled, false)
end
function tests.migration_rejects_invalid_schema_and_preserves_native_settings()
    local path = "/mock-profile/exchange-walker-live-settings.ini"
    local e = environment({ files = { [path] = "schema=99\ninterval_minutes=5\n" } })
    assert(e.F2T_EXCHANGE_WALKER.settings_error); eq(#e.sent, 0)
    e = environment({ files = { [path] = "schema=2\ninterval_minutes=invalid\n" } })
    assert(e.F2T_EXCHANGE_WALKER.settings_error); assert(not e.F2T_EXCHANGE_WALKER.on()); eq(#e.sent, 0)
    e = environment({ files = { [path] = "schema=2\ninterval_minutes=5\n" },
        data = { ew_general = { interval_minutes = 80 } } })
    eq(e.F2T_EXCHANGE_WALKER.settings.interval_minutes, 80)
end
function tests.api_session_validation_contention_and_cleanup()
    local e = environment(); local api = e.F2CE.API.v1
    local ctx = assert(api.modules.register({id = "test.exchange"}))
    assert(not api.exchange.acquire(ctx, {reason="test"})); eq(#e.sent, 0)
    ctx = assert(api.modules.enable("test.exchange"))
    local session = assert(api.exchange.acquire(ctx, {reason="test"}))
    assert(not api.commands.acquire(ctx, {reason="foreign"}))
    for _, change in ipairs({
        {kind="min",commodity="Alloys",value=10001,planet="Tempest"},
        {kind="max",commodity="Alloys",value=20001,planet="Tempest"},
        {kind="spread",commodity="Alloys",value=41,planet="Tempest"},
        {kind="min",commodity="Alloys;quit",value=1,planet="Tempest"},
        {kind="min",commodity="Alloys",value=1,planet="Tempest\nquit"},
    }) do assert(not session:set(change)) end
    e.gmcp.room.info.owner = "Other"; assert(not session:set({kind="min",commodity="Alloys",value=1}))
    eq(#e.sent, 0)
    e.F2T_GALAXY = {capture_active=true}; assert(not session:capture("exchange", "Tempest", function() end)); eq(#e.sent, 0)
    e.F2T_GALAXY.capture_active=false
    local called = false
    assert(session:capture("exchange", "Tempest", function() called = true end))
    eq(#e.sent, 1); api.modules.disable("test.exchange"); eq(e.f2t_po.phase, "idle")
    eq(api.commands._lease, nil); e.advance(30); eq(called, false); assert(not session:set({kind="min",commodity="Alloys",value=1,planet="Tempest"}))
end
function tests.apply_timeout_sends_no_retry()
    local e = environment(); local ew = sample(e, "Tempest")
    assert(ew.apply()); eq(#e.sent, 3); e.advance(10)
    eq(#e.sent, 3); eq(ew.applying, false); eq(e.F2CE.API.v1.commands._lease, nil)
end
function tests.blank_suppression_is_capture_scoped()
    local e = environment(); e.line = ""; e.load("src/triggers/po/capture_blank.lua"); eq(e.deleted, 0)
    local ew = e.F2T_EXCHANGE_WALKER; ew.on(); ew.preview("Tempest")
    e.load("src/triggers/po/capture_blank.lua"); eq(e.deleted, 0)
    e.line = "Tempest exchange - all products:"; e.load("src/triggers/po/exchange_header.lua")
    local before = e.deleted; e.line = ""; e.load("src/triggers/po/capture_blank.lua"); eq(e.deleted, before + 1)
    ew.cancel(); e.load("src/triggers/po/capture_blank.lua"); eq(e.deleted, before + 1)
end
function tests.parser_accepts_all_row_layouts_without_cross_join()
    local e = environment()
    local rows = e.f2t_po_parse_exchange_buffer({
        "Alloys: value 1ig/ton Spread: 6% Stock: current -525/min 0/max 0 Efficiency: 100% Net: -1",
        "Gold: value 2ig/ton Spread: 40% Stock: current 10000/min 10000/max 20000 Efficiency:", "200% Net: 3",
        "Fruit: value 3ig/ton Spread: 40% Stock: current 500/min 500/max 1500", "Efficiency: 100%", "Net: 4",
    }, "3 commodities, summary")
    eq(#rows, 3); eq(rows._expected_count, 3); eq(rows[1].stock_current, -525)
    local partial = e.f2t_po_parse_exchange_buffer({"Alloys: value 1ig/ton", "Gold: value 2ig/ton Spread: 6% Stock: current 0/min 0/max 0 Efficiency: 100% Net: 0"}, "2 commodities,")
    eq(#partial, 1); eq(partial[1].name, "Gold")
end

function tests.reserve_growth_and_every_intermediate_limit_are_legal()
    local e = environment(); local ew = e.F2T_EXCHANGE_WALKER
    local cases = 0
    for _, stock in ipairs({-525, 0, 9999, 10000, 20000}) do
        for _, net in ipairs({-1, 0, 1}) do
            for _, minimum in ipairs({0, 100, 9999, 10000}) do
                for _, maximum in ipairs({0, 500, 10000, 20000}) do
                    if minimum <= maximum then
                        local plan = assert(ew.policy.makePlan({
                            {name="Alloys",stock_current=stock,stock_min=minimum,stock_max=maximum,spread=20}, _expected_count=1,
                        }, {Alloys={production=2+net,consumption=2}}, "room", "Tempest"))
                        local low, high, spread = minimum, maximum, 20
                        for _, action in ipairs(plan.actions) do
                            if action.kind == "min" then low = action.value
                            elseif action.kind == "max" then high = action.value
                            else spread = action.value end
                            assert(low >= 0 and low <= 10000 and high >= low and high <= 20000)
                        end
                        eq(low, net <= 0 and 0 or stock >= 10000 and 10000 or math.max(stock, 0))
                        eq(high, net <= 0 and 0 or stock >= 10000 and 20000 or low + 1000)
                        eq(spread, net > 0 and 40 or 6)
                        cases = cases + 1
                    end
                end
            end
        end
    end
    eq(cases, 165); eq(#e.sent, 0)
end

function tests.timer_is_explicit_and_setting_changes_stop_it()
    local e = environment(); local ew = e.F2T_EXCHANGE_WALKER
    assert(ew.settings.configure({targets={"Tempest"}, interval_minutes=5}))
    e.advance(600); eq(#e.sent, 0)
    assert(not ew.autoOn(), "timer must require explicit ON")
    assert(ew.on())
    assert(ew.autoOn()); eq(e.sent[1], "display exchange Tempest")
    e.finishCapture("exchange", "Tempest", {
        "Alloys: value 100ig/ton Spread: 6% Stock: current 0/min 0/max 0 Efficiency: 100% Net: 0",
    }, "1 commodities, summary")
    e.advance(0.15)
    e.finishCapture("production", "Tempest", {"Alloys: production 1, consumption 1"})
    eq(#e.sent, 2); assert(ew.scheduler.enabled); assert(not ew.scheduler.running)
    e.advance(299); eq(#e.sent, 2)
    e.advance(1); eq(#e.sent, 3)
    assert(ew.settings.configure({interval_minutes=30})); assert(not ew.scheduler.enabled)
    eq(e.f2t_po.phase, "idle"); e.advance(2000); eq(#e.sent, 3)
end

function tests.api_timeout_callback_errors_and_resource_pruning()
    local e = environment(); local api = e.F2CE.API.v1
    local ctx = assert(api.modules.register({id="test.exchange"})); ctx = assert(api.modules.enable("test.exchange"))
    for _ = 1, 100 do assert(api.exchange.acquire(ctx,{reason="test"})):release() end
    eq(#ctx._resources, 0, "completed sessions must not accumulate forever")
    local session = assert(api.exchange.acquire(ctx,{reason="test"}))
    local callbacks = 0
    assert(session:capture("exchange", "Tempest", function(_, why) assert(why); callbacks = callbacks + 1 end))
    local late = e.f2t_po.callback
    e.killTimer(e.f2t_po.timer_id); e.f2t_po.timer_id = nil
    e.advance(16); eq(callbacks, 1); eq(api.commands._lease, nil); eq(e.f2t_po.phase, "idle")
    late({}, nil, {planet="Tempest"}); eq(callbacks, 1)
    session = assert(api.exchange.acquire(ctx,{reason="test"}))
    assert(session:capture("exchange", "Tempest", function() error("consumer error") end))
    e.finishCapture("exchange", "Tempest", {}, "0 commodities, summary")
    eq(api.commands._lease, nil); eq(#ctx._resources, 0)
end

function tests.board_tab_joins_existing_tabs_and_is_rank_gated()
    local e = environment({ tabHost = true, rank = "Financier" }); e.advance(0.25)
    local ew, pane = e.F2T_EXCHANGE_WALKER, e.Mux.panes.pane_2
    eq(#pane._tabs, 3); assert(not ew.on()); assert(not ew.inspect("Tempest")); eq(#e.sent, 0)
    assert(e.Mux._content.exchange_walker_live.internal)
    e.gmcp.char.vitals.rank = "Founder"; e.event("gmcp.char.vitals")
    eq(#pane._tabs, 4); eq(pane.active, "who")
    eq(pane._tabs[4]._activeContent, "exchange_walker_live")
    eq(e.Mux.panes.pane_1._activeContent, "nativeMap"); eq(e.Mux.panes.pane_7._activeContent, "fed2_galaxy")
    e.event("gmcp.char.vitals"); eq(#pane._tabs, 4)
    assert(ew.inspect("Tempest")); eq(e.f2t_po.phase, "capturing_exchange")
    e.gmcp.char.vitals.rank = nil; e.event("gmcp.char.vitals")
    assert(pane._tabs[4].hidden); eq(e.f2t_po.phase, "idle"); eq(e.F2CE.API.v1.commands._lease, nil)
    e.gmcp.char.vitals.rank = "Magnate"; e.event("gmcp.char.vitals")
    assert(not pane._tabs[4].hidden); eq(#pane._tabs, 4)
end

function tests.board_refresh_is_read_only_validated_and_cancelable()
    local e = environment({tabHost=true}); e.advance(0.25); local ew = e.F2T_EXCHANGE_WALKER
    local pane = e.Mux.panes.pane_2; local instance = ew.ui.instances[pane._tabs[4]]
    for _, control in pairs(instance.controls) do assert(control.spec.y >= instance.status.spec.y + 40) end
    eq(#instance.headers, 7); eq(#ew.ui.boardColumns, 7)
    assert(ew.inspect("Tempest")); eq(ew.enabled, false); eq(e.sent[1], "display exchange Tempest")
    e.finishCapture("exchange", "Tempest", {
        "AntiMatter: value 100ig/ton Spread: 40% Stock: current 20000/min 10000/max 20000 Efficiency: 275% Net: 24",
        "Alloys: value 100ig/ton Spread: 6% Stock: current -525/min 0/max 0 Efficiency: 100% Net: -3",
    }, "2 commodities, summary")
    eq(#ew.board.rows, 2); eq(ew.plan, nil); eq(ew.enabled, false); eq(e.F2CE.API.v1.commands._lease, nil)
    eq(ew.board.rows[1].stock_current, 20000); eq(ew.board.rows[1].net, 24)
    local cell = e.widgets["f2tsb_" .. instance.table_id .. "_r1_c7"]
    assert(cell.text:find("#ff7373", 1, true)); assert(cell.text:find("-3", 1, true))
    instance.headers[7].click(); instance.headers[7].click()
    assert(cell.text:find("+24", 1, true)); assert(cell.text:find("#65dd75", 1, true))
    pane._tabs[4].content:resize(643, 450); ew.ui.resizeTable(pane._tabs[4])
    for index, header in ipairs(instance.headers) do
        local body = e.widgets["f2tsb_" .. instance.table_id .. "_r1_c" .. index]
        eq(header.spec.width, body.spec.width); eq(header.spec.x, body.spec.x)
    end
    assert(ew.inspect("Denmark"))
    e.finishCapture("exchange", "Denmark", {}, "67 commodities, summary")
    eq(ew.board.planet, "Tempest"); eq(#ew.board.rows, 2); assert(ew.board.message:find("incomplete"))
    assert(ew.inspect("Tempest")); local late = e.f2t_po.callback
    instance.controls.cancel.click(); eq(e.f2t_po.phase, "idle"); eq(e.F2CE.API.v1.commands._lease, nil)
    late({}, nil, {planet="Tempest"}); eq(#ew.board.rows, 2); eq(ew.plan, nil)
    assert(not ew.inspect("Tempest;quit")); eq(#e.sent, 3)
end

function tests.board_fills_narrow_and_resized_panes_without_color_errors()
    local e = environment({tabHost=true}); e.advance(0.25)
    local ew = e.F2T_EXCHANGE_WALKER; local target = e.Mux.panes.pane_2._tabs[4]
    local instance = assert(ew.ui.instances[target])
    for _, message in ipairs(e.messages) do assert(not message:find("Mux content failed", 1, true), message) end
    eq(instance.input:getText(), "Tempest"); eq(#e.sent, 0)
    assert(instance.empty.text:find("No exchange loaded", 1, true))
    assert(instance.status.text:find("OFF | AUTO OFF | 0 targets | every 30m", 1, true))
    assert(instance.controls.toggle.text:find("TURN ON", 1, true))
    assert(instance.controls.auto.text:find("AUTO ON", 1, true))
    assert(instance.planet_label.text:find("Inspect", 1, true))
    assert(instance.input.tooltip:find("read%-only"))
    assert(instance.controls.refresh.css:find("#234f82", 1, true))
    eq(instance.background.echo_color, "nocolor", "board labels bypass Geyser color parsing")
    for _, size in ipairs({{417,828},{643,450},{1000,1000},{417,828}}) do
        target.content:resize(size[1], size[2]); ew.ui.resizeTable(target); ew.ui.updateTable()
        eq(instance.background:get_height(), size[2])
        eq(instance.body:get_height(), instance.scroll:get_height())
        eq(instance.scroll.spec.y + instance.scroll:get_height() + 4, instance.status.spec.y)
        for _, control in pairs(instance.controls) do
            assert(control.spec.y >= instance.status.spec.y + 40)
            assert(control.spec.y + control:get_height() <= size[2])
            assert(control.spec.x + control:get_width() <= size[1])
        end
        local width = 0
        for _, header in ipairs(instance.headers) do eq(header.spec.x, width); width = width + header:get_width() end
        eq(width, size[1]-17)
        eq(instance.columns[2].label, size[1] < 717 and "Spr%" or "Spread")
        eq(instance.columns[6].label, size[1] < 717 and "Eff%" or "Efficiency")
    end
    assert(ew.inspect("Tempest"))
    e.finishCapture("exchange", "Tempest", {
        "Pharmaceuticals: value 100ig/ton Spread: 40% Stock: current 20000/min 10000/max 20000 Efficiency: 275% Net: 24",
    }, "1 commodities, summary")
    assert(instance.empty.hidden)
    local name = e.widgets["f2tsb_" .. instance.table_id .. "_r1_c1"]
    eq(name.tooltip, "Pharmaceuticals")
    instance.controls.clear.click(); assert(not instance.empty.hidden)
    ew.board.message = 'captured <name> & "quoted"'; ew.ui.updateTable()
    assert(instance.status.text:find("&lt;name&gt;", 1, true))
end

function tests.hidden_zero_sized_tab_uses_host_geometry_before_reveal()
    local e = environment({tabHost=true, zeroSizedTab=true}); e.advance(0.25)
    local ew = e.F2T_EXCHANGE_WALKER; local target = e.Mux.panes.pane_2._tabs[4]
    local instance = assert(ew.ui.instances[target])
    eq(instance.background:get_width(), 417, "hidden tab uses its host viewport width")
    eq(instance.background:get_height(), 828, "hidden tab uses its host viewport height")
    target.content:resize(417, 828)
    e.Mux._content.exchange_walker_live.onReveal(target)
    e.advance(0)
    eq(instance.background:get_width(), 417, "revealed tab fills available width")
    eq(instance.background:get_height(), 828, "revealed tab fills available height")
    assert(instance.empty.text:find("No exchange loaded", 1, true))
    for _, message in ipairs(e.messages) do assert(not message:find("Mux content failed", 1, true), message) end
end

function tests.partial_existing_tab_instance_is_rebuilt_instead_of_accepted()
    local e = environment({tabHost=true}); e.advance(0.25)
    local ew = e.F2T_EXCHANGE_WALKER
    local target = e.Mux.panes.pane_2._tabs[4]
    local definition = assert(e.Mux._content.exchange_walker_live)
    definition.remove(target)
    ew.ui.instances[target] = { target=target, table_id="partial", headers={}, controls={} }
    local applied = #e.Mux.applied
    local placed, pane, status = ew.ui.placeRegisteredContent(
        ew.ui.content_id, ew.ui.preferred_pane_start, ew.ui.preferred_pane_end)
    assert(placed, tostring(pane)); eq(pane, "pane_2"); eq(status, "existing-tab")
    eq(#e.Mux.applied, applied + 1, "partial mount must be reapplied")
    assert(ew.ui.instanceHealthy(target), "replacement board is complete")
    assert(ew.ui.instances[target].empty.text:find("No exchange loaded", 1, true))
end

function tests.active_existing_tab_repairs_hidden_content_slot()
    local e = environment({tabHost=true}); e.advance(0.25)
    local ew = e.F2T_EXCHANGE_WALKER
    local target = e.Mux.panes.pane_2._tabs[4]
    target.pane._activeTabId = target.id
    target.content.hidden = true
    target._contentSlot = e.widgets.__missing or { hidden=true, show=function(self) self.hidden=false end }
    local placed = ew.ui.placeRegisteredContent(
        ew.ui.content_id, ew.ui.preferred_pane_start, ew.ui.preferred_pane_end)
    assert(placed); eq(target.content.hidden, false, "active tab container is revealed")
    eq(target._contentSlot.hidden, false, "active tab content slot is revealed")
    assert(ew.ui.instanceHealthy(target))
end

function tests.stale_named_exchange_walker_tab_is_rebound_to_native_content()
    local e = environment({tabHost=true, staleNamedTab=true}); e.advance(0.25)
    local ew = e.F2T_EXCHANGE_WALKER
    local pane = e.Mux.panes.pane_2
    eq(#pane._tabs, 4, "the stale named tab is reused instead of adding a duplicate")
    local target = pane._tabs[4]
    eq(target.name, "Exchange Walker")
    eq(target._activeContent, ew.ui.content_id, "stale cargo binding is replaced")
    assert(ew.ui.instanceHealthy(target), "rebound tab contains a complete Walker board")
end

function tests.stale_named_tab_wins_over_a_temporary_direct_pane_mount()
    local e = environment({tabHost=true, staleNamedTab=true}); e.advance(0.25)
    local ew = e.F2T_EXCHANGE_WALKER
    local named = e.Mux.panes.pane_2._tabs[4]
    local definition = e.Mux._content[ew.ui.content_id]
    definition.remove(named); named._activeContent = "fed2_cargo"
    local temporary = e.Mux.panes.pane_16
    e.Mux._applyContent(temporary, ew.ui.content_id, true)
    assert(ew.ui.instanceHealthy(temporary), "temporary pane reproduces the working workaround")
    local placed, pane, status = ew.ui.placeDefault()
    assert(placed, tostring(pane)); eq(pane, "pane_2"); eq(status, "existing-tab")
    eq(named._activeContent, ew.ui.content_id, "the intended named tab is still repaired")
    assert(ew.ui.instanceHealthy(named))
end

function tests.existing_tab_is_rebuilt_after_hot_reload_widget_teardown()
    local e = environment({tabHost=true}); e.advance(0.25)
    local ew = e.F2T_EXCHANGE_WALKER
    local target = e.Mux.panes.pane_2._tabs[4]
    local definition = assert(e.Mux._content.exchange_walker_live)
    assert(ew.ui.instances[target], "initial board instance")

    -- Muxlet preserves the tab/content identity across a package reload while
    -- the outgoing Walker removes its Geyser widgets.
    definition.remove(target)
    eq(target._activeContent, "exchange_walker_live", "saved content identity remains")
    eq(ew.ui.instances[target], nil, "outgoing board widgets were removed")

    local placed, pane, status = ew.ui.placeRegisteredContent(
        ew.ui.content_id, ew.ui.preferred_pane_start, ew.ui.preferred_pane_end)
    assert(placed, tostring(pane))
    eq(pane, "pane_2")
    eq(status, "existing-tab")
    assert(ew.ui.instances[target], "existing tab board was rebuilt")
    assert(ew.ui.instances[target].empty.text:find("No exchange loaded", 1, true))
end

function tests.trailing_blanks_stop_at_message_or_timeout_and_manual_output_is_visible()
    local e = environment(); local ew = e.F2T_EXCHANGE_WALKER
    assert(ew.inspect("Tempest"))
    e.finishCapture("exchange", "Tempest", {}, "0 commodities, summary")
    local before = e.deleted
    e.line = "0 commodities, summary"; e.load("src/triggers/po/capture_tail_boundary.lua")
    for _ = 1, 3 do e.line = ""; e.load("src/triggers/po/capture_blank.lua") end
    eq(e.deleted, before + 3); e.load("src/triggers/po/capture_blank.lua"); eq(e.deleted, before + 3)
    assert(ew.inspect("Tempest")); e.finishCapture("exchange", "Tempest", {}, "0 commodities, summary")
    before = e.deleted
    e.line = "Your comm unit crackles..."; e.load("src/triggers/po/capture_tail_boundary.lua")
    e.line = ""; e.load("src/triggers/po/capture_blank.lua"); eq(e.deleted, before)
    assert(ew.inspect("Tempest")); e.finishCapture("exchange", "Tempest", {}, "0 commodities, summary")
    before = e.deleted; e.advance(0.6); e.line = ""; e.load("src/triggers/po/capture_blank.lua"); eq(e.deleted, before)
    e.line = "Tempest exchange - all products:"; e.load("src/triggers/po/exchange_header.lua")
    e.line = "Alloys: value 100ig/ton"; e.load("src/triggers/po/capture_line.lua"); eq(e.deleted, before)
end

function tests.current_room_ownership_loss_blocks_local_apply()
    local e = environment(); local ew = sample(e)
    e.gmcp.room.info.owner = "Other"
    assert(not ew.apply()); eq(#e.sent, 2)
end

local names = {}; for name in pairs(tests) do names[#names + 1] = name end; table.sort(names)
for _, name in ipairs(names) do
    local ok, why = pcall(tests[name])
    if ok then passed = passed + 1; print("PASS " .. name)
    else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(why)) end
end
print(string.format("RESULT %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
