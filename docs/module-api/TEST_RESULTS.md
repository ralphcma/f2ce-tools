# Module API verification

Environment: Windows, portable Lua 5.1.5/luac 5.1.5 from the `dyne/luabinaries` GitHub release `54f813a`, and muddler 1.1.0 with the local Android OpenJDK 21 runtime. No game connection, profile automation, or public server was used.

## Commands and results

Lua syntax, run from the fork root (PowerShell loop supplies every `*.lua` path to the compiler):

```text
work/tools/lua51/luac51.exe -p <each Lua file>
LUAC checked=221 failed=0
```

Offline suite:

```text
work/tools/lua51/lua51.exe tests/api/run.lua src/scripts/api/v1.lua
PASS callback_errors_are_contained
PASS command_denial_and_zero_transmission
PASS duplicate_module_ids
PASS hauling_modes_and_release
PASS navigation_contention_and_callbacks
PASS navigation_graceful_and_immediate_cancel
PASS nil_and_partial_gmcp_are_copied
PASS provider_registration_and_fallback
PASS provider_timeout_ignores_late_callback
PASS reconnect_reset
PASS reload_idempotence
PASS scoped_cleanup
PASS unload_during_active_work
PASS version_and_capability_failure
RESULT 14 passed, 0 failed
```

Native package build/validation:

```text
java.exe -jar muddle-1.1.0-all.jar
MUDDLER: [INFO]: Found src\scripts\api\scripts.json
MUDDLER: [INFO]: Using script from src\scripts\api\v1.lua for script 'v1'
MUDDLER: [INFO]: Using script from src\scripts\api\adapter.lua for script 'adapter'
MUDDLER: [INFO]: XML created successfully
MUDDLER: [INFO]: Build completed successfully!
MUDDLER_EXIT=0
```

The suite covers version/capability failure, duplicate module IDs, reload idempotence, scoped cleanup, navigation contention and both cancel modes, command denial without a valid lease, provider fallback/timeout/late-callback isolation, callback containment, nil/partial GMCP, reconnect reset, unload during active navigation, hauling mode validation, and zero additional command transmission after disable/lease revocation.
