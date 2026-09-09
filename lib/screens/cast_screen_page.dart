import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/cast_device.dart';
import '../services/media_cast_service.dart';
import 'castview.dart';

String pathToUri(String path) =>
    path.contains('://') ? path : Uri.file(path).toString();

class CastScreenPage extends StatefulWidget {
  final MediaCastService? castService;
  final bool discover;
  final String mediaPath;
  final String? title;
  final Map<String, String> httpHeaders;
  final Duration initialPosition;
  final Duration mediaDuration;
  final bool isAudio;
  final VoidCallback? onCastStarted;
  const CastScreenPage(
      {super.key,
      required this.mediaPath,
      this.title,
      this.castService,
      this.discover = true,
      this.httpHeaders = const {},
      this.initialPosition = Duration.zero,
      this.mediaDuration = Duration.zero,
      this.isAudio = false,
      this.onCastStarted});
  @override
  State<CastScreenPage> createState() => _CastScreenPageState();
}

class _CastScreenPageState extends State<CastScreenPage> {
  late final service = widget.castService ?? MediaCastService();
  bool _connecting = false;
  double? _drag;
  double _volume = 50;
  CastExample? _systemPicker;
  bool _relayNetwork = true;
  List<NetworkInterface> _interfaces = const [];
  @override
  void initState() {
    super.initState();
    if (widget.discover) {
      service.startDiscovery();
      MediaCastService.localInterfaces().then((interfaces) {
        if (mounted) setState(() => _interfaces = interfaces);
      }).catchError((Object _) {});
    }
  }

