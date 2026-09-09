import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../mpvplayer.dart';
import '../services/media_server_client.dart';
import '../services/media_server_catalog.dart';
import '../widgets/media_server_poster.dart';
import '../widgets/media_server_playback_dialog.dart';
import '../services/media_server_playback.dart';
import '../services/media_server_sequence.dart';
import '../services/media_server_download.dart';
import '../services/download_manager.dart';
import 'downloads_page.dart';

class MediaServerDetailPage extends StatefulWidget {
  final MediaServerConnection connection;
  final MediaServerItem item;
  final MediaServerClient? client;
  const MediaServerDetailPage(
      {super.key, required this.connection, required this.item, this.client});
  @override
  State<MediaServerDetailPage> createState() => _MediaServerDetailPageState();
}

class _MediaServerDetailPageState extends State<MediaServerDetailPage> {
  late final _client = widget.client ?? MediaServerClient(widget.connection);
  late MediaServerItem _item = widget.item;
  final _lifetime = CancelToken();
  CancelToken? _detailCancel;
  CancelToken? _childrenCancel;
  CancelToken? _playbackCancel;
  MediaServerDownloadSource? _downloadSource;
  int _generation = 0, _nextStart = 0;
  bool _loading = true, _childrenBusy = false, _more = false, _acting = false;
  String? _error, _childrenError, _actionError;
  List<MediaServerItem> _seasons = [], _episodes = [];
  String? _seasonId;
  MediaServerPlaybackOptions _playOptions = const MediaServerPlaybackOptions();
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _lifetime.cancel('Detail closed');
    _detailCancel?.cancel();
    _childrenCancel?.cancel();
    _playbackCancel?.cancel('Detail closed');
    unawaited(_downloadSource?.disconnect());
    if (widget.client == null) unawaited(_client.close());
    super.dispose();
  }

  Future<void> _load() async {
    _detailCancel?.cancel();
    final token = _detailCancel = CancelToken();
    _childrenCancel?.cancel();
    _generation++;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await _client.details(widget.item.id, cancelToken: token);
      if (!mounted || token != _detailCancel) return;
      setState(() {
        _item = detail;
      });
      if (detail.type == 'Series') {
        final seasons = await _client.seasons(detail.id, cancelToken: token);
        if (!mounted || token != _detailCancel) return;
        setState(() {
          _seasons = seasons.items;
          if (!_seasons.any((s) => s.id == _seasonId))
            _seasonId = _seasons.firstOrNull?.id;
        });
        await _loadEpisodes();
      } else if (detail.type == 'Season' && detail.seriesId != null) {
        _seasonId = detail.id;
        await _loadEpisodes();
      }
    } catch (error) {
      if (mounted &&
          token == _detailCancel &&
          !(error is DioException && CancelToken.isCancel(error))) {
        setState(() {
          _error = mediaServerError(error);
        });
      }
    } finally {
      if (mounted && token == _detailCancel) setState(() => _loading = false);
    }
  }

  Future<void> _loadEpisodes({bool more = false}) async {
    if (more && (_childrenBusy || !_more)) return;
    final series = _item.type == 'Series' ? _item.id : _item.seriesId;
    if (series == null) return;
    _childrenCancel?.cancel();
    final cancel = _childrenCancel = CancelToken();
    final generation = ++_generation;
    final start = more ? _nextStart : 0;
    setState(() {
      _childrenBusy = true;
      _childrenError = null;
      if (!more) {
        _episodes = [];
        _more = false;
      }
    });
    try {
      final page = await _client.episodes(series,
          seasonId: _seasonId, start: start, cancelToken: cancel);
      if (!mounted || generation != _generation) return;
      final seen = <String>{};
      final previousCount = more ? _episodes.length : 0;
      setState(() {
        _episodes = [...(more ? _episodes : <MediaServerItem>[]), ...page.items]
            .where((e) => seen.add(e.id))
            .toList();
        _nextStart = page.nextStart;
        _more = page.hasMore && (!more || _episodes.length > previousCount);
      });
    } catch (error) {
      if (mounted &&
          generation == _generation &&
          !(error is DioException && CancelToken.isCancel(error))) {
        setState(() => _childrenError = mediaServerError(error));
      }
    } finally {
      if (mounted && generation == _generation)
        setState(() => _childrenBusy = false);
    }
  }

  Future<void> _change({required bool favorite}) async {
    if (_acting) return;
    setState(() {
      _acting = true;
      _actionError = null;
    });
    try {
      if (favorite) {
        await _client.setFavorite(_item.id, !_item.favorite);
      } else {
        await _client.setPlayed(_item.id, !_item.played);
      }
      final detail = await _client.details(_item.id, cancelToken: _lifetime);
      if (mounted) setState(() => _item = detail);
    } catch (_) {
      if (mounted) setState(() => _actionError = '操作或状态刷新失败，请刷新确认后重试');
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _play({bool fromStart = false}) async {
    if (_acting) return;
    setState(() {
      _acting = true;
      _actionError = null;
    });
    final playbackLifetime = _playbackCancel = CancelToken();
    try {
      final media = await _client.playback(_item,
          cancelToken: playbackLifetime, options: _playOptions);
      if (!mounted) {
        await _client.discardPlayback(media);
        return;
      }
      final sequence = MediaServerSequence(
          client: _client,
          cancelToken: playbackLifetime,
          item: _item,
          media: media,
          options: _playOptions);
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => MPVPlayer(
                  filePath: media.url,
                  mediaQueue: [media],
                  initialPositionMs: fromStart ? 0 : _item.resumeMs,
                  onPlayback: _client.report,
                  onDiscardMedia: sequence.discard,
                  onAdjacentMedia:
                      sequence.enabled ? sequence.adjacent : null)));
      playbackLifetime.cancel('Player closed');
      if (mounted) await _load();
    } catch (_) {
      if (mounted) setState(() => _actionError = '播放准备失败，请检查服务器媒体源或重新登录');
    } finally {
      playbackLifetime.cancel('Player closed');
      if (_playbackCancel == playbackLifetime) _playbackCancel = null;
      if (mounted) setState(() => _acting = false);
    }
  }

  String get _summary {
    final data = _item.metadata;
    return [
      if (data['ProductionYear'] != null) '${data['ProductionYear']}',
      if (_item.durationMs > 0) '${(_item.durationMs / 60000).round()} 分钟',
      if (data['OfficialRating'] != null) '${data['OfficialRating']}',
      if (data['CommunityRating'] != null) '评分 ${data['CommunityRating']}'
    ].join(' · ');
  }

  Future<void> _download() async {
    if (_acting) return;
    setState(() {
      _acting = true;
      _actionError = null;
    });
    final source =
        _downloadSource = MediaServerDownloadSource(widget.connection);
    try {
      final file = await source.prepare(_item, sourceId: _playOptions.sourceId);
      if (!mounted) return;
      await DownloadManager.instance.addMediaServer(widget.connection.id, file);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('已加入原文件下载队列'),
            action: SnackBarAction(
                label: '查看',
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const DownloadsPage())))));
    } catch (error) {
      if (mounted) setState(() => _actionError = '下载准备失败：$error');
    } finally {
      await source.disconnect();
      if (_downloadSource == source) _downloadSource = null;
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _choosePlayback() async {
    if (_acting) return;
    setState(() {
      _acting = true;
      _actionError = null;
    });
    try {
      final sources =
          await _client.playbackSources(_item, cancelToken: _lifetime);
      if (!mounted) return;
      if (sources.isEmpty) throw StateError('No sources');
      final options = await showDialog<MediaServerPlaybackOptions>(
          context: context,
          builder: (_) => MediaServerPlaybackDialog(
              sources: sources, initial: _playOptions));
      if (mounted && options != null) setState(() => _playOptions = options);
    } catch (_) {
      if (mounted) setState(() => _actionError = '无法获取媒体版本和轨道，请检查服务器后重试');
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(_item.name), actions: [
        IconButton(
            tooltip: '刷新详情',
            onPressed: _loading || _acting ? null : _load,
            icon: const Icon(Icons.refresh))
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (_loading || _acting) const LinearProgressIndicator(),
        if (_error != null) Text(_error!),
        if (_actionError != null) Text(_actionError!),
        Center(
            child: SizedBox(
                width: 200,
                height: 285,
                child: Image.network(_client.imageUrl(_item.id),
                    headers: _client.headers,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.movie_outlined, size: 80)))),
        const SizedBox(height: 16),
        Text(_item.name, style: Theme.of(context).textTheme.headlineSmall),
        if (_summary.isNotEmpty)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(_summary)),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (_item.playable)
            OutlinedButton.icon(
                onPressed: _acting ? null : _choosePlayback,
                icon: const Icon(Icons.tune),
                label: const Text('播放设置')),
          if (_item.playable)
            FilledButton.icon(
                onPressed: _acting ? null : _play,
                icon: const Icon(Icons.play_arrow),
                label: Text(_item.resumeMs > 0
                    ? '续播 ${(_item.resumeMs / 60000).floor()} 分钟'
                    : '播放')),
          if (_item.playable && _item.resumeMs > 0)
            OutlinedButton(
                onPressed: _acting ? null : () => _play(fromStart: true),
                child: const Text('从头播放')),
          if (_item.playable &&
              _item.type != 'TvChannel' &&
              _item.metadata['CanDownload'] != false)
            OutlinedButton.icon(
                onPressed: _acting ? null : _download,
                icon: const Icon(Icons.download_outlined),
                label: const Text('下载原文件')),
          FilterChip(
              selected: _item.favorite,
              label: const Text('收藏'),
              onSelected: _acting ? null : (_) => _change(favorite: true)),
          FilterChip(
              selected: _item.played,
              label: Text(_item.isFolder ? '全部已看' : '已看'),
              onSelected: _acting ? null : (_) => _change(favorite: false)),
        ]),
        if ((_item.metadata['Genres'] as List?)?.isNotEmpty == true)
          Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text((_item.metadata['Genres'] as List).join(' / '))),
        if (_item.overview?.isNotEmpty == true)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: SelectableText(_item.overview!)),
        if ((_item.metadata['People'] as List?)?.isNotEmpty == true)
          Text(
              '演职人员：${(_item.metadata['People'] as List).map((p) => p['Name']).take(20).join('、')}'),
        if (_seasons.isNotEmpty)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: DropdownButtonFormField<String>(
                  key: ValueKey(_seasonId),
                  initialValue: _seasonId,
                  decoration: const InputDecoration(labelText: '选择季度'),
                  items: _seasons
                      .map((s) =>
                          DropdownMenuItem(value: s.id, child: Text(s.name)))
                      .toList(),
                  onChanged: (value) {
                    _seasonId = value;
                    _loadEpisodes();
                  })),
        if (_childrenBusy) const LinearProgressIndicator(),
        if (_childrenError != null)
          TextButton(
              onPressed: () => _loadEpisodes(more: _episodes.isNotEmpty),
              child: Text('$_childrenError · 重试选集')),
        if (!_childrenBusy &&
            _childrenError == null &&
            ['Series', 'Season'].contains(_item.type) &&
            _episodes.isEmpty &&
            !_loading)
          const Padding(padding: EdgeInsets.all(16), child: Text('暂无可用剧集')),
        for (final episode in _episodes)
          ListTile(
              leading: Icon(episode.played
                  ? Icons.check_circle
                  : Icons.play_circle_outline),
              title: Text(
                  '${episode.index == null ? '' : '第 ${episode.index} 集 · '}${episode.name}'),
              subtitle: episode.overview == null
                  ? null
                  : Text(episode.overview!,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: episode.resumeMs > 0 ? const Text('续播') : null,
              onTap: () async {
                await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => MediaServerDetailPage(
                            connection: widget.connection, item: episode)));
                if (mounted) _loadEpisodes();
              }),
        if (_more)
          TextButton(
              onPressed: _childrenBusy ? null : () => _loadEpisodes(more: true),
              child: const Text('加载更多剧集')),
      ]));
}
