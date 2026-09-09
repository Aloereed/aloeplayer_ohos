# 里程碑 77：真实 Emby 验证与下一集修复（4.0.1+230）

Emby 4.10 的 Shows/NextUp 在默认模式下未返回测试剧集的下一集。对照服务器附带的官方 Web 客户端，采用相同的 LegacyNextUp=true 请求后正确返回第二集。此参数仅用于 Emby，保留 Jellyfin 的请求行为。

真实服务器测试现同时覆盖 Jellyfin 12.0.0 与 Emby 4.10.0.40：登录、媒体库与物理目录遍历、两个媒体版本、两条音轨、鉴权中文字幕、原画跳转后音视频解码哈希与源文件一致、HLS 转码跳转解码、7000 ms 续播位置、收藏、已看状态、分季分页和下一集。

测试媒体全部本机生成。Emby 的短视频续播阈值位于每个媒体库，测试初始化脚本分别处理两套服务的配置；Emby 外部字幕返回 zh，Jellyfin 返回 zho。测试不再假设两者拥有相同目录层级和语言代码。

Emby 官方便携包版本 4.10.0.40，133832700 字节，SHA-256：974F595F536A442DE28145337818E36423611C5F00910C5ABD1488ECB4DB3B32。下载地址：https://github.com/MediaBrowser/Emby.Releases/releases/download/4.10.0.40/embyserver-win-x64-4.10.0.40.7z 。运行数据位于 build/media-server-fixtures/emby-4.10-runtime，测试仅请求 127.0.0.1:7663/emby。

Windows Emby 不能仅凭 LocalNetworkAddresses 限制 HTTP 监听，因此测试启动器要求保留仅针对该测试二进制的 TCP/UDP 入站阻止规则，并关闭端口映射、远程访问。dlna.xml 的禁用配置未完全关闭 UDP 发现端口，验证后已停止测试进程。不删除或禁用防火墙规则。该启动器是当前测试环境的记录，不是用户部署脚本；再次运行需继续处理发现插件隔离。

初始化：tool/setup_jellyfin_fixture.py --kind emby。设置 ALOE_REAL_EMBY=1 和 ALOE_REAL_JELLYFIN=1，运行 test/media_server_real_test.dart 可同时验证两套真实服务；凭据仅保存在忽略的 build 目录。默认测试跳过真实服务用例。

本阶段未访问鸿蒙设备、用户媒体服务器或电视，未重新编译 MPV。真实服务结果不能替代鸿蒙实机渲染验证；连续播放、离线体验与其他优化继续推进。
