# SMB Service 迁移指南

## 概述

`lib/services/smb_service.dart` 已从使用 `smb_connect` 包迁移到使用原生 `libsmb2.so` FFI 实现。

## 迁移详情

### 改动范围

✅ **已完成的迁移:**

1. **lib/services/smb_service.dart** - 已完全重写，使用 `Libsmb2Service` 作为底层实现
2. **适配器层** - 创建了 `SmbFileAdapter` 来桥接 `Libsmb2File` 和 `SmbFile` 接口
3. **向后兼容** - 所有现有代码无需修改，API 保持不变

### 架构变化

#### 之前的实现:
```
SmbService (lib/services/smb_service.dart)
    ↓
SmbConnect (smb_connect package)
```

#### 现在的实现:
```
SmbService (lib/services/smb_service.dart)
    ↓
Libsmb2Service (lib/libsmb2_service/libsmb2_service.dart)
    ↓
Libsmb2Bindings (lib/libsmb2_service/libsmb2_bindings.dart)
    ↓
libsmb2.so (Native FFI)
```

### 文件结构

```
lib/
├── services/
│   ├── smb_service.dart           # 更新: 现在使用 Libsmb2Service
│   ├── smb_service.dart.backup    # 备份: 原来的实现
│   ├── file_service.dart          # 无需修改
│   └── http_service.dart          # 无需修改
└── libsmb2_service/
    ├── libsmb2_bindings.dart      # 新: FFI 绑定
    ├── libsmb2_service.dart       # 新: 核心服务实现
    ├── libsmb2_file.dart          # 新: 文件信息类
    ├── smb_file_adapter.dart      # 新: SmbFile 适配器
    ├── libsmb2_service_lib.dart   # 新: 库导出
    ├── README.md                  # 新: 文档
    └── example.dart               # 新: 使用示例
```

## API 兼容性

### ✅ 完全兼容的方法

所有现有的 API 都保持不变，包括:

- `connect()` - 连接到 SMB 服务器
- `disconnect()` - 断开连接
- `listFiles()` - 列出文件
- `getFileStream()` - 获取文件流
- `getFile()` - 获取文件信息
- `saveCredentials()` - 保存凭据
- `getSavedCredentials()` - 读取凭据
- `isConnected` - 连接状态

### 使用的文件

以下文件使用 `SmbService`，**无需修改**:

1. ✅ **lib/services/file_service.dart** - 通过 `SmbFileService` 使用
2. ✅ **lib/services/http_service.dart** - 通过 `setSmbService()` 使用
3. ✅ **lib/smb_browser_page.dart** - 直接使用 `SmbService`

## 部署要求

### 必需的依赖

在 `pubspec.yaml` 中确保有以下依赖:

```yaml
dependencies:
  ffi: any  # FFI 支持
  smb_connect: ^0.0.9  # 保留用于 SmbFile 类型定义
  shared_preferences: any
```

### 原生库要求

需要在目标平台上提供 `libsmb2` 库:

- **Linux/Android**: `libsmb2.so`
- **macOS**: `libsmb2.dylib`
- **Windows**: `libsmb2.dll`

#### 编译 libsmb2

如果需要自行编译:

```bash
cd libsmb2
./bootstrap
./configure
make
sudo make install
```

对于 Android/鸿蒙OS，可能需要交叉编译。

## 优势

### 🚀 性能提升
- 直接使用原生库，减少中间层开销
- 更高效的内存管理
- 更快的文件传输速度

### 🔧 更好的控制
- 直接访问 libsmb2 的所有功能
- 可以自定义连接参数
- 更细粒度的错误处理

### 🌐 跨平台支持
- 支持 Linux、macOS、Windows
- 为 Android 和鸿蒙OS 提供基础

## 回滚方案

如果需要回滚到原来的实现:

```bash
# 恢复备份文件
cp lib/services/smb_service.dart.backup lib/services/smb_service.dart
```

## 测试清单

在部署到生产环境之前，请测试以下功能:

- [ ] SMB 连接和认证
- [ ] 列出目录内容
- [ ] 读取文件流
- [ ] 获取文件信息
- [ ] HTTP 代理服务
- [ ] 保存和读取凭据
- [ ] 错误处理

## 故障排除

### 问题: 找不到 libsmb2.so

**解决方案:**
1. 确保已安装 libsmb2 库
2. 检查库路径是否在系统 LD_LIBRARY_PATH 中
3. 对于 Android，确保 .so 文件在 APK 的 lib 目录中

### 问题: FFI 绑定错误

**解决方案:**
1. 确认 libsmb2 版本兼容性
2. 检查函数签名是否匹配
3. 查看 libsmb2_bindings.dart 中的类型定义

### 问题: 性能问题

**解决方案:**
1. 调整读取缓冲区大小（当前为 64KB）
2. 检查网络连接质量
3. 考虑启用 SMB3 加密/签名

## 联系和支持

如有问题或需要帮助，请:

1. 查看 `lib/libsmb2_service/README.md`
2. 查看 `lib/libsmb2_service/example.dart` 示例代码
3. 查看 libsmb2 官方文档

## 更新日志

### 2025-12-06
- ✅ 创建 libsmb2_service 包装器
- ✅ 实现 SmbFileAdapter 适配器
- ✅ 更新 smb_service.dart 使用新实现
- ✅ 确保向后兼容
- ✅ 创建文档和示例
