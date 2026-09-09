import 'package:dio/dio.dart';
import '../models/playback_media.dart';
import 'media_server_catalog.dart';
import 'media_server_client.dart';
import 'media_server_playback.dart';

/// Prepares only the requested neighbour and keeps item-specific source IDs out
/// of subsequent negotiations. Shared by library playback and history resume.
class MediaServerSequence {
  final MediaServerClient client;
  final CancelToken cancelToken;
  final MediaServerPlaybackOptions options;
  final Map<String, MediaServerItem> _items;
  final bool enabled;
  MediaServerSequence(
      {required this.client,
      required this.cancelToken,
      required MediaServerItem item,
      required PlaybackMedia media,
      this.options = const MediaServerPlaybackOptions()})
      : _items = {media.url: item},
        enabled = item.type == 'Episode' && item.seriesId != null;

  Future<PlaybackMedia?> adjacent(PlaybackMedia current, bool forward) async {
    final item = _items[current.url];
    if (item == null) throw StateError('Current episode unavailable');
    _items.removeWhere((url, _) => url != current.url);
    final adjacent = await client.adjacentEpisode(item,
        forward: forward, cancelToken: cancelToken);
    if (adjacent == null) return null;
    final prepared = await client.playback(adjacent,
        cancelToken: cancelToken,
        options: MediaServerPlaybackOptions(
            mode: options.mode,
            maxBitrate: options.maxBitrate,
            subtitleIndex: options.subtitleIndex == -1 ? -1 : null));
    _items[prepared.url] = adjacent;
    return prepared;
  }

  Future<void> discard(PlaybackMedia media) async {
    _items.remove(media.url);
    await client.discardPlayback(media);
  }
}
