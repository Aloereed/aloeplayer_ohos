import 'package:path/path.dart' as path;

/// Persistent identity is independent of expiring proxy URLs and credentials.
class PlaybackMedia {
  final String id;
  final String url;
  final String title;
  final DateTime? modified;
  final List<String> subtitles;
  final Map<String, String> httpHeaders;
  final int? startPositionMs;
  const PlaybackMedia({required this.id, required this.url, required this.title, this.modified, this.subtitles = const [], this.httpHeaders = const {}, this.startPositionMs});

  static String remoteId(String serverId, String filePath) => Uri(
      scheme: 'aloe-media', host: serverId, path: filePath.startsWith('/') ? filePath : '/$filePath').toString();
  static bool isRemote(String id) => {'aloe-media', 'aloe-server'}.contains(Uri.tryParse(id)?.scheme);
  static String localId(String value) {
    final uri = Uri.tryParse(value);
    if (uri?.scheme == 'file' && (uri!.host.isEmpty || uri.host == 'localhost')) return path.normalize(uri.toFilePath());
    return uri != null && uri.hasScheme ? value : path.normalize(value);
  }
}
