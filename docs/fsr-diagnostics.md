# FSR 诊断日志

日志前缀为 `[AloeFSR]`，Release 包也会输出。每个播放器有 `session`，每次应用画质有 `revision`。不记录媒体路径、播放 URL、请求头或凭据。

## 抓取

1. 用 MPV 播放一段 720p SDR 视频，切换至 FSR 均衡。
2. 保持播放至少 4 秒，再切回高清缩放或原始画质进行对照。不要使用系统画中画。
3. 通过 SDK 执行 `tool/capture_fsr_logs.ps1`，多设备时传入 `-Target`。脚本导出当前 HiLog 缓冲中的 FSR 行到 `build/fsr-diagnostics-时间.log`，不清空日志。

切换画质后第 1 秒与第 4 秒各采样一次；重新打开画质面板时再采样一次。没有常驻逐帧采样；切换配置或退出播放器时取消待执行采样，迟到结果会被丢弃。

## 判读

| 事件 / 字段 | 含义 |
| --- | --- |
| `render_plan` | 请求档位、实际采用的档位、输入 / 目标尺寸，以及 HDR、RGB、无需放大等跳过原因 |
| `shader_asset_ready` | 已取得经过原有完整性校验的内置着色器 |
| `shader_configured` | `glsl-shaders` 参数回读匹配；仅证明配置成功 |
| `render_probe.fsrShaderListed` | 采样时播放器着色器列表是否仍含内置 FSR |
| `render_probe.textureWidth/textureHeight` | VideoController 报告的实际纹理尺寸，区别于请求尺寸 |
| `video-out-params/w,h` | 滤镜之后的视频尺寸，不等同于最终渲染窗口 |
| `video-target-params/w,h`、`osd-width/height` | 后端可用时报告的 VO 目标与窗口尺寸；不支持时为 null |
| `passEvidence=easu_rcas_timed` | 同时找到 EASU、RCAS，且都有采样数量与正的最近执行耗时 |
| `easu_rcas_listed_no_complete_timing` | 两个阶段都存在，但完整计时证据不足 |
| `partial` / `not_observed` | 只找到部分阶段 / 此次没有观察到 FSR 阶段，不直接判定失败 |
| `unavailable` | 后端不支持或查询失败，不能用“参数已设置”代替 GPU 证据 |
| `property_rejected` / `apply_failed` / `shader_runtime_error` | 参数拒绝、应用异常或 GPU 着色器错误，记录回退动作；运行错误标注编译 / 链接及 EASU / RCAS 线索 |

判定时结合**同一 session、revision 的 `fsrExpected=true`、着色器列表和渲染阶段计时**，不要只看档位选中。渲染阶段信息是后端保留的最近统计，不能证明每一帧均执行，更不证明主观画质改善。

`vo-passes` 使用 `MPV_FORMAT_NODE` 查询，避免将不支持的字符串子属性误判成没有渲染阶段。读取完成后释放节点与字符串；诊断失败不改变画质。属性语义参考 [mpv 官方文档](https://mpv.io/manual/stable/#command-interface-vo-passes)。

验证：16 项相关回归通过，覆盖证据分类、HDR 绕过、参数失败回退、迟到结果丢弃和退出后停止采样。真实设备上的 EASU / RCAS 证据需播放后抓取。

`3.1.1+192` HAP 构建通过，标准未签名包时间戳已核对为 `2026-09-06T16:25:15.5287866+08:00`；已通过 SDK 保留数据覆盖安装并启动，设备版本核对为 192。构建 / 部署日志位于 `build/fsr-diagnostics-build.log` 和 `build/fsr-v192-deploy.log`。
