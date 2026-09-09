# 投屏改进目标（2026-09-09，3 小时）

目标：播放页内提供投屏入口，修复当前设备发现、媒体投送和控制失败，优化投屏页面并保留可回退安装包。不得访问用户鸿蒙设备。

## 里程碑计划

1. 68：修复 SSDP、描述 URL 解析、SOAP 控制和错误处理，用本机模拟接收端验证。
2. 69：整合本地文件、网络视频与 SMB/WebDAV 播放地址的投送，处理网卡选择、Range、会话与断开生命周期。
3. 70：播放页投屏入口、设备选择和远程控制页面，保留系统投播入口并修正其阻塞或竞态问题。
4. 根据验证结果补充稳定性修复；完整回归、HAP/APP 归档、哈希与来源提交核验。

## 已确认问题

- HTTP URL 被 File() 处理；第一张网卡可能是 VPN 或不通向电视的接口。
- 发现使用全局 socket/map、没有等待设备描述请求结束；IPv6 初始化异常可破坏 IPv4 发现。
- 设备服务强依赖 SCPD 完整性和固定 serviceId；SOAP 的命名空间前缀、空响应和错误未可靠解析。
- 页面使用 async initState，离开页面后仍 setState，关闭页面直接关闭 HTTP 服务导致电视断流。
- 现有说明宣称必须有 URLBase；实际应按描述文档地址解析相对控制路径。

验证依据：[UPnP 设备架构](https://openconnectivity.org/developer/specifications/upnp-resources/upnp/)、[AVTransport 规范](https://upnp.org/specs/av/UPnP-av-AVTransport-v3-Service.pdf)。本机测试不冒充真实电视或鸿蒙设备验收。
