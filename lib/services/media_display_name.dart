import 'package:path/path.dart' as path;

/// Decode URI path segments exactly once for display. A plain filesystem name
/// can legitimately contain percent escapes, '+' or '#', so leave it alone.
String mediaDisplayName(String source) {
  if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(source)) {
    try {
      final uri = Uri.parse(source);
      final segments = uri.pathSegments.where((part) => part.isNotEmpty);
      return segments.isEmpty ? uri.host : segments.last;
    } on FormatException {
      // Even malformed URI text must not expose query tokens in the title.
      return path.basename(source.split(RegExp(r'[?#]')).first);
    }
  }
  return path.basename(source.replaceAll('\\', '/'));
}
