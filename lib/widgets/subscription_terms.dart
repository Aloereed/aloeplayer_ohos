import 'package:flutter/material.dart';
import '../services/ohos_iap_service.dart';
import 'customer_support.dart';

const cancellationInstructions = '取消流程：点击“管理订阅”，在华为订阅管理页选择 AloePlayer 订阅，关闭自动续费并确认结果。也可前往系统设置 → 华为账号 → 付款与账单 → 自动续费/订阅，选择本应用取消（菜单名称以设备显示为准）。请在下一次扣费前取消；取消后当前已付费周期内仍可使用会员，到期后不再续费。卸载应用或退出账号不会取消订阅。';

class SubscriptionTerms extends StatelessWidget {
  const SubscriptionTerms({super.key});
  @override
  Widget build(BuildContext context) => Wrap(children: [
    for (final renewal in [false, true]) TextButton(
      onPressed: () => showDialog<void>(context: context, builder: (context) => AlertDialog(
        title: Text(renewal ? '自动续费服务协议' : '会员服务说明'),
        content: SingleChildScrollView(child: Text(renewal
          ? '您主动同意并确认购买后，将通过华为支付开通所选月或年自动续费订阅。首次金额、优惠适用期限及后续续费金额在购买页和确认页展示，请核对华为支付页的实际订单。\n\n除非主动取消，华为支付会按照所选周期从您的支付方式扣款并延长会员服务。优惠结束后按显示的常规价格续费。本机免费体验不会自动转为付费订阅。\n\n$cancellationInstructions'
          : '会员提供 Anime4K / FSR 画质增强、更多服务器及批量下载等权益，月会员和年会员权益相同。基础播放等免费功能无需订阅。\n\n购买绑定当前应用账号。服务期限以验证后的订单为准，可通过“恢复购买”恢复权益。到期后保留已有来源、文件和记录。月/年方案切换的生效时间以华为支付页为准，请核对后确认。\n\n购买或订单问题可通过“联系客服”咨询；退款申请按华为支付订单页面的流程及适用规则处理。')),
        actions: [const CustomerSupportButton(), TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
      )), child: Text(renewal ? '自动续费服务协议' : '会员服务说明')),
    TextButton(onPressed: () => showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: const Text('如何取消自动续费'), content: const SingleChildScrollView(child: Text(cancellationInstructions)),
      actions: [TextButton(onPressed: OhosIapService.instance.manage, child: const Text('管理订阅')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
    )), child: const Text('取消自动续费流程')),
  ]);
}

Future<bool> confirmSubscription(BuildContext context, String summary) async {
  var accepted = false;
  return await showDialog<bool>(context: context, builder: (context) => StatefulBuilder(
    builder: (context, setState) => AlertDialog(
      title: const Text('确认付费与自动续费'),
      scrollable: true,
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(summary, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        const Text('这是自动续费订阅，除非主动取消，否则将持续按所选周期扣费。'),
        const SubscriptionTerms(),
        const Text(cancellationInstructions),
        CheckboxListTile(contentPadding: EdgeInsets.zero, value: accepted,
          onChanged: (value) => setState(() => accepted = value ?? false),
          title: const Text('我已阅读并同意会员服务说明和自动续费服务协议，了解扣费金额、周期及取消流程，自愿开通自动续费')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        FilledButton(onPressed: accepted ? () => Navigator.pop(context, true) : null, child: const Text('同意并前往支付'))],
    ))) ?? false;
}
