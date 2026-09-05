# 第二轮无人值守改进（2026-09-06）

本轮从 03:12 左右开始。保留现有本地文件复制逻辑，只优化说明和入口。
无实机：构建、静态检查和自动测试不能替代实际视频、GPU、画中画验证。

## 17 — 缩略图可靠性

- 修复 OHOS 缩略图插件未关闭文件描述符、未释放 PixelMap / ImagePacker 的资源泄漏；错误只返回一次。
- 插件修复源码纳入仓库，由构建脚本复制到隔离的插件 staging 目录，不依赖手工修改缓存。
- 缓存读写失败不再吞掉正常解码结果；快捷方式的 provider URI 不强制转换成 Dart 本地 URI。
- 解码失败时兼容旧 basename 缓存，仅当缓存不早于源文件且整个库内文件名唯一时使用；保留旧文件，不使用旧的永久失败标记。
- 三项新增测试通过；HAP 构建成功，canonical unsigned HAP 时间已验证。
- 实机重点：已有视频、重名视频、快捷方式，连续滚动大量缩略图后返回旧目录。

## 18 — 原生画中画承载页

- 移除 Flutter 纹理平台视图内嵌 Surface 的链路，使用独立 ArkUI 页面和 XComponentController.onSurfaceCreated。
- 解码准备完成后自动开启画中画；原生 30 秒 / Flutter 35 秒等待上限，显示失败阶段并支持返回原播放器。
- 独立 UIAbilityContext 创建 PiP，保留 HTTP 认证头、播放进度、系统控制与定时停止联动。
- 释放过程串行且可重复调用；取文件期间关闭页面会关闭迟到的文件句柄。
- 两项页面测试通过：返回最新进度和暂停状态；缺少回调时退出无限加载状态。HAP 编译通过并校验产物时间。
- 实机重点：本地 MP4 / MKV、网络视频，自动开启、悬浮窗暂停、返回、重复进入；原生 AVPlayer 不支持的编码应报错后返回 mpv。
- 参考：[官方 PiP API](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/js-apis-pipwindow)；Surface 生命周期依据本机 SDK xcomponent.d.ts。
