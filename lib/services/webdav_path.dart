/// Decoded, base-relative application paths and encoded transport URLs are
/// intentionally kept separate. A filename such as "100%20 #?.mkv" is literal.
class WebDavPaths {
  final Uri base;
  late final List<String> _root = _segments(base);

  WebDavPaths(String url) : base = _parseBase(url);

  static Uri _parseBase(String url) {
    final uri = Uri.parse(url.trim());
    if (!{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('WebDAV 地址应为 HTTP/HTTPS URL，凭据请填写在用户名和密码栏');
    }
    return uri.replace(
        path: uri.path.endsWith('/') ? uri.path : '${uri.path}/');
  }

  static List<String> _segments(Uri uri) =>
      uri.pathSegments.where((s) => s.isNotEmpty).map((s) {
        if (s.contains('/') ||
            s.contains('\\') ||
            s.contains('\x00') ||
            s == '.' ||
            s == '..') {
          throw const FormatException('WebDAV 路径包含无效的路径分隔符');
        }
        return s;
      }).toList();

  static String canonical(String path) {
    final result = <String>[];
    if (path.contains('\x00')) throw const FormatException('WebDAV 路径包含无效字符');
    for (final segment in path.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (result.isEmpty) throw const FormatException('WebDAV 路径超出根目录');
        result.removeLast();
      } else {
        result.add(segment);
      }
    }
    return '/${result.join('/')}';
  }

  Uri resolve(String path, {bool directory = false}) {
    final relative = canonical(path).split('/').where((s) => s.isNotEmpty);
    final segments = [..._root, ...relative];
    if (directory || segments.isEmpty) segments.add('');
    return base.replace(pathSegments: ['', ...segments]);
  }

  bool sameOrigin(Uri uri) =>
      uri.scheme == base.scheme &&
      uri.host == base.host &&
      uri.port == base.port;

  /// DAV href can be an absolute URL, absolute path or relative reference.
  /// Only resources inside this configured base are exposed to the browser.
  String? fromHref(String href, Uri requestUri) {
    try {
      final uri = requestUri.resolve(href.trim());
      if (!sameOrigin(uri) ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment) return null;
      final parts = _segments(uri);
      if (parts.length < _root.length) return null;
      for (var i = 0; i < _root.length; i++) {
        if (parts[i] != _root[i]) return null;
      }
      return '/${parts.skip(_root.length).join('/')}';
    } on FormatException {
      return null;
    }
  }

  static bool isDirectChild(String parent, String child) {
    parent = canonical(parent);
    child = canonical(child);
    final prefix = parent == '/' ? '/' : '$parent/';
    return child.startsWith(prefix) &&
        child.length > prefix.length &&
        !child.substring(prefix.length).contains('/');
  }
}
