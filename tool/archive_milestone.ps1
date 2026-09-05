param(
    [Parameter(Mandatory=$true)][string]$Name,
    [datetime]$BuildStarted = [datetime]::MinValue
)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$output = Join-Path $project 'ohos\entry\build\default\outputs\default'
$canonical = Join-Path $output 'entry-default-unsigned.hap'
$hap = Get-Item -LiteralPath $canonical
if ($hap.LastWriteTime -lt $BuildStarted) { throw 'Canonical HAP was not updated by this build.' }
if ($Name -notmatch '^[a-zA-Z0-9_-]+$') { throw 'Invalid milestone name.' }
$destination = Join-Path $project "build\milestones\$Name"
if (Test-Path -LiteralPath $destination) { throw "Milestone already exists: $destination" }
New-Item -ItemType Directory -Path $destination -Force | Out-Null
$artifacts = @()
foreach ($file in Get-ChildItem -LiteralPath $output -Filter '*.hap') {
    if ($file.LastWriteTime -lt $BuildStarted) { continue }
    Copy-Item -LiteralPath $file.FullName -Destination $destination
    $artifacts += @{ name=$file.Name; bytes=$file.Length; modified=$file.LastWriteTime.ToString('o'); sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash }
}
$manifest = @{
    milestone=$Name; commit=(git -C $project rev-parse HEAD); version=(Select-String -LiteralPath (Join-Path $project 'pubspec.yaml') -Pattern '^version:').Line;
    archived=(Get-Date).ToString('o'); buildStarted=$BuildStarted.ToString('o'); artifacts=$artifacts;
    worktree=(git -C $project status --short | Out-String); deviceTested=$false
}
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $destination 'manifest.json') -Encoding utf8
Write-Host "Archived: $destination"
