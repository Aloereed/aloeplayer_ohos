import 'file_service.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:path/path.dart' as path;
import 'package:mime/mime.dart';
import 'byte_range.dart';
import 'smb_service.dart';
import 'webdav_service.dart';

/// Local playback is loopback-only. LAN sharing is explicitly enabled and
/// constrained to issued, expiring file grants (never a server-wide credential).
class HttpService {
  static final HttpService instance = HttpService._();
  HttpService._();
  HttpService.forTesting(FileService source, {String? lanAddress})
      : _source = source,
        _lanAddressOverride = lanAddress;
  HttpServer? _server;
  HttpServer? _lanServer;
  Future<void>? _lanStarting;
  String? _lanAddressOverride;
  Future<bool>? _starting;
  FileService? _source;
  final Map<String, _FileGrant> _grants = {};
  final Random _tokenRandom = Random.secure();
  final Map<(FileService, String, bool), String> _grantTokens = {};
  final Map<(FileService, String), (DateTime, FileItem)> _metadata = {};
  final Map<(FileService, String), Future<FileItem?>> _metadataPending = {};
  int _port = 0;
  String? _localIp;
  bool _lanEnabled = false;
  bool get isRunning => _server != null;
  String? get localIpAddress => _localIp;
  String get baseUrl =>
      'http://${_lanEnabled ? (_localIp ?? "127.0.0.1") : "127.0.0.1"}:${_lanServer?.port ?? _port}';
  void setSmbService(SmbService service) {
    setFileService(SmbFileService(service: service));
  }

  void setWebDavService(WebDavService service) {
    setFileService(WebDavFileService(service: service));
  }

  void setFileService(FileService service) {
    _source = service;
    _pruneGrants();
  }

  void _pruneGrants() {
    final now = DateTime.now();
    final expired = _grants.entries
        .where((entry) =>
            entry.value.expires.isBefore(now) ||
            !entry.value.source.isConnected)
        .map((entry) => entry.key)
        .toList();
    for (final token in expired) {
      final grant = _grants.remove(token)!;
      _grantTokens.remove((grant.source, grant.path, grant.lan));
    }
  }

  Future<FileItem?> _fileInfo(FileService source, String path) {
    final key = (source, path);
    final cached = _metadata.remove(key);
    if (cached != null &&
        DateTime.now().difference(cached.$1) < const Duration(seconds: 2)) {
      _metadata[key] = cached;
      return Future.value(cached.$2);
    }
    final pending = _metadataPending[key];
    if (pending != null) return pending;
    final future = source.getFile(path).then((file) {
      if (file != null && source.isConnected) {
        _metadata[key] = (DateTime.now(), file);
        while (_metadata.length > 256) {
          _metadata.remove(_metadata.keys.first);
        }
      }
      return file;
    });
    _metadataPending[key] = future;
    // Attach cleanup to a separate future without making it await itself.
    unawaited(future.then<void>((_) {
      _metadataPending.remove(key);
    }, onError: (Object _, StackTrace __) {
      _metadataPending.remove(key);
    }));
    return future;
  }

  Future<bool> startServer({String? bindAddress}) {
    if (_server != null) return Future.value(true);
    return _starting ??=
        _start(bindAddress).whenComplete(() => _starting = null);
  }

