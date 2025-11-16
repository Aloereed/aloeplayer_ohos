# HTTP服务URL编码修复

## 问题描述

当SMB文件名包含中文、空格或特殊字符时，HTTP服务无法正确处理请求，导致：
- 404 文件不存在错误
- 播放器无法加载视频
- 文件信息查询失败

## 根本原因

1. **URL编码问题**: 浏览器和HTTP客户端会自动对URL进行编码（例如：`中文.mp4` → `%E4%B8%AD%E6%96%87.mp4`）
2. **解码缺失**: HTTP服务接收到编码后的路径，但没有解码就直接用于访问SMB文件
3. **编码缺失**: 生成URL时没有对路径进行编码

## 示例场景

**文件路径**: `/Movies/功夫熊猫 (2008).mp4`

### 修复前:
```
生成URL: http://192.168.1.100:8080/file/Movies/功夫熊猫 (2008).mp4
浏览器编码: http://192.168.1.100:8080/file/Movies/%E5%8A%9F%E5%A4%AB%E7%86%8A%E7%8C%AB%20(2008).mp4
服务器接收: /Movies/%E5%8A%9F%E5%A4%AB%E7%86%8A%E7%8C%AB%20(2008).mp4
尝试访问SMB: /Movies/%E5%8A%9F%E5%A4%AB%E7%86%8A%E7%8C%AB%20(2008).mp4  ❌ 文件不存在
```

### 修复后:
```
生成URL: http://192.168.1.100:8080/file/Movies/%E5%8A%9F%E5%A4%AB%E7%86%8A%E7%8C%AB%20(2008).mp4
服务器接收: /Movies/%E5%8A%9F%E5%A4%AB%E7%86%8A%E7%8C%AB%20(2008).mp4
URL解码: /Movies/功夫熊猫 (2008).mp4
尝试访问SMB: /Movies/功夫熊猫 (2008).mp4  ✅ 成功
```

## 修复详情

### 1. `_handleFileRequest()` - 文件请求处理

**修复前**:
```dart
final filePath = '/${request.params['path']}';
```

**修复后**:
```dart
// 获取并解码URL路径（处理中文和特殊字符）
final encodedPath = request.params['path'] ?? '';
final decodedPath = Uri.decodeComponent(encodedPath);
final filePath = '/$decodedPath';

print('请求文件: $filePath');
```

**改进**:
- 使用`Uri.decodeComponent()`解码URL编码
- 添加null检查
- 添加调试日志
- 在Content-Type中添加charset=utf-8
- 添加Content-Disposition头支持中文文件名下载

### 2. `_handleFileInfoRequest()` - 文件信息请求

**修复前**:
```dart
final filePath = '/${request.params['path']}';
```

**修复后**:
```dart
// 获取并解码URL路径（处理中文和特殊字符）
final encodedPath = request.params['path'] ?? '';
final decodedPath = Uri.decodeComponent(encodedPath);
final filePath = '/$decodedPath';
```

**改进**:
- 同样添加URL解码
- Content-Type添加charset=utf-8

### 3. `getFileUrl()` - URL生成

**修复前**:
```dart
String getFileUrl(String smbPath) {
  final cleanPath = smbPath.startsWith('/') ? smbPath.substring(1) : smbPath;
  return '$baseUrl/file/$cleanPath';
}
```

**修复后**:
```dart
String getFileUrl(String smbPath) {
  final cleanPath = smbPath.startsWith('/') ? smbPath.substring(1) : smbPath;

  // 对路径的每个部分分别进行URL编码，保留路径分隔符
  final pathSegments = cleanPath.split('/');
  final encodedSegments = pathSegments.map((segment) =>
    Uri.encodeComponent(segment)
  ).toList();
  final encodedPath = encodedSegments.join('/');

  return '$baseUrl/file/$encodedPath';
}
```

**改进**:
- 分段编码：对每个路径段分别编码，保留路径分隔符
- 避免将"/"也编码成"%2F"

## 支持的特殊字符

修复后，以下字符都能正确处理：

