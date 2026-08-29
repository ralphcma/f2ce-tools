# `F2CE.API.v1` reference

All data returned across the API boundary is copied. Errors are tables with `code`, `message`, optional copied `details`, and a useful `tostring(error)` value. Functions return `nil, error` when they fail closed.

## Metadata and dependency validation

- `API.version`: semantic API version (`1.0.0`).
- `API.f2ce_version`: installed F2CE package version.
- `API.info()`: copied API/F2CE/adapter/capability record.
- `API.hasCapability(name)`, `API.getCapabilities()`, `API.requireCapabilities(names)`.
- `API.validateDependency({api=">=1.0.0", f2ce=">=3.2.5", capabilities={...}})`.
- `API.versions.compare(a,b)` and `API.versions.satisfies(actual, requirement)`; operators are `=`, `>`, `>=`, `<`, `<=`, and `~` (same major/minor, at least the requested patch).

Capabilities include `modules`, `events`, `navigation`, `commands`, `gmcp.snapshots`, `prices.providers`, `hauling`, `hauling.exchange_override`, `map.queries`, and the available `resources.*` entries.

## Modules and scoped context

- `API.modules.register(spec)` where `spec.id` is a lowercase dotted ID and `spec` may define `version`, `requires`, `initialize(context)`, `enable(context)`, `disable(context,reason)`, and `unload(context,reason)`.
- `initialize(id)`, `enable(id)`, `disable(id,reason)`, `unload(id,reason)`, `unregister(id,reason)`, `reload(spec)`, and `status(id)`.
- `context:on(api_event, callback)`, `onMudlet(event,callback)`, `timer(delay,callback,repeating)`, `alias(regex,callback)`, `trigger(regex,callback)`, `http(request,callback)`, `widget(spec)`, and `own(kind,resource,cleanup)`.

Callbacks registered through a context are gated on the current enabled generation. Cleanup is reverse-order and idempotent.

## Navigation

`lease, err = API.navigation.acquire(context, metadata)` atomically acquires the sole navigation lease. `lease:request(destination, options)` returns a handle. Options: `suppress_hint`, `on_complete(result)`, `on_failure(result)`, and `on_interrupt(result)`. Returning `{auto_resume=true}` from the interruption callback requests F2CE's supported customs recovery behavior.

Handle functions: `status()`, `pause()`, `resume()`, `cancel(reason)` (graceful, finalized on the next service tick), and `cancelImmediate(reason)`. `lease:release(reason)` is allowed only when no request is active. `API.navigation.status()` returns `{state="idle"}` or a copied request record.

Events: `navigation.lease_acquired`, `.lease_released`, `.started`, `.paused`, `.resumed`, `.cancelling`, `.interrupted`, `.completed`, and `.failed`. Request fields include `request_id`, `lease_id`, `module_id`, `destination`, `state`, timestamps, `reason`, `interruption_reason`, `detail`, and copied progress.

## Commands

`lease = API.commands.acquire(context, metadata)` obtains the sole command lease. `lease:send(command,{reason="...", echo=false, ...})` transmits only while the owning module remains enabled. `lease:release(reason)` revokes it. Navigation and arbitrary command leases are mutually exclusive. `API.commands.audit()` returns copied bounded history.

`command.acknowledged` fields: `id`, `module_id`, `lease_id`, `command`, copied `metadata`, `timestamp`, `status`, and optional `reason`.

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

`API.hauling.start(context,{mode="auto"|"exchange"})` delegates to F2CE's rank-aware state machine. `auto` passes no override; `exchange` is the supported Founder+ exchange override. No hauling algorithm is duplicated. The returned handle exposes `status`, `pause`, `resume`, `cancel` (graceful), and `cancelImmediate`. Top-level equivalents and `API.hauling.status()` are also available.

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

