import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../feedback_page.dart';

class CustomerSupportButton extends StatelessWidget {
  const CustomerSupportButton({super.key});
  @override
  Widget build(BuildContext context) => TextButton.icon(
    icon: const Icon(Icons.support_agent), label: const Text('联系客服'),
    onPressed: () => showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: const Text('联系客服'),
      content: const SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('客服邮箱'), SelectableText('aloeplayer@aloereed.com'), SizedBox(height: 12),
        Text('可咨询购买、续费、取消订阅及播放问题。请说明问题和应用版本；订单问题可提供订单号，请勿发送密码或支付验证码。'),
      ])),
      actions: [
        TextButton(onPressed: () async {
          await Clipboard.setData(const ClipboardData(text: 'aloeplayer@aloereed.com'));
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('客服邮箱已复制')));
        }, child: const Text('复制邮箱')),
        TextButton(onPressed: () async {
          var opened = false;
          try { opened = await launchUrl(Uri.parse('mailto:aloeplayer@aloereed.com'), mode: LaunchMode.externalApplication); } catch (_) {}
          if (!opened && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未能打开邮件应用，请复制邮箱或使用在线反馈。')));
        }, child: const Text('发送邮件')),
        TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FeedbackPage())), child: const Text('在线反馈')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
      ],
    )));
}
