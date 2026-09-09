# 里程碑 67：4.0.1、反馈入口与无声 HDR 定时

版本 **4.0.1+220**。归档目录 `build/milestones/67-hdr-timing-feedback/`；源码提交、包版本、时间戳和 SHA-256 见归档 manifest.json。

## 用户可见变化

- 设置页新增“进群吐槽”，通过 QQ 群名片协议拉起指定群，界面不显示群号。补齐鸿蒙 module.json5 的 `mqqapi` querySchemes；未安装或无法拉起时给出提示。
- 打开视频直链对话框新增带下划线的“测试链接”，点击替换输入内容、清除旧错误，然后使用原有“播放”按钮。仍允许编辑或粘贴自己的地址。
- 测试视频使用 `https://player.alicdn.com/video/aliyunmedia.mp4`，来源为 [阿里云官方播放器示例](https://help.aliyun.com/zh/vod/developer-reference/advanced-features-3)。当前本机网络 HEAD 返回 200，并验证 Range 请求及 MP4 文件头；公共示例的后续可用性由提供方决定。

## HDR 直出过快的根因与修复

当前项目随附的定制 MPV 0.41.0 预编译库中，`ohcodec` 和 `ohcodec-osd` 两个驱动的 caps 都为 20，即 `VO_CAP_NORETAIN | VO_CAP_UNTIMED`。播放器在没有可用音频时会因 UNTIMED 清除下一帧等待时间，导致无音轨或音频解码失败的视频快速播放。有音频时音频时钟掩盖了此问题。

清除两个驱动的 UNTIMED 位，保留 NORETAIN，恢复 MPV 按视频 PTS、播放速度及单调时钟安排帧提交。直出 Surface、HDR 色彩、硬件解码及正常音轨路径保持现有实现。源码依据：[vo.h 能力定义](https://github.com/ErBWs/mpv/blob/feat-ohos-0.41.0/video/out/vo.h)、[player/video.c 的 update_avsync_before_frame](https://github.com/ErBWs/mpv/blob/feat-ohos-0.41.0/player/video.c)、[vo.c 的 wait_until/flip_page](https://github.com/ErBWs/mpv/blob/feat-ohos-0.41.0/video/out/vo.c)。

项目携带的是包含定制驱动的预编译库，未用其他分支重建替换整个 MPV。`tool/repair_mpv_timing.ps1` 对当前库执行可复现的两个数据字节修正，未改机器指令；build.ps1 在编译前自动应用或验证。这里不是可跨版本复用的任意偏移补丁：输入与输出都锁定完整 SHA-256，未知版本立即失败，必须重新核对驱动实现。

| 项目 | 值 |
| --- | --- |
| 原库 SHA-256 | `DAECEFE473819A40EFC795D2E0CF6916BE2C830BC39CB9CCF4251F4C67194D63` |
| 修复后 SHA-256 | `7438FCC2AAC0E0BBF2F7ED7F04C286EFD2A06BC5BCB8C2212A3123FCA1F1DFF5` |
| 文件偏移 | `0x26922dc`、`0x2693144`，各 `0x14 → 0x04` |

原生测试通过 ELF RELA 重定位按驱动名称及描述独立定位 caps，确认纹理驱动未改；还检查精确字节差异、幂等、未修复库验证失败及未知库拒绝。打包后将包内 `libs/arm64-v8a/libmpv.so.2` 的所有运行时 SHF_ALLOC 段与修复后的库逐字节核验；允许 Hvigor 删除非运行时的调试/符号信息。

## 验证和部署

- Flutter 完整回归 **209 项通过、2 项显式 SMB 回环默认跳过**；直链交互和 HDR Surface/输出策略专项 5 项通过。
- 修改代码静态分析无 error；settings.dart 存在 4 项既有 warning（未使用/重复导入、冗余 null 判断、未使用字段），本轮没有扩展其范围。
- 原生补丁检查：`python tool/test_mpv_timing_patch.py`；验证包内容时在末尾传 HAP 路径。
- 构建：`./build.ps1 hap debug -Offline -Locked -NoVersionBump`。规范未签名 HAP 路径及时间戳由构建脚本检查。
- 没有访问鸿蒙设备。真机请重点验证无音轨 HDR、不支持音频格式的 HDR、正常有声 HDR，以及暂停/恢复、拖动、倍速和直出/纹理切换。QQ 拉起也需已安装 QQ 的设备验证。
- 最新包有问题时可按 [安装包索引](../build/milestones/README.md) 回退 66；旧归档包未被改写。

构建源码提交：`dab78d6`；规范未签名 HAP 时间戳：`2026-09-09T08:44:38.9411542+08:00`。签名 HAP 构建成功，包内运行时段与修复库核验通过。
