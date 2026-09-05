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

function Repair-MediaKitVideoSurfaceDispose([string]$PluginRoot) {
    $videoOutputPath = Join-Path $PluginRoot (
        'ohos\src\main\ets\com\alexmercerind\media_kit_video\VideoOutput.ets'
    )
    if (-not (Test-Path -LiteralPath $videoOutputPath)) {
        throw "media_kit_video VideoOutput source not found: $videoOutputPath"
    }

    $content = Get-Content -LiteralPath $videoOutputPath -Raw
    $doubleRelease = @'
      this.surfaceProducer.release();
      this.onSurfaceDestroyed();
'@
    $singleRelease = @'
      // onSurfaceDestroyed notifies mpv before releasing the texture once.
      this.onSurfaceDestroyed();
'@

    if ($content.Contains($doubleRelease)) {
        $content = $content.Replace($doubleRelease, $singleRelease)
        Set-Content -LiteralPath $videoOutputPath -Value $content -Encoding utf8 -NoNewline
        Write-Host 'Patched media_kit_video duplicate SurfaceTextureEntry release.' -ForegroundColor DarkCyan
    }
}

function Repair-MediaKitNativeDispose([string]$MediaKitVideoRoot) {
    $mediaKitRoot = Join-Path (Split-Path -Parent $MediaKitVideoRoot) 'media_kit'
    $nativePlayerPath = Join-Path $mediaKitRoot 'lib\src\player\native\player\real.dart'
    if (-not (Test-Path -LiteralPath $nativePlayerPath)) {
        throw "media_kit native player source not found: $nativePlayerPath"
    }

    $content = Get-Content -LiteralPath $nativePlayerPath -Raw
    $unsafeDispose = @'
      Initializer(mpv).dispose(ctx);

      Future.delayed(const Duration(seconds: 5), () {
        mpv.mpv_terminate_destroy(ctx);
      });
'@
    $safeDispose = @'
      // Stop libmpv from scheduling new Dart callbacks before disposal. Keep
      // the NativeCallable alive until mpv is fully terminated so callbacks
      // already queued on the Dart event loop remain valid.
      mpv.mpv_set_wakeup_callback(ctx, nullptr, nullptr);

      Future.delayed(const Duration(seconds: 5), () {
        mpv.mpv_terminate_destroy(ctx);
        Initializer(mpv).dispose(ctx);
      });
'@

    if ($content.Contains($unsafeDispose)) {
        $content = $content.Replace($unsafeDispose, $safeDispose)
        Set-Content -LiteralPath $nativePlayerPath -Value $content -Encoding utf8 -NoNewline
        Write-Host 'Patched media_kit wakeup callback disposal ordering.' -ForegroundColor DarkCyan
    }
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
    $isPubCachePath = $sourceRoot -match '[\\/]\.?pub-cache[\\/]'
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
        New-Item -ItemType Directory -Path $destinationOhos -Force | Out-Null
        Get-ChildItem -LiteralPath $sourceOhos -Force |
            Where-Object { $_.Name -notin @('oh_modules', 'build', '.hvigor') } |
            ForEach-Object {
                Copy-Item -LiteralPath $_.FullName -Destination $destinationOhos -Recurse -Force
            }
        if ([string]$plugin.name -eq 'media_kit_video') {
            Repair-MediaKitNativeDispose $sourceRoot
            Repair-MediaKitVideoSurfaceDispose $destinationRoot
        }
        if ([string]$plugin.name -eq 'video_thumbnail_ohos') {
            Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'ohos_patches\VideoThumbnailOhosPlugin.ets') -Destination (Join-Path $destinationOhos 'src\main\ets\components\plugin\VideoThumbnailOhosPlugin.ets') -Force
        }
        $plugin.path = $destinationRoot.TrimEnd('\') + '\'
        Write-Host "Staged OHOS plugin: $($plugin.name)" -ForegroundColor DarkCyan
    } else {
        $plugin.path = $sourceRoot.TrimEnd('\') + '\'
    }
}

$metadata | ConvertTo-Json -Depth 100 -Compress |
    Set-Content -LiteralPath $metadataPath -Encoding utf8

Write-Host "Prepared $($ohosPlugins.Count) OHOS plugin paths." -ForegroundColor Green
