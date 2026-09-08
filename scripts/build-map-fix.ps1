param(
  [Parameter(Mandatory=$true)][string]$InstalledPackage,
  [Parameter(Mandatory=$true)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$mapSource = Get-Content -LiteralPath (Join-Path $repo 'src\scripts\ui\content\map.lua') -Raw
$xml = [xml](Get-Content -LiteralPath (Join-Path $InstalledPackage 'f2ce-tools.xml') -Raw)
function Normalize-LuaText([string]$value) { return $value.Replace("`r`n", "`n").Replace("`r", "`n") }
$originalSources = @($xml.SelectNodes('//Script') | ForEach-Object { Normalize-LuaText $_.SelectSingleNode('script').InnerText })
$mapNodes = @($xml.SelectNodes('//Script') | Where-Object {
  [string]$_.script -match 'function f2tRegisterMapContent\('
})
if ($mapNodes.Count -ne 1) { throw 'Expected exactly one installed F2CE Map content script.' }
$oldMapSource = [string]$mapNodes[0].script
if ($oldMapSource -notmatch 'local function releaseLive\(' -or $oldMapSource -notmatch 'local function mapperAcquire\(') {
  throw 'Unrecognized installed Map lifecycle; refusing a blind package patch.'
}
$stage = Join-Path $env:TEMP ('f2ce-map-fix-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage | Out-Null
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$members = @('config.lua','commodities.json','full.lua','galaxy_brief.json',
             'starter_map.json','starter_map_with_exchanges.json')
foreach ($member in $members) {
  Copy-Item -LiteralPath (Join-Path $InstalledPackage $member) -Destination (Join-Path $stage $member)
}
# Preserve the user's installed F2CE build. Replace only Map's Lua source and
# package version metadata; do not mix in this checkout's other feature work.
$mapNodes[0].SelectSingleNode('script').InnerText = $mapSource
$xml.Save((Join-Path $stage 'f2ce-tools.xml'))
$configPath = Join-Path $stage 'config.lua'
$config = Get-Content -LiteralPath $configPath -Raw
if ($config -notmatch 'version\s*=\s*\[\[3\.3\.') { throw 'This local build requires F2CE 3.3.' }
$config = $config -replace '(?m)^version\s*=.*$', 'version = [[3.3.0-mapfix1]]'
[IO.File]::WriteAllText($configPath, $config, (New-Object Text.UTF8Encoding($false)))
$verify = [xml](Get-Content -LiteralPath (Join-Path $stage 'f2ce-tools.xml') -Raw)
$verifiedMap = @($verify.SelectNodes('//Script') | Where-Object { [string]$_.script -match 'function f2tRegisterMapContent\(' })
if ($verifiedMap.Count -ne 1 -or (Normalize-LuaText $verifiedMap[0].SelectSingleNode('script').InnerText) -ne (Normalize-LuaText $mapSource)) { throw 'Map patch verification failed.' }
$originalScripts = @($xml.SelectNodes('//Script'))
$verifiedScripts = @($verify.SelectNodes('//Script'))
if ($originalScripts.Count -ne $verifiedScripts.Count) { throw 'Script count changed.' }
for ($i=0; $i -lt $originalScripts.Count; $i++) {
  $verifiedSource = Normalize-LuaText $verifiedScripts[$i].SelectSingleNode('script').InnerText
  if ($verifiedSource -match 'function f2tRegisterMapContent\(') { continue }
  if ($originalSources[$i] -ne $verifiedSource) { throw 'Unrelated script changed during serialization.' }
}
$output = Join-Path $OutputDirectory 'f2ce-tools-3.3.0-mapfix1.mpackage'
if (Test-Path -LiteralPath $output) { throw 'Output already exists; use a new output directory.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $output)
$resolvedStage = (Resolve-Path -LiteralPath $stage).Path
$expectedPrefix = (Resolve-Path -LiteralPath $env:TEMP).Path.TrimEnd('\') + '\f2ce-map-fix-'
if (-not $resolvedStage.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected build stage path.' }
Remove-Item -LiteralPath $resolvedStage -Recurse -Force
Get-Item -LiteralPath $output | Select-Object FullName,Length
Get-FileHash -LiteralPath $output -Algorithm SHA256