  Future<bool> _start(String? bindAddress) async {
    try {
      _server = await shelf_io.serve((request) => _handle(request, lan: false),
          InternetAddress.loopbackIPv4, _port);
      _port = _server!.port;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> enableLanSharing() => _lanStarting ??=
      _enableLanSharing().whenComplete(() => _lanStarting = null);
  Future<void> _enableLanSharing() async {
    if (_lanEnabled) return;
    if (!await startServer()) throw StateError('无法启动本地播放服务');
    if (_lanAddressOverride != null) {
      _localIp = _lanAddressOverride;
    } else {
      final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
          includeLoopback: false,
          includeLinkLocal: false);
      if (interfaces.isEmpty || interfaces.first.addresses.isEmpty)
        throw StateError('未连接局域网');
      _localIp = interfaces.first.addresses.first.address;
    }
    _lanServer = await shelf_io.serve(
        (request) => _handle(request, lan: true), InternetAddress.anyIPv4, 0);
    _lanEnabled = true;
  }

  Future<void> disableLanSharing() async {
    await _lanStarting;
    await _lanServer?.close(force: true);
    _lanServer = null;
    _lanEnabled = false;
    _grants.removeWhere((_, grant) => grant.lan);
    _grantTokens.removeWhere((key, _) => key.$3);
  }

  Future<void> stopServer() async {
    await _starting;
    await disableLanSharing();
    await _server?.close(force: true);
    _server = null;
    _lanEnabled = false;
    _grants.clear();
    _grantTokens.clear();
    _metadata.clear();
  }

  String _url(String filePath, String origin, {bool lan = false}) {
    if (!isRunning) throw StateError('文件服务尚未就绪');
    final source = _source;
    if (source == null || !source.isConnected) throw StateError('媒体服务器未连接');
    final key = (source, filePath, lan);
    final existing = _grantTokens[key];
    if (existing != null &&
        _grants[existing]!.expires.isAfter(DateTime.now())) {
      return '$origin/media/${Uri.encodeComponent(path.posix.basename(filePath))}?token=$existing';
    }
    if (_grants.length >= 32768) {
      _pruneGrants();
      if (_grants.length >= 32768) throw StateError('播放链接数量过多，请关闭并重新打开媒体库');
    }
    final token = base64UrlEncode(
        List<int>.generate(24, (_) => _tokenRandom.nextInt(256)));
    if (existing != null) _grants.remove(existing);
    _grants[token] = _FileGrant(
        source, filePath, DateTime.now().add(const Duration(hours: 24)), lan);
    _grantTokens[key] = token;
    return '$origin/media/${Uri.encodeComponent(path.posix.basename(filePath))}?token=$token';
  }

  String getFileUrl(String filePath) =>
      _url(filePath, baseUrl, lan: _lanEnabled);
  String getFileUrlLocalhost(String filePath) =>
      _url(filePath, 'http://127.0.0.1:$_port');
  List<String> getAccessUrls() => [baseUrl];

  Future<Response> _handle(Request request, {required bool lan}) async {
    if (request.method != 'GET' && request.method != 'HEAD')
      return Response(405, headers: {'Allow': 'GET, HEAD'});
    final grant = _grants[request.url.queryParameters['token']];
    if (grant == null ||
        grant.lan != lan ||
        grant.expires.isBefore(DateTime.now()))
      return Response.forbidden('链接已失效');
    try {
      final source = grant.source;
      if (!source.isConnected) return Response(503, body: '服务器未连接');
      final file = await _fileInfo(source, grant.path);
      if (file == null || file.isDirectory) return Response.notFound('文件不存在');
      final size = file.size;
      if (!hasKnownFileSize(file)) return Response(502, body: '无法确定远端文件大小');
      var rangeHeader = request.headers['range'];
      final etag = fileEtag(file);
      final modified =
          file.modified == null ? null : HttpDate.format(file.modified!);
      final ifRange = request.headers['if-range'];
      if (ifRange != null && rangeHeader != null) {
        // A stale validator requests a full replacement representation, not
        // bytes from a different revision appended to an old partial file.
        final matches = ifRange.startsWith('"')
            ? etag != null && !etag.startsWith('W/') && ifRange == etag
            : modified != null && ifRange == modified;
        if (!matches) rangeHeader = null;
      }
      final range =
          rangeHeader == null ? null : ByteRange.parse(rangeHeader, size);
      if (rangeHeader != null && range == null)
        return Response(416, headers: {'Content-Range': 'bytes */$size'});
      final headers = <String, String>{
        'Content-Type':
            lookupMimeType(grant.path) ?? 'application/octet-stream',
        'Content-Length': '${range?.length ?? size}',
        'Accept-Ranges': 'bytes',
        'Cache-Control': 'no-store',
        if (etag != null) 'ETag': etag,
        if (modified != null) 'Last-Modified': modified,
        if (range != null)
          'Content-Range': 'bytes ${range.start}-${range.end}/$size',
      };
      if (request.method == 'HEAD' || size == 0)
        return Response(range == null ? 200 : 206, headers: headers);
      final stream = source is RevisionAwareFileService
          ? await (source as RevisionAwareFileService).getFileStreamForRevision(
              file,
              start: range?.start,
              end: range?.end)
          : await source.getFileStream(grant.path,
              start: range?.start, end: range?.end);
      return Response(range == null ? 200 : 206,
          body: stream, headers: headers);
    } catch (_) {
      return Response(502, body: '读取失败，请检查服务器连接');
    }
  }
}

class _FileGrant {
  final FileService source;
  final String path;
  final DateTime expires;
  final bool lan;
  _FileGrant(this.source, this.path, this.expires, this.lan);
}
