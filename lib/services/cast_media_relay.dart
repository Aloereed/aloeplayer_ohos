import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:mime/mime.dart';
import 'byte_range.dart';

class _CastResource {
  final Uri source;
  final Map<String, String> headers;
  final String route;
  _CastResource(this.source, this.headers, this.route);
}

/// A receiver can read only resources granted by the chosen media/manifest.
/// Credentials remain on the phone; URLs contain an unguessable session token.
class CastMediaRelay {
  static const maxManifestBytes = 2 * 1024 * 1024;
  static const maxResources = 32768;
  static const maxReaders = 16;
  static const ioTimeout = Duration(seconds: 20);
  final String host;
  final void Function(String)? onError;
  final Uri? Function(Uri, String)? resolveReference;
  final Future<void> Function()? onClose;
  final _token =
      base64UrlEncode(List.generate(24, (_) => Random.secure().nextInt(256)));
  final _resources = <String, _CastResource>{};
  final _resourceKeys = <String, String>{};
  final _clients = <HttpClient>{};
  late HttpServer _server;
  late String url;
  bool _closed = false;
  int _readers = 0;
  int bytesServed = 0;
  int requestsServed = 0;
  String? _localRoot;
  CastMediaRelay._(
      this.host, this.onError, this.resolveReference, this.onClose);

  static Future<CastMediaRelay> start(String mediaPath,
      {required String host,
      Map<String, String> headers = const {},
      void Function(String)? onError,
      Uri? Function(Uri, String)? resolveReference,
      Future<void> Function()? onClose}) async {
    final relay = CastMediaRelay._(host, onError, resolveReference, onClose);
    final parsed = Uri.tryParse(mediaPath);
    final remote = parsed != null && ['http', 'https'].contains(parsed.scheme);
    final source = remote
        ? parsed.replace(userInfo: '')
        : File(parsed?.scheme == 'file'
                ? (parsed!.host.isEmpty ? parsed.toFilePath() : parsed.path)
                : mediaPath)
            .absolute
            .uri;
    if (!remote) {
      final file = File.fromUri(source);
      if (!await file.exists()) throw StateError('本地媒体不可读，请重新选择文件');
      relay._localRoot = await file.parent.resolveSymbolicLinks();
    }
    final v6 = InternetAddress.tryParse(host)?.type == InternetAddressType.IPv6;
    relay._server = await HttpServer.bind(
        v6 ? InternetAddress.anyIPv6 : InternetAddress.anyIPv4, 0);
    relay._server.idleTimeout = const Duration(seconds: 30);
    try {
      final forwarded = _cleanHeaders(headers);
      if (remote &&
          parsed.userInfo.isNotEmpty &&
          !forwarded.keys.any((key) => key.toLowerCase() == 'authorization')) {
        forwarded['Authorization'] =
            'Basic ${base64Encode(utf8.encode(Uri.decodeComponent(parsed.userInfo)))}';
      }
      relay.url = relay._grant(source, forwarded);
      relay._server.listen(relay._serve, onError: (Object error) {
        if (!relay._closed) onError?.call('投屏媒体服务异常：$error');
      });
      return relay;
    } catch (_) {
      await relay.close();
      rethrow;
    }
  }

  static Map<String, String> _cleanHeaders(Map<String, String> input) => {
        for (final entry in input.entries)
          if (![
            'host',
            'content-length',
            'connection',
            'transfer-encoding',
            'range',
            'accept-encoding',
            'proxy-authorization'
          ].contains(entry.key.toLowerCase()))
            entry.key: entry.value,
      };
  static Map<String, String> _headersFor(
          Uri from, Uri to, Map<String, String> headers) =>
      {
        for (final entry in headers.entries)
          if (from.origin == to.origin ||
              !RegExp(r'auth|cookie|token|key|secret|credential',
                      caseSensitive: false)
                  .hasMatch(entry.key))
            entry.key: entry.value,
      };
  String _grant(Uri source, Map<String, String> headers) {
    if (!['http', 'https', 'file'].contains(source.scheme) ||
        source.userInfo.isNotEmpty) {
      throw StateError('播放列表包含不支持的媒体地址');
    }
    // Include credentials in the private deduplication key, never in the LAN URL.
    final key = '${source.toString()}\n${jsonEncode(headers)}';
    final existing = _resourceKeys[key];
    if (existing != null) return _address(_resources[existing]!.route);
    if (_resources.length >= maxResources) throw StateError('播放列表资源数量超过上限');
    final id = _resources.length.toRadixString(36);
    final name = source.pathSegments.lastOrNull;
    final route =
        '/media/$id/${name == null || name.isEmpty ? 'stream' : name}';
    _resources[id] = _CastResource(source, Map.unmodifiable(headers), route);
    _resourceKeys[key] = id;
    return _address(route);
  }

