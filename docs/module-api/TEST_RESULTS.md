# Module API verification

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
