# 里程碑 75：播放版本、轨道与转码协商（4.0.1+228）

详情页新增“播放设置”，按需探查媒体源后选择版本、自动/原画/服务器转码、2–120 Mbps 带宽上限、音轨与字幕。探查不自动打开直播源；正式播放将轨道索引与 MediaSourceId 一起提交。切换版本后重置轨道选择，已移除的旧轨道不会以不可见状态提交。

PlaybackInfo 发送 MPV 播放能力描述、直接播放/转码策略、码率、轨道选择。优先直接播放，其次使用服务器提供的 DirectStreamUrl 或 TranscodingUrl；转码视频协商 H.264/AAC HLS，音频协商 MP3。需要打开的源支持 AutoOpenLiveStream，必要时显式调用 LiveStreams/Open。流时间线从零开始，由播放器执行续播定位，避免重复偏移。

媒体经仅监听 127.0.0.1 的会话转发器播放，复用此前已验证的 Range、HEAD、HLS 分片/密钥重写、背压与跨源认证清理。播放器获得本机会话令牌，不持有服务器认证头；外部字幕使用同一转发器的独立授权资源。兼容服务器返回的相对地址及已含/未含反向代理前缀的根路径。同源 URL 中 api_key 移除，使用认证头。

每次播放按独立本机 URL 保存会话，不再按影片 ID 共享 PlaySessionId。上报携带准确的 MediaSourceId、播放方式、音轨/字幕索引、直播 ID 和可跳转状态；停止与关闭释放转发器、直播源和转码任务，重复停止不会重复清理。关闭客户端等待上报有时间上限。MPV 在已有偏好应用后落实本次显式轨道选择。

验证：本机真实 HTTP 链路读取转码 HLS 和外部字幕、同片两会话隔离、直播开启/关闭、反向代理与认证清理、窄屏选项与失效轨道恢复，并回归原转发器测试。仍需真实 Jellyfin/Emby 版本和实际媒体解码验证；能力列表不是所有编码、所有设备的兼容性证明。Jellyfin 12.0 官方便携包下载中，后续按总路线验证并修正。连续选集、同步重试、离线、完整音乐/直播浏览与高级筛选继续推进。

协议参考：
- https://dev.emby.media/reference/RestAPI/MediaInfoService/postItemsByIdPlaybackinfo.html
- https://github.com/jellyfin/jellyfin/blob/master/Jellyfin.Api/Controllers/MediaInfoController.cs

未重编译 MPV，继续保留此前 HDR 无音轨时钟修复。安装包分别归档 debug 签名 HAP 与 release APP，不访问用户设备。
