param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$projectPath = [System.IO.Path]::GetFullPath($ProjectRoot)
$metadataPath = Join-Path $projectPath '.flutter-plugins-dependencies'
$stageRoot = Join-Path $projectPath '.dart_tool\ohos-plugins'

if (-not (Test-Path -LiteralPath $metadataPath)) {
    throw "Flutter plugin metadata not found: $metadataPath. Run flutter pub get first."
}

function Normalize-GeneratedPath([string]$Value) {
    $normalized = $Value
    while ($normalized.Contains('\\')) {
        $normalized = $normalized.Replace('\\', '\')
    }
    return $normalized
}

function Test-IsUnderPath([string]$Candidate, [string]$Parent) {
    $candidatePath = [System.IO.Path]::GetFullPath($Candidate).TrimEnd('\') + '\'
    $parentPath = [System.IO.Path]::GetFullPath($Parent).TrimEnd('\') + '\'
    return $candidatePath.StartsWith(
        $parentPath,
        [System.StringComparison]::OrdinalIgnoreCase
    )
}

$metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
$ohosPlugins = @($metadata.plugins.ohos)

if ($ohosPlugins.Count -eq 0) {
    Write-Host 'No OHOS plugins found in Flutter metadata.' -ForegroundColor Yellow
    exit 0
}

New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null

foreach ($plugin in $ohosPlugins) {
    $sourceRoot = Normalize-GeneratedPath ([string]$plugin.path)
    if (-not [System.IO.Path]::IsPathRooted($sourceRoot)) {
        $sourceRoot = Join-Path $projectPath $sourceRoot
    }
    $sourceRoot = [System.IO.Path]::GetFullPath($sourceRoot)

    $sourceOhos = Join-Path $sourceRoot 'ohos'
    if (-not (Test-Path -LiteralPath $sourceOhos)) {
        throw "OHOS source for plugin '$($plugin.name)' not found: $sourceOhos"
    }

    $sourceDrive = [System.IO.Path]::GetPathRoot($sourceRoot)
    $projectDrive = [System.IO.Path]::GetPathRoot($projectPath)
    $isPubCachePath = $sourceRoot -match '[\\/]\.pub-cache[\\/]'
    $isDifferentDrive = -not $sourceDrive.Equals(
        $projectDrive,
        [System.StringComparison]::OrdinalIgnoreCase
    )
    $alreadyStaged = Test-IsUnderPath $sourceRoot $stageRoot

    if (($isPubCachePath -or $isDifferentDrive) -and -not $alreadyStaged) {
        $destinationRoot = Join-Path $stageRoot ([string]$plugin.name)
        $destinationOhos = Join-Path $destinationRoot 'ohos'

        if (-not (Test-IsUnderPath $destinationRoot $stageRoot)) {
            throw "Refusing to stage plugin outside $stageRoot"
        }

        if (Test-Path -LiteralPath $destinationRoot) {
            Remove-Item -LiteralPath $destinationRoot -Recurse -Force
        }
        New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
        Copy-Item -LiteralPath $sourceOhos -Destination $destinationOhos -Recurse -Force
        $plugin.path = $destinationRoot.TrimEnd('\') + '\'
        Write-Host "Staged OHOS plugin: $($plugin.name)" -ForegroundColor DarkCyan
    } else {
        $plugin.path = $sourceRoot.TrimEnd('\') + '\'
    }
}

$metadata | ConvertTo-Json -Depth 100 -Compress |
    Set-Content -LiteralPath $metadataPath -Encoding utf8

Write-Host "Prepared $($ohosPlugins.Count) OHOS plugin paths." -ForegroundColor Green
