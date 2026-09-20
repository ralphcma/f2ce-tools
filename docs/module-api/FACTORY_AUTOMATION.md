# Factory automation API — 2026-09-20

Integration package: `3.3.0-native-ew33`. This adds an all-company duplicate
commodity check. ew32 fixed wage-verification ordering and settled-handle cleanup.
ew31 added the bounded automation service described below and superseded the
incorrectly numbered `ew29-pr` / `ew29-factory-auto` candidates. The manifest
carries the package version; ordinary builds need no version override.
This remains an upstream-review candidate.

`API.company.factoryAutomationVersion == 1` advertises optional bounded
automation fields on the existing `prepareFactory` / `confirm` operation.
Existing manual clients retain their prior behavior.

`API.company.factoryCompetitionVersion == 1` advertises public-planet exclusion.
All automatic factory builds, and manual proposals with
`exclude_existing_commodity=true`, read `di planet <planet>` under the existing
command lease at preview, confirmation and any post-depot continuation. They
refuse a matching commodity in ANY company's public factory list or the owned
roster. Malformed/partial/missing lists fail closed. Depot-only builds are exempt.
This is a fresh snapshot check, not an atomic server-side reservation against
another player building between the response and the purchase command.

Automation requires `automation=true`, `wages=40`, `planet_limit=2`,
`factory_limit=8`, `require_depot=true`, and a nonnegative integer
`reserved_workers`. The consumer supplies conservative workforce reservations
for colocated owned factories. Native fresh validation adds those reservations
to new-factory and missing-depot labour and refuses a third factory on a planet.
Each purchase still rechecks current stock, market sides, company identity,
slot limits, reserve, workforce, stamina, and positive material contribution
after the requested wage. No automatic native retry or general growth loop.

After the factory slot and exact company debit reconcile, the service asks the
consumer to authorize `company.factory.wages` with the original bounded build
payload. It sends `set factory <new slot> wages 40` once and waits for the exact
server acknowledgement matching slot, product, planet and wage. Only then does
it request the complete factory display and check owner/product/planet/slot/wage.
Buying a factory also prints its initial display, which can arrive after its
GMCP update: all pre-acknowledgement displays are ignored, even if they report
40ig. The acknowledgement has a 15-second deadline, followed by a separate
15-second display deadline. Wrapped/colored acknowledgement text is accepted
within bounded line/character limits. Completion includes
`wages=40` and `wages_confirmed=true`. Failure retains an uncertain result and
never repeats construction. The consumer must journal before the first depot
or factory send and close that intent only after wage verification as well.
Cleanup or a late cancellation preserves a completed handle's confirmed state.
Existing uncertain journals are not automatically cleared or replayed by this
update. Inspect the actual assets and wages before consumer-side reconciliation.

Depot-only operations have no factory wage write. Default load/reconnect grants
no automation authority. A consumer's explicit Start must provide a bounded
session, budget, identity fencing, shutdown cleanup and per-site selection.

Offline coverage: `tests/api/company_run.lua` checks both company ranks,
two-per-planet/reserved-workforce/contribution limits, exact wage command,
pre-acknowledgement purchase displays, matching/wrapped/malformed acknowledgements,
complete display verification, lost authority, timeout, cancellation, and combined
depot/factory purchases. Successful completion remains confirmed after cleanup.
FedHauler consumer tests additionally cover batch limits and native integration.
No public-server or graphical profile acceptance is claimed by these tests.
