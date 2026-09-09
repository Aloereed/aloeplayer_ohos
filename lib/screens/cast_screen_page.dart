import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/cast_device.dart';
import '../services/media_cast_service.dart';
import 'castview.dart';

String pathToUri(String path) => path.contains('://') ? path : Uri.file(path).toString();

class CastScreenPage extends StatefulWidget {
  final MediaCastService? castService;
  final bool discover;
  final String mediaPath;
  final String? title;
  final Map<String, String> httpHeaders;
  final Duration initialPosition;
  final VoidCallback? onCastStarted;
  const CastScreenPage({super.key, required this.mediaPath, this.title,
    this.castService, this.discover = true, this.httpHeaders = const {}, this.initialPosition = Duration.zero, this.onCastStarted});
  @override
  State<CastScreenPage> createState() => _CastScreenPageState();
}

class _CastScreenPageState extends State<CastScreenPage> {
  late final service = widget.castService ?? MediaCastService();
  bool _connecting = false;
  double? _drag;
  double _volume = 50;
  CastExample? _systemPicker;
  @override
  void initState() { super.initState(); if (widget.discover) service.startDiscovery(); }

  Future<void> _cast(CastDevice device) async {
    setState(() => _connecting = true);
    try {
      if (!await service.connectToDevice(device)) return;
      if (await service.castMedia(widget.mediaPath, headers: widget.httpHeaders, title: widget.title,
          startPosition: widget.initialPosition)) widget.onCastStarted?.call();
    } finally { if (mounted) setState(() => _connecting = false); }
  }

  Future<void> _manual() async {
    final text = TextEditingController();
    final location = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('手动添加设备'),
      content: TextField(controller: text, autofocus: true, keyboardType: TextInputType.url,
        decoration: const InputDecoration(labelText: '设备描述地址', hintText: 'http://电视IP:端口/description.xml',
          helperText: '使用接收端提供的 DLNA 描述地址，可绕过组播发现限制。', helperMaxLines: 3)),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, text.text.trim()), child: const Text('添加'))]));
    // Dispose after the dialog has completed its closing animation.
    Future<void>.delayed(const Duration(seconds: 1), text.dispose);
    if (location != null && location.isNotEmpty) await service.addDevice(location);
  }

  Future<void> _system() async {
    setState(() => _connecting = true);
    try {
      final url = await service.startLocalServer(widget.mediaPath, headers: widget.httpHeaders);
      if (mounted) setState(() => _systemPicker = CastExample(initUri: '${pathToUri(widget.mediaPath)}|||$url', toggleFullScreen: () {}));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('系统投播准备失败：$e')));
    } finally { if (mounted) setState(() => _connecting = false); }
  }

  String _time(Duration value) => '${value.inMinutes}:${(value.inSeconds%60).toString().padLeft(2,'0')}';
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: service, builder: (context, _) {
    final busy = service.busy || _connecting;
    final active = service.activeDevice;
    final name = widget.title ?? Uri.tryParse(widget.mediaPath)?.pathSegments.lastOrNull ?? widget.mediaPath;
    return Scaffold(
      appBar: AppBar(title: const Text('投屏'), actions: [
        IconButton(tooltip: '刷新设备', onPressed: service.scanning ? null : service.startDiscovery, icon: const Icon(Icons.refresh)),
        IconButton(tooltip: '手动添加设备', onPressed: busy ? null : _manual, icon: const Icon(Icons.add)),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: ListTile(leading: const Icon(Icons.movie_outlined), title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(widget.initialPosition > Duration.zero ? '从 ${_time(widget.initialPosition)} 开始投屏' : '选择设备后开始播放'))),
        const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('手机与电视需连接同一局域网，并在电视上开启 DLNA 接收。投屏期间请保持播放器运行。')),
        if (service.lastError != null) Card(color: Theme.of(context).colorScheme.errorContainer, child: Padding(
          padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText(service.lastError!),
            TextButton.icon(onPressed: () => Clipboard.setData(ClipboardData(text: service.lastError!)), icon: const Icon(Icons.copy), label: const Text('复制错误详情')),
          ]))),
        if (busy) const LinearProgressIndicator(),
        if (active != null) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('已连接：${active.name}', style: Theme.of(context).textTheme.titleMedium),
          Text(active.isPlaying ? '正在投屏' : '已暂停或停止'),
          if (service.duration > Duration.zero) ...[
            Slider(value: (_drag ?? service.position.inSeconds.toDouble()).clamp(0, service.duration.inSeconds.toDouble()),
              max: service.duration.inSeconds.toDouble(), onChanged: busy ? null : (v) => setState(() => _drag = v),
              onChangeEnd: (v) async { await service.seek(Duration(seconds: v.round())); if (mounted) setState(() => _drag = null); }),
            Text('${_time(service.position)} / ${_time(service.duration)}'),
          ],
          Wrap(spacing: 8, children: [
            FilledButton.icon(onPressed: busy ? null : () => _cast(active), icon: const Icon(Icons.cast), label: const Text('投送当前媒体')),
            OutlinedButton.icon(onPressed: busy ? null : (active.isPlaying ? service.pauseMedia : service.resumeMedia), icon: Icon(active.isPlaying ? Icons.pause : Icons.play_arrow), label: Text(active.isPlaying ? '暂停' : '继续')),
            TextButton(onPressed: busy ? null : service.stopMedia, child: const Text('停止')),
            TextButton(onPressed: busy ? null : service.disconnectFromDevice, child: const Text('断开连接')),
          ]),
          if (active.device.renderingControlService != null) Row(children: [const Icon(Icons.volume_up), Expanded(child: Slider(value: _volume, max: 100,
            onChanged: busy ? null : (v) => setState(() => _volume = v), onChangeEnd: (v) => service.setVolume(v.round())))]),
          const Text('返回播放页不会断开投屏；结束时请点“断开连接”。'),
        ]))),
        Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Row(children: [
          Expanded(child: Text('可用设备', style: Theme.of(context).textTheme.titleMedium)),
          if (service.scanning) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        ])),
        if (service.devices.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Text(service.scanning ? '正在搜索电视和播放器…' : '未找到设备。请检查同一 Wi-Fi、电视接收开关和路由器的访客网络隔离，然后刷新或手动添加。')),
        for (final device in service.devices) Card(child: ListTile(
          leading: Icon(device == active ? Icons.cast_connected : Icons.tv),
          title: Text(device.name), subtitle: Text('${device.manufacturer} · ${device.model}'),
          trailing: const Icon(Icons.chevron_right), onTap: busy ? null : () => _cast(device))),
        if (Platform.operatingSystem == 'ohos') ...[
          const Divider(height: 32),
          OutlinedButton.icon(onPressed: busy || active != null ? null : _system, icon: const Icon(Icons.devices), label: const Text('使用鸿蒙系统投播')),
          if (_systemPicker != null) SizedBox(height: 76, child: _systemPicker),
        ],
      ]),
    );
  });
}
