# F2CE 3.3.0 compatibility and deprecation policy

The native adapter is aligned with the upstream `v3.3.0` source and preserves all existing globals and functions. New modules should require F2CE-Tools 3.3.0 or newer. The adapter uses these established contracts internally:

- navigation: `f2t_map_navigate` statuses (`walking`, `arrived`, `pending`, and `failed`), its `on_result(ok,status)` callback, compare-and-release ownership around the native owner set/clear functions, pause/resume/stop, destination re-resolution, and copied speedwalk/exploration status;
- hauling: rank-aware `f2t_hauling_start(nil)`, supported `f2t_hauling_start("exchange")`, pause/resume/graceful stop/immediate terminate, and copied hauling status;
- pricing: `f2t_price_check_commodity(commodity, callback)` with callback `(commodity,buy_data,sell_data)`;
- map: location resolution, room flag queries, area tables, galaxy index, and copied `getPath` results;
- GMCP: lowercase F2CE-established room/char/jobs/exchange paths.

## Deprecation policy

Legacy `f2t_*` and `F2T_*` names are not removed or changed in API v1. They are implementation compatibility surfaces, not stable module contracts.

1. New integrations should use `F2CE.API.v1` immediately.
2. A legacy global can be marked deprecated only after an official API replacement ships. The announcement must identify the replacement and first deprecated F2CE version.
3. Deprecations remain functional for at least two minor F2CE releases and six months, whichever is longer.
4. Removal requires a major F2CE release, release-note callout, and runtime warning for at least one preceding minor release.
5. `F2CE.API.v1` behavior and schemas receive additive compatible changes only. Breaking changes require `F2CE.API.v2`; v1 remains available through the same deprecation window.
6. Internal globals may continue changing without notice once official bundled modules and documented consumers have migrated behind the API.

The adapter retains a best-effort fallback for 3.2.5's older boolean/`nil` navigation result behavior, but that path does not receive the stronger 3.3.0 status contract and is not the recommended module baseline.

Known limitations: a started native speedwalk still has no dedicated completion event, so the adapter observes copied status on room events. Pending 3.3.0 self-healing routes are settled by their status callback or by resolving the requested destination; intermediate speedwalk completion is deliberately ignored. Graceful navigation cancel stops at the next API tick. Built-in price cancellation cannot abort a command already transmitted. The command broker blocks known native automation at acquisition and rechecks immediately before API transmissions, but it cannot prevent a user command or legacy code outside the API from starting afterward. Mapper `getPath` updates Mudlet's internal planned path before the adapter copies it.
