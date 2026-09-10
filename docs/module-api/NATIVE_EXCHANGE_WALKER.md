# Native Exchange Walker integration candidate

This branch integrates Exchange Walker into **the user's F2CE fork**, not an
upstream-approved official release. It builds one `f2ce-tools` package containing
the native `F2CE.API.v1` API and Walker. There is no separate Walker or
`Fed2ModuleAPI` dependency for this module. FedHauler 1.16.0 can use this native
API directly; older FedHauler versions still require the separate API.

Baseline: F2CE 3.3.0 plus the existing map-content lifecycle repair, native API
1.2.0 candidate.3, and Walker 3.4.0-native.7 ported from the public Walker 3.3.3
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

For example, enter `Tempest, Amsterdam, Holland, Denmark` in **Owned exchange
targets** and click **Apply beside that settings field**. The board footer
shows `4 targets`; hover for the saved list. The board's separate **Apply** button
applies an unexpired preview to the game; it does not save the planet list.
Refresh alone does not create a preview. Each Mudlet profile retains its own
list and automation state; no account/profile folders are shared or edited.

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

The content ID remains `exchange_walker_live`. New Full workspaces include an
**Exchange Walker tab beside Who, Events and Exchange**. Existing layouts are
searched by their tab content, not a hard-coded pane number; one Walker tab is
added without switching the active tab. An existing Walker tab is reused. If
that host is absent, an existing Walker pane or empty pane 15–32 is used. Map,
Galaxy and foreign content are never repurposed or deleted.

The tab is hidden below **Founder** and while rank is unknown. Promotion reveals
it; losing eligibility stops Walker and cancels its pending read-only capture.
Both visibility and command entry points check rank.

The table displays the last complete `display exchange <planet>` response:
Commodity, Spread, Current, Min, Max, Efficiency and Net. Headers sort; numeric
cells align right and signed Net/stock colors distinguish positive/negative
values. Header and body widths resize together. Refresh, Preview, ON/OFF, Apply,
Auto, Cancel, Settings and Clear controls are at the bottom.
Narrow panes use `Spr%`, `Stock`, and `Eff%` headings with full-name tooltips,
and two rows of three action buttons. The scrollable table follows the current
viewport height, including when empty. A visible empty-state explains Refresh.

Candidate `native-ew3` fixes a Lua multiple-return bug: the HTML escaping
helper leaked `gsub`'s replacement count to Geyser as an invalid numeric color,
causing `GeyserColor.lua` / `next_num` initialization failures. A settings edit
could then save to Muxlet but fail during repaint before updating the runtime
target list. Escaping now returns only text, accepted settings update runtime
before repaint, and display exceptions cannot interrupt lifecycle updates or
settings invalidation. Previously saved native lists are loaded on upgrade.

Candidate `native-ew8` hardens the actual Mudlet 5.0.1 path. Exchange Walker's
CSS-colored board labels explicitly use Geyser's `nocolor` mode, so board
construction and row rendering never enter the fragile `Geyser.Color.parse`
path. A Walker tab first applied while hidden may report a `0x0` content area;
the content now reflows immediately and once more on the next event-loop turn
when restored or revealed. This prevents a permanently black tab after its
container receives its real size. Target-setting application remains independent
of board rendering and the footer reports the saved target count.

Candidate `native-ew9` also repairs the hot-update lifecycle. Muxlet retains a
saved tab's `exchange_walker_live` content identity when the outgoing package
removes its widgets. Placement now requires both that identity and a live board
instance, and safely reapplies the registered content into the existing tab
when the widgets are missing. Updating F2CE no longer strands an otherwise
valid Exchange Walker tab as an empty black panel until a profile restart.

**Refresh is read-only and works while OFF**. It does not make an applicable
plan or authorize writes. Incomplete or wrong-planet responses retain the last
valid table with an error. Preview still requires ON, captures production too,
and highlights changed cells in cyan with observed/proposed hover details.
Apply remains explicit and acknowledgement-gated. Timer runs still require
explicit Auto ON.

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
limited to an identified active PO response and up to three immediately trailing
blank separators within 0.5 seconds. A different nonblank message immediately
ends trailing suppression. Room descriptions, chat and ordinary manually
requested exchange displays outside a managed capture remain visible. Leading
blanks before the identifying response header are not globally gagged.

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
