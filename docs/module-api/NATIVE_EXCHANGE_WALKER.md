# Native Exchange Walker integration candidate

This branch integrates Exchange Walker into **the user's F2CE fork**, not an
upstream-approved official release. It builds one `f2ce-tools` package containing
the native `F2CE.API.v1` API and Walker. There is no separate Walker or
`Fed2ModuleAPI` dependency for this module. FedHauler's existing compatibility
package is unaffected and may still require the separate API.

Baseline: F2CE 3.3.0 plus the existing map-content lifecycle repair, native API
1.1.0 candidate.1, and Walker 3.4.0-native.1 ported from the public Walker 3.3.3
source at `e7276b81f962b3c7e4c72c6b34a161e1d3415ba6`.

## Settings and defaults

All configurable preferences live in **Muxlet Settings > F2CE-Tools > Exchange
Walker**. `ew settings` or the content's SETTINGS button opens that window.
The interface uses hooks present in Muxlet v2.2.9 (`register`, `validator`,
`onChange`, `toggle`, `showTab`). The F2CE dependency remains v2.3.2; do not
downgrade Muxlet to use the window.

| Policy | Default |
| --- | --- |
| Review interval | 30 minutes; configurable 5–1440 |
| Deficit producers | 6% spread, min/max 0/0 |
| Breakeven producers | 6% spread, min/max 0/0 |
| Growing surplus producers | 40% spread, min=current stock (clamped), max=min+1000 |
| Reserve policy | At 10000 stock: min 10000, max 20000 |
| Owned remote targets | Empty; explicitly select planets |
| Excluded commodities | Empty; case-insensitive exact names |

Saving a valid policy invalidates previews and stops the timer/current work.
Saving does not arm or start anything. Invalid field combinations are rejected.
Changing settings cannot retroactively recall a command already sent to the game.
The internal confirmation/capture timeouts are protocol safeguards, not user
preferences. Settings persistence belongs to Muxlet's existing profile storage.

## Upgrade and lifecycle

1. Back up the Mudlet profile and install the candidate F2CE package in a test
   profile first. This is a full package replacement, not a generated-XML overlay.
2. On Muxlet readiness, the module imports a valid legacy
   `exchange-walker-live-settings.ini` if no native settings are present. Native
   settings take precedence. Unsupported/invalid legacy input blocks enablement
   and is not applied. The migration does not remove the original INI.
3. While the standalone `exchange-walker-live` package/runtime is present, native
   Walker remains blocked and does not install a competing `ew` alias. After
   checking the migrated settings, uninstall the standalone package; its own
   uninstall routine may delete its INI, but the imported Muxlet settings remain.
4. Native Walker starts OFF after load, reload, or reconnect. Use `ew on`,
   `ew preview [planet]`, then `ew apply`. Timer management still requires
   explicit `ew auto on`; `ew auto off`/`ew cancel` stops it.

The content ID remains `exchange_walker_live` so existing saved assignments
continue to resolve. New default Full workspaces include a resizable floating
`pane_15`. Existing custom layouts are not replaced: existing Walker placement
wins; optional placement only uses an empty existing pane numbered 15–32.
If none exists, use the Content Library. Minimal/BYOW mode remains user-managed.
Map, Galaxy, and foreign panes are never repurposed or deleted by Walker.

Uninstalling F2CE stops Walker, cleans its runtime and removes its native
preferences. Migration-source files are not deleted by the native module.

## Native API addition

`API.exchange.acquire(context, {reason="explicit reviewed operation"})` returns
a scoped session holding the command broker. Only an enabled module can acquire
one. The session supports:

- `capture("exchange"|"production", planet_or_nil, callback, {timeout=15})`:
  native PO capture, copied results, response-target verification, serialized
  capture, bounded timeout, and late-callback isolation. Callback is `(rows,error)`.
- `set({kind="min"|"max"|"spread", commodity, value, planet=optional})`:
  integer/range/name validation and typed command construction through the
  broker. Local mutations require matching current owner/player GMCP; remote
  requests explicitly name a planet and the server remains the ownership
  authority. The consumer must validate the server acknowledgement.
- `status()` and `release(reason)`: cancellation compares callback ownership
  before resetting the native capture; foreign work is never reset.

Keep a session until a capture pair or apply sequence ends, then release it.
OFF/unload/reconnect also revoke it. Walker waits for each exact commodity,
planet, kind and value confirmation before sending the next setting, with no
automatic retry. Incomplete captures never produce an applicable plan.

`command.sent` is a transport event, **not game acceptance**. The older
`command.acknowledged` event remains a deprecated transport alias for existing
consumers. Reconnect now disables module authority, not just its current leases.

The native PO parser handles one-line and wrapped rows directly. No parser
replacement or standalone adapter loader is shipped. Blank suppression is
limited to an identified active PO response, never general room output.

## Source and release boundaries

The original F2CE MIT notice remains. Walker-derived files retain GPL-2.0-only
notices and the GPL text is shipped as `EXCHANGE-WALKER-LICENSE.txt`; the F2CE
notice is shipped as `F2CE-LICENSE.txt`. This mixed-source candidate must not
be described as entirely MIT-licensed. Upstream adoption, licensing review and
an official release version remain maintainer decisions.

Only the user's `ralphcma/f2ce-tools` fork is the update destination. No PR,
release, live installation, game command, or upstream write is performed by
the offline build/test workflow.

## Build

```powershell
./scripts/build-native.ps1 -MuddlerJar <muddle-1.1.0-all.jar> -JavaCommand <java.exe>
```

The build injects the pinned Muxlet release URL in a disposable staging tree,
verifies package structure/notices/markers, and produces a portable candidate
`.mpackage`. See `TEST_RESULTS.md` for actual verification results and remaining
live acceptance checks.
