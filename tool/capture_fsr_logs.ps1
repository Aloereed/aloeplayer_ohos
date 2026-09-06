param(
    [string]$Target,
    [string]$Hdc = 'E:\Huawei\DevEco_Studio\sdk\default\openharmony\toolchains\hdc.exe'
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Hdc)) { throw 'HDC executable not found.' }
if ($Target -and $Target -notmatch '^[a-zA-Z0-9_.:-]+$') { throw 'Invalid HDC target.' }
$devices = @(& $Hdc list targets | Where-Object { $_ -and $_ -notmatch '\[Empty\]|^\s*$' } | ForEach-Object { $_.Trim() })
if ($LASTEXITCODE -ne 0 -or $devices.Count -eq 0) { throw 'No connected HDC device.' }
if (-not $Target) {
    if ($devices.Count -ne 1) { throw 'Multiple devices connected. Select one with -Target.' }
    $Target = $devices[0]
}
if ($Target -notin $devices) { throw 'The selected device is not connected.' }
# Dump the existing buffer; do not clear logs or leave a streaming process running.
$lines = @(& $Hdc -t $Target shell hilog -x -e Aloe 2>&1)
if ($LASTEXITCODE -ne 0) { throw ($lines | Out-String) }
$fsrLines = @($lines | Where-Object { "$_" -match '\[Aloe(?:FSR|Anime4K)\]' })
$outputDirectory = Join-Path (Split-Path -Parent $PSScriptRoot) 'build'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$outputFile = Join-Path $outputDirectory ('fsr-diagnostics-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$fsrLines | Set-Content -LiteralPath $outputFile -Encoding utf8
$fsrLines | ForEach-Object { Write-Output $_ }
Write-Output "Captured $($fsrLines.Count) FSR / Anime4K log lines: $outputFile"
if ($fsrLines.Count -eq 0) { Write-Output 'Play a video, switch FSR or Anime4K, wait 4 seconds, then run this script again.' }
