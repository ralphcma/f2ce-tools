param(
    [Parameter(Mandatory = $true)][string]$InputPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][string[]]$Systems,
    [string]$ReportPath,
    [ValidateSet(2, 4)][int]$IndentWidth = 2
)

$ErrorActionPreference = 'Stop'

$inputFullPath = [IO.Path]::GetFullPath($InputPath)
$outputFullPath = [IO.Path]::GetFullPath($OutputPath)
if (-not (Test-Path -LiteralPath $inputFullPath -PathType Leaf)) {
    throw "Map export not found: $inputFullPath"
}
if ($inputFullPath -eq $outputFullPath) {
    throw 'InputPath and OutputPath must differ so the source export is preserved until validation succeeds.'
}

$targets = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($system in $Systems) {
    $name = ([string]$system).Trim()
    if ($name) { [void]$targets.Add($name) }
}
if ($targets.Count -eq 0) { throw 'At least one non-empty system name is required.' }

$document = Get-Content -LiteralPath $inputFullPath -Raw | ConvertFrom-Json
$allAreas = @($document.areas)

function Get-AreaSystem($area) {
    $areaSystem = [string]$area.userData.fed2_system
    if ($areaSystem) { return $areaSystem }

    $roomSystems = @(
        @($area.rooms) |
            ForEach-Object { [string]$_.userData.fed2_system } |
            Where-Object { $_ } |
            Sort-Object -Unique
    )
    if ($roomSystems.Count -eq 1) { return $roomSystems[0] }

    foreach ($target in $targets) {
        if ([string]$area.name -ieq "$target Space") { return $target }
    }
    return $null
}

$removedAreas = [Collections.Generic.List[object]]::new()
$keptAreas = [Collections.Generic.List[object]]::new()
$removedRoomIds = [Collections.Generic.HashSet[int]]::new()
$removedRoomHashes = [Collections.Generic.List[string]]::new()

foreach ($area in $allAreas) {
    $system = Get-AreaSystem $area
    if ($system -and $targets.Contains($system)) {
        $rooms = @($area.rooms)
        $removedAreas.Add([pscustomobject]@{
            id = [int]$area.id
            name = [string]$area.name
            system = $system
            roomCount = $rooms.Count
        })
        foreach ($room in $rooms) {
            [void]$removedRoomIds.Add([int]$room.id)
            if ($room.hash) { $removedRoomHashes.Add([string]$room.hash) }
        }
    } else {
        $keptAreas.Add($area)
    }
}

foreach ($target in $targets) {
    if (-not ($removedAreas | Where-Object { $_.system -ieq $target })) {
        throw "No map areas were found for system '$target'; refusing to produce a misleading cleanup."
    }
}

$removedCrossExits = 0
foreach ($area in $keptAreas) {
    foreach ($room in @($area.rooms)) {
        $oldExits = @($room.exits)
        $newExits = @($oldExits | Where-Object {
            -not $removedRoomIds.Contains([int]$_.exitId)
        })
        $removedCrossExits += $oldExits.Count - $newExits.Count
        $room.exits = $newExits
    }
    $area.roomCount = @($area.rooms).Count
}

$removedTopologySystems = [Collections.Generic.List[string]]::new()
if ($document.userData -and $document.userData.f2t_topology) {
    $topology = ([string]$document.userData.f2t_topology) | ConvertFrom-Json

    if ($topology.systems) {
        foreach ($property in @($topology.systems.PSObject.Properties)) {
            if ($targets.Contains($property.Name)) {
                $removedTopologySystems.Add($property.Name)
                $topology.systems.PSObject.Properties.Remove($property.Name)
            }
        }
    }

    foreach ($listName in @('exiled', 'refused')) {
        if ($null -ne $topology.$listName) {
            $topology.$listName = @($topology.$listName | Where-Object {
                -not $targets.Contains([string]$_)
            })
        }
    }
    if ($topology.closed) {
        foreach ($property in @($topology.closed.PSObject.Properties)) {
            if ($targets.Contains($property.Name)) {
                $topology.closed.PSObject.Properties.Remove($property.Name)
            }
        }
    }

    # Do not remove a same-named cartel. For example, Stellar is both a system
    # and a cartel; the cartel remains valid after the two map systems are reset.
    $document.userData.f2t_topology = $topology | ConvertTo-Json -Depth 100 -Compress
}

