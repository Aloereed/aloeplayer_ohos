# HTTP服务修复说明

## 问题诊断

访问SMB转HTTP服务时出现`ERR_INVALID_RESPONSE`错误，原因如下：

### 1. 未正确处理Future
**问题**: 第136行的`getFileStream()`返回`Future<Stream<Uint8List>>`，但没有await
```dart
// 错误代码
final stream = _smbService.getFileStream(filePath);
```

**修复**: 添加await
```dart
// 修复后
final stream = await _smbService!.getFileStream(filePath);
```

### 2. Range请求字节处理错误
**问题**: 使用Stream的`.skip()`和`.take()`处理字节范围，但这些方法操作的是块数量而非字节数
```dart
// 错误代码
final stream = (await _smbService.getFileStream(file.path))
    .skip(start)
    .take(contentLength);
```

**修复**: 使用StreamTransformer正确处理字节级别的范围请求
```dart
final rangeStream = sourceStream.transform(
  StreamTransformer<Uint8List, Uint8List>.fromHandlers(
    handleData: (chunk, sink) {
      // 正确跳过和提取字节
      if (bytesToSkip > 0) { /* ... */ }
      if (bytesToSend > 0) { /* ... */ }
    },
  ),
);
```

### 3. SMB服务实例未共享
**问题**: HttpService创建了自己的SmbService实例，但该实例未连接到SMB服务器
```dart
// 错误代码
final SmbService _smbService = SmbService();
```

**修复**: HttpService接受外部SmbService实例
```dart
SmbService? _smbService;

void setSmbService(SmbService service) {
  _smbService = service;
}
```

## 修复的文件

### 1. `lib/services/http_service.dart`
- 将`_smbService`改为可空类型
- 添加`setSmbService()`方法接受外部实例
- 修复`_handleFileRequest()`中的await问题
- 完全重写`_handleRangeRequest()`使用StreamTransformer
- 更新所有使用`_smbService`的地方进行null检查

### 2. `lib/pages/smb_browser_page_new.dart`
- 在`_connectAndLoad()`中连接成功后调用`_httpService.setSmbService(_smbService)`

### 3. `lib/smb_browser_page.dart`
- 在`_connectSmb()`中连接成功后调用`_httpService.setSmbService(_smbService)`

## 工作流程

1. 用户在浏览器页面连接到SMB服务器
2. 连接成功后，将SmbService实例传递给HttpService
3. HttpService使用该实例读取SMB文件
4. 当播放器请求HTTP URL时，HttpService从SMB读取文件流并返回

## Range请求的正确处理

新的实现正确处理了字节级别的范围请求：

1. **跳过字节**: 正确跳过前面的字节，可能跨越多个块
2. **提取字节**: 精确提取所需的字节数
3. **部分块处理**: 可以正确处理起始或结束位置在块中间的情况

这对于视频播放器的seek操作和断点续传至关重要。

## 测试建议

1. **基本播放**: 点击视频文件测试是否能正常播放
2. **Seek操作**: 在播放过程中拖动进度条测试Range请求
3. **大文件**: 测试大于1GB的视频文件
4. **网络切换**: 测试在localhost和局域网IP之间切换
5. **多种格式**: 测试mp4, mkv, avi等不同格式

## 已知限制

1. **单实例**: 同时只能连接一个SMB服务器（因为HttpService是单例）
2. **性能**: 对于大文件的Range请求，需要读取并跳过前面的所有字节
3. **并发**: 多个客户端同时请求同一文件可能影响性能

## 未来改进建议

1. **缓存**: 添加文件块缓存，提高重复访问性能
2. **连接池**: 支持同时连接多个SMB服务器
3. **预加载**: 实现智能预加载机制
4. **压缩**: 对非视频文件支持gzip压缩传输
