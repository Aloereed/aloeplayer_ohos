import 'package:flutter/material.dart';
import '../services/media_url.dart';

Future<String?> showMediaUrlDialog(BuildContext context) => showDialog<String>(
  context: context, builder: (_) => const _MediaUrlDialog());

class _MediaUrlDialog extends StatefulWidget {
  const _MediaUrlDialog();
  @override
  State<_MediaUrlDialog> createState() => _MediaUrlDialogState();
}

class _MediaUrlDialogState extends State<_MediaUrlDialog> {
  final _text = TextEditingController();
  String? _error;
  String? _selected;
  bool _busy = false;
  @override
  void dispose() { _text.dispose(); super.dispose(); }

  Future<void> _open() async {
    final urls = extractMediaUrls(_text.text);
    final url = _selected ?? (urls.length == 1 ? urls.first : null);
    if (url == null) {
      setState(() => _error = urls.isEmpty ? '未找到有效的 HTTP/HTTPS 链接，请检查粘贴内容。' : '检测到多个链接，请先选择要播放的链接。');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await validateMediaUrl(url);
      if (mounted) Navigator.pop(context, url);
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = mediaUrlFailure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final urls = extractMediaUrls(_text.text);
    return AlertDialog(
      title: const Text('打开视频直链'),
      content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(mediaUrlHint, style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          TextField(controller: _text, enabled: !_busy, minLines: 2, maxLines: 4,
            decoration: const InputDecoration(labelText: '链接或分享文本', border: OutlineInputBorder()),
            onChanged: (_) => setState(() { _selected = null; _error = null; })),
          if (urls.length == 1) Padding(padding: const EdgeInsets.only(top: 8), child: Text('识别到：${urls.first}')),
          if (urls.length > 1) for (final url in urls) RadioListTile<String>(
            title: Text(url), value: url, groupValue: _selected,
            onChanged: _busy ? null : (value) => setState(() => _selected = value)),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12),
            child: Semantics(liveRegion: true, child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)))),
        ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: _busy ? null : _open, child: Text(_busy ? '正在检查链接…' : '播放'))],
    );
  }
}
