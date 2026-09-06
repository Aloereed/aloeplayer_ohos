import 'package:flutter/material.dart';
import 'package:aloeplayer/services/membership_service.dart';
import 'package:aloeplayer/services/ohos_iap_service.dart';
import 'package:url_launcher/url_launcher.dart';

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
    _refreshMembership();
  }

  Future<void> _refreshMembership() async {
    try { await widget.membershipService.fetchMySubscriptions().timeout(const Duration(seconds: 20)); }
    catch (_) { /* Keep cached membership visible while offline. */ }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: _iap, builder: (context, _) {
    final colors = Theme.of(context).colorScheme;
    final product = _iap.product;
    final membership = widget.membershipService;
    return AlertDialog(
      title: const Text('会员服务'),
      content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(membership.isPremium ? '当前会员：${membership.subscriptionName ?? '付费会员'}' : '当前未开通会员',
            style: Theme.of(context).textTheme.titleSmall),
          if (membership.expiryDate != null) Text('有效期至 ${membership.expiryDate!.toLocal().toString().split(' ').first}'),
          const SizedBox(height: 20),
          Text(product?.title ?? '月度会员', style: Theme.of(context).textTheme.titleLarge),
          if (product != null) ...[
            const SizedBox(height: 8),
            Text(product.price, style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: colors.primary)),
            if (product.description.isNotEmpty) Text(product.description),
          ],
          const SizedBox(height: 8),
          const Text('按月自动续费，价格及优惠以华为支付页面为准。可在“管理订阅”中取消续费。'),
          const SizedBox(height: 12),
          if (!_iap.serverReady) const Text('购买前请先登录应用账号，会员将绑定到该账号。'),
          const SizedBox(height: 16),
          if (_iap.busy) const LinearProgressIndicator(),
          if (_iap.message != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12),
            child: Semantics(liveRegion: true, child: Text(_iap.message!))),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: FilledButton(
            onPressed: _iap.busy || product == null || !_iap.serverReady || _iap.pendingVerification ? null : _iap.purchase,
            child: Text(_iap.pendingVerification ? '订单待验证' : '购买月会员'))),
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
