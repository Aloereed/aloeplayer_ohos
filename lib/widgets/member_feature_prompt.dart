import 'package:flutter/material.dart';
import '../membership_details.dart';
import '../services/member_access.dart';
import '../services/membership_service.dart';

/// Invoked only after an explicit feature action; dismissing has no side effects.
Future<bool> requestMemberFeature(BuildContext context, MemberFeature feature) async {
  final access = MemberAccess.instance;
  try { await access.initialize(); }
  catch (_) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('暂时无法读取权益，请稍后重试')));
    return false;
  }
  if (access.unlocked) return true;
  if (!context.mounted) return false;
  final choice = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
    title: Text(feature.title),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(feature.description),
      const SizedBox(height: 12),
      Text(access.canStartTrial ? '可在本机免费体验 7 天，无需支付，不会自动续费。体验结束后，已保存的来源和已加入队列的下载仍可使用。' : '已有来源、下载文件和基础播放不受影响。'),
    ])),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('暂时不用')),
      TextButton(onPressed: () => Navigator.pop(ctx, 'plans'), child: const Text('查看会员权益')),
      if (access.canStartTrial) FilledButton(onPressed: () => Navigator.pop(ctx, 'trial'), child: const Text('免费体验 7 天')),
    ],
  ));
  if (!context.mounted) return false;
  if (choice == 'trial') {
    try { return await access.startTrial(); }
    catch (_) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('体验未能开启，请稍后重试')));
      return false;
    }
  }
  if (choice == 'plans') {
    await showDialog<void>(context: context, builder: (_) => MembershipDetailsDialog(membershipService: MembershipService()));
  }
  return access.unlocked;
}
