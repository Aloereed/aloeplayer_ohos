# 网络媒体库可复现验证

不需要 NAS 或鸿蒙设备，所有网络测试仅连接本机临时端口。Flutter 测试按项目规定在沙箱外执行。

## 常规回归

```powershell
./tool/prepare_smb_loopback.ps1
E:/source/flutter_327/bin/flutter.bat test --no-pub
```

脚本依赖已安装的 MinGW GCC 和 CMake。只在 `build/` 复制并编译 Windows 测试库，不替换 `ohos/entry/libs/arm64-v8a/libsmb2.so`。C 夹具从项目自带头文件取得布局，覆盖共享枚举 ABI、失败释放和读取请求数量。

## 真实 SMB2 本机回环

```powershell
python -m venv build/network-test-venv
./build/network-test-venv/Scripts/python.exe -m pip install --progress-bar off impacket==0.13.1
./tool/prepare_smb_loopback.ps1
./build/network-test-venv/Scripts/python.exe tool/smb_loopback_server.py
```

保持测试服务器运行，在另一终端执行：

```powershell
E:/source/flutter_327/bin/flutter.bat test --no-pub --dart-define=SMB_LOOPBACK_TEST=true test/smb_loopback_test.dart
```

结束后用 Ctrl+C 关闭自己启动的测试服务器。服务及其 RPC 辅助端口只绑定 `127.0.0.1`，账户是公开的专用测试账户，共享只读，文件全部生成于 `build/smb-loopback-data/`。

Windows Impacket 的只读模式会覆盖 O_BINARY；夹具只在自身进程恢复二进制打开，避免 0x1a 被误当文件结束。Windows libsmb2 的 MinGW 移植修正也仅应用于 `build/smb-test-source/`。

## 已记录结果与边界

- 真实 SMB2：根目录共享枚举、跨共享目录访问、中文/特殊字符、stat、分段读取、空文件、8 MiB 完整内容校验通过。
- 该服务协商 64 KiB 块，8 MiB 使用 128 块；一次含逐字节断言的本机运行约 619 ms，不代表设备吞吐。
- C 夹具：8 MiB 在 1 MiB 协商上限下只需 8 次原生读取；64 KiB 上限下保持 128 次，验证不超过服务器能力。
- 本机队列：5000 媒体 + 5001 字幕生成约 111–116 ms；原嵌套字幕扫描改为索引。
- 代理：12 个并发 HEAD 只发起 1 次底层 stat；链接重复生成复用令牌，切换服务器不串源。
- 不代表 SMB1、Kerberos、所有 SMB3 加密组合、所有 WebDAV/NAS 厂商或鸿蒙硬件已经通过验收。
