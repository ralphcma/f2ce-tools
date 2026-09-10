# Module API verification

## 2026-09-10 Exchange Walker tab paint-order recovery

Candidate: `f2ce-tools-3.3.0-native-ew15.mpackage`; Walker
3.4.0-native.11. API 1.2.0-candidate.3 is unchanged.

SHA-256: `1c3eb07757e68b2a18333e7b5461e9e2198ecb93b60e80ef35b223e6fa26beb3`.

Ersella's saved workspace proves ew14 loaded and completed its reconstruction:
the selected `Exchange Walker` is a new locked tab with the registered Founder
rule and the expected content ID. A diagnostic copy of the same content in
floating pane_11 renders correctly, isolating the remaining failure to hidden
tab construction and reveal rather than the board renderer.

Mudlet 5.0.1 Geyser reveals a container's children through
`pairs(windowList)`, which does not preserve paint order. A board first built in
an inactive tab can therefore reveal its full-size black background after its
foreground and cover every otherwise healthy widget. Walker now activates a
selected replacement before applying content, routes Muxlet resize/reveal
callbacks through the complete visibility repair, and pins the background below
the table and controls after every immediate and settled reflow.

Source and exact-package verification pass all 81 native groups: API 23,
adapter 5, Walker 30, startup 7, topology 8, map lifecycle 1, and Galaxy
lifecycle 7. All 250 Lua checks, 32 metadata checks, and 221 packaged-script
comparisons pass. No profile was modified and pane_11 was not removed.

## 2026-09-10 Exchange Walker native-tab reconstruction

Candidate: `f2ce-tools-3.3.0-native-ew14.mpackage`; Walker
3.4.0-native.10. API 1.2.0-candidate.3 is unchanged.

SHA-256: `0a31c4f13764ac4c76f1086c8803e78945bc582916b3c219106deb8d9b9f555f`.

The remaining black-tab reports shared a malformed saved tab shell. Muxlet's
working Who, Events, and Exchange tabs are restored with native locked
capabilities, while older Walker placement created a normal user tab and then
appended its Founder rule without registering that tab with the reactive rule
engine. Replacing only the content slot left that broken lifecycle intact.

Walker now identifies only an exact `Exchange Walker` tab inside the native
Who/Events/Exchange host. If it has the legacy shell, Walker removes its active
content through Muxlet, deletes the old tab object, recreates it at the same
position with the same locked settings as the working tabs, registers the
Founder rule through Muxlet's native API, applies a new content slot, and
restores active selection. A valid native tab remains untouched. The exported
Full workspace now declares every matching setting explicitly.

Source and exact-package runs pass all 81 native groups: API 23, adapter 5,
Walker 30, startup 7, topology 8, map lifecycle 1, and Galaxy lifecycle 7. All
250 Lua checks, 32 metadata checks, and 221 compiled-script/source matches pass.
No profile was modified and no package was installed, pushed, or released.

## 2026-09-10 Exchange Walker restored-tab inherited visibility recovery

Candidate: `f2ce-tools-3.3.0-native-ew13.mpackage`; Walker
3.4.0-native.9. API 1.2.0-candidate.3 is unchanged.

SHA-256: `675803813537a705f50ca33c086af7b01a66ed88b6e47f34adb227f882bd357f`.

Live inspection confirmed that Ersella had ew12 installed and the selected
`Exchange Walker` tab was correctly persisted with
`_activeContent: exchange_walker_live`. The black surface therefore was not a
stale binding or missing package. Inspection of Mudlet 5.0.1's
`Geyser.Container` showed the remaining defect: explicit `hidden` and inherited
`auto_hidden` flags are independent, while plain `show()` clears only the
former. The Muxlet-owned slot built while the restored tab was inactive could
remain `auto_hidden=true` after our earlier one-call reveal.

Active-tab repair now clears both visibility flags, in the required order, on
the tab content and Muxlet-owned content slot before reflow. The offline Geyser
mock now models Mudlet's two-flag behavior, and the saved-tab test starts with
both flags asserted on both layers and verifies all four are cleared.

