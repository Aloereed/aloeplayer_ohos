import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../settings.dart';
import '../services/private_space.dart';
import '../services/shortcut_source.dart';
import '../models/playback_media.dart';
import '../mpvplayer.dart';

class PrivateSpacePage extends StatefulWidget {
  final String? importSource;
  final PrivateSpace? space;
  const PrivateSpacePage({super.key, this.importSource, this.space});
  @override
  State<PrivateSpacePage> createState() => _PrivateSpacePageState();
}

class _PrivateSpacePageState extends State<PrivateSpacePage>
    with WidgetsBindingObserver {
  late final PrivateSpace space;
  final _pin = TextEditingController(),
      _confirmation = TextEditingController(),
      _search = TextEditingController();
  bool _ready = false, _busy = false;
  String? _error;
  List<String> _pending = [];
  static Future<void> _windowTail = Future.value();
  Future<void> _protect(bool value) {
    if (Platform.operatingSystem != 'ohos') return Future.value();
    final next = _windowTail.then((_) =>
        const MethodChannel('aloeplayer/device-tools')
            .invokeMethod<void>('privateWindow', {'enabled': value}));
    _windowTail =
        next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  @override
  void initState() {
    super.initState();
    space = widget.space ?? PrivateSpace.instance;
    space.lock();
    space.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    if (widget.importSource != null) _pending = [widget.importSource!];
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _protect(true);
      await space.initialize();
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _error = '隐私空间暂时无法初始化，请退出后重试。');
    }
  }

  void _changed() {
    if (!space.unlocked) {
      _error = null;
      _pin.clear();
      _confirmation.clear();
      _search.clear();
    }
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      space.lock();
      _pin.clear();
      _confirmation.clear();
      _search.clear();
      final ownRoute = ModalRoute.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ownRoute?.isActive == true)
          Navigator.of(context).popUntil((route) => route == ownRoute);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    space.removeListener(_changed);
    space.lock();
    unawaited(_protect(false).catchError((_) {}));
    _pin.dispose();
    _confirmation.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _authenticate() async {
    if (_busy || !_ready) return;
    final pin = _pin.text;
    if (!space.configured && pin != _confirmation.text) {
      setState(() => _error = '两次 PIN 不一致');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!space.configured) {
        await space.configure(pin);
      } else if (!await space.unlock(pin)) {
        throw StateError('PIN 不正确');
      }
      _pin.clear();
      _confirmation.clear();
      await _finishImport();
    } catch (error) {
      if (mounted)
        setState(
            () => _error = error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finishImport() async {
    while (mounted && _pending.isNotEmpty && space.unlocked) {
      final original = _pending.first;
      String source;
      if (isMediaShortcut(original)) {
        source = await resolveMediaShortcut(original);
      } else {
        await activateShortcutSource(original);
        source = shortcutPlaybackSource(original);
      }
      if (!mounted || !space.unlocked) return;
      final uri = Uri.tryParse(source);
      if (uri?.hasScheme == true &&
          !RegExp(r'^[A-Za-z]:[\\/]').hasMatch(source))
        throw StateError('此文件提供方暂不支持直接导入，请先复制到本地视频库。');
      await space.importFile(source);
      _pending.removeAt(0);
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final selected = await SettingsService().getPersistPermission(
          '媒体文件|.mp4,.mkv,.avi,.mov,.webm,.ts,.m4v,.mp3,.flac,.m4a,.wav,.aac,.ogg,.opus');
      if (!mounted) return;
      _pending.addAll(selected.split('|||').where((value) => value.isNotEmpty));
      if (space.unlocked) await _finishImport();
    } catch (error) {
      if (mounted)
        setState(
            () => _error = space.unlocked ? error.toString() : '导入未完成，请解锁后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _play(PrivateMedia item) async {
    final source = space.sourceFor(item);
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => MPVPlayer(
                filePath: source,
                privateMode: true,
                mediaQueue: [
                  PlaybackMedia(
                      id: 'private:${item.id}', url: source, title: item.name)
                ])));
    space.lock();
  }

  Future<void> _delete(PrivateMedia item) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('删除私密文件？'),
                content: const Text('此操作删除隐私空间内的副本，无法撤销。导入来源不会被删除。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('取消')),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('删除'))
                ]));
    if (confirmed != true || !space.unlocked) return;
    try {
      await space.delete(item);
    } catch (_) {
      if (mounted) setState(() => _error = '删除失败，请稍后重试');
    }
  }

  Future<void> _changePin() async {
    final old = TextEditingController(),
        next = TextEditingController(),
        confirm = TextEditingController();
    String? error;
    await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, update) => AlertDialog(
                    title: const Text('修改 PIN'),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      _pinField(old, '原 PIN'),
                      _pinField(next, '新 PIN'),
                      _pinField(confirm, '再次输入新 PIN'),
                      if (error != null) Text(error!)
                    ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('取消')),
                      TextButton(
                          onPressed: () async {
                            try {
                              if (next.text != confirm.text)
                                throw StateError('两次 PIN 不一致');
                              await space.changePin(old.text, next.text);
                              if (ctx.mounted) Navigator.pop(ctx);
                            } catch (_) {
                              if (ctx.mounted)
                                update(() =>
                                    error = '修改失败，请检查原 PIN 和两次新 PIN，或稍后再试');
                            }
                          },
                          child: const Text('保存'))
                    ])));
    // Controllers may still be used by the dialog's exit transition.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    old.dispose();
    next.dispose();
    confirm.dispose();
  }

  Widget _pinField(TextEditingController controller, String label) => TextField(
      controller: controller,
      obscureText: true,
      enableSuggestions: false,
      autocorrect: false,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6)
      ],
      decoration: InputDecoration(labelText: label));
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('隐私空间'), actions: [
        if (space.unlocked)
          IconButton(
              tooltip: '立即锁定',
              icon: const Icon(Icons.lock),
              onPressed: space.lock),
        if (space.unlocked)
          IconButton(
              tooltip: '修改 PIN',
              icon: const Icon(Icons.password),
              onPressed: _busy ? null : _changePin),
      ]),
      body: !space.unlocked
          ? Center(
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.lock_person_outlined, size: 56),
                        const SizedBox(height: 20),
                        Text(space.configured ? '输入 PIN 解锁' : '设置 6 位数字 PIN',
                            style: Theme.of(context).textTheme.titleLarge),
                        _pinField(_pin, 'PIN'),
                        if (!space.configured)
                          _pinField(_confirmation, '再次输入 PIN'),
                        const SizedBox(height: 16),
                        const Text(
                            '文件保存在应用私有目录，不额外加密。切到后台或离开后需要重新解锁。请记住 PIN，忘记后无法通过应用找回。'),
                        if (_pending.isNotEmpty)
                          const Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: Text('解锁后完成待导入文件')),
                        if (_error != null)
                          Text(_error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error)),
                        const SizedBox(height: 16),
                        FilledButton(
                            onPressed: !_ready || _busy ? null : _authenticate,
                            child: Text(_busy
                                ? '处理中…'
                                : (space.configured ? '解锁' : '创建隐私空间'))),
                      ]))))
          : Column(children: [
              if (_busy) const LinearProgressIndicator(),
              Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    const Text(
                        '导入会创建独立副本，原文件仍留在原位置。私密播放不记录到普通历史，且不使用投屏、画中画和后台播放。'),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                        onPressed: _busy ? null : _import,
                        icon: const Icon(Icons.add),
                        label: const Text('导入副本')),
                    TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: '搜索隐私空间')),
                    if (_error != null)
                      Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                  ])),
              Expanded(
                  child: space.items.isEmpty
                      ? const Center(child: Text('尚无私密媒体，点击“导入副本”添加'))
                      : ListView(children: [
                          for (final item in space.items.where((item) => item
                              .name
                              .toLowerCase()
                              .contains(_search.text.toLowerCase())))
                            ListTile(
                                leading: const Icon(Icons.video_file_outlined),
                                title: Text(item.name),
                                subtitle: Text(
                                    '${(item.bytes / 1048576).toStringAsFixed(1)} MB'),
                                onTap: _busy ? null : () => _play(item),
                                trailing: IconButton(
                                    tooltip: '删除私密文件',
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed:
                                        _busy ? null : () => _delete(item))),
                        ])),
            ]));
}