### 1. 中文字符
```
文件名: 电影/功夫熊猫.mp4
编码后: %E7%94%B5%E5%BD%B1/%E5%8A%9F%E5%A4%AB%E7%86%8A%E7%8C%AB.mp4
```

### 2. 日韩文字符
```
文件名: 映画/名探偵コナン.mp4
编码后: %E6%98%A0%E7%94%BB/%E5%90%8D%E6%8E%A2%E5%81%B5%E3%82%B3%E3%83%8A%E3%83%B3.mp4
```

### 3. 空格
```
文件名: My Video.mp4
编码后: My%20Video.mp4
```

### 4. 特殊符号
```
文件名: (2008) #1.mp4
编码后: (2008)%20%231.mp4
```

### 5. 括号和其他符号
```
文件名: [1080P] 电影 (2008) - 导演剪辑版.mp4
编码后: %5B1080P%5D%20%E7%94%B5%E5%BD%B1%20(2008)%20-%20%E5%AF%BC%E6%BC%94%E5%89%AA%E8%BE%91%E7%89%88.mp4
```

## Content-Disposition头支持

新增的Content-Disposition头遵循RFC 5987标准：
```http
Content-Disposition: inline; filename*=UTF-8''%E4%B8%AD%E6%96%87.mp4
```

这确保：
- 浏览器正确显示中文文件名
- 下载时保持正确的文件名
- 兼容现代浏览器

## 测试用例

### 测试1: 纯中文文件名
```
文件: /测试视频.mp4
预期: 正常播放
```

### 测试2: 中文+英文+空格
```
文件: /Movies/功夫熊猫 Kung Fu Panda.mp4
预期: 正常播放
```

### 测试3: 特殊字符
```
文件: /[2008] 电影 (HD) #1.mp4
预期: 正常播放
```

### 测试4: 嵌套目录
```
文件: /电影/动作片/功夫熊猫/功夫熊猫 (2008).mp4
预期: 正常播放
```

### 测试5: URL保留字符
```
文件: /Q&A Session.mp4
预期: 正常播放（&会被编码为%26）
```

## 技术细节

### URL编码规则

使用`Uri.encodeComponent()`进行编码，遵循RFC 3986标准：
- 保留字符（Reserved）：`:/?#[]@!$&'()*+,;=` → 必须编码
- 非保留字符（Unreserved）：`A-Za-z0-9-._~` → 不编码
- 其他字符：UTF-8编码后转为百分号编码

### 解码过程

使用`Uri.decodeComponent()`进行解码：
- 将百分号编码转回原始字符
- 自动处理UTF-8编码
- 处理多字节字符

## 向后兼容性

✅ 完全向后兼容：
- 纯英文文件名：无影响
- 已编码的URL：正确解码
- 未编码的URL：保持原样

## 性能影响

最小：
- 编码/解码操作非常快（微秒级）
- 对大文件流传输无影响
- 只在URL处理时执行一次

## 调试建议

如果遇到问题，检查控制台输出：
```dart
print('请求文件: $filePath');  // 已添加到代码中
```

输出示例：
```
请求文件: /Movies/功夫熊猫 (2008).mp4
```

如果看到乱码或编码字符，说明解码失败。

## 常见问题

### Q: 为什么不对整个路径编码？
A: 因为路径分隔符"/"也会被编码成"%2F"，导致路径解析错误。必须分段编码。

### Q: Uri.encodeComponent vs Uri.encodeFull?
A:
- `Uri.encodeComponent()`: 编码所有特殊字符（用于路径段）✅
- `Uri.encodeFull()`: 不编码URL保留字符如"/"（不适合我们的场景）❌

### Q: 为什么需要在两端都处理？
A:
- **生成URL时编码**: 确保URL格式正确
- **接收请求时解码**: 将编码还原为原始文件名

## 总结

通过正确的URL编码/解码处理，HTTP服务现在可以：
✅ 支持中文文件名
✅ 支持特殊字符
✅ 支持空格和各种符号
✅ 保持路径分隔符正确
✅ 兼容所有现代浏览器和HTTP客户端

这是Web服务的基本要求，现在已经完全实现。