Source and exact-package runs pass all 80 native groups: API 23, adapter 5,
Walker 29, startup 7, topology 8, map lifecycle 1, and Galaxy lifecycle 7.
All 250 Lua checks, 32 metadata checks, and 221 compiled-script/source matches
pass. No profile was modified and no package was installed, pushed, or
released.

## 2026-09-10 Exchange Walker Mudlet 5.0.1 footer compatibility

Candidate: `f2ce-tools-3.3.0-native-ew12.mpackage`; Walker
3.4.0-native.8. API 1.2.0-candidate.3 is unchanged.

SHA-256: `aa103bb5e8c492934bab702020a9c8aff114494726fdf4db6e7c506336373a2b`.

Live Mudlet reported `[string "Script: board"]:327: attempt to call method
'setToolTip' (a nil value)` while constructing the integrated Exchange Walker
tab. Mudlet 5.0.1's `Geyser.CommandLine` does not implement the Label-only
tooltip method. Because the input was constructed before Refresh, Preview, and
the action rows, that uncaught enhancement call explained the visible input and
missing buttons exactly.

All board tooltip calls are now optional and protected. The test Geyser command
line intentionally omits `setToolTip`, matching the installed runtime, while
the visible Inspect label retains the field explanation and its supported
tooltip. Per-widget footer layout is also isolated so a future unsupported
primitive cannot prevent later controls from being positioned.

Source and exact-package runs pass all 80 native groups: API 23, adapter 5,
Walker 29, startup 7, topology 8, map lifecycle 1, and Galaxy lifecycle 7.
All 250 Lua checks, 32 metadata checks, and 221 compiled-script/source matches
pass. No profile was modified and no package was installed, pushed, or
released.

## 2026-09-10 Exchange Walker stale-tab recovery and board polish

Candidate: `f2ce-tools-3.3.0-native-ew11.mpackage`; Walker
3.4.0-native.7. API 1.2.0-candidate.3 is unchanged.

SHA-256: `a0ab2635ba6d0a0f9bdce6ac4ca30d1deff6be320749c614bf4ec71d378f6e7b`.

