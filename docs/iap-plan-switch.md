# 月年方案选择与订阅切换

后端 `eaeeeaa`，客户端 `3a207c7`，里程碑 43 / 3.1.1+187。
用户已确认月年商品同组；同权益的月、年方案应在 AGC 中使用同一等级。
等级用于决定升级/降级，和订阅时长没有必然关系。

## 部署

覆盖后端 ZIP 中的 backend 文件，保留已有 .env，按原方式重启。
自动补齐 iap_subscription_groups、iap_group_tokens 表，不需要手动建表，也不改变原有表结构。
月商品映射保留 HUAWEI_IAP_MONTHLY_PRODUCT_ID；年商品 HUAWEI_IAP_YEARLY_PRODUCT_ID 默认 4（yearly/1，启用）。
配置接口只公布已正确映射的商品；年商品不存在或配置不正确时，客户端不会开放其购买。
保留此前补齐末尾 a 的 Key ID。本包累计包含此前所有 IAP 更新，不含 .env/私钥。
客户端验单等待时间为 60 秒；后端按组加锁后重查最新状态，避免多个 Token 同步相互覆盖。
URL 任务仍每分钟调用一次，建议任务和代理超时调到 120 秒，避免华为请求较慢时多阶段处理被截断。

## 切换规则与权益

- 同等级、不同周期：通常在原周期结束后生效，保留当前会员；显示当前方案、预约方案及预计生效日期。
- 升级到更高等级或同等级同周期的切换：由华为决定即时生效及折算，本地不计算退款或累加时长。
- 发放只依据华为 lastSubscriptionStatus 的当前商品和 expiresTime；renewalInfo 的下一期商品只用于展示，绝不提前发放。
- 每次按订阅组串行重查。同组旧记录在新方案生效后结束，历史订单保留；不同组互不清理。
- 切换可能更换 purchaseToken；只有华为签名历史证明同一订阅组代的关联，才允许从旧 Token 转到新 Token。所有已绑定账号必须一致。
- 兼容部署前已有订单，利用签名历史把旧 Token 关联到组。没有关联证据则保留重试，不放宽验单。
- 下期生效的购买回调可能仍返回旧商品凭证，原生插件按凭证的真实商品标识传给 Dart，不把预约年方案显示为已经到账。
- AGC/华为市场外部变更由通知任务或定时同步更新；客户端重新加载或恢复购买后展示。任务处理存在延迟。

## 验证

47 项后端回归、11 项 Flutter IAP 回归、8 个原生模拟场景通过；相关 Dart 静态检查通过。
覆盖预约、取消预约、Token 更换、旧通知重放、锁前旧快照、已有订单迁移、跨账号保护、到期解锁。
真实同组并发 MySQL、真实扣款切换尚需部署后沙盒验收；没有代用户提交购买。

## 官方依据

- https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/store-iap-product
- https://developer.huawei.com/consumer/cn/doc/harmonyos-references/iap-query-subscription-status

2026-09-06 通过华为官方文档接口核对当前切换规则，以及 subscriptionId / purchaseToken / subGroupGenerationId 的关系。

后端包：`build/backend-milestones/06-plan-switch/ucenter-iap-plan-switch-update.zip`。
客户端包：`build/milestones/43-iap-plan-switch`。
