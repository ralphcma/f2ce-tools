# F2CE module API v1 architecture

Status: upstream-adoption candidate on `feature/module-api-v1`. The API version is `1.0.0`; the implementation build is `1.0.0-candidate.2`.

The public boundary is one namespace, `F2CE.API.v1`. Existing `f2t_*` functions and `F2T_*` state remain unchanged for backwards compatibility, but new modules should never read, replace, or retain them. `src/scripts/api/adapter.lua` is the only compatibility boundary that reads those implementation globals.

## Boundary with Muxlet

Muxlet remains the supported owner of visual content, panes, tabs, and saved workspace layouts. Third-party packages should register those elements directly with `Mux.registerContent`; `F2CE.API.v1` deliberately provides no widget or workspace wrapper.

The API is limited to F2CE gameplay services that Muxlet does not provide: navigation ownership, command coordination, copied game state, price-provider extension, hauling control, and map queries. Its event stream reports only those service changes. Packages continue using Mudlet for their own aliases, triggers, timers, HTTP, and general client events, and may attach any such resource to `context:own(...)` when they want F2CE lifecycle cleanup.

The service design has five layers:

1. A small module registry gives service leases and providers a stable owner. Scoped contexts own F2CE API subscriptions and explicit cleanup tokens only. Lifecycle transitions are register → initialize → enable → disable/unload → unregister. Disable, unload, reconnect, and API reload revoke active work before callbacks can transmit commands.
2. Navigation serializes F2CE speedwalking behind an atomic lease and returns an opaque request handle. Completion, failure, pause, resume, graceful/immediate cancellation, and interruption reasons are normalized without exposing `F2T_SPEEDWALK_*` or `F2T_MAP_EXPLORE_STATE`.
3. The command broker allows one enabled module to hold a command lease. Every send requires a non-empty audit reason. Arbitrary command leases and navigation leases are mutually exclusive. Long-running hauling and serialized price requests acquire service command leases internally.
4. Data and map services deep-copy results. GMCP channels are normalized to stable names; callers can mutate their copy without changing F2CE or Mudlet state. Mapper queries return copied arrays/records, never live mapper tables.
5. Price providers are registered by scoped token, ordered by priority, filtered by scope, serialized, timed out, cancelled on teardown, and followed by the built-in F2CE provider. No function monkey-patching is performed, so unloading restores behavior simply by unregistering the provider.

## Fail-closed rules

- Dependency validation rejects incompatible API/F2CE versions and missing capabilities before module registration.
- Duplicate module and provider IDs fail.
- Disabled or stale contexts cannot acquire leases or execute guarded callbacks.
- A command without a current lease and audit reason is denied and recorded without transmission.
- Navigation, hauling, provider work, and leases are revoked on module disable/unload and reconnect reset.
- Callback exceptions are contained and emitted as `api.callback_error`; they do not abort other subscribers.
- Missing or partial GMCP yields `nil`/`available=false`, not fabricated data.

## Source classification

- Official-adoption code: `src/scripts/api/v1.lua`, `src/scripts/api/adapter.lua`, `src/scripts/api/scripts.json`, docs, tests, and example in this branch.
- Temporary standalone overlay: not used. An editable, MIT-licensed upstream repository was found and forked, so the generated installed 3.2.5 XML was never edited. The native adapter deliberately remains compatible with 3.2.5 for local offline validation.

## Upstream integration notes

For the first official release, retain the adapter boundary so behavior is reviewable. A later internal refactor can replace its polling/snapshot reads with direct calls from map, hauling, and commodity state transitions while leaving `F2CE.API.v1` unchanged. The API folder must load as a package script group; the adapter uses a zero-delay installation so all native F2CE functions exist regardless of muddler folder ordering.

No new license was selected. The fork retains the upstream MIT license (`Copyright (c) 2025 ping65510`). Source-owner review is required for API naming, service-event naming, the v1 stability commitment, the first release number, and which internal transition points should replace the compatibility polling hooks.
