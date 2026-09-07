# 里程碑 53：MPV 统一输出、ASS 字幕与后台下载

版本：**4.0.0+206**。

## 播放器

- 统一 MPV 纹理和原生 Surface 输出，在同一播放器实例内切换，保留播放列表、轨道及播放状态。
- HDR 默认自动直出；可手动选择直出（含 SDR，便于调试）或纹理。超分、调色、镜像、缩放等功能优先使用纹理，短提示说明回退。
- HDR 引擎入口和旧 HDR 引擎偏好均改为 MPV，不再启动流心视频窗口。
- 移除 HDR 自动最大亮度、亮度恢复和相关提示；保留用户手动调亮度。
- 原生直出叠加独立 libass 字幕层，读取外部 ASS/SSA、内嵌 ASS 样式及字体附件；跟随播放时间、字幕延迟和字幕开关。读取期间显示文本字幕，失败时回退纹理。
- 鸿蒙文件选择器默认合并显示所有允许的扩展名，修复字幕选择默认只显示 SRT；修复输出模式选择框在亮色主题下的对比度。

## 后台下载

- 原来已声明 `KEEP_BACKGROUND_RUNNING` 和 `dataTransfer`，但新版请求未传子类型。
- 补齐 `SUBMODE_LIVE_VIEW_NOTIFICATION`，下载前按需申请通知授权；用户授权等待与后台服务超时分开处理。
- 使用系统返回的通知 ID 更新下载进度，避免长期无进度更新导致后台任务取消；开始失败后允许重新申请。
- 区分通知权限关闭、服务超时和后台校验失败，保留错误码，不再把所有异常都归为系统拒绝。
- 依据：[OpenHarmony 后台任务 API](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/reference/apis-backgroundtasks-kit/js-apis-resourceschedule-backgroundTaskManager.md)。

## 验证与归档

- 18 项 Flutter 回归通过：输出策略、画质切换顺序、Surface 透明区域、HDR 检测设置、下载错误分类、续传、暂停、取消和中断恢复。
- HAP 使用调试签名，APP 使用 release 签名；Flutter 编译模式均为 release。
- 包内版本、时间戳、SHA-256 和源码提交保存在 `build/milestones/53-mpv-hdr-ass/manifest.json`。
- 早期迭代已覆盖安装并启动；完整 HDR 色彩效果、复杂 ASS 特效及后台下载的长时间锁屏运行仍需设备验收。独立原生字幕测试未完成，不将其计为通过。
- 字幕独立读取有 25 秒和 32 MiB 字幕数据上限，慢网络或超大字幕会回退纹理播放。

归档目录：`build/milestones/53-mpv-hdr-ass/`。
