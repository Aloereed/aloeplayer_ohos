param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateSet("hap", "app")]
    [string]$BuildType,

    [Parameter(Mandatory=$false, Position=1)]
    [ValidateSet("debug", "release")]
    [string]$Config,

    [string]$FlutterRoot = "E:\source\flutter_327",

    [string]$DevEcoRoot = "E:\Huawei\DevEco_Studio",

    [switch]$Offline,
    [switch]$Locked,
    [switch]$NoVersionBump
)

$ErrorActionPreference = "Stop"
$projectRoot = $PSScriptRoot
$flutterCommand = Join-Path $FlutterRoot "bin\flutter.bat"
$devEcoSdk = Join-Path $DevEcoRoot "sdk"
$devEcoNode = Join-Path $DevEcoRoot "tools\node"
$devEcoOhpm = Join-Path $DevEcoRoot "tools\ohpm\bin"
$devEcoHvigor = Join-Path $DevEcoRoot "tools\hvigor\bin"
$preparePluginsScript = Join-Path $projectRoot "tool\prepare_ohos_plugins.ps1"

if (-not (Test-Path -LiteralPath $flutterCommand)) {
    throw "Flutter executable not found: $flutterCommand"
}
if (-not (Test-Path -LiteralPath $preparePluginsScript)) {
    throw "OHOS plugin preparation script not found: $preparePluginsScript"
}

# Keep the complete Pub cache on the workspace drive. This avoids Hvigor 6.x
# rejecting plugins whose generated paths resolve through a cross-drive cache.
$env:FLUTTER_ROOT = $FlutterRoot
$env:HOS_SDK_HOME = $devEcoSdk
$env:DEVECO_SDK_HOME = $devEcoSdk
$env:NODE_HOME = $devEcoNode
$env:PUB_CACHE = Join-Path $projectRoot ".dart_tool\pub-cache"
# Skip Git LFS smudge during dependency checkout. Some upstream example assets
# reference unavailable LFS objects, while they are not needed by this app build.
$env:GIT_LFS_SKIP_SMUDGE = "1"
$env:Path = "$FlutterRoot\bin;$devEcoNode;$devEcoOhpm;$devEcoHvigor;$env:Path"

# 函数: 检查是否有代码变更并更新版本号
function Update-VersionIfChanged {
    # 检查是否在 git 仓库中
    $isGitRepo = Test-Path ".git"
    if (-not $isGitRepo) {
        Write-Host "不是 git 仓库，跳过版本号检查" -ForegroundColor Yellow
        return
    }

    # 检查是否有未提交的变更
    $gitStatus = git status --porcelain
    if ([string]::IsNullOrWhiteSpace($gitStatus)) {
        Write-Host "没有代码变更，保持当前版本号" -ForegroundColor Green
        return
    }

    Write-Host "检测到代码变更，准备更新版本号..." -ForegroundColor Cyan

    # 读取 pubspec.yaml
    $pubspecPath = "pubspec.yaml"
    if (-not (Test-Path $pubspecPath)) {
        Write-Warning "未找到 pubspec.yaml，跳过版本号更新"
        return
    }

    $content = Get-Content $pubspecPath -Raw

    # 匹配版本号 (格式: version: x.y.z+build)
    if ($content -match 'version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)') {
        $major = [int]$matches[1]
        $minor = [int]$matches[2]
        $patch = [int]$matches[3]
        $build = [int]$matches[4]

        $oldVersion = "$major.$minor.$patch+$build"

        # 增加构建号
        $build++
        $newVersion = "$major.$minor.$patch+$build"

        Write-Host "版本号更新: $oldVersion -> $newVersion" -ForegroundColor Green

        # 更新文件内容
        $newContent = $content -replace "version:\s*\d+\.\d+\.\d+\+\d+", "version: $newVersion"
        Set-Content -Path $pubspecPath -Value $newContent -NoNewline

        Write-Host "pubspec.yaml 已更新" -ForegroundColor Green
    } else {
        Write-Warning "无法解析 pubspec.yaml 中的版本号"
    }
}

# 设置默认签名配置；实际 Flutter 构建始终为 Release。
if (-not $Config) {
    if ($BuildType -eq "hap") {
        $Config = "debug"
    } else {
        $Config = "release"
    }
}

# 每次构建按项目既定规则自动递增版本号。
if (-not $NoVersionBump) { Update-VersionIfChanged }

# 定义路径
$buildProfilePath = "ohos\build-profile.json5"
$buildProfileSource = "ohos\build-profile.json5.$Config"

# 检查源配置文件是否存在
if (-not (Test-Path $buildProfileSource)) {
    Write-Error "配置文件不存在: $buildProfileSource"
    exit 1
}

# 备份当前配置文件（如果存在）
if (Test-Path $buildProfilePath) {
    Write-Host "备份当前配置文件..."
    Copy-Item $buildProfilePath "$buildProfilePath.backup" -Force
}

# 复制对应的配置文件
Write-Host "使用配置: $Config"
Write-Host "复制 $buildProfileSource 到 $buildProfilePath"
Copy-Item $buildProfileSource $buildProfilePath -Force

try {
    Write-Host "Flutter SDK: $FlutterRoot" -ForegroundColor Cyan
    & $flutterCommand --version
    if ($LASTEXITCODE -ne 0) {
        throw "无法执行指定 Flutter SDK"
    }

    # Phase 1: always resolve dependencies. Iterations can add, remove, or
    # upgrade packages normally; pubspec.lock remains authoritative.
    Write-Host "----------------------------------------"
    Write-Host "阶段 1/3: 解析 Dart 依赖" -ForegroundColor Cyan
    $pubArguments = @("pub", "get")
    if ($Offline) { $pubArguments += "--offline" }
    if ($Locked) { $pubArguments += "--enforce-lockfile" }
    & $flutterCommand @pubArguments
    if ($LASTEXITCODE -ne 0) {
        throw "flutter pub get 失败，退出代码: $LASTEXITCODE"
    }

    # Flutter 3.41 OHOS rewrites plugin metadata during pub get. Normalize and
    # localize paths before Hvigor consumes that generated file.
    Write-Host "阶段 2/3: 准备 OHOS 插件路径" -ForegroundColor Cyan
    & $preparePluginsScript -ProjectRoot $projectRoot

    # --no-pub is intentional only in this second phase: dependencies were
    # refreshed immediately above, and another implicit pub get would overwrite
    # the normalized OHOS metadata.
    Write-Host "阶段 3/3: Release 构建" -ForegroundColor Cyan
    $compilationStarted = Get-Date
    & $flutterCommand build $BuildType --release --no-pub
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        if ($BuildType -eq "hap") {
            $canonicalPath = Join-Path $projectRoot "ohos\entry\build\default\outputs\default\entry-default-unsigned.hap"
            $canonicalHap = Get-Item -LiteralPath $canonicalPath
            if ($canonicalHap.LastWriteTime -lt $compilationStarted) {
                throw "Canonical HAP timestamp was not refreshed. Do not archive a cached artifact as a new milestone."
            }
            Write-Host "Verified canonical HAP: $($canonicalHap.LastWriteTime.ToString('o'))" -ForegroundColor Cyan
        }
        Write-Host "----------------------------------------"
        Write-Host "构建成功!" -ForegroundColor Green
    } else {
        Write-Host "----------------------------------------"
        Write-Host "构建失败! 退出代码: $exitCode" -ForegroundColor Red
        exit $exitCode
    }
} catch {
    Write-Host "----------------------------------------"
    Write-Host "构建过程中发生错误: $_" -ForegroundColor Red
    exit 1
}
