# 里程碑 105：反向优惠标志对照测试

版本：4.0.2+258。按用户要求尝试把 hasEligibilityForIntroOffer 按“是否已经使用过推介优惠”解释：true 使用商店常规价，false 使用商店推介优惠价并说明期限与续费价。字段缺失保留条件披露；没有优惠对象的月会员继续正常使用常规价格。无固定金额。

27 项 Flutter 回归通过，证明客户端按上述规则执行。2026-09-11，用户安装 258 版后反馈“这下对了”，确认反向判断符合其设备表现，并要求构建 Release APP。

调试签名、Release 编译 HAP 与正式签名 Release APP 均归档到 `build/milestones/105-reversed-offer-flag`。HAP 已覆盖安装并保留数据；Release APP 使用相同版本和实现，构建与产物校验结果见归档清单。

上一版条件披露测试包保留于里程碑 104，可用 `tool/deploy_milestone.ps1 -Name 104-offer-disclosure` 回退。
