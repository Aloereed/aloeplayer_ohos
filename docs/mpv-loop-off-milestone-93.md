# 里程碑 93：循环关闭时停在当前视频

版本：4.0.1+246。

修复 MPV 播放本地文件或媒体队列时，循环模式关闭仍自动进入下一项的问题。media-kit 的 PlaylistMode.none 仅关闭 loop-file/loop-playlist，MPV 默认 keep-open=yes 仍会顺序播放到列表末尾。

关闭模式使用 keep-open=always，在当前视频完整结束后停止自动前进；单曲和列表模式恢复 keep-open=yes，并由原有循环选项控制重复。两个模式选择入口及打开媒体时使用同一串行配置方法，避免快速切换造成属性组合错乱。手动上一项/下一项仍可使用。媒体服务器独立的“自动下一集”开关继续按其设置生效。

依据：https://mpv.io/manual/master/#options-keep-open

继续使用里程碑 92 的 20260715 上游 MPV，原版 SHA256：672e98d497199a89e20893979ecec686dee1113bbe1b609c9a9266aa1679bd32。未修改 MPV 二进制。

构建命令：./build.ps1 hap debug -Offline -Locked -NoVersionBump。debug 为调试签名，Flutter release 编译。

真机复测：在包含多个视频的本地目录选择第一项，关闭循环后完整播放应留在当前视频；手动下一项应正常。单曲应重播当前视频；列表应前进并在末项返回首项。片尾硬解稳定性仍需持续观察。
