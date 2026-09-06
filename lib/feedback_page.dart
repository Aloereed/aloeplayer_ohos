import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'env/env.dart';

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _content = TextEditingController();
  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    sendTimeout: const Duration(seconds: 20),
  ));
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _content.dispose();
    _dio.close(force: true);
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final base = Env.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '');
      await _dio.post('$base/feedback/', data: {
        'email': _email.text.trim(),
        'content': _content.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('反馈已提交，感谢你的建议！')),
      );
      Navigator.of(context).pop();
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.response?.statusCode == 429
            ? '提交过于频繁，请一分钟后再试。'
            : '提交未成功，请检查网络后重试。你填写的内容已保留。';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '提交未成功，请稍后重试。你填写的内容已保留。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_sending,
      child: Scaffold(
        appBar: AppBar(title: const Text('用户反馈')),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text('无需登录即可反馈问题或建议。反馈内容和邮箱将发送给开发者，邮箱仅用于联系你处理反馈。'),
              const SizedBox(height: 24),
              TextFormField(
                controller: _content,
                enabled: !_sending,
                minLines: 6,
                maxLines: 12,
                maxLength: 5000,
                decoration: const InputDecoration(
                  labelText: '反馈内容',
                  hintText: '请描述遇到的问题或你的建议',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? '请输入反馈内容' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _email,
                enabled: !_sending,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                maxLength: 254,
                decoration: const InputDecoration(
                  labelText: '联系邮箱',
                  hintText: 'name@example.com',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    RegExp(r'^[^\s@]+@[^\s@.]+(?:\.[^\s@.]+)+$')
                            .hasMatch((value ?? '').trim())
                        ? null
                        : '请输入有效的电子邮箱',
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _sending ? null : _submit,
                child: Text(_sending ? '正在提交…' : '提交反馈'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
