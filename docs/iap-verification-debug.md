# 2026-09-06 订单待验证排查

客户端里程碑 40：`3.1.1+184`，提交 `552bbab`，已保留数据覆盖安装到调试设备。
打包目录：`build/milestones/40-iap-verification-diagnostics`。
5 项客户端回归通过，区分后端验单失败和华为确认发货失败；诊断只记录阶段、异常类型、HTTP 状态，不记录凭证或购买 Token。

## 已确认原因

用户提供的后端日志显示账号鉴权成功，`POST /api/v1/iap/verify` 返回 503。
`issuer_config.txt` 中 Key ID 少了末尾字符，之前生成的本地配置片段也沿用了该截断值。
完整 Key ID 与本地 `IAPKey_*.p8` 文件名对应。

同一私钥、Issuer ID、应用 ID，向华为查询一个不存在的诊断订单：

- 原 Key ID：HTTP 401，业务码 `1001880006`，`can not obtain a valid merchant key`。
- 补齐末尾字符后：HTTP 200，业务码 `1001880008`（不存在的诊断订单不拥有商品，预期响应）。

探测仅调用订阅查询接口，没有购买或确认发货。第二个响应证明鉴权通过，不代表真实购买已经发放权益。

## 线上修正

用 `build/iap-private/iap-key-id-fix.env` 中的值替换服务器已有 `.env` 的 `HUAWEI_IAP_KEY_ID`，避免重复配置同名项，然后按原方式重启后端。
本地 `build/iap-private/iap-server.env` 已修正；原始用户文件保留用于回溯。私密配置不进入 Git 或更新包。
华为通知 URL、根证书、签名证书、私钥文件都无需因为此次 Key ID 截断而更换。

重启后通过客户端“恢复购买”验证现有订单，无需重复付款。真实订单验单、续订同步仍需在配置修正后验证。
