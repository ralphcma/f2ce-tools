# Company inspection API (native-ew20)

## System workforce inspection (native-ew26)

Capability `company.system.read` exposes
`API.company.system(context, systemName, callback)`, authorized as
`company.system.inspect` with `{system=systemName}`. It holds one command lease
across `di system <systemName>` and the rank's `di business` / `di company`.
Both the matching report text and fresh owner-bound GMCP must arrive before
completion. Silence is never successful completion; timeout is 15 seconds.
Cancel/disconnect/unload remove observers, timers and the lease before callback.

The result is `{system, captured_at, planets}` keyed by lowercase planet name.
Each entry has `planet`, `system`, `economy`, `available`, `total`, and `closed`.
Economy None has no workforce values. Parse rejects missing/duplicate workers,
unknown economies, impossible counts, conflicting identities and partial
reports. Validates all planets in the response, with a 256-planet / 128KiB bound.
Additional infrastructure/approval fields are not interpreted. This read does
not use/enable navigation's capture flags, explore, gag output, or reserve labour.
Available workers are a snapshot, not a hiring guarantee or build permission.

## Original inspection contract

`F2CE.API.v1` 1.2.0 candidate.4 adds `company.read` and the `company` GMCP
channel (`char.company`, `data.company`). This is read-only groundwork, not
an autonomous company manager or an upstream-approved release.

- `API.company.snapshot()` returns a copied company/business snapshot and
  receipt, or an error. It checks current GMCP character, CEO and rank.
- `API.company.refresh(context, callback)` requests `di business` at
  Industrialist, `di company` at Manufacturer/Financier. Only an actual new
  GMCP push completes the read; refreshing a cache does not.
- `API.company.inspect(context, number, callback)` requires that factory in
  the owned company snapshot. It sends `display factory <number>` and accepts
  only a complete, validated display for that company and slot. The pure
  native factory parser preserves input names, required/available tons,
  shortfall, output storage, disposal, workers, efficiency and progress.
  Reported accounting profit is separate from current income minus expenditure.

Requests require an enabled context with an explicit `authorize` callback for
`company.refresh`/`company.inspect`. They return a cancellable handle and hold
the command broker until response, cancellation or a 15-second timeout. A
callback receives `(value, error)` after cleanup/release. Disconnect/unload
cancels outstanding work. Inputs are never inferred from missing GMCP fields.
This reader does not gag unrelated output or alter Mux panes.

No typed company-spending operations are exposed. Existing native company
panels and manual factory controls remain unchanged. Automated growth toward
100m, factory selection, repair/dividend budgets, depot capacity validation and
input/output hauling remain follow-on work, not features of this release.

## PO stamina change

Protection clients may declare `isSettlingCommands()`. When pausing, a true
result permits only the already-existing command lease owned by that same
module to drain. The existing movement-settle gate waits for both movement and
that lease, bounded to ten seconds. New or foreign leases fail closed. Clients
must cancel their read captures and must not issue follow-on work during pause.
FedHauler 1.17.10 records cargo confirmations while suspended, then freshly
revalidates delivery after food recovery. No literal `yes` is sent by this API.

## Offline checks

Run `lua tests/api/company_run.lua`, `lua tests/api/run.lua` and
`lua tests/api/native_adapter_run.lua`. Consumer integration and food-handoff
regressions run in FedHauler's `tests/test_native_f2ce.lua` against this tree.
Synthetic factory fixtures follow `Factory::Display` in the game server source;
no account profiles or live transactions are part of these tests.
