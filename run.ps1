param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateSet("debug", "release")]
    [string]$Config,

    [Parameter(Mandatory=$true, Position=1)]
    [string]$DeviceId
)

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

# 检查代码变更并更新版本号
Update-VersionIfChanged

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

# 执行运行命令
$runCommand = "flutter run --release -d $DeviceId"
Write-Host "执行运行命令: $runCommand"
Write-Host "目标设备: $DeviceId"
Write-Host "----------------------------------------"

try {
    Invoke-Expression $runCommand
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        Write-Host "----------------------------------------"
        Write-Host "运行完成!" -ForegroundColor Green
    } else {
        Write-Host "----------------------------------------"
        Write-Host "运行失败! 退出代码: $exitCode" -ForegroundColor Red
        exit $exitCode
    }
} catch {
    Write-Host "----------------------------------------"
    Write-Host "运行过程中发生错误: $_" -ForegroundColor Red
    exit 1
}
