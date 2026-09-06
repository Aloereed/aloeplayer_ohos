import 'package:flutter/material.dart';
import 'package:aloeplayer/services/membership_service.dart';
import 'package:aloeplayer/services/ohos_iap_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:aloeplayer/services/iap_price.dart';

class MembershipDetailsDialog extends StatefulWidget {
  final MembershipService membershipService;
  const MembershipDetailsDialog({super.key, required this.membershipService});
  @override
  State<MembershipDetailsDialog> createState() => _MembershipDetailsDialogState();
}

class _MembershipDetailsDialogState extends State<MembershipDetailsDialog> {
  final _iap = OhosIapService.instance;
  @override
  void initState() {
    super.initState();
    _iap.load();
    _iap.addListener(_onIapChanged);
    widget.membershipService.addListener(_onMembershipChanged);
    _refreshMembership();
  }

  bool _wasBusy = false;
  void _onMembershipChanged() {
    if (mounted) setState(() {});
  }
  void _onIapChanged() {
    if (_wasBusy && !_iap.busy) _refreshMembership();
    _wasBusy = _iap.busy;
  }

  @override
  void dispose() {
    _iap.removeListener(_onIapChanged);
    widget.membershipService.removeListener(_onMembershipChanged);
    super.dispose();
  }

  String _planName(Object? id) => id == 'premium_1year' ? '年会员' : '月会员';
  String _date(Object? value) => DateTime.tryParse(value?.toString() ?? '')?.toLocal().toString().split(' ').first ?? '当前周期结束后';

  Future<void> _refreshMembership() async {
    try { await widget.membershipService.fetchMySubscriptions().timeout(const Duration(seconds: 20)); }
    catch (_) { /* Keep cached membership visible while offline. */ }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: _iap, builder: (context, _) {
    final colors = Theme.of(context).colorScheme;
    final product = _iap.product;
    final price = product == null ? null : IapPrice.forProduct(product);
    final membership = widget.membershipService;
    return AlertDialog(
      title: const Text('会员服务'),
      content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(membership.isPremium ? '当前会员：${membership.subscriptionName ?? '付费会员'}' : '当前未开通会员',
            style: Theme.of(context).textTheme.titleSmall),
          if (membership.expiryDate != null) Text('有效期至 ${membership.expiryDate!.toLocal().toString().split(' ').first}'),
          const SizedBox(height: 20),
          Wrap(spacing: 10, runSpacing: 8, children: [
            for (final plan in _iap.products)
              ChoiceChip(label: Text('${_planName(plan.id)}  ${IapPrice.forProduct(plan).displayPrice}'),
                selected: product?.id == plan.id,
                onSelected: _iap.busy ? null : (_) => _iap.selectProduct(plan.id)),
          ]),
          const SizedBox(height: 12),
          Text(product?.title ?? '会员方案', style: Theme.of(context).textTheme.titleLarge),
          if (product != null) ...[
            const SizedBox(height: 8),
            Text(price!.displayPrice, style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: colors.primary)),
            if (price.originalPrice != null) Text(price.originalPrice!,
              style: TextStyle(color: colors.onSurfaceVariant, decoration: TextDecoration.lineThrough)),
            if (price.explanation != null) Text(price.explanation!, style: TextStyle(color: colors.primary)),
            if (product.description.isNotEmpty) Text(product.description),
          ],
          const SizedBox(height: 8),
          Text('${product?.id == 'premium_1year' ? '按年' : '按月'}自动续费，价格、优惠及切换生效时间以华为支付页面为准。可在“管理订阅”中取消续费。'),
          const SizedBox(height: 8),
          const Text('月、年方案权益相同。同等级方案通常在当前周期结束后切换，现有会员继续有效。'),
          for (final plan in _iap.subscriptionPlans)
            Padding(padding: const EdgeInsets.only(top: 10), child: Text(
              plan['next_product_id'] != null && plan['next_product_id'] != plan['current_product_id']
                ? '当前：${_planName(plan['current_product_id'])}；预计 ${_date(plan['change_date'])} 切换为${_planName(plan['next_product_id'])}'
                : '当前华为方案：${_planName(plan['current_product_id'])}，有效期至 ${_date(plan['expiry_date'])}',
              style: TextStyle(color: colors.primary))),
          const SizedBox(height: 12),
          if (!_iap.serverReady) const Text('购买前请先登录应用账号，会员将绑定到该账号。'),
          const SizedBox(height: 16),
          if (_iap.busy) const LinearProgressIndicator(),
          if (_iap.message != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12),
            child: Semantics(liveRegion: true, child: Text(_iap.message!))),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: FilledButton(
            onPressed: _iap.busy || product == null || !_iap.serverReady || _iap.pendingVerification ? null : _iap.purchase,
            child: Text(_iap.pendingVerification ? '订单待验证' : membership.isPremium ? '订购或切换方案' : '开通${_planName(product?.id)}'))),
          Wrap(spacing: 8, children: [
            TextButton(onPressed: _iap.busy ? null : _iap.load, child: const Text('重新加载')),
            TextButton(onPressed: _iap.busy ? null : _iap.restore, child: const Text('恢复购买')),
            TextButton(onPressed: _iap.busy ? null : _iap.manage, child: const Text('管理订阅')),
          ]),
          TextButton.icon(onPressed: () => launchUrl(Uri.parse('https://afdian.com/a/aloereed'),
            mode: LaunchMode.externalApplication), icon: const Icon(Icons.favorite_border), label: const Text('支持作者')),
        ],
      ))),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
    );
  });
}
