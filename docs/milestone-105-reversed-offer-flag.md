# 里程碑 105：反向优惠标志对照测试

版本：4.0.2+258。按用户要求尝试把 hasEligibilityForIntroOffer 按“是否已经使用过推介优惠”解释：true 使用商店常规价，false 使用商店推介优惠价并说明期限与续费价。字段缺失保留条件披露；没有优惠对象的月会员继续正常使用常规价格。无固定金额。

这是用于账号和收银台对照的实验版本，不表示已证实 SDK 的布尔语义。27 项 Flutter 回归通过，证明客户端按上述规则执行；不替代真实华为账号的验证。

仅构建调试签名、Release 编译 HAP，归档 `build/milestones/105-reversed-offer-flag`，覆盖安装保留数据。暂不生成上架 APP。对照时核对老账号页面与收银台是否均为常规价、新账号是否均为首年优惠价；无需完成付款。

上一版条件披露测试包保留于里程碑 104，可用 `tool/deploy_milestone.ps1 -Name 104-offer-disclosure` 回退。
