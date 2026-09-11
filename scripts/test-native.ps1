param(
    [Parameter(Mandatory = $true)][string]$LuaExe,
    [Parameter(Mandatory = $true)][string]$LuacExe,
    [string]$PackagePath
)
$ErrorActionPreference = 'Stop'
$repoPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$manifest = Get-Content -LiteralPath (Join-Path $repoPath 'mfile') -Raw | ConvertFrom-Json
Push-Location $repoPath
try {
    $luaFiles = Get-ChildItem -LiteralPath @('src', 'tests', 'examples') -Recurse -File -Filter '*.lua'
    foreach ($file in $luaFiles) {
        & $LuacExe -p $file.FullName
        if ($LASTEXITCODE -ne 0) { throw "Lua syntax failed: $($file.FullName)" }
    }
    Write-Output "SYNTAX=$($luaFiles.Count) passed"
    $jsonFiles = @(Get-ChildItem -LiteralPath @('src', 'tests', 'examples') -Recurse -File -Filter '*.json') + @(Get-Item mfile)
    foreach ($file in $jsonFiles) { Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json | Out-Null }
    Write-Output "METADATA=$($jsonFiles.Count) passed"

    function Invoke-Suites([string]$SourceRoot) {
        $commands = @(
            @('tests/api/run.lua', "$SourceRoot/src/scripts/api/v1.lua"),
            @('tests/api/native_adapter_run.lua', "$SourceRoot/src/scripts/api/v1.lua", "$SourceRoot/src/scripts/api/adapter.lua"),
            @('tests/exchange_walker/run.lua', $SourceRoot),
            @('tests/map/startup_topology_sync_run.lua', "$SourceRoot/src/scripts/map/events.lua"),
            @('tests/map/topology_capture_safety_run.lua', "$SourceRoot/src/scripts/map/topology_capture.lua"),
            @('tests/map/content_lifecycle_run.lua', "$SourceRoot/src/scripts/ui/content/map.lua"),
            @('tests/map/galaxy_capture_lifecycle_run.lua', $SourceRoot),
            @('tests/map/explore_orbit_direction_run.lua',
                "$SourceRoot/src/scripts/map/explore_frontier.lua",
                "$SourceRoot/src/scripts/map/explore_system_helpers.lua",
                "$SourceRoot/src/scripts/map/explore.lua"),
            @('tests/map/navigation_resilience_run.lua',
                "$SourceRoot/src/scripts/map/speedwalk.lua",
                "$SourceRoot/src/scripts/map/whereis_capture.lua",
                "$SourceRoot/src/scripts/map/navigate.lua",
                "$SourceRoot/src/scripts/map/exit.lua",
                "$SourceRoot/src/scripts/map/room_query.lua",
                "$SourceRoot/src/scripts/map/import_export.lua")
        )
        foreach ($command in $commands) {
            & $LuaExe @command
            if ($LASTEXITCODE -ne 0) { throw "Suite failed: $($command[0])" }
        }
    }
    Invoke-Suites '.'

    if ($PackagePath) {
        # Reconstruct Lua sources from the actual compiled XML, not the stage
        # directory, then run the same regression suite against those bytes.
        $verifyPath = Join-Path $repoPath ('build\package-verify-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $verifyPath | Out-Null
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::OpenRead([IO.Path]::GetFullPath($PackagePath))
        try {
            $reader = [IO.StreamReader]::new($archive.GetEntry('f2ce-tools.xml').Open())
            try { $document = [xml]$reader.ReadToEnd() } finally { $reader.Dispose() }
            $matched = 0
            foreach ($kind in @('Script', 'Trigger')) {
                $directory = if ($kind -eq 'Script') { 'scripts' } else { 'triggers' }
                foreach ($node in $document.SelectNodes("//$kind")) {
                    $body = $node.SelectSingleNode('script')
                    if (-not $body) { continue }
                    $parts = [Collections.Generic.List[string]]::new()
                    $parts.Add($node.SelectSingleNode('name').InnerText)
                    $parent = $node.ParentNode
                    while ($parent.LocalName -eq $kind -or $parent.LocalName -eq ($kind + 'Group')) {
                        $parts.Insert(0, $parent.SelectSingleNode('name').InnerText)
                        $parent = $parent.ParentNode
                    }
                    $relative = 'src/' + $directory + '/' + ($parts -join '/') + '.lua'
                    if ($relative -match '(^|/)\.\.?(/|$)|:|\\') { throw "Unsafe generated script path $relative" }
                    $original = Join-Path $repoPath $relative
                    if (-not (Test-Path -LiteralPath $original -PathType Leaf)) { throw "Unexpected compiled script $relative" }
                    $text = $body.InnerText.Replace("`r`n", "`n").TrimEnd()
                    $source = [IO.File]::ReadAllText($original).Replace("`r`n", "`n").TrimEnd()
                    $source = $source.Replace('@PKGNAME@', $manifest.package).Replace('__PKGNAME__', $manifest.package)
                    $source = $source.Replace('@VERSION@', $manifest.version).Replace('__VERSION__', $manifest.version)
                    if ($relative -eq 'src/scripts/init.lua') {
                        $url = 'https://github.com/' + $manifest.dependency.repo + '/releases/download/' + $manifest.dependency.version + '/Muxlet.mpackage'
                        $source = $source.Replace('local F2T_REQUIRED_MUXLET = nil', 'local F2T_REQUIRED_MUXLET = "' + $manifest.dependency.version + '"')
                        $source = $source.Replace('local MUXLET_URL = nil', 'local MUXLET_URL = "' + $url + '"')
                    }
                    if ($source -ne $text) {
                        throw "Packaged code differs from tested source: $relative"
                    }
                    $destination = Join-Path $verifyPath $relative
                    New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($destination)) -Force | Out-Null
                    [IO.File]::WriteAllText($destination, $text, [Text.UTF8Encoding]::new($false))
                    $matched++
                }
            }
            Write-Output "PACKAGED_SCRIPTS=$matched matched (init has the intended dependency injection)"
            foreach ($required in @('EXCHANGE-WALKER-LICENSE.txt', 'F2CE-LICENSE.txt', 'full.lua')) {
                if (-not $archive.GetEntry($required)) { throw "Package is missing $required" }
            }
        } finally { $archive.Dispose() }
        Invoke-Suites $verifyPath
        Write-Output "PACKAGE_VERIFIED=$PackagePath"
    }
} finally { Pop-Location }
