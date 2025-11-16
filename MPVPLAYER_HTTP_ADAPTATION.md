# MPVPlayer HTTP协议适配修复

## 问题描述

当通过SMB媒体库点击视频文件播放时，播放器无法正常工作。原因是MPVPlayer没有正确处理HTTP URL，将其当作本地文件路径处理。

## 修复内容

### 1. `_loadPlaylist()` 方法修复

**问题**:
- 尝试对HTTP URL调用`Directory(path.dirname(widget.filePath))`导致失败
- 尝试创建`File(widget.filePath)`对象处理HTTP URL

**修复**:
```dart
void _loadPlaylist() async {
  // 检查是否为HTTP/HTTPS URL
  final isHttpUrl = widget.filePath.startsWith('http://') ||
                    widget.filePath.startsWith('https://');

  // 如果是HTTP URL或未启用播放列表导入，只创建当前文件的播放列表
  if (isHttpUrl || !_usePlaylist) {
    // 对于HTTP URL，不使用File对象，直接使用路径字符串
    if (isHttpUrl) {
      _playlist = [];
      _originalPlaylist = [];
    } else {
      _playlist = [File(widget.filePath)];
      _originalPlaylist = [File(widget.filePath)];
    }
    _currentIndex = 0;
    if (mounted) setState(() {});
    return;
  }
  // ... 本地文件处理
}
```

**说明**:
- 检测HTTP/HTTPS URL
- 对于HTTP URL，创建空的播放列表（因为无法列出远程目录）
- 对于本地文件，保持原有逻辑

### 2. `_openMedia()` 方法修复

**问题**:
- 对HTTP URL调用`resolveLnkFile()`尝试读取文件
- 尝试遍历空的播放列表
- 对HTTP URL记录播放历史可能失败

**修复**:
```dart
void _openMedia(String filePath) async {
  // 检查是否为HTTP/HTTPS URL
  final isHttpUrl = filePath.startsWith('http://') ||
                    filePath.startsWith('https://');

  // 根据是否为HTTP URL选择不同的处理方式
  String resolvedPath;
  if (isHttpUrl) {
    // HTTP URL直接使用，不需要解析.lnk
    resolvedPath = filePath;
  } else {
    // 本地文件需要解析.lnk
    resolvedPath = await resolveLnkFile(filePath);
  }

  // 创建播放列表
  final List<Media> mediaList = [];
  if (isHttpUrl) {
    // HTTP URL直接创建单个媒体项
    mediaList.add(Media(resolvedPath));
  } else {
    // 本地文件从播放列表创建
    for (final file in _playlist) {
      final path = await resolveLnkFile(file.path);
      mediaList.add(Media(path));
    }
  }

  // ... 打开播放器

  // 尝试恢复历史播放位置 (只对本地文件)
  if (!isHttpUrl) {
    _restorePlaybackPosition(resolvedPath);
  }

  // 记录到历史 (只对本地文件)
  if (!isHttpUrl) {
    _recordToHistory(resolvedPath);
  }
}
```

**说明**:
- 检测HTTP URL并跳过.lnk文件解析
- 对HTTP URL直接创建Media对象
- 跳过HTTP URL的历史记录功能（避免尝试写入无效路径）

### 3. 播放列表导航

**现状**: `_playNext()` 和 `_playPrevious()` 方法已经有空列表检查:
```dart
void _playNext() {
  if (_playlist.isEmpty) return;  // 已存在的保护
  // ...
}

void _playPrevious() {
  if (_playlist.isEmpty) return;  // 已存在的保护
  // ...
}
```

**说明**: 当播放HTTP URL时（播放列表为空），上一曲/下一曲按钮会被禁用。

## 工作流程

### HTTP URL播放流程:
1. 用户在SMB浏览器点击视频文件
2. 生成HTTP URL: `http://192.168.1.100:8080/file/path/to/video.mp4`
3. 导航到MPVPlayer并传递HTTP URL
4. MPVPlayer检测到HTTP URL
5. 跳过播放列表加载
6. 跳过.lnk解析
7. 直接创建Media对象
8. 开始播放

### 本地文件播放流程（保持不变）:
1. 传递本地文件路径
2. 加载同目录下的播放列表
3. 解析.lnk文件
4. 恢复播放位置
5. 记录到历史

## 功能限制

当播放HTTP URL时，以下功能不可用（这是预期行为）：

1. **播放列表**: 无法显示同目录下的其他文件
2. **上一曲/下一曲**: 因为没有播放列表，这些按钮无效
3. **播放历史**: 不记录HTTP URL的播放历史和位置
4. **续播功能**: HTTP URL每次从头播放

这些限制是合理的，因为HTTP URL指向的是远程文件，无法访问同目录内容或保存本地状态。

## 测试建议

1. **本地文件播放**: 确保原有功能不受影响
   - 播放列表正常
   - 上一曲/下一曲正常
   - 播放历史正常
   - 续播功能正常

2. **HTTP URL播放**: 验证新功能
   - 从SMB浏览器点击视频能正常播放
   - 播放过程中seek操作正常
   - 播放控制（暂停、快进等）正常
   - 不会显示错误提示

3. **混合测试**:
   - 先播放本地文件，再播放HTTP URL
   - 先播放HTTP URL，再播放本地文件
   - 确保两种模式切换正常

## 协议白名单

MPVPlayer的配置已包含HTTP协议支持（第512-521行）:
```dart
player = Player(
  configuration: PlayerConfiguration(
    protocolWhitelist: const [
      'file',
      'http',      // ✓ 已支持
      'https',     // ✓ 已支持
      'tcp',
      'tls',
      'rtsp',
      'smb',
      'ftp'
    ],
  ),
);
```

## 总结

修复后，MPVPlayer可以无缝处理：
- ✅ 本地文件路径（包括.lnk快捷方式）
- ✅ HTTP URL（来自SMB转HTTP服务）
- ✅ HTTPS URL（如果需要）

播放器会自动检测URL类型并应用适当的处理逻辑，确保在两种场景下都能正常工作。
