import 'dart:io';
import 'package:path/path.dart' as path;
import '../history_service.dart';
import '../models/catalog_item.dart';
import '../models/playback_media.dart';
import '../settings.dart';

Future<String> catalogSource(CatalogItem item, {bool activate = false}) async {
  if (!item.filePath.endsWith('.lnk')) return item.filePath;
  var source = (await File(item.filePath).readAsString()).trim();
  if (source.isEmpty) throw const FileSystemException('快捷方式为空');
  if (activate) {
    final uri = Uri.tryParse(source);
    final permissionUri = uri?.hasScheme == true
        ? source
        : Uri(
                scheme: 'file',
                host: source.startsWith('/Photos') ? 'media' : 'docs',
                path: source)
            .toString();
    await SettingsService().activatePersistPermission(permissionUri);
  }
  final uri = Uri.tryParse(source);
  if (uri?.scheme == 'file' && uri?.host == 'docs') source = uri!.path;
  if (uri?.scheme == 'file' && uri?.host.isEmpty == true) {
    source = uri!.toFilePath();
  }
  return source;
}

Future<List<PlaybackMedia>> catalogQueue(
    CatalogItem selected, List<CatalogItem> items) async {
  final queue = <PlaybackMedia>[];
  for (final item in items) {
    try {
      final source = await catalogSource(item, activate: true);
      if ((path.isAbsolute(source) ||
              Uri.tryParse(source)?.hasScheme != true) &&
          !await File(source).exists()) {
        throw const FileSystemException('文件已移动或无法访问');
      }
      queue.add(PlaybackMedia(
          id: PlaybackMedia.localId(source),
          url: source,
          title: item.isAudio ? item.mediaName : item.title));
    } catch (_) {
      if (item.filePath == selected.filePath) rethrow;
      // Missing episodes must not prevent other episodes from playing.
    }
  }
  return queue;
}

bool catalogCompleted(HistoryItem? history) =>
    history != null &&
    history.durationMs > 0 &&
    history.lastPosition >= history.durationMs * .95;

int? catalogResume(HistoryItem? history) =>
    history != null && history.lastPosition > 0 && !catalogCompleted(history)
        ? history.lastPosition
        : null;

CatalogItem catalogNext(
    CatalogCollection collection, Map<String, HistoryItem> history) {
  final unfinished = collection.items
      .where((item) => catalogResume(history[item.filePath]) != null)
      .toList()
    ..sort((a, b) => history[b.filePath]!
        .lastPlayed
        .compareTo(history[a.filePath]!.lastPlayed));
  if (unfinished.isNotEmpty) return unfinished.first;
  return collection.items
          .where((item) => !catalogCompleted(history[item.filePath]))
          .firstOrNull ??
      collection.first;
}

String catalogTime(int milliseconds) {
  final total = milliseconds ~/ 1000;
  final hours = total ~/ 3600;
  final minutes = (total ~/ 60) % 60;
  final seconds = (total % 60).toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:${minutes.toString().padLeft(2, '0')}:$seconds'
      : '$minutes:$seconds';
}
