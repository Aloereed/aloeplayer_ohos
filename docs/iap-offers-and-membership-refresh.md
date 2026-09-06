# 优惠展示与会员状态刷新

客户端提交 `e0b4b99`，里程碑 44 / 3.1.1+188。本次无需更新后端。

- 原生商品查询保留完整商品 JSON，补上之前 Dart 包装层丢失的 subscriptionInfo。
- 根据华为 hasEligibilityForIntroOffer 展示当前账号可享受的推介优惠；只有明确为 true 才展示优惠价。
- 免费试用、分期优惠、一次性支付优惠分别展示期限、价格和之后的常规续费价。
- 已使用新客优惠的账号、资格未知、优惠信息缺失或无法解析时显示常规价。
- 普通折扣同时保留原价展示。自定义人群促销需要配套促销签名，目前没有配置这类优惠，不擅自宣称可用。
- 设置页和会员弹窗监听同一个 MembershipService。验单更新会员状态时立即通知，不必关闭弹窗或重新进入设置。
- 购买前发出的订阅查询若晚于新会员状态返回，会被丢弃；切换登录账号时的旧查询也不会覆盖当前账号。

17 项 Flutter 回归和 6 个原生商品查询模拟场景通过。静态分析未发现 error；settings.dart 和会员服务原有代码仍有风格/弃用 API 提示。
测试包含优惠资格、未知资格、免费试用、一次性价格、异常数据回退，以及不重开页面的会员观察者刷新。
没有代用户发起支付。当前华为账号已使用推介优惠时，设备显示常规价格属于正确行为。

字段核对：本地当前 Huawei SDK `@hms.core.iap.d.ts` 中 SubscriptionInfo、SubscriptionOffer、OfferPaymentMode。
资格依据：[华为官方 FAQ](https://developer.huawei.com/consumer/cn/doc/doccenter-operations/agc-help-countries-faq-0000002425264361)。

HAP 归档：`build/milestones/44-iap-offers-and-refresh`。
