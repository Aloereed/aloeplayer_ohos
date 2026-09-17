# Linux 构建与局域网传输

目标机器：`aloereed@192.168.124.26`（Debian 12，x86_64）。

## 部署位置

| 访问路径 | 实际目录 |
| --- | --- |
| `~/flutter_327` | `/vol1/1000/development/flutter_327` |
| `~/source/aloeplayer_ohos` | `/vol1/1000/development/source/aloeplayer_ohos` |
| `~/jdk-21` | `/vol1/1000/development/jdk-21` |
| `~/command-line-tools-26.0.0.821` | 主目录下先前部署的 HarmonyOS SDK/工具 |

源码、依赖和构建输出使用 `/vol1` 大容量卷。Windows 上的原仓库保留。
Flutter 和项目均携带完整 `.git`；`libsmb2`、`rhttp` 两个嵌套仓库也保留完整 Git。
四个仓库均已通过 `git fsck --full`，未提交改动随工作区迁移。

- Flutter：`3.41.10-ohos-1.0.0`，提交 `244a0e8abb3085e8675589b13e219af8c41cb7aa`。
- 项目基线提交：`8dc6704414193f561e1573792a57fe086b6344bf`。
- 应用版本：`4.0.2+259`。
- HarmonyOS 命令行工具：`26.0.0.821`，Hvigor `6.26.4`，OHPM `26.0.0.630`。
- Java：用户目录中的 Java 21；不依赖系统 Java。

## 构建

在远端执行：

```bash
cd ~/source/aloeplayer_ohos
./build.sh hap debug --offline
./build.sh app release --offline
```

与现有 `build.ps1` 一致，第二个参数选择签名配置，Flutter 编译模式均为
`--release`。Linux 脚本保持 `pubspec.yaml` 中的版本，不自动递增版本号。
`--offline` 传给 Dart Pub；它不禁止 Flutter 引擎或 OHPM 在缺失依赖时联网。
删除这个参数即可正常解析新增依赖。

脚本自动设置 Flutter、Node、SDK、Java 和项目内 Pub 缓存路径，替换签名文件路径，
准备 OHOS 插件、检查 MPV 二进制，并检查构建产物更新时间及 ZIP 完整性。
可通过 `FLUTTER_ROOT`、`DEVECO_ROOT`、`JAVA_HOME` 覆盖工具位置。
Flutter 的通用下载源默认为 `https://storage.flutter-io.cn`，可通过
`FLUTTER_STORAGE_BASE_URL` 覆盖。OHOS 引擎仍使用此 Flutter 分支配置的源。

Linux 兼容修改包含 `FindAki.cmake` 的精确文件名，以及三个插件对
`FfmpegUtils.ets` 的精确大小写导入。

签名文件放在被 Git 忽略的 `.signing/debug/`、`.signing/release/`。
每个目录包含该配置使用的证书、profile、P12 及其必须的 `material/`。
原 debug/release 配置仍保存在被忽略的 `ohos/build-profile.json5.debug/release`。
这些文件及应用环境文件通过 SSH 加密直传，未通过明文服务传输。

## 已验证产物

保留的独立产物目录不会被另一种构建覆盖：

- `output/linux/hap-debug/entry-default-signed.hap`：199,782,827 字节。
- `output/linux/app-release/ohos-default-signed.app`：90,947,670 字节。
- `output/linux/verification.json`：版本、大小、时间和 SHA-256 验证记录。
- `output/linux/hap-debug.log`、`output/linux/app-release.log`：远端构建日志。

HAP 的规范 unsigned 输出仍是
`ohos/entry/build/default/outputs/default/entry-default-unsigned.hap`，构建后已核验时间。
两种签名产物均验证版本为 `4.0.2+259`，实际打包的 `libmpv.so` ELF 运行时节
与选定的源二进制一致。构建验证不包含真机安装或播放测试。

## 按需启动高速传输

`tool/lan_transfer.py` 仅使用 Python 标准库，支持 HTTP PUT/GET、SHA-256 校验和
原子上传，不允许覆盖已有目标。服务只绑定指定内网地址，并限制对端 IP。
本次 5.77 GB 包上传实测 **82.5 MB/s**；双向传输和校验均验证成功。

先 SSH 登录远端，在一个终端中启动前台服务：

```bash
python3 ~/source/aloeplayer_ohos/tool/lan_transfer.py serve \
  --bind 192.168.124.26 --peer 192.168.124.12 \
  --root /vol1/1000/development/transfers
```

本机 PowerShell 在项目目录中上传或下载普通文件：

```powershell
python tool/lan_transfer.py put C:/path/archive.tar.gz http://192.168.124.26:18765/archive.tar.gz
python tool/lan_transfer.py get C:/path/download.tar.gz http://192.168.124.26:18765/archive.tar.gz
```

文件只通过两台机器的局域网 IP 传输，不使用互联网中转。压缩包可避免逐个小文件的
请求开销。证书、私钥和环境秘密继续使用 SSH/SCP。本机 IP 改变时相应调整 `--peer`。
使用完后在服务终端按 Ctrl+C 关闭；没有安装自启动或常驻服务。

## Windows / Linux Git 同步

两机共同维护 `f341` 并跟踪 `origin/f341`，设置 `pull.ff=only`。换机开发前，先在当前机器提交并推送，再在另一台执行 `git pull --ff-only`。同一批改动只创建一组提交；保留未提交修改后再处理分叉，不使用 force push 覆盖另一台历史。