$document.areas = @($keptAreas)
$document.areaCount = @($keptAreas).Count
$document.roomCount = @($keptAreas | ForEach-Object { @($_.rooms) }).Count

$json = $document | ConvertTo-Json -Depth 100
if ($IndentWidth -eq 4) {
    $json = [regex]::Replace($json, '(?m)^( +)', {
        param($match)
        return ' ' * ($match.Groups[1].Value.Length * 2)
    })
}
$outputDirectory = Split-Path -Parent $outputFullPath
if ($outputDirectory) { New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null }
[IO.File]::WriteAllText($outputFullPath, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))

# Validate the serialized artifact rather than trusting the in-memory object.
$verified = Get-Content -LiteralPath $outputFullPath -Raw | ConvertFrom-Json
$verifiedRooms = @($verified.areas | ForEach-Object { @($_.rooms) })
$badRooms = @($verifiedRooms | Where-Object {
    $targets.Contains([string]$_.userData.fed2_system)
})
if ($badRooms.Count -gt 0) { throw "Validation failed: $($badRooms.Count) target-system room(s) remain." }

$dangling = @($verifiedRooms | ForEach-Object { @($_.exits) } | Where-Object {
    $removedRoomIds.Contains([int]$_.exitId)
})
if ($dangling.Count -gt 0) { throw "Validation failed: $($dangling.Count) exit(s) still target deleted rooms." }
if ([int]$verified.areaCount -ne @($verified.areas).Count) { throw 'Validation failed: areaCount is incorrect.' }
if ([int]$verified.roomCount -ne $verifiedRooms.Count) { throw 'Validation failed: roomCount is incorrect.' }

if ($verified.userData -and $verified.userData.f2t_topology) {
    $verifiedTopology = ([string]$verified.userData.f2t_topology) | ConvertFrom-Json
    $remainingTopologySystems = @($verifiedTopology.systems.PSObject.Properties | Where-Object {
        $targets.Contains($_.Name)
    })
    if ($remainingTopologySystems.Count -gt 0) {
        throw 'Validation failed: target system entries remain in f2t_topology.'
    }
}

$report = [ordered]@{
    inputPath = $inputFullPath
    inputSha256 = (Get-FileHash -LiteralPath $inputFullPath -Algorithm SHA256).Hash
    outputPath = $outputFullPath
    outputSha256 = (Get-FileHash -LiteralPath $outputFullPath -Algorithm SHA256).Hash
    systems = @($targets | Sort-Object)
    removedAreaCount = $removedAreas.Count
    removedRoomCount = $removedRoomIds.Count
    removedCrossExitCount = $removedCrossExits
    removedTopologySystems = @($removedTopologySystems | Sort-Object)
    resultingAreaCount = [int]$verified.areaCount
    resultingRoomCount = [int]$verified.roomCount
    removedAreas = @($removedAreas | Sort-Object system, name)
    removedRoomHashes = @($removedRoomHashes | Sort-Object)
}

if ($ReportPath) {
    $reportFullPath = [IO.Path]::GetFullPath($ReportPath)
    $reportDirectory = Split-Path -Parent $reportFullPath
    if ($reportDirectory) { New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null }
    [IO.File]::WriteAllText(
        $reportFullPath,
        (($report | ConvertTo-Json -Depth 20) + [Environment]::NewLine),
        [Text.UTF8Encoding]::new($false)
    )
}

$report | ConvertTo-Json -Depth 20
