# F2CE 3.2.5 compatibility and deprecation policy

The native adapter was checked against the installed 3.2.5 package behavior and the upstream `v3.2.5` tag. It preserves all existing globals and functions and uses these established contracts internally:

- navigation: `f2t_map_navigate`, owner set/clear, pause/resume/stop, and the speedwalk status globals;
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

Known 3.2.5 adapter limitations: native navigation exposes no direct completion event, so the compatibility adapter observes copied speedwalk status on room events; graceful navigation cancel stops at the next API tick; built-in price cancellation cannot abort a command already transmitted; mapper `getPath` updates Mudlet's internal planned path before the adapter copies it.
