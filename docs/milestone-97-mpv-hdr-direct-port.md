# 里程碑 97：移植 OHCodec HDR 直出

版本：4.0.1+250。

在 ErBWs/mpv 6edeee00a07b9b76f197aa71eee3d029fb090de4 上新增 vo=ohcodec，移植提交为 7b89e73。恢复播放器 HDR 直出使用的 Surface 输出驱动，沿用新版 FFmpeg 的 AVOHCodecBuffer 生命周期，保留完整视频片尾。驱动由 MPV 定时呈现，不声明 VO_CAP_UNTIMED；重复帧不重复提交，重置和销毁时释放待提交帧。

FFmpeg 基线为 7dddf74de0346fee1f17bd49563efc5ab9deaf98。使用 WSL ~/tpc_c_cplusplus-current 的独立 aloe-mpv-direct 配方及 WSL SDK 完成源码编译，最终产物导出用于 HAP 打包。依赖重新构建，着色器编译使用 glslang；并非仅修改上游二进制中的几个字节。配方、源码补丁、来源记录和生命周期测试保存在 tool/mpv-direct。

libmpv.so SHA-256：0e566eaa73a04cbf7bbb3aad6f3b6e51096a4f00fd13028a06a3286ce8d665d8，38,633,880 字节。构建保护脚本接受这一确定版本，不套用旧库偏移补丁。

验证：原生交叉编译成功；实际驱动源码的宿主模拟测试在 ASan/UBSan 下运行 1000 轮通过，覆盖呈现、重复帧、重置、失效 token 和清理。真实设备 HDR、无音轨播放速度及完整播放后再次打开视频仍需实播验证；安装成功不代表这些行为已验证。

部署使用覆盖安装并保留应用数据。里程碑目录独立保存 Debug 签名 HAP、清单及构建日志，不覆盖此前里程碑。
