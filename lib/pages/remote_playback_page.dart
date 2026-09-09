import '../services/media_server_client.dart';
import '../services/media_server_catalog.dart';
import '../services/media_server_sequence.dart';
import '../services/download_manager.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import '../models/playback_media.dart';
import '../mpvplayer.dart';
import '../services/file_service.dart';
import '../services/http_service.dart';
import '../services/network_playback.dart';
import '../services/server_config_service.dart';

/// Reconnects a saved source instead of replaying a stale localhost URL.
class RemotePlaybackPage extends StatefulWidget {
  final String mediaId;
  final int? initialPositionMs;
  const RemotePlaybackPage(
      {super.key, required this.mediaId, this.initialPositionMs});
  @override
  State<RemotePlaybackPage> createState() => _RemotePlaybackPageState();
}

class _RemotePlaybackPageState extends State<RemotePlaybackPage> {
  FileService? _files;
  MediaServerClient? _mediaClient;
  MediaServerSequence? _sequence;
  final _lifetime = CancelToken();
  List<PlaybackMedia>? _queue;
  String? _url;
  String? _error;
  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    try {
      final uri = Uri.parse(widget.mediaId);
      if (uri.scheme == 'aloe-server') {
        final offline = await DownloadManager.instance
            .offlineMedia(widget.mediaId)
            .catchError((_) => null);
        if (!mounted) return;
        if (offline != null) {
          setState(() {
            _queue = [offline];
            _url = offline.url;
          });
          return;
        }
        final connection = (await MediaServerStore.load())
            .where((c) => c.id == uri.host)
            .firstOrNull;
        if (connection == null) throw StateError('媒体服务器配置已删除');
        if (!mounted) return;
        await _mediaClient?.close();
        if (!mounted) return;
        final client = MediaServerClient(connection);
        _mediaClient = client;
        final item =
            await client.details(uri.pathSegments.last, cancelToken: _lifetime);
        final media = await client.playback(item, cancelToken: _lifetime);
        if (!mounted) {
          await client.discardPlayback(media);
          return;
        }
        _sequence = MediaServerSequence(
            client: client, cancelToken: _lifetime, item: item, media: media);
        if (mounted)
          setState(() {
            _queue = [media];
            _url = media.url;
          });
        return;
      }
      final config = await ServerConfigService().getConfig(uri.host);
      if (config == null) throw StateError('服务器配置已删除，请重新添加');
      final files = FileServiceFactory.createService(config.type);
      _files = files;
      if (!await files.connect(config)) throw StateError('无法连接服务器');
      if (!mounted) {
        await files.disconnect();
        return;
      }
      final proxy = HttpService.instance;
      if (!await proxy.startServer()) throw StateError('无法启动本地播放服务');
      if (files is SmbFileService) proxy.setSmbService(files.smbService);
      if (files is WebDavFileService)
        proxy.setWebDavService(files.webdavService);
      final entries = await files
          .listFiles(path.posix.dirname(Uri.decodeComponent(uri.path)));
      final queue = networkQueue(config, entries, proxy);
      final media = queue.where((m) => m.id == widget.mediaId).firstOrNull;
      if (media == null) throw StateError('文件已移动或删除');
      if (mounted)
        setState(() {
          _queue = queue;
          _url = media.url;
        });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _lifetime.cancel('Player closed');
    _mediaClient?.close();
    _files?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_url != null)
      return MPVPlayer(
          filePath: _url!,
          mediaQueue: _queue,
          initialPositionMs: widget.initialPositionMs,
          onPlayback: _mediaClient?.report,
          onAdjacentMedia:
              _sequence?.enabled == true ? _sequence!.adjacent : null,
          onDiscardMedia: _sequence?.discard);
    return Scaffold(
        appBar: AppBar(title: const Text('继续播放')),
        body: Center(
            child: _error == null
                ? const CircularProgressIndicator()
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!),
                    TextButton(
                        onPressed: () {
                          setState(() => _error = null);
                          _connect();
                        },
                        child: const Text('重试'))
                  ])));
  }
}
