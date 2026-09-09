# 里程碑 92：换回 media-kit OHOS 上游 MPV

版本：4.0.1+245。

按用户要求使用 ErBWs/media-kit 的 feat-ohos 分支自动下载脚本所指定的 MPV，未应用本地 EOF 候选补丁，也未重编 MPV。此前锁定的 f609ef6 提交没有自动下载代码；当前 feat-ohos 提交为 33bb9f4b7aa6ec3ea205de3a2570d5c19e658526。

来源脚本：`libs/ohos/media_kit_libs_ohos/ohos/src/main/cpp/CMakeLists.txt`。

下载地址：<https://github.com/mpv-ohos/libmpv-ohos-build/releases/download/20260715/libmpv_aarch64.zip>

- ZIP SHA256：`ac8b176dc4c86f4772d62ff530762ec187c3c46383bf2d476870d17dad806e5b`，已与上游脚本核对。
- ZIP 内文件：`libmpv.so`，35,491,168 字节。
- MPV SHA256：`672e98d497199a89e20893979ecec686dee1113bbe1b609c9a9266aa1679bd32`。

该库 SONAME 是 libmpv.so。原生链接与 Flutter 两处初始化统一使用这个名称；原有 libmpv.so.2 保留作为本地备份，不参与本次链接。正常构建校验此上游库哈希并保持二进制原样。

构建：`./build.ps1 hap debug -Offline -Locked -NoVersionBump`。按项目惯例 debug 指调试签名，Flutter 使用 release 编译。归档：`build/milestones/92-media-kit-upstream-mpv`。

验证：编译、canonical HAP 时间戳、包内 MPV 运行时内容与上游库比较、包内名称与链接依赖核对。没有在设备上安装此版本；片尾完整播放、后续切集/重新打开视频及 HDR 输出仍需真机复测。此次回退不等于确认修复硬解 EOF。