Live inspection established that Ersella's selected tab was named `Exchange
Walker` but persisted `_activeContent: fed2_cargo`. The same tab stayed black
with other content while Walker rendered in a newly created pane. Muxlet 2.3.2
restores tab content while the tab is hidden, can leave both the tab container
and its framework-owned content slot explicitly hidden, and later activates the
saved tab without revealing that slot.

The native placement path now recognizes the intended named tab, replaces its
stale content binding with `exchange_walker_live`, verifies the complete board,
and reveals both Mux layers when that tab is active. It reuses the existing
Who/Events/Exchange host rather than creating another tab or pane. The named
tab remains the repair target even when a temporary direct-pane Walker mount
also exists, matching the live diagnostic workaround.

The board footer is also reorganized and styled for clearer action hierarchy.
The formerly ambiguous `Planet` field is now `Inspect`: Enter/Refresh performs
a one-off read-only remote exchange capture, while Preview calculates proposed
settings without applying them. Tooltips explain each action, state and schedule
remain separate from the operational message, and Unicode comparison text that
rendered incorrectly in Mudlet was replaced with ASCII-safe wording.

Source and exact-package runs pass all 80 native groups: API 23, adapter 5,
Walker 29, startup 7, topology 8, map lifecycle 1, and Galaxy lifecycle 7.
All 250 Lua checks, 32 metadata checks, and 221 compiled-script/source matches
pass. No profile was modified and no package was installed, pushed, or
released.

## 2026-09-10 Exchange Walker saved-tab mount recovery

Candidate: `f2ce-tools-3.3.0-native-ew10.mpackage`; Walker
3.4.0-native.6. API 1.2.0-candidate.3 is unchanged.

SHA-256: `04601c29d2c0a4459c0d14faaeea789fb606c5a0bb858fa4ab34420ea33e2811`.

The remaining black-tab failure was reproduced from the Ersella workspace:
Muxlet restores every saved tab before activating the selected tab, so an
inactive Exchange Walker tab can initially report `0x0` content geometry.
Walker previously built and permanently accepted that effectively invisible
board. A construction interrupted during hot reload could likewise leave a
partial instance that later placement attempts mistook for a healthy mount.

Walker now uses the host tab viewport when an inactive tab has no usable
geometry, validates the complete widget/control tree before accepting any tab
or pane placement, rebuilds partial instances, reveals an active content slot,
and reflows after successful recovery. It preserves the saved tab, selected
workspace, Founder gate, bottom controls, and all map/Galaxy content.

Source and exact-package runs pass all 78 native groups: API 23, adapter 5,
Walker 27, startup 7, topology 8, map lifecycle 1, and Galaxy lifecycle 7.
All 250 Lua checks, 32 metadata checks, and 221 compiled-script/source matches
pass. No profile was modified and no package was installed, pushed, or
released.

## 2026-09-09 Exchange Walker hot-update board recovery

Candidate: `f2ce-tools-3.3.0-native-ew9.mpackage`; Walker
3.4.0-native.5. API 1.2.0-candidate.3 is unchanged.

SHA-256: `263fdffba7df8da8b7e80a3e1e32a4d1bf811d4f8867dfccfe5cec8b32c32e56`.

The Exchange Walker board now explicitly renders CSS-colored labels in
Geyser `nocolor` mode, bypassing Mudlet 5.0.1's color parser. Content applied
to a hidden zero-sized Mux tab reflows when restored/revealed and again on the
next event-loop turn. The existing-tab placement path now also verifies that
the newly loaded Walker owns a live board instance. If a hot package update
removed the outgoing widgets while Muxlet retained the saved content ID, the
board is reapplied into that same tab instead of remaining black. The existing
Who/Events/Exchange host, Founder gate, bottom controls, and map/Galaxy content
remain unchanged.

The Walker suite passes 25 groups, including exact four-target Mux Settings
persistence, render-failure isolation, `0x0` hidden-tab recovery, and explicit
color-parser bypass, plus hot-reload reconstruction of an existing tab. Source
and exact-package runs pass all 76 native groups: API 23, adapter 5, Walker 25,
startup 7, topology 8, map lifecycle 1 and Galaxy
lifecycle 7. All 250 Lua checks, 32 metadata checks and 221 compiled-script/source
matches pass. No profile, gameplay command, push, release, or API policy change
is performed.

## 2026-09-09 topology capture and owned-response serialization

Candidate: `f2ce-tools-3.3.0-native-ew7.mpackage`; pair with FedHauler 1.16.6.
API 1.2.0-candidate.3 and Walker 3.4.0-native.3 remain unchanged.

SHA-256: `bf327afa910db69a284b3a68c2cfedaab990fabb93eca9e9f48646505a36c9b5`.

The reported `topology_capture` is F2CE's two-phase login sync. Automatic
topology now defers to active API/native command and navigation reservations;
a busy startup attempt reschedules without output. Capture timers are armed
before each phase's command. Timer/transport failure, disconnect and hot reload
clear topology's own state while preserving unrelated captures. Manual sync
remains explicitly available.

The paired consumer holds an existing public API command lease through owned
and automated local-market responses, preventing topology/Galaxy output from
starting inside either scan. If topology began first, it waits through both
native 15-second phase bounds, then dispatches one owned request. Persistent
contention remains fail-closed; no native guard was relaxed.

Source and compiled package pass 74 groups, 250 Lua checks, 32 metadata checks,
and 221 embedded-script/source matches. Paired FedHauler source/package checks
pass 243 tests and all 17 archive members match source. No install, gameplay,
push, release, trade-policy or Exchange Walker UI change was performed.

## 2026-09-09 Galaxy capture lifecycle and consumer handoff

Candidate: `f2ce-tools-3.3.0-native-ew6.mpackage`; pair with FedHauler 1.16.5.
API 1.2.0-candidate.3 and Walker 3.4.0-native.3 are unchanged. This patch is to
native Galaxy's capture lifecycle, not a relaxation of API contention guards.

SHA-256: `6864ae8985a06f72bf11cae9504fa9a750aa05f304e551992f06fbd6f7022e23`.

The live blocker is `galaxy_capture`; capture duration/staleness cannot be
deduced from the transcript. Native Galaxy previously sent its background
request without consulting existing reservations. It now defers to API/native
owners, arms bounded cleanup before sending, and clears its own state/gag
triggers on send/timer failure, disconnect, character change or reload. A
reload preserves the last complete index and retires its owned handlers.
No other capture is reset or navigation owner overridden.

Seven real-script lifecycle groups cover silence completion, continuous-output
maximum duration, missing/broken timers or transport, UI failure, reservation
deferral, disconnect, and reload. Consumer integration reproduces the real
Galaxy scrape overlapping a zero-owned text response: route 1 now waits at
the same target, then acquires normally after capture ends. A permanently
blocked capture stops after a bounded wait with review memory retained.

Source and compiled package pass 69 groups, 250 Lua checks, 32 metadata checks,
and 221 embedded-script/source matches. Paired FedHauler source/package checks
pass 237 tests and 17 archive/source matches. Live acceptance remains pending;
no install, gameplay, publication or Exchange Walker UI changes were performed.

## 2026-09-09 navigation completion handoff

Candidate: `f2ce-tools-3.3.0-native-ew5.mpackage`, API 1.2.0-candidate.3.
Pair with FedHauler 1.16.4. Exchange Walker remains 3.4.0-native.3; its
separately reported black-tab issue is unchanged.

SHA-256: `6203910217eb6b06d2dc8bc97a9972d3c2fa159a7088e2c23e7358475c5ec795`.

The previous API completed a navigation request as soon as the destination ID
matched, before checking native active/pending movement. Its `arrived` callback
path bypassed that check as well. Now retain the lease until speedwalking,
pending movement/arrival, exploration/circuit and customs continuation settle.
Only then release ownership and publish completion, so event subscribers see
the same released broker as the result callback. Foreign ownership remains
untouched. Native map code and map/pane contents are not changed.

New regressions cover each unsettled state, early native arrived callbacks,
and command acquisition from completion events. Consumer integration also
walks two simulated exchanges, waits before each local futures request, and
advances without contention. FedHauler separately waits at most five seconds
for temporary capture contention; persistent or foreign-owner contention stops
with explicit blocker details and preserves its checkpoint for explicit resume.
No capture reset, owner override, or trade retry is introduced.

Offline source and compiled-package checks cover 62 groups (API 23, adapter 5,
Walker 23, startup 6, topology 4, map lifecycle 1), 249 Lua syntax checks,
32 metadata checks and 221 compiled-script matches. Paired FedHauler checks
cover 182 legacy, 36 native and 13 Trader-goal tests. Live acceptance is pending;
the user's earlier message did not identify which native blocker persisted.
No live install, gameplay or publication was performed.

## 2026-09-09 premium hauling ownership correction

Candidate: `f2ce-tools-3.3.0-native-ew4.mpackage`, API 1.2.0-candidate.2.
Walker stays 3.4.0-native.3; its separately reported black-tab issue is not
claimed fixed by this package.

SHA-256: `e5e3032cf0ac8a46545d7792b7f5822831407b77c2d54771a26e5d093d89554b`.
249 syntax checks, 32 metadata checks, 221 compiled-script matches, and all
59 regression groups passed against source and compiled package (API 20,
adapter 5, Walker 23, startup 6, topology 4, map lifecycle 1). The paired
FedHauler 1.16.2 native integration suite also passes all 22 tests against
the Lua extracted from both built artifacts.

Native `f2t_hauling_start` reserves navigation owner `hauling` before invoking
price analysis. The API already borrowed the correct hauling command lease,
but its adapter still treated that stationary reservation as foreign contention.
Allow only the owned hauling-price request to share that exact reservation.
Active or pending movement, foreign owners, recovery and capture conflicts
remain denied. Ownership is neither cleared nor overwritten.

The native adapter test covers this boundary and FedHauler's real native-API
test invokes the price checker synchronously inside hauling start with the
reservation set. No live account, profile, or network gameplay is exercised.

## 2026-09-09 Exchange Walker color/settings/layout repair

Candidate: `f2ce-tools-3.3.0-native-ew3.mpackage`, Walker 3.4.0-native.3.
Native API and FedHauler are unchanged in this repair.

SHA-256: `59ffff8eb9bb71e15c8ceaba3f66b79a342db61f14b74d945dfdef960849a446`.

- 249 Lua syntax and 32 metadata checks passed.
- API 20, adapter 4, Walker 23, map startup 6, topology 4, map lifecycle 1
  groups passed: 58 total, against both source and the compiled package.
- 221 embedded scripts matched the tested source.
- Strengthening the Geyser echo mock to reject a numeric second argument
  reproduced the color crash before the patch (16 failing Walker groups).
- Exact `tempest, amsterdam, holland, denmark` Settings edits update the runtime
  four-target list, survive a mock profile reload, remain isolated from another
  profile, and send no commands until explicitly armed and started.
- An injected board repaint failure no longer interrupts settings application,
  preview invalidation, or cancellation. Target and interval defaults are visible.
- Empty and populated table geometry checked at 417x828, 643x450 and 1000x1000;
  compact/full headings, bottom controls, viewport height, sorting, header/body
  alignment, blank suppression and map/Galaxy isolation remain covered.

No live account or profile was modified; actual Qt appearance still needs a
test-profile check. This artifact does not claim to fix the separately reported
futures owned-refresh navigation issue.

## 2026-09-09 native consumer services / exchange board candidate

Candidate: `f2ce-tools-3.3.0-native-ew2.mpackage`, API 1.2.0-candidate.1,
Walker 3.4.0-native.2, pinned Muxlet v2.3.2.

SHA-256: `a64526c784fcb9c4e45253f52c34882300a113e66e7b83db6c5e85ee15cfbb13`.

- 249 Lua syntax checks and 32 JSON/manifest checks passed.
- API 20, native adapter 4, Walker 20, map startup 6, topology capture 4,
  and map content lifecycle 1 groups passed (55 total).
- 221 scripts reconstructed from compiled package XML matched source. All
  six suites passed again against those actual packaged scripts.
- FedHauler 1.16.0 companion: 182 legacy regressions and 17 actual native
  API/consumer integration tests passed against source and both built packages.
- New native coverage: load order, OFF authority, disconnect, genuine GMCP
  receipt generations and server-local/map room identity, broker release before
  arrival callback, top-20 premium provider hook, PO discovery/bulk ownership,
  low-stamina synchronous startup, in-flight movement settlement/timeout,
  foreign navigation isolation, bounded verified navigation, cancellation, and
  an already-here arrival synchronously starting the next route.
- New board coverage: Founder promotion/demotion/unknown rank; tab insertion
  without changing other tabs/maps; bottom controls; header/body pixel alignment
  after resize; signed Net colors and sorting; OFF read-only refresh; incomplete
  capture retention; cancellation; and bounded capture-only blank suppression.

No live account, installation, game command or GUI mutation was used. Geyser and
Mux behavior is exercised with mocks plus the real native table implementation;
actual Qt/Mudlet appearance and interactive lifecycle remain acceptance checks.
This candidate is not an upstream release. Native manual premium scans while a
haul is paused remain broker-blocked; use its registered premium provider flow
or stop hauling before a manual scan.

## 2026-09-09 native Exchange Walker / API 1.1 candidate

API development handoff was completed from the Build F2CE Module API task.
Work continues on `codex/native-exchange-walker`, based on `9d81fec`, in the
user's F2CE fork. No live profile, server, deployment, release, or push was used.

Candidate: `f2ce-tools-3.3.0-native-ew1.mpackage` (Walker 3.4.0-native.1;
API 1.1.0-candidate.1; pinned Muxlet v2.3.2).

SHA-256: `949CD3F4107FF21EB60605859BDC7BCE370B1B24D1ADA2EB7CE7CF6B795C9BEC`.

Build and verify with the checked-in scripts (Lua/luac 5.1.5, Muddler 1.1.0,
OpenJDK 21):

```powershell
./scripts/build-native.ps1 -MuddlerJar <muddle-1.1.0-all.jar> -JavaCommand <java.exe>
./scripts/test-native.ps1 -LuaExe <lua51.exe> -LuacExe <luac51.exe> -PackagePath <candidate.mpackage>
```

Results:

- Lua syntax: **244 files passed**.
- JSON/mfile validation: **32 files passed**.
- API suite: **20 passed, 0 failed**.
- Native adapter suite: **4 passed, 0 failed**.
- Native Walker integration: **17 groups passed, 0 failed**, including 165
  stock-policy cases verifying every intermediate min/max command is legal.
- Map startup safety: **6 passed, 0 failed**.
- Topology capture safety: **4 passed, 0 failed**.
- Map content lifecycle regression: **passed**.
- Exact compiled XML: **216 embedded scripts matched** checkout source after
  the documented Muddler metadata substitutions and dependency injection.
- All six suites were then repeated successfully against the reconstructed
  Lua from the actual package XML, not merely the staging directory.
- ZIP portable paths, required notices, native markers, pinned Muxlet URL,
  package XML parsing, and absence of the separate API loader: **passed**.
- `git diff --check`: **passed**.

New coverage includes disabled/contended API sessions; command input/range and
local ownership rejection; capture timeout, foreign callback ownership and
late callback isolation; callback-error cleanup; pruning released resources;
reconnect authority revocation; one-line/wrapped rows; wrong remote response
targets; incomplete counts; exact apply acknowledgements; no timeout retry;
Muxlet late load, visible defaults and custom validators; migration/schema
rejection and preserving native settings; explicit timer start and interval;
settings-change cancellation; duplicate-package blocking; pane 1/7/foreign
pane isolation; idempotent registration/reload/uninstall; and capture-scoped
blank suppression.

### Remaining live acceptance

The candidate has **not** been installed into Mudlet or run against the game.
Offline widget mocks do not prove Qt rendering. In a backed-up test profile,
check the real Settings form, old-to-native migration, standalone uninstall,
the default pane 15 and an existing custom layout, map/Galaxy rendering,
remote capture/preview, one explicit confirmed apply, timer start/stop, and
reconnect OFF behavior before adopting it for unattended use.

The interface hooks were inspected in Muxlet v2.2.9, but the package keeps the
existing v2.3.2 dependency; there was no live v2.2.9 installation test. No new
repository-wide lint claim is made; the older lint results below are historical.

## Historical candidate 1.0 validation

Environment: Windows, portable Lua/luac 5.1.5, LuaCheck 1.2.0, muddler 1.1.0, and Android OpenJDK 21. Validation was run on `feature/module-api-v1` after merging upstream `v3.3.0`. No game connection, profile automation, installed Mudlet package, or public server was used.

## Commands and results

Repository-wide Lua syntax (PowerShell supplied every `*.lua` path outside `build/` to luac):

```text
tools/lua51/luac51.exe -p <each Lua file>
LUAC checked=233 failed=0
```

JSON/package metadata parsing:

```text
Get-Content -Raw <each JSON file and mfile> | ConvertFrom-Json
JSON checked=31 failed=0
```

Offline API suite:

```text
tools/lua51/lua51.exe tests/api/run.lua src/scripts/api/v1.lua
RESULT 20 passed, 0 failed
API_TEST_EXIT=0
```

Native 3.3 adapter contract suite:

```text
tools/lua51/lua51.exe tests/api/native_adapter_run.lua src/scripts/api/v1.lua src/scripts/api/adapter.lua
RESULT 4 passed, 0 failed
ADAPTER_TEST_EXIT=0
```

Lint:

```text
luacheck.cmd src/scripts/api tests/api examples/module_api_v1
Total: 122 warnings / 0 errors in 6 files
LUACHECK_EXIT=1
```

The lint warnings are non-blocking style findings, predominantly long lines and unused callback arguments already present in the candidate API/test files. No undefined-variable or syntax errors were reported. The new native-adapter contract test is warning-free.

Native package build:

```text
java.exe -jar muddle-1.1.0-all.jar
MUDDLER: [INFO]: Version     : 3.3.0
MUDDLER: [INFO]: Found src\scripts\api\scripts.json
MUDDLER: [INFO]: Using script from src\scripts\api\v1.lua for script 'v1'
MUDDLER: [INFO]: Using script from src\scripts\api\adapter.lua for script 'adapter'
MUDDLER: [INFO]: XML created successfully, writing it to disk
MUDDLER: [INFO]: Build completed successfully!
MUDDLER_EXIT=0
```

The generated `build/f2ce-tools.mpackage` was opened as a ZIP and checked for `config.lua`, package XML, `1.0.0-candidate.3`, and the 3.3 adapter compatibility marker; every assertion passed. The local muddler-only artifact deliberately has no `MUXLET_URL` injection. GitHub's release workflow performs that injection before its build, so this local structural-validation artifact is not an installable release and is not committed.

## 2026-09-05 map command-safety follow-up

The 3.3-aligned branch was additionally checked after gating its automatic
login topology refresh on mapping enablement, the topology auto-sync setting,
login state, and a live connection. Minimal mode remains an intentional UI-only
choice: automatic topology refresh is permitted there when the map settings
remain enabled. Manual `map topology sync` remains available even when
automatic mapping is disabled.

```text
tools/lua51/luac51.exe -p <each Lua file outside build/>
LUAC checked=235 failed=0

