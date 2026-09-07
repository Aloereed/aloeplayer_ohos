import 'widgets/subscription_terms.dart';
import 'widgets/customer_support.dart';
import 'services/member_access.dart';
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
    MemberAccess.instance.initialize().then((_) { if (mounted) setState(() {}); }).catchError((_) {});
    MemberAccess.instance.addListener(_onMembershipChanged);
    _iap.addListener(_onIapChanged);
    widget.membershipService.addListener(_onMembershipChanged);
    _refreshMembership();
  }

  bool _startingTrial = false;
  String? _trialError;
  Future<void> _startTrial() async {
    setState(() { _startingTrial = true; _trialError = null; });
    try { await MemberAccess.instance.startTrial(); }
    catch (_) { if (mounted) setState(() => _trialError = '体验未能开启，请稍后重试'); }
    finally { if (mounted) setState(() => _startingTrial = false); }
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
    MemberAccess.instance.removeListener(_onMembershipChanged);
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
    final theme = Theme.of(context), colors = theme.colorScheme;
    final product = _iap.product;
    final price = product == null ? null : IapPrice.forProduct(product);
    final membership = widget.membershipService;
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 12, 12, 0),
      title: Row(children: [
        const Expanded(child: Text('会员服务')),
        IconButton(tooltip: '关闭', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
      ]),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(membership.isPremium ? '${membership.subscriptionName ?? '付费会员'} · ${_date(membership.expiryDate?.toIso8601String())}到期' : 'Anime4K / FSR 画质增强 · 更多服务器 · 批量下载',
            style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 8, children: [
            for (final plan in _iap.products)
              ChoiceChip(label: Text('${_planName(plan.id)}  ${IapPrice.forProduct(plan).displayPrice}'),
                selected: product?.id == plan.id,
                onSelected: _iap.busy ? null : (_) => _iap.selectProduct(plan.id)),
          ]),
          for (final plan in _iap.subscriptionPlans)
            if (plan['next_product_id'] != null && plan['next_product_id'] != plan['current_product_id'])
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(
                '已预约：${_date(plan['change_date'])} 切换为${_planName(plan['next_product_id'])}',
                style: TextStyle(color: colors.primary))),
          if (!_iap.serverReady) const Padding(padding: EdgeInsets.only(top: 8),
            child: Text('请先登录，会员将绑定到应用账号。')),
          if (_iap.busy) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
          if (_iap.message != null) Padding(padding: const EdgeInsets.only(top: 8),
            child: Semantics(liveRegion: true, child: Text(_iap.message!))),
          if (MemberAccess.instance.trialActive)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text('本机体验至 ${_date(MemberAccess.instance.trialEnds?.toIso8601String())}，不自动续费。')),
          if (MemberAccess.instance.initialized && MemberAccess.instance.canStartTrial)
            Padding(padding: const EdgeInsets.only(top: 8), child: TextButton(
              onPressed: _startingTrial ? null : _startTrial,
              child: Text(_startingTrial ? '正在开启…' : '免费体验 7 天 · 不自动续费'))),
          if (_trialError != null) Text(_trialError!),
          Wrap(spacing: 4, children: [
            TextButton(onPressed: _iap.busy ? null : _iap.restore, child: const Text('恢复购买')),
            TextButton(onPressed: _iap.busy ? null : _iap.manage, child: const Text('管理订阅')),
            TextButton(onPressed: _iap.busy ? null : _iap.load, child: const Text('重新加载')),
          ]),
          const SubscriptionTerms(),
          const CustomerSupportButton(),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            title: Text('权益与订阅说明', style: theme.textTheme.bodyMedium),
            children: [Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final feature in MemberFeature.values)
                Padding(padding: const EdgeInsets.only(bottom: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(feature.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(feature.description),
                ])),
              const Text('基础播放、字幕、画中画、继续观看、海报库及单文件下载免费。到期后保留已有来源、文件和记录，已加入的下载可继续。'),
              const SizedBox(height: 8),
              const Text('月、年方案权益相同。同等级方案通常在当前周期结束后切换，现有会员继续有效。价格、优惠及切换时间以华为支付页面为准。'),
              if (product != null && product.description.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 8), child: Text(product.description)),
              TextButton.icon(onPressed: () => launchUrl(Uri.parse('https://afdian.com/a/aloereed'),
                mode: LaunchMode.externalApplication), icon: const Icon(Icons.favorite_border), label: const Text('支持作者')),
            ])],
          ),
        ],
      ))),
      // Checkout stays visible while the optional details scroll independently.
      actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      actions: [SizedBox(width: double.infinity, child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          if (price != null) ...[
            Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('${_planName(product!.id)} · ${price.displayPrice}',
                style: theme.textTheme.titleLarge?.copyWith(color: colors.primary)),
              if (price.originalPrice != null) Text(price.originalPrice!,
                style: TextStyle(color: colors.onSurfaceVariant, decoration: TextDecoration.lineThrough)),
            ]),
            if (price.explanation != null) Text(price.explanation!, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 6),
          Text(product == null ? '价格加载后可购买' : '每${product.id == 'premium_1year' ? '年' : '月'}自动续费 ${product.price}，可在“管理订阅”取消。', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _iap.busy || product == null || !_iap.serverReady || _iap.pendingVerification ? null : () async {
              final selected = product;
              final summary = '${_planName(selected.id)}：开通时 ${price!.displayPrice}。${price.explanation ?? ''}\n后续每${selected.id == 'premium_1year' ? '年' : '月'}自动续费 ${selected.price}。';
              if (!await confirmSubscription(context, summary) || !mounted) return;
              if (_iap.product != selected || _iap.busy) return;
              await _iap.purchase();
            },
            child: Text(_iap.pendingVerification ? '订单待验证' : membership.isPremium ? '订购或切换方案' : '开通${_planName(product?.id)}')),
        ],
      ))],
    );
  });
}
