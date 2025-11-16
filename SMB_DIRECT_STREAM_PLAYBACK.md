# SMB 直接流式播放实现说明

## 问题背景

之前的实现使用 **SMB → HTTP 代理 → mpvplayer** 的方式播放视频，这会导致：
- 额外的性能开销（HTTP 服务器中转）
- 播放卡顿
- 内存和 CPU 使用率增加

## 解决方案

由于 media-kit 不直接支持 SMB 协议，我们实现了**边下载边播放**的流式缓存机制：

```
SMB Stream → 临时文件（流式写入） → mpvplayer（边下边播）
```

## 核心实现

### 1. 流式缓存服务 (`stream_cache_service.dart`)

创建了 `StreamCacheService` 单例服务，提供：

- **边下边播**：将 SMB `Stream<Uint8List>` 后台写入临时文件，同时允许播放器读取
- **预分配空间**：根据文件大小预先分配磁盘空间，减少碎片
- **缓冲策略**：播放前等待最小缓存量（默认 5MB 或文件的 10%）
- **进度跟踪**：实时跟踪下载进度
- **自动清理**：播放结束后自动清理临时文件

#### 关键方法：

```dart
// 开始流式缓存
Future<String> startStreamCache({
  required Stream<Uint8List> stream,
  required String fileName,
  required int fileSize,
})

// 等待最小缓存
Future<void> waitForMinimumCache(String cachePath, {int minBytes = 5 * 1024 * 1024})

// 停止并清理缓存
Future<void> stopCache(String cachePath, {bool deleteFile = true})

// 清理所有缓存
Future<void> clearAllCache()
```

### 2. 播放流程修改 (`browser_page.dart`)

修改 `_playVideo` 方法：

**之前（HTTP 代理）**：
```dart
final httpUrl = _httpService.getFileUrlLocalhost(file.path);
Navigator.push(..., MPVPlayer(filePath: httpUrl));
```

**现在（直接流式缓存）**：
```dart
// 1. 获取 SMB 文件流
final stream = await _fileService.getFileStream(file.path);

// 2. 开始流式缓存到临时文件
final cachePath = await _cacheService.startStreamCache(
  stream: stream,
  fileName: file.name,
  fileSize: file.size,
);

// 3. 等待最小缓存（智能计算）
final minCache = (file.size * 0.1).toInt().clamp(2MB, 10MB);
await _cacheService.waitForMinimumCache(cachePath, minBytes: minCache);

// 4. 播放本地缓存文件
Navigator.push(..., MPVPlayer(filePath: cachePath))
  .then((_) {
    // 5. 播放结束后清理
    _cacheService.stopCache(cachePath, deleteFile: true);
  });
```

### 3. 缓存位置

临时缓存文件存储在：
```
/storage/Users/currentUser/Download/com.aloereed.aloeplayer/StreamCache/
```

文件命名格式：`{timestamp}_{filename}.{ext}`

## 性能优势

### 相比 HTTP 代理：

1. **零网络延迟**：直接读取本地文件，无 HTTP 往返
2. **原生 Range 支持**：文件系统原生支持 seek 操作，无需额外实现
3. **减少 CPU 开销**：无需 HTTP 协议处理
4. **更好的缓存控制**：可以自定义缓冲策略和预读取量
5. **播放流畅度**：播放器可以直接使用文件系统的缓存机制

### 缓冲策略：

- **小文件（< 20MB）**：等待 2MB 缓存
- **中等文件（20MB - 100MB）**：等待文件大小的 10%
- **大文件（> 100MB）**：最多等待 10MB 缓存

这样可以快速开始播放，同时保证足够的缓冲。

## 使用示例

### 播放 SMB 视频：

```dart
// 在 browser_page.dart 中
await _playVideo(file);  // 自动使用流式缓存

// 内部流程：
// 1. 显示"准备播放..."对话框
// 2. 从 SMB 获取 Stream
// 3. 后台写入临时文件
// 4. 等待初始缓存
// 5. 开始播放
// 6. 后台继续下载
// 7. 播放结束后自动清理
```

### 手动管理缓存：

```dart
final cacheService = StreamCacheService.instance;

// 开始缓存
final cachePath = await cacheService.startStreamCache(
  stream: smbStream,
  fileName: 'video.mp4',
  fileSize: 1024 * 1024 * 100, // 100MB
);

// 等待 10MB 缓存
await cacheService.waitForMinimumCache(cachePath, minBytes: 10 * 1024 * 1024);

// 播放
player.open(Media(cachePath));

// 清理（保留文件）
await cacheService.stopCache(cachePath, deleteFile: false);

// 或者清理所有缓存
await cacheService.clearAllCache();
```

## 注意事项

1. **磁盘空间**：确保有足够的磁盘空间存储临时文件
2. **自动清理**：播放结束后会自动删除临时文件，但如果应用异常退出可能留下残留文件
3. **并发限制**：同时播放多个文件会创建多个缓存任务，需要注意资源管理
4. **错误处理**：网络中断或 SMB 连接断开会自动停止缓存任务

## 未来优化

1. **智能缓存复用**：同一文件再次播放时可以复用之前的缓存
2. **断点续传**：支持暂停和恢复下载
3. **多线程下载**：分块并行下载提高速度
4. **LRU 缓存策略**：保留最近播放的文件缓存
5. **预读取优化**：根据播放进度动态调整下载速度

## 测试建议

1. **小文件测试**（< 50MB）：验证快速启动
2. **大文件测试**（> 1GB）：验证边下边播和进度跟踪
3. **网络波动测试**：测试 SMB 连接不稳定情况
4. **快进快退测试**：验证 seek 操作的流畅度
5. **多文件切换**：测试缓存清理和资源管理

## 总结

通过直接使用 SMB Stream 写入临时文件，我们：
- ✅ 消除了 HTTP 代理的性能瓶颈
- ✅ 实现了真正的边下边播
- ✅ 提供了更流畅的播放体验
- ✅ 保留了原有的所有播放功能（seek、暂停、倍速等）
