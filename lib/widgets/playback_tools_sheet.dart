import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import '../services/playback_tools_store.dart';
import 'sleep_timer_button.dart';

Future<void> applyPlaybackPreferences(Player player, String id) async {
  final settings = await PlaybackToolsStore.preferences(id);
  final native = player.platform;
  if (native is! NativePlayer) return;
  await native.setProperty('sub-delay', '${settings.subtitleDelay}');
  await native.setProperty('audio-delay', '${settings.audioDelay}');
  await native.setProperty('slang', settings.subtitleLanguage);
  await native.setProperty('alang', settings.audioLanguage);
  if (settings.subtitleTrack == 'no') {
    await player.setSubtitleTrack(SubtitleTrack.no());
  } else if (settings.subtitleTrack != null) {
    final track = player.state.tracks.subtitle.where((t) => t.id == settings.subtitleTrack).firstOrNull;
    if (track != null) await player.setSubtitleTrack(track);
  }
  if (settings.audioTrack != null) {
    final track = player.state.tracks.audio.where((t) => t.id == settings.audioTrack).firstOrNull;
    if (track != null) await player.setAudioTrack(track);
  }
}

class PlaybackToolsSheet extends StatefulWidget {
  final Player player;
  final String mediaId;
  final void Function(Duration start, Duration? end) onBookmark;
  final Duration? loopStart;
  final Duration? loopEnd;
  const PlaybackToolsSheet({super.key, required this.player, required this.mediaId, required this.onBookmark, this.loopStart, this.loopEnd});
  @override
  State<PlaybackToolsSheet> createState() => _PlaybackToolsSheetState();
}
class _PlaybackToolsSheetState extends State<PlaybackToolsSheet> {
  PlaybackPreferences? _preferences;
  List<MediaBookmark> _bookmarks = [];
  List<MediaBookmark> _chapters = [];
  String? _error;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final settings = await PlaybackToolsStore.preferences(widget.mediaId);
    final bookmarks = await PlaybackToolsStore.bookmarks(widget.mediaId);
    final chapters = <MediaBookmark>[];
    try {
      final native = widget.player.platform;
      if (native is NativePlayer) {
        final count = int.tryParse(await native.getProperty('chapter-list/count')) ?? 0;
        for (var i = 0; i < count.clamp(0, 300); i++) {
          final time = double.tryParse(await native.getProperty('chapter-list/$i/time')) ?? 0;
          final title = await native.getProperty('chapter-list/$i/title');
          chapters.add(MediaBookmark(title.isEmpty ? '章节 ${i + 1}' : title, (time * 1000).round()));
        }
      }
    } catch (_) { /* Chapters are optional; bookmarks remain available. */ }
    if (mounted) setState(() { _preferences = settings; _bookmarks = bookmarks; _chapters = chapters; });
  }
  Future<void> _addBookmark(bool loop) async {
    final controller = TextEditingController(text: loop ? '循环片段' : '书签 ${_bookmarks.length + 1}');
    final name = await showDialog<String>(context: context, builder: (context) => AlertDialog(title: const Text('命名书签'),
      content: TextField(controller: controller, maxLength: 80, autofocus: true), actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('保存')),
      ]));
    // The dialog's route transition may still reference its controller.
    Future.delayed(const Duration(seconds: 1), controller.dispose);
    if (name == null || name.isEmpty || !mounted) return;
    _bookmarks.add(MediaBookmark(name, (loop ? widget.loopStart! : widget.player.state.position).inMilliseconds,
      endMs: loop ? widget.loopEnd?.inMilliseconds : null));
    await PlaybackToolsStore.saveBookmarks(widget.mediaId, _bookmarks);
    if (mounted) setState(() {});
  }
  Future<void> _save() async {
    try {
      await PlaybackToolsStore.savePreferences(widget.mediaId, _preferences!);
      await applyPlaybackPreferences(widget.player, widget.mediaId);
      if (mounted) Navigator.pop(context);
    } catch (_) { if (mounted) setState(() => _error = '应用设置失败，请稍后重试'); }
  }
  void _change({double? sub, double? audio, String? slang, String? alang, String? sid, String? aid}) {
    final old = _preferences!;
    setState(() => _preferences = PlaybackPreferences(subtitleDelay: sub ?? old.subtitleDelay, audioDelay: audio ?? old.audioDelay,
      subtitleLanguage: slang ?? old.subtitleLanguage, audioLanguage: alang ?? old.audioLanguage,
      subtitleTrack: sid ?? old.subtitleTrack, audioTrack: aid ?? old.audioTrack));
  }
  Widget _language(String title, String value, ValueChanged<String> onChange) => DropdownButtonFormField<String>(
    initialValue: ['', 'zh,zho,chi,chs,cht', 'en,eng', 'ja,jpn'].contains(value) ? value : '', decoration: InputDecoration(labelText: title),
    items: const [DropdownMenuItem(value: '', child: Text('自动')), DropdownMenuItem(value: 'zh,zho,chi,chs,cht', child: Text('中文优先')),
      DropdownMenuItem(value: 'en,eng', child: Text('英语优先')), DropdownMenuItem(value: 'ja,jpn', child: Text('日语优先'))],
    onChanged: (value) => onChange(value ?? ''));
  @override
  Widget build(BuildContext context) {
    final settings = _preferences;
    return SafeArea(child: SizedBox(height: MediaQuery.sizeOf(context).height * 0.85,
      child: settings == null ? const Center(child: CircularProgressIndicator()) : ListView(padding: const EdgeInsets.all(20), children: [
        Row(children: [const Expanded(child: Text('播放工具', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))), const SleepTimerButton(), IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close))]),
        Text('字幕延迟 ${settings.subtitleDelay.toStringAsFixed(1)} 秒（正值延后）'),
        Slider(value: settings.subtitleDelay.clamp(-10, 10), min: -10, max: 10, divisions: 200, onChanged: (v) => _change(sub: v)),
        Text('声音延迟 ${settings.audioDelay.toStringAsFixed(1)} 秒（正值延后）'),
        Slider(value: settings.audioDelay.clamp(-5, 5), min: -5, max: 5, divisions: 100, onChanged: (v) => _change(audio: v)),
        _language('字幕语言', settings.subtitleLanguage, (v) => _change(slang: v)),
        _language('音轨语言', settings.audioLanguage, (v) => _change(alang: v)),
        DropdownButtonFormField<String>(decoration: const InputDecoration(labelText: '记住字幕轨道'),
          initialValue: widget.player.state.tracks.subtitle.any((t) => t.id == settings.subtitleTrack) ? settings.subtitleTrack : null,
          items: widget.player.state.tracks.subtitle.where((t) => !t.id.contains('://')).map((t) => DropdownMenuItem(value: t.id, child: Text(t.title ?? t.language ?? t.id, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) => _change(sid: v)),
        DropdownButtonFormField<String>(decoration: const InputDecoration(labelText: '记住音轨'),
          initialValue: widget.player.state.tracks.audio.any((t) => t.id == settings.audioTrack) ? settings.audioTrack : null,
          items: widget.player.state.tracks.audio.map((t) => DropdownMenuItem(value: t.id, child: Text(t.title ?? t.language ?? t.id, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) => _change(aid: v)),
        if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
        FilledButton(onPressed: _save, child: const Text('应用并记住此媒体设置')),
        const Divider(),
        Wrap(spacing: 8, children: [OutlinedButton.icon(onPressed: () => _addBookmark(false), icon: const Icon(Icons.bookmark_add_outlined), label: const Text('保存当前位置')),
          if (widget.loopStart != null && widget.loopEnd != null) OutlinedButton(onPressed: () => _addBookmark(true), child: const Text('保存 AB 循环'))]),
        for (var i = 0; i < _bookmarks.length; i++) ListTile(title: Text(_bookmarks[i].name), subtitle: Text('${(_bookmarks[i].positionMs / 60000).toStringAsFixed(1)} 分钟${_bookmarks[i].endMs != null ? ' · 循环片段' : ''}'),
          onTap: () { final b = _bookmarks[i]; widget.onBookmark(Duration(milliseconds: b.positionMs), b.endMs == null ? null : Duration(milliseconds: b.endMs!)); Navigator.pop(context); },
          trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async { _bookmarks.removeAt(i); await PlaybackToolsStore.saveBookmarks(widget.mediaId, _bookmarks); if (mounted) setState(() {}); })),
        const Divider(), const Text('章节', style: TextStyle(fontWeight: FontWeight.bold)),
        if (_chapters.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('此媒体没有可读取的章节')),
        for (final chapter in _chapters) ListTile(title: Text(chapter.name), onTap: () { widget.player.seek(Duration(milliseconds: chapter.positionMs)); Navigator.pop(context); }),
      ])));
  }
}
