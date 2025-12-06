# Libsmb2 Service

Flutter FFI 包装器，用于调用 libsmb2.so 实现 SMB 文件共享访问。

## 概述

此库提供了与 `smb_service.dart` 兼容的接口，但使用原生的 libsmb2 库而不是 `smb_connect` 包。这样可以获得更好的性能和更直接的控制。

## 功能特性

- ✅ SMB 连接和认证
- ✅ 列出目录内容
- ✅ 读取文件流
- ✅ 获取文件信息
- ✅ 保存和读取凭据
- ✅ 跨平台支持 (Linux, macOS, Windows)

## 文件结构

```
lib/libsmb2_service/
├── libsmb2_bindings.dart      # FFI 绑定定义
├── libsmb2_service.dart       # 主服务类
├── libsmb2_file.dart          # 文件信息类
└── libsmb2_service_lib.dart   # 库导出文件
```

## 使用方法

### 1. 添加依赖

在 `pubspec.yaml` 中添加 ffi 依赖:

```yaml
dependencies:
  ffi: ^2.0.0
  shared_preferences: any
```

### 2. 确保 libsmb2.so 可用

确保您的系统中已安装 libsmb2 库，或将编译好的库文件放在正确的位置:

- **Linux/Android**: `libsmb2.so`
- **macOS**: `libsmb2.dylib`
- **Windows**: `libsmb2.dll`

### 3. 基本使用示例

```dart
import 'package:aloeplayer/libsmb2_service/libsmb2_service_lib.dart';

void main() async {
  final smbService = Libsmb2Service();

  try {
    // 连接到 SMB 服务器
    final connected = await smbService.connect(
      host: '//192.168.1.100/share',
      username: 'user',
      password: 'password',
      domain: 'WORKGROUP',
    );

    if (connected) {
      print('连接成功!');

      // 列出文件
      final files = await smbService.listFiles('/');
      for (final file in files) {
        print('${file.isDirectory ? "📁" : "📄"} ${file.name} (${file.size} bytes)');
      }

      // 读取文件
      final stream = await smbService.getFileStream('/test.txt');
      await for (final chunk in stream) {
        print('读取了 ${chunk.length} 字节');
      }

      // 获取文件信息
      final fileInfo = await smbService.getFile('/test.txt');
      print('文件大小: ${fileInfo.size}');
      print('修改时间: ${fileInfo.modifiedTime}');
    }
  } catch (e) {
    print('错误: $e');
  } finally {
    await smbService.disconnect();
  }
}
```

## API 参考

### Libsmb2Service

主要的 SMB 服务类。

#### 方法

- **`connect()`** - 连接到 SMB 服务器
  ```dart
  Future<bool> connect({
    required String host,      // 格式: //server/share
    required String username,
    required String password,
    required String domain,
  })
  ```

- **`disconnect()`** - 断开连接
  ```dart
  Future<void> disconnect()
  ```

- **`listFiles()`** - 列出目录内容
  ```dart
  Future<List<Libsmb2File>> listFiles(String path)
  ```

- **`getFileStream()`** - 获取文件流
  ```dart
  Future<Stream<Uint8List>> getFileStream(String filePath)
  ```

- **`getFile()`** - 获取文件信息
  ```dart
  Future<Libsmb2File> getFile(String path)
  ```

- **`saveCredentials()`** - 保存登录凭据
  ```dart
  Future<void> saveCredentials({
    required String host,
    required String username,
    required String password,
    required String domain,
  })
  ```

- **`getSavedCredentials()`** - 获取保存的凭据
  ```dart
  Future<Map<String, String>> getSavedCredentials()
  ```

### Libsmb2File

文件信息类。

#### 属性

- `String name` - 文件名
- `String path` - 完整路径
- `bool isDirectory` - 是否为目录
- `int size` - 文件大小（字节）
- `DateTime? modifiedTime` - 修改时间
- `DateTime? createdTime` - 创建时间

## 与 smb_service.dart 的差异

此库设计为与现有的 `smb_service.dart` 接口兼容，主要差异:

1. **返回类型**: 使用 `Libsmb2File` 而不是 `SmbFile`
2. **底层实现**: 直接使用 libsmb2 FFI 而不是 smb_connect 包
3. **性能**: 通常更快，因为减少了中间层

## 编译 libsmb2

如果需要自行编译 libsmb2 库:

```bash
cd libsmb2
./bootstrap
./configure
make
sudo make install
```

对于 Android 或其他平台，可能需要交叉编译。

## 注意事项

1. **线程安全**: libsmb2 不是线程安全的，确保在同一个 isolate 中使用
2. **资源管理**: 使用完毕后务必调用 `disconnect()` 释放资源
3. **错误处理**: 所有方法都可能抛出异常，请妥善处理
4. **路径格式**: 路径应使用正斜杠 `/`，如 `/folder/file.txt`

## 许可证

此包装器遵循项目的许可证。libsmb2 本身遵循 LGPL 2.1 许可证。

## 贡献

欢迎提交问题和拉取请求!
