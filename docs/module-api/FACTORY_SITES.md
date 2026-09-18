# Explicit factory-site construction

Additive native contract: `API.company.factorySiteVersion == 1`, exposed as
`company.factory.site`. Existing single-factory API callers remain compatible.
No module is armed or started by loading the API.

The additive `API.company.factoryPriceReviewVersion == 1` contract accepts
`review_prices=true`. During the initial preview only, valid live bids/asks can
replace worse scan bounds. `proposal.market_review` carries `required`, the
output and input `previous_price` / `current_price` pairs, and material
contribution before/now per 75t batch (excluding wages and other costs).
`required=true` MUST revoke the consumer's old purchase confirmation and present
the updated terms for new explicit approval. No purchase occurs at preview.
Favourable quotes retain the old bounds; legacy callers remain strict.
The reviewed bounds are frozen for confirmation and depot-to-factory continuation;
neither phase silently rebases worse prices. Stock, demand, workers and all other
construction guards still apply even to the initial price-review preview.

`prepareFactory(context, options, callback)` additionally accepts:

- `require_depot=true`: reuse a named owned depot, or explicitly quote and buy
  one missing depot before the single factory. Requires a complete depot roster.
- `factory_limit=8`: lower total factory count cap, including existing factories;
  never increases the source rank's slot limit.
- `depot_only=true`: requires `require_depot`, commodity `Depot`, labour `0`,
  empty inputs and an existing owned factory at this planet. Quotes one missing
  depot only, with proposal slot `0`; full factory count does not block backfill.

The source `BuyDepot -> AddDepot -> Depot::Wages` path charges 1m construction
plus `7 * 40 * 16 = 4,480ig` initial wages. Proposed total cost is therefore
1,004,480 for depot-only, 3,004,480 for a factory plus missing depot, or 2m for
a factory with an existing depot. Company reserve covers that entire debit.
Seven additional workers are checked when a depot is missing. These mechanics
come from retained server source and disposable-server tests, not a promise
that a different public server revision has identical rules.

All proposals include boolean `require_depot`, `depot_needed`, `depot_only`.
Factory/depot rosters must remain unchanged between preview and confirm.
`company.factory.buy` authorizes the complete quoted site and must durably
journal its intent before spending. No purchase occurs at preview.

When needed, send `buy depot` once, then use an ordered fresh system/company
read to reconcile exactly one depot and its full debit, with unchanged factory
roster. Before proceeding, repeat market/workforce checks and request
`company.factory.continue` authorization against the same original proposal.
The consumer must still have the initial scoped confirmation and durable intent.
One `buy factory <product>` follows; exact new slot and 2m further debit must
reconcile, with unchanged depot roster. Depot-only stops after its reconciliation.

No automatic retries, rollback, refund or assumed success exist. Cancellation,
OFF, disconnect, late replies, changed owners/rank/location, reserve or stock
failure, and partial outcomes release owned resources. Once any purchase was
sent, failure remains **unconfirmed** and consumer journals block further
construction until inspected. A depot can have been bought even if a factory
was not; report and inspect both ownership and cash.

`scripts/build-native.ps1 -VersionOverride <version>` only updates disposable
stage metadata. It supports packaging a clean committed-source snapshot while
preserving unrelated worktree map/resource or version edits.
