# Module API verification

Environment: Windows, portable Lua/luac 5.1.5, LuaCheck 1.2.0, muddler 1.1.0, and Android OpenJDK 21. Validation was run on `feature/module-api-v1` after merging upstream `v3.3.0`. No game connection, profile automation, installed Mudlet package, or public server was used.

## Commands and results

Repository-wide Lua syntax (PowerShell supplied every `*.lua` path outside `build/` to luac):

```text
tools/lua51/luac51.exe -p <each Lua file>
LUAC checked=233 failed=0
```

JSON/package metadata parsing:

```text
Get-Content -Raw <each JSON file and mfile> | ConvertFrom-Json
JSON checked=31 failed=0
```

Offline API suite:

```text
tools/lua51/lua51.exe tests/api/run.lua src/scripts/api/v1.lua
RESULT 20 passed, 0 failed
API_TEST_EXIT=0
```

Native 3.3 adapter contract suite:

```text
tools/lua51/lua51.exe tests/api/native_adapter_run.lua src/scripts/api/v1.lua src/scripts/api/adapter.lua
RESULT 4 passed, 0 failed
ADAPTER_TEST_EXIT=0
```

Lint:

```text
luacheck.cmd src/scripts/api tests/api examples/module_api_v1
Total: 122 warnings / 0 errors in 6 files
LUACHECK_EXIT=1
```

The lint warnings are non-blocking style findings, predominantly long lines and unused callback arguments already present in the candidate API/test files. No undefined-variable or syntax errors were reported. The new native-adapter contract test is warning-free.

Native package build:

```text
java.exe -jar muddle-1.1.0-all.jar
MUDDLER: [INFO]: Version     : 3.3.0
MUDDLER: [INFO]: Found src\scripts\api\scripts.json
MUDDLER: [INFO]: Using script from src\scripts\api\v1.lua for script 'v1'
MUDDLER: [INFO]: Using script from src\scripts\api\adapter.lua for script 'adapter'
MUDDLER: [INFO]: XML created successfully, writing it to disk
MUDDLER: [INFO]: Build completed successfully!
MUDDLER_EXIT=0
```

The generated `build/f2ce-tools.mpackage` was opened as a ZIP and checked for `config.lua`, package XML, `1.0.0-candidate.3`, and the 3.3 adapter compatibility marker; every assertion passed. The local muddler-only artifact deliberately has no `MUXLET_URL` injection. GitHub's release workflow performs that injection before its build, so this local structural-validation artifact is not an installable release and is not committed.

## Covered behavior

The suites cover version/capability mismatch, duplicate module IDs, reload idempotence, scoped cleanup, 3.3 navigation start statuses, pending multi-leg navigation with an intermediate completion, native-owner contention and compare-and-release cleanup, interruption policy, both cancel modes, zero-command behavior after disable or native contention, built-in provider contention recheck, provider fallback/timeout/late-callback isolation, callback containment, nil/partial GMCP, reconnect reset, unload during active navigation, hauling mode validation, native hauling rejection, and service-lease release.