tools/lua51/lua51.exe tests/map/startup_topology_sync_run.lua src/scripts/map/events.lua
RESULT 6 passed, 0 failed

tools/lua51/lua51.exe tests/map/topology_capture_safety_run.lua src/scripts/map/topology_capture.lua
RESULT 4 passed, 0 failed

tools/lua51/lua51.exe tests/api/run.lua src/scripts/api/v1.lua
RESULT 20 passed, 0 failed

tools/lua51/lua51.exe tests/api/native_adapter_run.lua src/scripts/api/v1.lua src/scripts/api/adapter.lua
RESULT 4 passed, 0 failed

Get-Content -Raw <each JSON file and mfile> | ConvertFrom-Json
JSON checked=33 failed=0

tools/muddler/expanded/muddle-shadow-1.1.0/bin/muddle.bat
MUDDLER_EXIT=0
```

The two map suites cover pre-login and disconnected startup, disabled mapping,
disabled topology auto-sync, duplicate vitals initialization, disabling while
the deferred timer is pending, cancellation before the second capture command,
fresh reconnect behavior, and preservation of an explicitly requested manual
sync. No network, game connection, profile, credentials, or installed package
was used.

## Covered behavior

The suites cover version/capability mismatch, duplicate module IDs, reload idempotence, scoped cleanup, 3.3 navigation start statuses, pending multi-leg navigation with an intermediate completion, native-owner contention and compare-and-release cleanup, interruption policy, both cancel modes, zero-command behavior after disable or native contention, built-in provider contention recheck, provider fallback/timeout/late-callback isolation, callback containment, nil/partial GMCP, reconnect reset, unload during active navigation, hauling mode validation, native hauling rejection, and service-lease release.
