# Anime4K 会员超分

播放器“超分与画质”新增带钻石徽标的 **Anime4K · 动漫**；“动漫”预设也使用该方案。适用对象是 SDR 动漫，默认不自动启用。会员或主动开启的本机体验可用，不收紧原有免费 FSR 均衡及普通播放能力。

## 来源与执行

- 使用 [bloc97/Anime4K](https://github.com/bloc97/Anime4K) v4.0.1，固定提交 `4029bf701ecaa15f163cdc49cffe5501c1acf410`。
- 按上游 [Mode A（Fast）模板](https://github.com/bloc97/Anime4K/blob/master/md/Template/GLSL_Windows_Low-end/input.conf) 加载 6 个着色器，保留原始内容与 MIT 许可。
- 文件随 HAP 离线提供；内置 SHA-256 校验，已有缓存校验失败时从包内恢复。依次加载：高光去振铃 → Restore CNN M → Upscale CNN x2 M → AutoDownscalePre x2 / x4 → Upscale CNN x2 S。
- 每边最多 2 倍，输出最大 3840×2160（竖屏对应交换）。上游超分阶段要求放大比例超过 1.2 倍，不满足时跳过并显示说明；“Anime4K”名称不意味着任何片源都固定输出 4K。
- HDR / RGB 回退高清缩放；与 FSR 互斥切换，不叠加上一套着色器。关闭后恢复初始渲染状态。系统画中画不继承本效果。
- 会员到期不强行中断正在播放的画质；下次初始化使用免费高清缩放，保留原来的设置。新版本不会把 Anime4K 误当成升级前的免费权益。
- 文件加载、参数设置或 GPU 着色器出错时回退默认画质，防止失败预设反复加载。

## 日志

前缀 `[AloeAnime4K]`；既有 `tool/capture_fsr_logs.ps1` 现在会同时抓取 FSR 与 Anime4K。切换后第 1 秒、第 4 秒及再次打开面板时采样。

- `shader_asset_ready`：6 个包内文件准备完成，尚不能证明 GPU 执行。
- `anime4kShaderFiles`：播放器当前着色器列表内的 Anime4K 文件名。
- `anime4kExpected`：当前尺寸和片源是否应执行 Anime4K。
- `anime4kEvidence=restore_upscale_timed`：找到了 Restore M 最终输出及 Upscale M Depth-to-Space 阶段，并具有正的执行时间和采样数量。
- `anime4kPassGroups`：clamp / restore / upscale / downscale 各组的阶段数、计时阶段数与最近耗时之和。
- `partial_or_untimed`、`not_observed`、`unavailable`：证据不完整、此次未观察到或后端无法提供；不冒充成功。

在同一 session / revision 内结合着色器列表、实际纹理尺寸和阶段耗时判断。本版不承诺某台手机的帧率或功耗；真实画质、发热与 GPU 执行证据仍需设备播放验证。

## 验证

23 项相关回归通过，包含固定版本着色器校验、会员拦截、2 倍 / 4K 限制、HDR / RGB 跳过、FSR ↔ Anime4K 切换不叠加、损坏组合回退及诊断证据分类。

`3.1.1+193` Release HAP 构建通过，标准未签名包时间戳已核对为 `2026-09-06T16:38:21.4074791+08:00`；已检查包内包含 6 个 GLSL 文件、许可和清单。已使用 SDK 保留数据覆盖安装并启动，设备版本为 193。日志见 `build/anime4k-tests.log`、`build/anime4k-build.log`、`build/anime4k-v193-deploy.log`。本次未宣称实际 GPU 渲染已验证，需选择 Anime4K 播放后抓取日志。
