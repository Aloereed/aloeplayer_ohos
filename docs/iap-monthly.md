# 月会员 IAP 联调（里程碑 34）

开放商品 `premium_monthly`，类型为华为自动续期订阅，价格和商品文案读取商店。使用用户指定的 CPF-Flutter `br_in_app_purchase-v3.2.3_ohos` 分支，固定上游提交 `5e6abec7d3687b3904a403c7a38402ced24d2e60`，源码和许可证保留在 `third_party/huawei_iap`。

修复旧依赖只出现在 dependency_overrides 导致原生插件未注册的问题；最终生成清单和 HAP 均包含 `in_app_purchase_ohos`。本地插件修补包括每笔交易携带独立完整凭证、账户绑定写入 developerPayload、系统订阅管理入口。

购买流程：应用账号登录 → 后端检查配置并提供账户绑定值 → 华为系统收银台 → 服务端校验签名和权益、幂等落库 → 客户端更新会员 → 商店确认发货。取消或验单失败不发放会员，不提前确认发货；可恢复未完成订单。只有月会员商品可购买。

## 配套用户中心

仓库 `E:/source/wp-ucenter-py`，代码提交 `aed8397`。增加 `/api/v1/iap/config` 与 `/api/v1/iap/verify`、凭证索引和订阅账户绑定两张新表；管理前端增加华为 IAP 支付方式和交易号。原有 `backend/app/config.py` 与 `.env.example` 用户修改保留，未混入提交。

先阅读用户中心的 `backend/HUAWEI_IAP.md`，部署后端并配置华为应用 ID、可信根证书、后台月会员商品数字 ID。沙盒测试还需要 AppGallery Connect 配置测试账号和签名。后端未配置或未登录时，客户端不会打开收银台。

没有部署网站、执行真实数据库迁移或实际支付。验签使用华为官方文档的客户端上报签名凭证流程；实时退款 / 续费关键事件通知及主动查单仍需后续接入，当前通过客户端恢复同步。

## 验证

- Flutter 全量 65 项通过，包含新增 4 项支付与凭证回归；相关 Dart 静态检查无错误。
- 用户中心 8 项隔离测试通过：伪造签名、错应用 / 商品 / 环境、过期 / 撤销、账号串用、幂等恢复、续费时间及长订单号；内存 SQLite 与临时测试证书，不连接现有数据库。
- 管理前端构建通过（保留原有大 chunk 提示），HAP 编译通过并核对 canonical unsigned 时间。
- 无实机；商店商品可见性、签名/商户授权、真实支付、取消、杀进程恢复、会员到账和系统取消续费需要联调。

参考：[指定插件](https://gitcode.com/CPF-Flutter/flutter_packages/tree/master/packages/in_app_purchase)、[华为订阅接入](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V13/iap-integrate-subscription-V13)、[购买数据模型](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/iap-server-data-model)。
