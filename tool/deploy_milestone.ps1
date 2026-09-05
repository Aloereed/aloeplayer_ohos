param(
    [string]$Name = 'latest',
    [string]$Target,
    [string]$Hdc = 'E:\Huawei\DevEco_Studio\sdk\default\openharmony\toolchains\hdc.exe',
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$root = Join-Path $project 'build\milestones'
if ($Name -eq 'latest') {
    $Name = (Get-ChildItem -LiteralPath $root -Directory | Where-Object { $_.Name -match '^\d{2}-' } | Sort-Object Name -Descending | Select-Object -First 1).Name
}
if ($Name -notmatch '^\d{2}-[a-zA-Z0-9_-]+$') { throw 'Invalid milestone name.' }
if ($Target -and $Target -notmatch '^[a-zA-Z0-9_.:-]+$') { throw 'Invalid HDC target.' }
$directory = Join-Path $root $Name
$manifest = Get-Content -LiteralPath (Join-Path $directory 'manifest.json') -Raw | ConvertFrom-Json
$signed = $manifest.artifacts | Where-Object { $_.name -eq 'entry-default-signed.hap' } | Select-Object -First 1
if (-not $signed) { throw 'This milestone has no signed HAP. Sign the unsigned HAP for your device first.' }
$hap = Join-Path $directory $signed.name
if ((Get-FileHash -LiteralPath $hap -Algorithm SHA256).Hash -ne $signed.sha256) { throw 'HAP SHA-256 mismatch.' }
$remote = '/data/local/tmp/aloeplayer-' + $signed.sha256.Substring(0, 16).ToLower() + '.hap'
Write-Host "Milestone: $Name / $($manifest.version) / $($manifest.commit)"
if ($DryRun) {
    Write-Host "Verified SHA-256. Would send: $hap -> $remote"
    Write-Host "Would run on the selected device: bm install -p $remote -r -d"
    Write-Host 'No device commands executed. No uninstall or data clearing is performed.'
    exit 0
}
if (-not (Test-Path -LiteralPath $Hdc)) { throw 'HDC executable not found.' }
$devices = @(& $Hdc list targets | Where-Object { $_ -and $_ -notmatch '\[Empty\]|^\s*$' } | ForEach-Object { $_.Trim() })
if ($LASTEXITCODE -ne 0 -or $devices.Count -eq 0) { throw 'No connected HDC device.' }
if (-not $Target) {
    if ($devices.Count -ne 1) { throw 'Multiple devices connected. Select one with -Target.' }
    $Target = $devices[0]
}
if ($Target -notin $devices) { throw 'The selected HDC device is not connected.' }
$prefix = @('-t', $Target)
& $Hdc @prefix file send $hap $remote
if ($LASTEXITCODE -ne 0) { throw 'Sending HAP failed.' }
# API 23+ permits -d for debug-signed apps. This keeps app data while testing
# newer-to-older milestones. Signing identity and device authorization still apply.
$result = & $Hdc @prefix shell bm install -p $remote -r -d 2>&1
$installExit = $LASTEXITCODE
$log = Join-Path $root ("deploy-{0}-{1}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $Name)
$result | Set-Content -LiteralPath $log -Encoding utf8
$result | ForEach-Object { Write-Host $_ }
if ($installExit -ne 0 -or ($result | Out-String) -match '(?i)error:|failed|failure' -or ($result | Out-String) -notmatch '(?i)success') {
    throw "Installation failed. App data was not cleared. See $log"
}
Write-Host "Installed $Name. Open AloePlayer and follow docs/morning-verification.md."
