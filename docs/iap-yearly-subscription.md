# 隐藏年会员兼容

后端提交 `b42d049`，客户端提交 `e27eb08`，里程碑 42 / 3.1.1+186。

- Huawei `premium_monthly` 仍映射 HUAWEI_IAP_MONTHLY_PRODUCT_ID。
- Huawei `premium_1year` 映射 HUAWEI_IAP_YEARLY_PRODUCT_ID，默认 4，无需新增环境变量。
- 用户中心商品 4 应是启用的订阅商品，周期 yearly、时长 1；不自动修改现有商品。
- 客户端购买页仍只查询和展示月商品；年商品回调、恢复购买、验单、续订通知、定时同步和失效解锁均支持。
- 订单金额取华为签名价格；会员截止时间取华为签名 expiresTime，包括沙盒加速到期，绝不按本地一年累加。
- 订阅记录的名称、商品 ID、周期和时长来自映射商品，避免年订单记录为月会员。
- 旧月凭证查询到已切换的年会员时，按最新签名中的年商品映射发放。

覆盖更新 ZIP 中的 backend 文件，保留已有 .env（含此前补齐末尾 a 的 Key ID），按原方式重启。
包累计包含自动续订、自动建表、URL 任务和到期订单修复。无需手动建表或更改通知/任务地址。
本地 42 项后端测试、9 项客户端测试通过。未发起真实年会员购买；线上部署由用户完成。

关于复用商品 ID 1：即使到期时间正确，也会把商品名称、订阅周期和报表归属记录为月商品。
当前实现明确校验年商品映射为 yearly/1，不支持把 premium_1year 映射到 monthly/1 的商品。
使用独立商品 4 保持订单语义正确。

更新包：`build/backend-milestones/05-yearly-subscription/ucenter-iap-yearly-update.zip`。
客户端：`build/milestones/42-iap-yearly-compatibility`。
