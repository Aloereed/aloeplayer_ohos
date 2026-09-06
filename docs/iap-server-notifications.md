# 自动续订后端交付

后端仓库 `E:\source\wp-ucenter-py`，实现提交 `89adb1c`。
客户端继续使用里程碑 39（3.1.1+183），本次不需要重新安装 HAP。

更新包：`build/backend-milestones/03-url-worker/ucenter-iap-url-task-update.zip`。
包内以 `backend/` 为顶层目录，应对应覆盖服务器仓库中的 backend 文件。
不包含 `.env`、私钥或用户原有 `app/config.py` 改动。
部署前提是服务器已安装此前 `a6ab5fb` 或更新的 IAP 后端。

完整部署步骤见后端 `backend/IAP_NOTIFICATIONS.md`（交付目录也有副本）。
本地已根据用户提供的 Issuer/Key ID 生成配置片段：`build/iap-private/iap-server.env`。
此片段没有打入更新包；追加到服务器已有 `.env`，不要覆盖原配置。
私钥文件单独上传到该片段指定路径，保留已部署的 Huawei 根证书路径。

部署概要：备份数据库并停止后端 -> 覆盖更新文件 -> 追加环境变量 ->
按原方式启动后端（启动时自动补齐表，数据库锁防止并发抢建） ->
添加每分钟访问一次 URL 的 GET/POST 计划任务（地址见私密文件 `build/iap-private/iap-task-url.txt`，超时建议 90 秒） ->
在 AGC 沙盒事件通知地址填入 `https://user.aloereed.com/api/v1/iap/notifications`（v3）。

已验证 35 项本地回归（临时 SQLite、测试证书、模拟华为服务），包括导入不执行 DDL、四进程启动、重启及已有数据保留。
尚未部署线上、未发起沙盒购买或收到真实华为回调；MySQL 并发行为需部署后联调。
更新包 SHA-256 和文件清单见同目录 `manifest.json`。

URL 任务还需将 `build/iap-private/iap-task.env` 追加到服务器已有 `.env` 后重启。任务地址为 `/api/v1/iap/tasks/process`，支持查询参数 `key` 或请求头 `X-IAP-Task-Key`，无需请求正文。使用独立随机密钥，密钥不进入 Git 或交付 ZIP。AGC 通知地址仍为 `/api/v1/iap/notifications`。
