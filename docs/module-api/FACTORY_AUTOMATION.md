# Factory automation API — 2026-09-20

`API.company.factoryAutomationVersion == 1` advertises optional bounded
automation fields on the existing `prepareFactory` / `confirm` operation.
Existing manual clients retain their prior behavior.

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
payload. It sends `set factory <new slot> wages 40` once, requests the complete
factory display, and checks owner/product/planet/slot/wage. Completion includes
`wages=40` and `wages_confirmed=true`. Failure retains an uncertain result and
never repeats construction. The consumer must journal before the first depot
or factory send and close that intent only after wage verification as well.

Depot-only operations have no factory wage write. Default load/reconnect grants
no automation authority. A consumer's explicit Start must provide a bounded
session, budget, identity fencing, shutdown cleanup and per-site selection.

Offline coverage: `tests/api/company_run.lua` checks both company ranks,
two-per-planet/reserved-workforce/contribution limits, exact wage command,
complete display verification, lost authority, timeout and cancellation.
FedHauler consumer tests additionally cover batch limits and native integration.
No public-server or graphical profile acceptance is claimed by these tests.
