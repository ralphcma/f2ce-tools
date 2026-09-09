# `F2CE.API.v1` reference

All data returned across the API boundary is copied. Errors are tables with `code`, `message`, optional copied `details`, and a useful `tostring(error)` value. Functions return `nil, error` when they fail closed.

## Metadata and dependency validation

- `API.version`: semantic API version (`1.1.0`; candidate build).
- `API.f2ce_version`: installed F2CE package version.
- `API.info()`: copied API/F2CE/adapter/capability/integration record.
- `API.hasCapability(name)`, `API.getCapabilities()`, `API.requireCapabilities(names)`.
- `API.validateDependency({api=">=1.0.0", f2ce=">=3.3.0", capabilities={...}})`.
- `API.versions.compare(a,b)` and `API.versions.satisfies(actual, requirement)`; operators are `=`, `>`, `>=`, `<`, `<=`, and `~` (same major/minor, at least the requested patch).

Capabilities include `modules`, `events`, `navigation`, `navigation.status.v33`, `commands`, `commands.native_contention`, `gmcp.snapshots`, `prices.providers`, `hauling`, `hauling.exchange_override`, `map.queries`, and `muxlet.content` when `Mux.registerContent` is available. The two dotted 3.3 capabilities let modules distinguish the explicit navigation-status and native-contention contracts from the legacy fallback.

`API.integration` identifies this API's scope as F2CE gameplay services and identifies Muxlet as the UI/content provider. Visual integrations should call `Mux.registerContent` directly; this API does not wrap Muxlet.

## Modules and scoped context

- `API.modules.register(spec)` where `spec.id` is a lowercase dotted ID and `spec` may define `version`, `requires`, `initialize(context)`, `enable(context)`, `disable(context,reason)`, and `unload(context,reason)`.
- `initialize(id)`, `enable(id)`, `disable(id,reason)`, `unload(id,reason)`, `unregister(id,reason)`, `reload(spec)`, and `status(id)`.
- `context:on(api_event,callback)` subscribes to F2CE API service events.
- `context:own(kind,resource,cleanup)` attaches an explicit cleanup token for a resource created through Mudlet, Muxlet, or another library.

Callbacks registered through a context are gated on the current enabled generation. Cleanup is reverse-order and idempotent.

The context does not create aliases, triggers, timers, HTTP requests, widgets, or general Mudlet event handlers. Those remain with their native owner. For example, a package can create an alias with `tempAlias` and attach its ID using `context:own("mudlet_alias", id, killAlias)`.

## Navigation

`lease, err = API.navigation.acquire(context, metadata)` acquires the sole API lease only if no native navigation owner or known native automation is active. `lease:request(destination, options)` returns a handle. Options: `suppress_hint`, `interactive`, `compensate_incomplete_map`, `on_complete(result)`, `on_failure(result)`, and `on_interrupt(result)`. The first three map directly to F2CE-Tools 3.3.0 navigation options. Returning `{auto_resume=true}` from the interruption callback requests F2CE's supported customs recovery behavior.

Request state is normalized from the 3.3.0 native start status: `walking` becomes `running`, `pending` remains `pending`, `arrived` completes immediately, and `failed` is rejected. A pending self-healing route is not completed by an intermediate speedwalk's `LAST_RESULT`; it remains pending until native resolution advances it or the requested destination resolves to the current room. Releasing a lease clears the native owner only when the API's owner token still matches.

Handle functions: `status()`, `pause()`, `resume()`, `cancel(reason)` (graceful, finalized on the next service tick), and `cancelImmediate(reason)`. `lease:release(reason)` is allowed only when no request is active. `API.navigation.status()` returns `{state="idle"}` or a copied request record.

Events: `navigation.lease_acquired`, `.lease_released`, `.started`, `.paused`, `.resumed`, `.cancelling`, `.interrupted`, `.completed`, and `.failed`. Request fields include `request_id`, `lease_id`, `module_id`, `destination`, `state`, timestamps, `reason`, `interruption_reason`, `detail`, and copied progress.

## Commands

`lease = API.commands.acquire(context, metadata)` obtains the sole command lease. `lease:send(command,{reason="...", echo=false, ...})` transmits only while the owning module remains enabled. `lease:release(reason)` revokes it. Navigation and arbitrary command leases are mutually exclusive. Acquisition fails while known native speedwalk, exploration, circuit, hauling, death-recovery, bulk-trade, or command/response capture state is active; every API send rechecks that state and fails closed with zero transmission if it changed. `API.commands.audit()` returns copied bounded history.

`command.sent` / `command.failed` fields: `id`, `module_id`, `lease_id`, `command`, copied `metadata`, `timestamp`, `status`, and optional `reason`. These report transport only, not game acceptance. `command.acknowledged` remains a deprecated transport alias for backward compatibility.

