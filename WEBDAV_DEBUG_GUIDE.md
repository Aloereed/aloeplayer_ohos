# WebDAV 调试指南

## 问题：连接成功但没有显示文件

### 调试步骤

1. **查看控制台日志**
   - 打开应用的调试控制台
   - 连接到 WebDAV 服务器
   - 查看详细的调试输出

2. **关键日志信息**

   连接阶段：
   ```
   WebDAV 连接到: http://your-server
   用户名: xxx
   测试连接响应状态码: 207
   ```

   文件列表阶段：
   ```
   WebDAV PROPFIND 响应状态码: 207
   WebDAV PROPFIND 响应数据: <xml...>
   开始解析 XML 响应...
   找到 X 个 response 元素
   处理文件 href: ...
   最终解析到 X 个文件
   ```

3. **常见问题排查**

   **问题 1: 找不到 response 元素**
   - 检查 XML 响应数据的格式
   - 可能使用了不同的命名空间

   **问题 2: 所有文件都被跳过**
   - 查看 "路径相同，跳过" 日志
   - 可能是路径规范化问题

   **问题 3: XML 解析失败**
   - 查看 "解析文件条目失败" 日志
   - 可能是 WebDAV 服务器返回格式不标准

4. **提供调试信息**

   如果问题仍未解决，请提供：
   - 完整的控制台日志
   - WebDAV 服务器类型（Nextcloud、ownCloud、Synology 等）
   - WebDAV URL 格式

## 临时解决方案

如果您使用的是 Nextcloud/ownCloud：
- 确保 URL 格式正确: `http://server/remote.php/dav/files/username/`
- 或使用简化格式: `http://server/remote.php/webdav/`

如果您使用的是 Synology NAS：
- URL 格式: `http://server:5005/`
- 可能需要启用 WebDAV 服务

## 下一步优化

基于调试日志，我们可以：
1. 调整 XML 解析策略
2. 优化路径处理
3. 添加特定服务器的兼容性支持
