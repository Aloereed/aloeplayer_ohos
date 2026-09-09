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

## 68 — 首批完整投屏修复（4.0.1+221）

为满足先交付上架包的时间要求，本阶段合并协议、媒体转发与主播放页入口，后续继续完善系统投播及兼容边界。

- MPV 视频播放页（手机/桌面）及 MPV 音乐页新增投屏按钮；接收端开始播放成功后才暂停本机播放。
- 修正 AVTransport 和 RenderingControl 默认 InstanceID：1 → 0；兼容带前缀 XML、厂商 serviceId、不同服务版本、缺失 URLBase/SCPD、相对或绝对控制地址和空成功响应。
- SSDP 每次扫描独立 socket/map，按网络接口搜索并重试，去重并有界读取描述；等待接近扫描结束时收到的设备描述。单个接口失败不会终止全部发现。
- 普通 HTTP/HTTPS 直链直接投送；本地文件、带请求头的网络文件、SMB/WebDAV 的本机播放链接通过临时令牌局域网地址供电视读取。根据到电视的实际路由选择本机地址。提供 HEAD/Range、MIME 和 DLNA 流式响应头。
- 投屏页面重做为主题自适应列表，提供手动描述地址添加、错误复制、播放/暂停/停止/断开、进度拖动、音量控制及两秒状态刷新。返回页面不会销毁投屏文件服务。
- 保留鸿蒙系统投播入口，改为用户主动展开；系统原生链路仍在后续专项验证范围内。
- 全量 Flutter 测试 214 项通过、默认跳过 2 项显式 SMB 回环。新增真实本机 UDP/HTTP 模拟接收端验证，另验证 320px 深色界面；无真机、电视或上架验证。
- 本阶段不承诺电视支持原视频编码，不进行转码；带鉴权的多级 HLS、系统投播生命周期及部分非 MPV 旧播放页入口在后续继续完善。

安装包：`build/milestones/68-casting-first-release/`；release 签名 APP 和对应 HAP、源码 commit、哈希、构建时间见 manifest.json。

补充：68 的首批 APP 构建只保留了 release 签名 HAP。10:07 从同一源码提交补建 `entry-debug-signed.hap` 和 `entry-debug-unsigned.hap`，保留所有原产物及其哈希。这里 debug 指项目调试签名配置，Flutter 编译仍为 release。部署脚本优先选择独立 debug 签名 HAP；已通过 `-DryRun` 核验，未连接设备。后续里程碑同样分别保留 debug 签名 HAP 和 release APP。