## Exchange capture and stock settings (1.1)

Capabilities: `exchange.capture`, `exchange.settings`.
`session = API.exchange.acquire(context,{reason="explicit reviewed operation"})`
holds the existing command lease across related operations. A disabled module,
foreign API lease, or known native automation prevents acquisition.

- `session:capture(kind,planet,callback,{timeout=15})`: kind is `exchange` or
  `production`; planet may be nil for local capture. Callback `(rows,error)`
  receives copied native PO results. Remote response headers must identify the
  requested planet. Exchange results include `_expected_count` from the summary.
  The consumer must validate completeness before acting on the data.
- `session:set({kind,commodity,value,planet})`: typed setting command. Accepted
  ranges are integer min 0–10000, max 0–20000, spread 6–40. Local operations
  require current owner/player GMCP equality; remote ownership is enforced by
  the server. A sent result is not a server acknowledgement.
- `session:status()`, `session:release(reason)`: release cancels only the capture
  callback owned by that session. The client must release after a capture pair
  or confirmed apply sequence. Disable/unload/reconnect also clean the session.

`exchange.captured` / `exchange.capture_failed` carry copied `kind`, `planet`,
`module_id`, `rows`, and optional `error`. Invalid kinds, names, numbers,
contention, missing capabilities, disabled contexts and timeouts fail closed.

The native [Exchange Walker integration](NATIVE_EXCHANGE_WALKER.md) demonstrates
complete capture validation and one-at-a-time acknowledged setting changes.
Reconnect now disables every enabled module; consumers must explicitly enable
again, rather than obtaining new leases with old connection authority.

## Copied GMCP data

`API.data.get(channel)`, `refresh(channel)`, and `channels()`. Channels and events:

| Channel | Normalized event | Established source |
|---|---|---|
| `room` | `data.room` | `gmcp.room.info` |
| `vitals` | `data.vitals` | `gmcp.char.vitals` |
| `ship` | `data.ship` | `gmcp.char.ship` |
| `cargo` | `data.cargo` | `gmcp.char.ship.cargo` |
| `jobs_board` | `data.jobs_board` | `gmcp.jobs.board` |
| `job` | `data.job` | `gmcp.char.job` |
| `commodities` | `data.commodities` | `gmcp.exchange.commodities` |
| `futures_market` | `data.futures_market` | `gmcp.exchange.futures` |
| `futures_owned` | `data.futures_owned` | `gmcp.char.futures` |

Each event is `{channel, available, value, timestamp}`. `value` is a deep copy and may be `nil` for absent/partial GMCP.

## Price providers

`API.prices.registerProvider(context,{id,priority,scopes,capabilities,request})` returns a scoped registration token. `request(provider_request,done)` returns `false` to decline or calls `done(result)` / `done(nil,error)`. `provider_request:send(command,metadata)` uses the serialized service command lease and audit trail. It also exposes copied `options`, `commodity`, `id`, and `isCancelled()`.

`API.prices.request(context,commodity,{scope,timeout,...},callback)` returns a cancel/status handle. Providers run by descending priority, then the built-in `f2t_price_check_commodity` provider. Events: `provider.registered`, `.queued`, `.started`, `.timed_out`, `.completed`, `.failed`.

## Hauling

`API.hauling.start(context,{mode="auto"|"exchange"})` delegates to F2CE's rank-aware state machine. `auto` passes no override; `exchange` is the supported Founder+ exchange override. No hauling algorithm is duplicated. The API verifies that native state actually became active; cargo, rank, or other synchronous native rejection releases the service command lease and returns `E_HAUL_START`. The returned handle exposes `status`, `pause`, `resume`, `cancel` (graceful), and `cancelImmediate`. Top-level equivalents and `API.hauling.status()` are also available.

Events: `hauling.started`, `hauling.state`, and `hauling.stopped`. Status copies the established F2CE state fields, including `active`, `paused`, `mode`, `current_phase`, `stopping`, and counters when present.

## Map queries

- `API.map.roomHasFlag(room_id,flag)`.
- `findRoomsWithFlag(area_id_or_name,flag)`.
- `findExchange(area_id_or_name)` returns copied `{room_id,name,area_id}` records.
- `resolve(location)` returns `{room_id,error,hint}`.
- `areas()` and `systems()` return copied sorted records.
- `reachability(from_room,to_room)` returns `{reachable,from_room,to_room,directions,rooms}` copies.

## Reconnect and schema discovery

`reconnect.reset` is emitted after leases/active work are revoked and caches cleared. `API.schemas` documents required fields for `module.state`, `navigation.*`, `hauling.*`, `provider.*`, `command.acknowledged`, `data.*`, and `reconnect.reset`.
