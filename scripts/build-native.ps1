param(
    [Parameter(Mandatory = $true)][string]$MuddlerJar,
    [string]$JavaCommand = 'java',
    [string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
$repoPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$manifestPath = Join-Path $repoPath 'mfile'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repoPath 'build' }
$outputPath = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
$stagePath = Join-Path $repoPath ('build\native-stage-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stagePath -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repoPath 'src') -Destination (Join-Path $stagePath 'src') -Recurse
Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $stagePath 'mfile')

# Match the release workflow's dependency injection in the disposable build
# stage. Never edit the checkout or a live profile to produce an artifact.
$initPath = Join-Path $stagePath 'src\scripts\init.lua'
$initText = [IO.File]::ReadAllText($initPath)
$tag = $manifest.dependency.version
$url = 'https://github.com/' + $manifest.dependency.repo + '/releases/download/' + $tag + '/Muxlet.mpackage'
if (-not $initText.Contains('local F2T_REQUIRED_MUXLET = nil') -or -not $initText.Contains('local MUXLET_URL = nil')) {
    throw 'Dependency injection placeholders changed; build stopped.'
}
$initText = $initText.Replace('local F2T_REQUIRED_MUXLET = nil', 'local F2T_REQUIRED_MUXLET = "' + $tag + '"')
$initText = $initText.Replace('local MUXLET_URL = nil', 'local MUXLET_URL = "' + $url + '"')
[IO.File]::WriteAllText($initPath, $initText, [Text.UTF8Encoding]::new($false))
Push-Location $stagePath
try {
    & $JavaCommand -jar $MuddlerJar
    if ($LASTEXITCODE -ne 0) { throw "Muddler failed ($LASTEXITCODE)" }
} finally { Pop-Location }
$packagePath = Join-Path $stagePath 'build\f2ce-tools.mpackage'
if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) { throw 'Muddler did not produce the package' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($packagePath)
try {
    foreach ($required in @('config.lua', 'f2ce-tools.xml', 'EXCHANGE-WALKER-LICENSE.txt', 'F2CE-LICENSE.txt')) {
        if (-not $archive.GetEntry($required)) { throw "Package missing $required" }
    }
    foreach ($entry in $archive.Entries) {
        if ($entry.FullName -match '\\|(^|/)\.\.?(/|$)|^[A-Za-z]:|^/') { throw "Unsafe ZIP entry: $($entry.FullName)" }
    }
    $reader = [IO.StreamReader]::new($archive.GetEntry('f2ce-tools.xml').Open())
    try { $xmlText = $reader.ReadToEnd() } finally { $reader.Dispose() }
    foreach ($marker in @('1.2.0-candidate.4', '3.4.0-native.12', $url, 'exchange_walker_live', 'f2t_factory_parse_display')) {
        if (-not $xmlText.Contains($marker)) { throw "Package missing integration marker $marker" }
    }
    if ($xmlText.Contains('fed2-module-api/src/fed2_module_api.lua')) { throw 'Unexpected separate API loader in native package' }
    [xml]$xmlText | Out-Null
} finally { $archive.Dispose() }
$destination = Join-Path $outputPath ('f2ce-tools-' + $manifest.version + '.mpackage')
Copy-Item -LiteralPath $packagePath -Destination $destination -Force
Get-FileHash -LiteralPath $destination -Algorithm SHA256
Write-Output "PACKAGE=$destination"
Write-Output "STAGE=$stagePath"
