# 里程碑 76：Jellyfin 12 实证兼容修复（4.0.1+229）

在真实 Jellyfin 12.0.0 上发现旧认证头导致登录返回 HTTP 400；服务端记录 request.App 为空。标准 Authorization: MediaBrowser 头携带 Client、Device、DeviceId、Version 及登录后的 Token 后，登录和所有测试接口成功。应用现在发送标准认证头，并保留旧 X-Emby 兼容头；令牌不加入对外播放 URL。

验证使用官方 Windows 便携包 Jellyfin 12.0（208483686 字节，SHA-256 22A16178160C03F8C9D4BF4350449551B2F9901F708F41A632B2957AD5AE4A57），独立数据库/缓存/配置和生成的测试媒体库。进程监听 127.0.0.1，关闭自动发现、UPnP、远程访问，配置 /fixture 路径前缀；未接触用户设备或用户媒体服务器。服务器附带 FFmpeg 8.1.2。

生产 Dart 客户端直接验证通过：
- 标准认证登录、两个媒体库、分页和媒体详情。
- 两个版本、双音轨与中文外部字幕，字幕经客户端本机通道鉴权读取。
- 原画播放在第 5 秒跳转、解码 3 秒，视频和选定第二音轨的解码 SHA-256 与源文件一致。
- 2 Mbps H.264/AAC HLS 转码，通过客户端通道跳转并实际解码音视频成功。
- 停止后续播位置为 7000 ms，继续观看和收藏可查询。
- 三集连续剧按季分页（2+1），标记第一集已看后 NextUp 返回第二集。

可重复验证：先运行 tool/create_media_server_fixture.py；下载并解压官方包到 build/media-server-fixtures/jellyfin-12-bin；运行 tool/start_jellyfin_fixture.ps1、tool/setup_jellyfin_fixture.py，然后设置 ALOE_REAL_JELLYFIN=1 运行 test/media_server_real_test.dart。测试账号仅写入 build 下的隔离测试目录，不提交凭据。默认全量测试跳过真实服务器用例，必须单独显式执行。

这证明了上述场景在 Jellyfin 12 的实际行为；Emby 的真实版本验证、鸿蒙播放器实机行为及路线中的其他能力继续推进，不扩大结论为所有编码或所有服务器均已完成验证。
