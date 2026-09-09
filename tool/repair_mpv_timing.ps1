param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$LibraryPath,
    [switch]$VerifyOnly
)
$ErrorActionPreference = 'Stop'
if (-not $LibraryPath) {
    $LibraryPath = Join-Path $ProjectRoot 'ohos\entry\src\main\cpp\thirdparty\mpv\arm64-v8a\lib\libmpv.so'
}

# The bundled customized 0.41.0 library is supplied prebuilt. Clear only the
# VO_CAP_UNTIMED data bit; retain VO_CAP_NORETAIN and all executable code.
# Fixed offsets are valid ONLY for the exact SHA-256 below. Unknown libraries
# must be reviewed, never blindly patched. See docs/milestone-67-4.0.1.md.
$originalHash = 'DAECEFE473819A40EFC795D2E0CF6916BE2C830BC39CB9CCF4251F4C67194D63'
$repairedHash = '7438FCC2AAC0E0BBF2F7ED7F04C286EFD2A06BC5BCB8C2212A3123FCA1F1DFF5'
$actualHash = (Get-FileHash -LiteralPath $LibraryPath -Algorithm SHA256).Hash
if ($actualHash -eq '0E566EAA73A04CBF7BBB3AAD6F3B6E51096A4F00FD13028A06A3286CE8D665D8') {
    Write-Host 'Verified rebuilt MPV OHCodec direct output with timed presentation and upstream buffer tokens; no binary patch required.'
    return
}
if ($actualHash -eq '672E98D497199A89E20893979ECEC686DEE1113BBE1B609C9A9266AA1679BD32') {
    Write-Host 'Verified unchanged media-kit OHOS upstream MPV (20260715); no custom binary patches applied.'
    return
}
if ($actualHash -eq $repairedHash) {
    Write-Host 'Verified MPV OHCodec timed output (including silent/unsupported audio).'
    return
}
if ($actualHash -ne $originalHash) { throw "Unknown MPV library SHA-256: $actualHash. Review OHCodec timing before updating the pinned patch." }
if ($VerifyOnly) { throw 'MPV OHCodec timing repair has not been applied.' }

$bytes = [IO.File]::ReadAllBytes($LibraryPath)
foreach ($offset in @(0x26922dc, 0x2693144)) {
    # int caps = VO_CAP_NORETAIN (4) | VO_CAP_UNTIMED (16).
    if ([BitConverter]::ToInt32($bytes, $offset) -ne 20) { throw 'Unexpected OHCodec capabilities.' }
    $bytes[$offset] = 4
}
$sha = [Security.Cryptography.SHA256]::Create()
try { $resultHash = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '') }
finally { $sha.Dispose() }
if ($resultHash -ne $repairedHash) { throw 'MPV timing repair result hash mismatch.' }
[IO.File]::WriteAllBytes($LibraryPath, $bytes)
Write-Host "Repaired MPV OHCodec timing: $resultHash"
