import 'package:path/path.dart' as path;
import '../models/playback_media.dart';
import '../models/server_config.dart';
import 'file_service.dart';
import 'http_service.dart';

const mediaExtensions = {
  '.mp4',
  '.m3u8',
  '.mkv',
  '.avi',
  '.mov',
  '.flv',
  '.wmv',
  '.webm',
  '.m4v',
  '.ts',
  '.mpg',
  '.mpeg',
  '.mp3',
  '.wav',
  '.aac',
  '.flac',
  '.m4a',
  '.ogg',
  '.opus',
  '.m2ts',
  '.mts',
  '.vob',
  '.ogv',
  '.3gp',
  '.asf',
  '.rm',
  '.rmvb',
  '.divx',
  '.mpe',
  '.mp2',
  '.aiff',
  '.aif',
  '.wma',
  '.alac',
  '.ape',
  '.amr',
  '.ac3',
  '.eac3',
  '.dts',
  '.dsf',
  '.dff',
  '.oga'
};

bool isNetworkMedia(FileItem file) =>
    !file.isDirectory &&
    (mediaExtensions.contains(path.posix.extension(file.path).toLowerCase()) ||
        mediaExtensions
            .contains(path.posix.extension(file.name).toLowerCase()));

List<PlaybackMedia> networkQueue(
    ServerConfig config, List<FileItem> files, HttpService proxy) {
  final media = files.where(isNetworkMedia).toList();
  // Index each subtitle once. The previous nested scan did N*M filename
  // comparisons and blocked the UI for large music/video directories.
  final subtitleIndex = <String, List<FileItem>>{};
  for (final file in files) {
    final name = path.posix.basename(file.path).toLowerCase();
    if (file.isDirectory ||
        !{'.srt', '.ass', '.ssa', '.vtt', '.lrc'}
            .contains(path.posix.extension(name))) continue;
    final stem = path.posix.basenameWithoutExtension(name);
    final keys = <String>{stem};
    for (var i = stem.indexOf('.'); i >= 0; i = stem.indexOf('.', i + 1)) {
      if (i > 0) keys.add(stem.substring(0, i));
    }
    for (final key in keys) {
      (subtitleIndex[key] ??= []).add(file);
    }
  }
  for (final subtitles in subtitleIndex.values) {
    subtitles.sort((a, b) => a.name.compareTo(b.name));
  }
  return media.map((file) {
    final stem = path.posix.basenameWithoutExtension(file.path).toLowerCase();
    final subtitles = subtitleIndex[stem] ?? const <FileItem>[];
    return PlaybackMedia(
        id: PlaybackMedia.remoteId(config.id, file.path),
        url: proxy.getFileUrlLocalhost(file.path),
        title: file.name,
        modified: file.modified,
        subtitles:
            subtitles.map((f) => proxy.getFileUrlLocalhost(f.path)).toList());
  }).toList();
}