  String _address(String route) => Uri(
      scheme: 'http',
      host: host,
      port: _server.port,
      path: route,
      queryParameters: {'token': _token}).toString();
  bool _looksLikeManifest(Uri uri, String? mime) =>
      uri.path.toLowerCase().endsWith('.m3u8') ||
      (mime ?? '').toLowerCase().contains('mpegurl');

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    // Forward headers and small live-stream chunks immediately. Otherwise a
    // receiver can wait for its first byte while the origin waits for playback.
    response.bufferOutput = false;
    var counted = false;
    try {
      final parts = request.uri.pathSegments;
      final resource = parts.length >= 3 && parts[0] == 'media'
          ? _resources[parts[1]]
          : null;
      if (_closed ||
          resource == null ||
          request.uri.path != Uri(path: resource.route).path ||
          request.uri.queryParameters['token'] != _token) {
        response.statusCode = 403;
      } else if (!['GET', 'HEAD'].contains(request.method)) {
        response.statusCode = 405;
        response.headers.set('Allow', 'GET, HEAD');
      } else if (_readers >= maxReaders) {
        response.statusCode = 503;
        response.headers.set('Retry-After', '1');
      } else {
        _readers++;
        counted = true;
        requestsServed++;
        response.headers.set('Cache-Control', 'no-store');
        response.headers.set('transferMode.dlna.org', 'Streaming');
        if (resource.source.scheme == 'file')
          await _file(request, resource);
        else
          await _network(request, resource);
      }
      await response.close();
    } catch (error) {
      if (!_closed && error is! HttpException && error is! SocketException)
        onError?.call('投屏媒体读取失败：$error');
      try {
        response.statusCode = 502;
        await response.close();
      } catch (_) {}
    } finally {
      if (counted) _readers--;
    }
  }

  void _features(HttpResponse response, {required bool seekable}) {
    response.headers.set('contentFeatures.dlna.org',
        'DLNA.ORG_OP=${seekable ? '01' : '00'};DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000');
  }

  Future<void> _file(HttpRequest request, _CastResource resource) async {
    final file = File.fromUri(resource.source);
    final resolved = await file.resolveSymbolicLinks();
    final root = _localRoot;
    if (root == null ||
        (resolved != root &&
            !resolved.startsWith('$root${Platform.pathSeparator}'))) {
      throw StateError('播放列表引用了媒体目录之外的文件');
    }
    if (_looksLikeManifest(resource.source, null)) {
      final bytes = await _readManifest(file.openRead());
      await _manifest(request, resource.source, resource.headers, bytes);
      return;
    }
    final size = await file.length();
    final rangeValue = request.headers.value('range');
    final range = rangeValue == null ? null : ByteRange.parse(rangeValue, size);
    final response = request.response;
    response.headers.set('Accept-Ranges', 'bytes');
    _features(response, seekable: true);
    if (rangeValue != null && range == null) {
      response.statusCode = 416;
      response.headers.set('Content-Range', 'bytes */$size');
      return;
    }
    response.statusCode = range == null ? 200 : 206;
    response.headers.contentType = ContentType.parse(
        lookupMimeType(file.path) ?? 'application/octet-stream');
    response.contentLength = range?.length ?? size;
    if (range != null)
      response.headers
          .set('Content-Range', 'bytes ${range.start}-${range.end}/$size');
    if (request.method == 'GET')
      await response.addStream(_count(file.openRead(
          range?.start ?? 0, range == null ? null : range.end + 1)));
  }

  Stream<List<int>> _count(Stream<List<int>> stream) async* {
    await for (final chunk in stream.timeout(ioTimeout)) {
      bytesServed += chunk.length;
      yield chunk;
    }
  }

  Future<List<int>> _readManifest(Stream<List<int>> stream) async {
    final bytes = <int>[];
    await for (final chunk in stream.timeout(ioTimeout)) {
      if (bytes.length + chunk.length > maxManifestBytes)
        throw StateError('HLS 播放列表过大');
      bytes.addAll(chunk);
    }
    return bytes;
  }

  Future<void> _network(HttpRequest incoming, _CastResource resource) async {
    final client = HttpClient()
      ..autoUncompress = false
      ..connectionTimeout = ioTimeout;
    _clients.add(client);
    // Cancel upstream reads when the receiver closes its connection.
    unawaited(incoming.response.done.then((_) {
      client.close(force: true);
    }, onError: (Object _) {
      client.close(force: true);
    }));
    var uri = resource.source;
    var headers = resource.headers;
    var fullManifest = false;
    var emulateHead = false;
    try {
      for (var redirects = 0; redirects < 7; redirects++) {
        final knownManifest = _looksLikeManifest(uri, null);
        final method = knownManifest || fullManifest || emulateHead
            ? 'GET'
            : incoming.method;
        final upstream = await client.openUrl(method, uri).timeout(ioTimeout);
        upstream.followRedirects = false;
        headers.forEach((key, value) => upstream.headers.set(key, value));
        upstream.headers.set('Accept-Encoding', 'identity');
        if (!knownManifest && !fullManifest) {
          for (final name in ['range', 'if-range']) {
            final value = incoming.headers.value(name);
            if (value != null) upstream.headers.set(name, value);
          }
        }
        final response = await upstream.close().timeout(ioTimeout);
        if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
          final location = response.headers.value('location');
          await response.listen((_) {}).cancel();
          if (location == null) throw StateError('媒体重定向缺少地址');
          final next = uri.resolve(location);
          if (!['http', 'https'].contains(next.scheme) ||
              next.userInfo.isNotEmpty ||
              (uri.scheme == 'https' && next.scheme != 'https'))
            throw StateError('不支持的媒体重定向');
          headers = _headersFor(uri, next, headers);
          uri = next;
          continue;
        }
        final output = incoming.response;
        if (method == 'HEAD' && [405, 501].contains(response.statusCode)) {
          await response.listen((_) {}).cancel();
          emulateHead = true;
          continue;
        }
        if (!fullManifest &&
            _looksLikeManifest(uri, response.headers.value('content-type')) &&
            (response.statusCode == 206 ||
                (response.statusCode == 200 && method == 'HEAD'))) {
          await response.listen((_) {}).cancel();
          fullManifest = true;
          continue;
        }
        final manifest = response.statusCode == 200 &&
            _looksLikeManifest(uri, response.headers.value('content-type'));
        if (manifest && method == 'GET') {
          Stream<List<int>> body = response;
          final encoding =
              response.headers.value('content-encoding')?.toLowerCase();
          if (encoding == 'gzip')
            body = gzip.decoder.bind(body);
          else if (encoding == 'deflate')
            body = zlib.decoder.bind(body);
          else if (encoding != null && encoding != 'identity')
            throw StateError('不支持的 HLS 压缩格式');
          await _manifest(incoming, uri, headers, await _readManifest(body));
        } else {
          output.statusCode = response.statusCode;
          for (final name in [
            'content-type',
            'content-length',
            'content-range',
            'accept-ranges',
            'content-encoding',
            'etag',
            'last-modified'
          ]) {
            final value = response.headers.value(name);
            if (value != null) output.headers.set(name, value);
          }
          _features(output,
              seekable: response.statusCode == 206 ||
                  response.headers.value('accept-ranges') == 'bytes');
          if (response.statusCode >= 400 &&
              response.statusCode != 416 &&
              !_closed) onError?.call('接收端读取媒体失败：HTTP ${response.statusCode}');
          if (incoming.method == 'GET')
            await output.addStream(_count(response));
          else
            await response.listen((_) {}).cancel();
        }
        return;
      }
      throw StateError('媒体重定向次数过多');
    } finally {
      client.close(force: true);
      _clients.remove(client);
    }
  }

  Future<void> _manifest(HttpRequest request, Uri source,
      Map<String, String> headers, List<int> bytes) async {
    final text = utf8.decode(bytes).replaceFirst('\uFEFF', '');
    if (!text.trimLeft().startsWith('#EXTM3U'))
      throw StateError('无效的 HLS 播放列表');
    String resolve(String reference) {
      final uri = resolveReference?.call(source, reference) ??
          source.resolve(reference);
      if (source.scheme == 'https' && uri.scheme != 'https')
        throw StateError('不允许 HLS 媒体降级到不安全地址');
      final scoped = source.scheme == 'file' || uri.scheme == 'file'
          ? <String, String>{}
          : _headersFor(source, uri, headers);
      return _grant(uri, scoped);
    }

    final rewritten = text.split('\n').map((line) {
      final value = line.trim();
      if (value.isEmpty) return line;
      if (!value.startsWith('#')) return resolve(value);
      return line.replaceAllMapped(RegExp(r'(\bURI\s*=\s*")([^"]+)(")'),
          (match) => '${match[1]}${resolve(match[2]!)}${match[3]}');
    }).join('\n');
    final output = utf8.encode(rewritten);
    final response = request.response;
    final rangeValue = request.headers.value('range');
    final range =
        rangeValue == null ? null : ByteRange.parse(rangeValue, output.length);
    response.headers.contentType =
        ContentType('application', 'vnd.apple.mpegurl', charset: 'utf-8');
    response.headers.set('Accept-Ranges', 'bytes');
    _features(response, seekable: true);
    if (rangeValue != null && range == null) {
      response.statusCode = 416;
      response.headers.set('Content-Range', 'bytes */${output.length}');
      return;
    }
    response.statusCode = range == null ? 200 : 206;
    response.contentLength = range?.length ?? output.length;
    if (range != null)
      response.headers.set('Content-Range',
          'bytes ${range.start}-${range.end}/${output.length}');
    if (request.method == 'GET') {
      final body =
          range == null ? output : output.sublist(range.start, range.end + 1);
      response.add(body);
      bytesServed += body.length;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final client in _clients.toList()) {
      client.close(force: true);
    }
    _clients.clear();
    try {
      await _server.close(force: true);
    } finally {
      _resources.clear();
      _resourceKeys.clear();
      await onClose?.call();
    }
  }
}
