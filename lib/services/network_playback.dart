import 'package:path/path.dart' as path;
import '../models/playback_media.dart';
import '../models/server_config.dart';
import 'file_service.dart';
import 'http_service.dart';

const mediaExtensions = {'.mp4', '.mkv', '.avi', '.mov', '.flv', '.wmv', '.webm', '.m4v', '.ts', '.mpg', '.mpeg', '.mp3', '.wav', '.aac', '.flac', '.m4a', '.ogg', '.opus', '.m2ts'};

List<PlaybackMedia> networkQueue(ServerConfig config, List<FileItem> files, HttpService proxy) {
  final media = files.where((f) => !f.isDirectory && mediaExtensions.contains(path.extension(f.name).toLowerCase())).toList();
  return media.map((file) {
    final stem = path.basenameWithoutExtension(file.name).toLowerCase();
    final subtitles = files.where((f) {
      final name = f.name.toLowerCase();
      return !f.isDirectory && {'.srt', '.ass', '.ssa', '.vtt'}.contains(path.extension(name)) &&
          (path.basenameWithoutExtension(name) == stem || name.startsWith('$stem.'));
    }).toList()..sort((a, b) => a.name.compareTo(b.name));
    return PlaybackMedia(id: PlaybackMedia.remoteId(config.id, file.path), url: proxy.getFileUrlLocalhost(file.path),
      title: file.name, modified: file.modified, subtitles: subtitles.map((f) => proxy.getFileUrlLocalhost(f.path)).toList());
  }).toList();
}
