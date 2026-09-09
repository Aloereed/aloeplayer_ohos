import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/media_server_client.dart';
import '../services/media_server_diagnostics.dart';

class MediaServerDiagnosticsPage extends StatefulWidget {
  final MediaServerConnection connection;
  final MediaServerClient? client;
  const MediaServerDiagnosticsPage(
      {super.key, required this.connection, this.client});
  @override
  State<MediaServerDiagnosticsPage> createState() =>
      _MediaServerDiagnosticsPageState();
}

class _MediaServerDiagnosticsPageState
    extends State<MediaServerDiagnosticsPage> {
  late final _client = widget.client ?? MediaServerClient(widget.connection);
  final _rows = <MediaServerDiagnostic>[];
  CancelToken? _cancel;
  bool _running = false;
  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    _cancel?.cancel();
    final token = _cancel = CancelToken();
    setState(() {
      _rows.clear();
      _running = true;
    });
    try {
      await for (final result in MediaServerDiagnostics(_client).run(token)) {
        if (!mounted || token != _cancel) return;
        setState(() => _rows.add(result));
      }
    } finally {
      if (mounted && token == _cancel) setState(() => _running = false);
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(
        text: mediaServerDiagnosticSummary(widget.connection.kind, _rows)));
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已复制诊断摘要')));
  }

  @override
  void dispose() {
    _cancel?.cancel();
    if (widget.client == null) unawaited(_client.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('连接诊断'), actions: [
        IconButton(
            tooltip: '重新检查', onPressed: _run, icon: const Icon(Icons.refresh)),
        IconButton(
            tooltip: '复制诊断摘要',
            onPressed: _rows.isEmpty ? null : _copy,
            icon: const Icon(Icons.copy)),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('检查接口连接和账号权限，耗时为本次接口响应时间。复制摘要不包含账号、令牌或服务器地址。'),
        if (widget.connection.userId.isEmpty) const Text('登录前仅检查服务器地址与版本。'),
        if (_running)
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator()),
        for (final row in _rows)
          Card(
              child: ListTile(
            isThreeLine: true,
            leading: Icon(switch (row.status) {
              MediaServerDiagnosticStatus.passed => Icons.check_circle_outline,
              MediaServerDiagnosticStatus.warning => Icons.info_outline,
              MediaServerDiagnosticStatus.failed => Icons.error_outline
            }),
            title: Text('${row.title} · ${row.statusLabel}'),
            subtitle: Text('${row.detail}\n${row.elapsedMs} ms'),
          )),
      ]));
}
