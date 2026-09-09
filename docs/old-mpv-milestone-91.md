# 里程碑 91：旧 MPV 对比包

版本：4.0.1+244。保留里程碑 90 的应用代码，只替换本次打包所用 MPV，用于对比“硬解完整播完后，其他视频一直缓冲”的问题。此包不是已验证的硬解修复。

旧库来源：`C:\Users\huzheng\Downloads\old_aloe_player.app`（实际存在的文件），内部 `entry-default.hap/libs/arm64-v8a/libmpv.so.2`。旧 APP 版本为 3.1.0+142。

旧库大小：42,356,832 字节。SHA256：`bb66263f8f559922849cc5eb4c6d363da2402104ea19c28986616df2e7e91f0c`。

构建命令：

```powershell
./build.ps1 hap debug -Offline -Locked -NoVersionBump -ComparisonMpvSha256 bb66263f8f559922849cc5eb4c6d363da2402104ea19c28986616df2e7e91f0c
```

该参数仅允许 debug 签名 HAP，并严格检查库哈希后跳过当前 MPV 时钟补丁。普通构建仍执行原有补丁校验。按项目现有构建约定，debug 指签名配置，Flutter 仍为 release 编译。本次没有重新编译 MPV。

归档目录：`build/milestones/91-old-mpv-comparison`。保存 signed/unsigned HAP、旧库副本、校验日志与清单。打包后恢复工作区原 MPV 库，避免影响后续正常构建。

验证使用 `tool/verify_comparison_mpv.py` 对照旧库 SHA256 并逐一比较 HAP 内 ELF 的全部运行时节，允许打包移除非运行时符号信息。没有访问鸿蒙设备。

真机重点：开启硬解，完整播完后检查列表自动下一项，再退出播放器打开其他视频，重复两轮。旧库未经当前时钟补丁，HDR 无音轨播放速度也需留意。
