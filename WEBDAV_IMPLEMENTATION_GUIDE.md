# WebDAV 支持实现指南

## 概述
成功为播放器添加了 WebDAV 支持，现在可以通过 SMB 或 WebDAV 协议访问媒体文件并实现转 HTTP 播放。

## 新增文件

### 1. 数据模型
- **`lib/models/server_config.dart`** - 统一的服务器配置模型
  - 支持 SMB 和 WebDAV 两种服务器类型
  - 包含 WebDAV 特有字段（port, useHttps）
  - 提供 `webdavUrl` 属性生成完整的 WebDAV URL

### 2. 服务层
- **`lib/services/webdav_service.dart`** - WebDAV 客户端实现
  - 使用 `dio` 库实现 WebDAV 协议
  - 支持 PROPFIND 列出目录
  - 支持流式读取文件（getFileStream）
  - 支持 Range 请求（断点续传）
  - 正确处理中文文件名和路径

- **`lib/services/file_service.dart`** - 文件系统抽象层
  - 统一的 `FileItem` 接口
  - `SmbFileService` - SMB 文件服务包装器
  - `WebDavFileService` - WebDAV 文件服务包装器
  - `FileServiceFactory` - 服务工厂

- **`lib/services/server_config_service.dart`** - 服务器配置管理
  - 替代原来的 `smb_config_service.dart`
  - 支持多种服务器类型
  - 使用 SharedPreferences 存储配置

### 3. UI 层
- **`lib/pages/servers_page.dart`** - 统一的服务器管理页面
  - 替代原来的 `smb_servers_page.dart`
  - 支持添加/编辑/删除 SMB 和 WebDAV 服务器
  - 服务器类型可视化区分（SMB 蓝色，WebDAV 紫色）
  - 支持 WebDAV 特有配置（端口、HTTPS）

- **`lib/pages/browser_page.dart`** - 统一的文件浏览器页面
  - 替代原来的 `smb_browser_page_new.dart`
  - 统一的界面支持 SMB 和 WebDAV
  - 列表/网格视图切换
  - 搜索、排序功能
  - 视频文件直接播放

## 修改的文件

### 1. HTTP 服务
**`lib/services/http_service.dart`**
- 添加 `_webdavService` 支持
- 新增 `setWebDavService()` 方法
- 重构文件请求处理:
  - `_handleFileRequest()` - 统一入口
  - `_handleSmbFileRequest()` - SMB 文件处理
  - `_handleWebDavFileRequest()` - WebDAV 文件处理
  - `_handleSmbRangeRequest()` - SMB Range 请求
  - `_handleWebDavRangeRequest()` - WebDAV Range 请求
- 更新状态和文件信息请求支持 WebDAV

## 使用方法

### 1. 添加 WebDAV 服务器
1. 打开应用，进入服务器管理页面
2. 点击"添加服务器"按钮
3. 选择 "WebDAV" 类型
4. 填写配置信息:
   - 服务器名称: 例如 "我的 WebDAV"
   - 主机地址: 例如 "nas.example.com" 或 "192.168.1.100"
   - 端口（可选）: 例如 80 或 443
   - HTTPS: 根据需要开启
   - 用户名: WebDAV 用户名
   - 密码: WebDAV 密码
   - 初始路径: 例如 "/" 或 "/media"
5. 保存配置

### 2. 浏览和播放
1. 点击服务器卡片连接
2. 浏览文件夹和文件
3. 点击视频文件直接播放
4. 长按文件显示更多选项（复制链接等）

## 技术细节

### WebDAV 协议实现
- **PROPFIND** - 列出目录内容
  - Depth: 1 获取子项
  - Depth: 0 获取单个文件信息
  - XML 响应解析

- **GET with Range** - 流式读取文件
  - 支持 Range 头实现断点续传
  - 适用于视频播放

### 文件流处理
- SMB: 使用 `smb_connect` 库的流式API
- WebDAV: 使用 `dio` 的 ResponseType.stream
- HTTP 服务: 统一转换为 HTTP Range 请求

### 中文文件名处理
- URL 编码/解码
- XML 中的 displayname 字段
- Content-Disposition 头使用 RFC 5987 格式

## 依赖项
已存在于 pubspec.yaml:
- `dio` - HTTP 客户端
- `xml` - XML 解析

## 迁移建议

如果您之前使用了 `smb_servers_page.dart` 或 `smb_browser_page_new.dart`，建议:

1. 更新导入路径为新的页面:
   ```dart
   import 'package:aloeplayer/pages/servers_page.dart';
   import 'package:aloeplayer/pages/browser_page.dart';
   ```

2. 现有的 SMB 配置可以通过数据迁移保留，但需要添加 `type` 字段。

## 下一步

1. 测试 WebDAV 连接和文件浏览
2. 测试视频播放功能
3. 根据需要添加更多 WebDAV 特性（上传、删除等）
4. 优化性能和用户体验

## 注意事项

- WebDAV 服务器必须支持基本认证（Basic Auth）
- 确保 WebDAV 服务器支持 Range 请求以实现流式播放
- HTTPS 连接需要有效的 SSL 证书（或在开发中接受自签名证书）
- 某些 WebDAV 服务器可能有并发连接限制