  Future<void> _cast(CastDevice device) async {
    if (_systemPicker != null) return;
    setState(() => _connecting = true);
    try {
      if (!await service.connectToDevice(device)) return;
      if (await service.castMedia(widget.mediaPath,
          headers: widget.httpHeaders,
          title: widget.title,
          relayNetwork: _relayNetwork,
          isAudio: widget.isAudio,
          startPosition: widget.initialPosition)) widget.onCastStarted?.call();
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _manual() async {
    final text = TextEditingController();
    final location = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('手动添加设备'),
                content: TextField(
                    controller: text,
                    autofocus: true,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                        labelText: '设备描述地址',
                        hintText: 'http://电视IP:端口/description.xml',
                        helperText: '使用接收端提供的 DLNA 描述地址，可绕过组播发现限制。',
                        helperMaxLines: 3)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, text.text.trim()),
                      child: const Text('添加'))
                ]));
    // Dispose after the dialog has completed its closing animation.
    Future<void>.delayed(const Duration(seconds: 1), text.dispose);
    if (location != null && location.isNotEmpty)
      await service.addDevice(location);
  }

  Future<void> _system() async {
    setState(() => _connecting = true);
    try {
      final url = await service.startLocalServer(widget.mediaPath,
          headers: widget.httpHeaders, forceRelay: _relayNetwork);
      if (!mounted) {
        await service.closeIdleRelay();
        return;
      }
      if (mounted)
        setState(() => _systemPicker = CastExample(
            initUri: jsonEncode({
              'url': url,
              'title': widget.title ??
                  Uri.tryParse(widget.mediaPath)?.pathSegments.lastOrNull ??
                  'AloePlayer',
              'mediaType': widget.isAudio ? 'AUDIO' : 'VIDEO',
              'durationMs': widget.mediaDuration.inMilliseconds,
              'positionMs': widget.initialPosition.inMilliseconds,
            }),
            duration: widget.mediaDuration,
            onCastStarted: widget.onCastStarted,
            toggleFullScreen: () {}));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('系统投播准备失败：$e')));
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  String _time(Duration value) =>
      '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

  Future<void> _closeSystem() async {
    setState(() {
      _systemPicker = null;
      _connecting = true;
    });
    try {
      await service.closeIdleRelay();
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  void dispose() {
    if (_systemPicker != null) unawaited(service.closeIdleRelay());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final busy = service.busy || _connecting;
        final active = service.activeDevice;
        final name = widget.title ??
            Uri.tryParse(widget.mediaPath)?.pathSegments.lastOrNull ??
            widget.mediaPath;
        return Scaffold(
          appBar: AppBar(title: const Text('投屏'), actions: [
            IconButton(
                tooltip: '刷新设备',
                onPressed: service.scanning ? null : service.startDiscovery,
                icon: const Icon(Icons.refresh)),
            IconButton(
                tooltip: '手动添加设备',
                onPressed: busy ? null : _manual,
                icon: const Icon(Icons.add)),
          ]),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            Card(
                child: ListTile(
                    leading: Icon(widget.isAudio
                        ? Icons.music_note
                        : Icons.movie_outlined),
                    title: Text(name,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(widget.initialPosition > Duration.zero
                        ? '从 ${_time(widget.initialPosition)} 开始投屏'
                        : '选择设备后开始播放'))),
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('手机与电视需连接同一局域网，并在电视上开启 DLNA 接收。投屏期间请保持播放器运行。')),
            if (service.lastError != null)
              Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SelectableText(service.lastError!),
                            TextButton.icon(
                                onPressed: () => Clipboard.setData(
                                    ClipboardData(text: service.lastError!)),
                                icon: const Icon(Icons.copy),
                                label: const Text('复制错误详情')),
                          ]))),
            if (busy) const LinearProgressIndicator(),
            Card(
                child: ExpansionTile(title: const Text('投屏网络设置'), children: [
              SwitchListTile(
                  title: const Text('通过本机转发网络媒体'),
                  subtitle: const Text(
                      '帮助仅支持 HTTP 的电视读取 HTTPS、鉴权和 HLS 地址。关闭后，普通网络直链由电视直接读取。'),
                  value: _relayNetwork,
                  onChanged: busy || _systemPicker != null
                      ? null
                      : (value) => setState(() => _relayNetwork = value)),
              ListTile(
                  title: Text(service.preferredInterfaceAddress ?? '自动选择投屏网络'),
                  subtitle:
                      const Text('连接多个网络或 VPN 时，可手动选择 Wi-Fi 地址。更改将在下次投送时生效。'),
                  trailing: PopupMenuButton<String>(
                      tooltip: '选择投屏网络',
                      enabled: !busy && _systemPicker == null,
                      onSelected: (value) => setState(() =>
                          service.preferredInterfaceAddress =
                              value.isEmpty ? null : value),
                      itemBuilder: (_) => [
                            const PopupMenuItem(value: '', child: Text('自动选择')),
                            for (final interface in _interfaces)
                              for (final address in interface.addresses)
                                PopupMenuItem(
                                    value: address.address,
                                    child: Text(
                                        '${interface.name} · ${address.address}')),
                          ])),
            ])),
            if (active != null)
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('已连接：${active.name}',
                                style: Theme.of(context).textTheme.titleMedium),
                            Text(active.isPlaying ? '正在投屏' : '已暂停或停止'),
                            if (service.relayRequests > 0)
                              Text(
                                  '接收端已读取 ${(service.relayedBytes / 1048576).toStringAsFixed(1)} MB'),
                            if (service.duration > Duration.zero) ...[
                              Slider(
                                  value: (_drag ??
                                          service.position.inSeconds.toDouble())
                                      .clamp(
                                          0,
                                          service.duration.inSeconds
                                              .toDouble()),
                                  max: service.duration.inSeconds.toDouble(),
                                  onChanged: busy
                                      ? null
                                      : (v) => setState(() => _drag = v),
                                  onChangeEnd: (v) async {
                                    await service
                                        .seek(Duration(seconds: v.round()));
                                    if (mounted) setState(() => _drag = null);
                                  }),
                              Text(
                                  '${_time(service.position)} / ${_time(service.duration)}'),
                            ],
                            Wrap(spacing: 8, children: [
                              FilledButton.icon(
                                  onPressed: busy ? null : () => _cast(active),
                                  icon: const Icon(Icons.cast),
                                  label: const Text('投送当前媒体')),
                              OutlinedButton.icon(
                                  onPressed: busy
                                      ? null
                                      : (active.isPlaying
                                          ? service.pauseMedia
                                          : service.resumeMedia),
                                  icon: Icon(active.isPlaying
                                      ? Icons.pause
                                      : Icons.play_arrow),
                                  label: Text(active.isPlaying ? '暂停' : '继续')),
                              TextButton(
                                  onPressed: busy ? null : service.stopMedia,
                                  child: const Text('停止')),
                              TextButton(
                                  onPressed: busy
                                      ? null
                                      : service.disconnectFromDevice,
                                  child: const Text('断开连接')),
                            ]),
                            if (active.device.renderingControlService != null)
                              Row(children: [
                                const Icon(Icons.volume_up),
                                Expanded(
                                    child: Slider(
                                        value: _volume,
                                        max: 100,
                                        onChanged: busy
                                            ? null
                                            : (v) =>
                                                setState(() => _volume = v),
                                        onChangeEnd: (v) =>
                                            service.setVolume(v.round())))
                              ]),
                            const Text('返回播放页不会断开投屏；结束时请点“断开连接”。'),
                          ]))),
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(children: [
                  Expanded(
                      child: Text('可用设备',
                          style: Theme.of(context).textTheme.titleMedium)),
                  if (service.scanning)
                    const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                ])),
            if (service.devices.isEmpty)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(service.scanning
                      ? '正在搜索电视和播放器…'
                      : '未找到设备。请检查同一 Wi-Fi、电视接收开关和路由器的访客网络隔离，然后刷新或手动添加。')),
            for (final device in service.devices)
              Card(
                  child: ListTile(
                      leading: Icon(
                          device == active ? Icons.cast_connected : Icons.tv),
                      title: Text(device.name),
                      subtitle:
                          Text('${device.manufacturer} · ${device.model}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: busy || _systemPicker != null
                          ? null
                          : () => _cast(device))),
            if (Platform.operatingSystem == 'ohos') ...[
              const Divider(height: 32),
              OutlinedButton.icon(
                  onPressed: busy || active != null || _systemPicker != null
                      ? null
                      : _system,
                  icon: const Icon(Icons.devices),
                  label: const Text('使用鸿蒙系统投播')),
              if (_systemPicker != null) ...[
                _systemPicker!,
                TextButton(
                    onPressed: busy ? null : _closeSystem,
                    child: const Text('关闭系统投播，返回 DLNA')),
              ],
            ],
          ]),
        );
      });
}
