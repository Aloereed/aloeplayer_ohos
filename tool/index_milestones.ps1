param([switch]$VerifyHashes)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$root = Join-Path $project 'build\milestones'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$rows = @()
$verified = 0
foreach ($directory in Get-ChildItem -LiteralPath $root -Directory | Where-Object { $_.Name -match '^\d{2}-' } | Sort-Object Name -Descending) {
    $manifest = Get-Content -LiteralPath (Join-Path $directory.FullName 'manifest.json') -Raw | ConvertFrom-Json
    foreach ($artifact in $manifest.artifacts) {
        $file = Get-Item -LiteralPath (Join-Path $directory.FullName $artifact.name)
        if ($file.Length -ne $artifact.bytes) { throw "Artifact size mismatch: $($file.FullName)" }
        if ($VerifyHashes -and (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash -ne $artifact.sha256) { throw "SHA-256 mismatch: $($file.FullName)" }
        $verified++
    }
    $signed = $manifest.artifacts | Where-Object { $_.name -eq 'entry-default-signed.hap' } | Select-Object -First 1
    $unsigned = $manifest.artifacts | Where-Object { $_.name -eq 'entry-default-unsigned.hap' } | Select-Object -First 1
    $metadataFile = if ($signed) { $signed.name } else { $unsigned.name }
    $zip = [System.IO.Compression.ZipFile]::OpenRead((Join-Path $directory.FullName $metadataFile))
    try {
        $reader = [System.IO.StreamReader]::new($zip.GetEntry('module.json').Open())
        try { $module = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
    } finally { $zip.Dispose() }
    $version = "$($module.app.versionName)+$($module.app.versionCode)"
    if ($directory.Name -notlike '00-*') {
        $source = git -C $project show ($manifest.commit + ':pubspec.yaml')
        if ($LASTEXITCODE -ne 0) { throw "Source commit unavailable: $($manifest.commit)" }
        $sourceVersion = ($source | Select-String -Pattern '^version:').Line
        if ($sourceVersion -ne $manifest.version -or $sourceVersion -notmatch ('^version:\s*' + [regex]::Escape($version) + '\s*$')) {
            throw "Source/HAP version mismatch: $($directory.Name)"
        }
    }
    $signedLink = if ($signed) { "[签名 HAP]($($directory.Name)/$($signed.name))" } else { '无' }
    $unsignedLink = if ($unsigned) { "[未签名 HAP]($($directory.Name)/$($unsigned.name))" } else { '无' }
    $commit = $manifest.commit.Substring(0, 7)
    $rows += "| $($directory.Name) | $version | $commit | $signedLink | $unsignedLink | [来源清单]($($directory.Name)/manifest.json) |"
}
$lines = @(
    '# AloePlayer 鸿蒙版：里程碑安装包', '',
    '按下表从新到旧测试。每个包独立保留，SHA-256、构建时间和源码提交见来源清单。00 是工作开始前已有产物，来源不能视为本轮重建验证。', '',
    '建议先安装第一行；最新版本正常即可停在最新版本。部署脚本支持 API 23+ 的调试签名降级安装，不执行卸载或清空数据。', '',
    '在仓库根目录运行：`./tool/deploy_milestone.ps1`。指定旧版：`./tool/deploy_milestone.ps1 -Name 27-thumbnail-rebuild-file-actions`。只查看操作：加 `-DryRun`。', '',
    '验收说明：[明早检查清单](../../docs/morning-verification.md)；[第二轮实现与局限](../../docs/round2-milestones.md)；[第一轮记录](../../docs/overnight-milestones.md)；[界面预览](../ui-review/index.html)。', '',
    '| 里程碑（新 → 旧） | HAP 内版本 | Git commit | 部署包 | 重新签名用 | 追溯 |',
    '| --- | --- | --- | --- | --- | --- |'
)
$lines += $rows
$lines += @('', "检查时间：$((Get-Date).ToString('o'))；产物数：$verified；SHA-256 全量验证：$VerifyHashes。", '',
    '兼容性：本轮重建包沿用项目的 HarmonyOS API 23 最低要求；使用项目已有调试签名。更换目标设备可能需要重新签名。', '',
    '本轮功能回退：28 原生 PiP 竞态；27 缩略图重建与文件菜单；26 PiP / 画质交互；25 FFmpeg 后备缩略图；24 后台探测；23 主题 / 音频库；22 导航 / 视频库；21 FSR；20 导入说明；19 媒体来源；18 原生 PiP 页面；17 缩略图资源释放。', '',
    '历史回退提示：02 起密码迁入安全存储，旧基线可能需要重新输入服务器密码；06–09 的缩略图等待问题在 10 修复；16 的 PiP 仍收到无限等待反馈，18 已替换承载链路；13 修正 SMB 时间戳后，旧 SMB 下载任务可能需要取消重建。', '',
    '01–06 的来源清单保留了构建时的工作区记录（主要为下一阶段尚未接入的文件）；本轮 17–28 均单独提交后归档。00 是此前留下的产物。')
$lines | Set-Content -LiteralPath (Join-Path $root 'README.md') -Encoding utf8
Write-Host "Indexed $($rows.Count) milestones / $verified artifacts; verified hashes: $VerifyHashes"
