import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'webdav_auth.dart';
import 'webdav_multistatus.dart';
import 'webdav_path.dart';
import 'webdav_xml_encoding.dart';
export 'webdav_multistatus.dart' show WebDavFile;

class WebDavService {
  Dio? _dio;
  WebDavPaths? _paths;
  WebDavDigest? _digest;
  String _username = '', _password = '';
  bool _connected = false;
  int _generation = 0;
  final Set<CancelToken> _requests = {};
  bool get isConnected => _connected && _dio != null;

  static const _propfind = '''<?xml version="1.0" encoding="utf-8"?>
<D:propfind xmlns:D="DAV:"><D:prop><D:displayname/><D:getcontentlength/>
<D:getlastmodified/><D:resourcetype/><D:getcontenttype/><D:getetag/>
</D:prop></D:propfind>''';

  Future<bool> connect(
      {required String baseUrl,
      required String username,
      required String password,
      String probePath = '/'}) async {
    await disconnect();
    final generation = _generation;
    _paths = WebDavPaths(baseUrl);
    _username = username;
    _password = password;
    _dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 30),
        followRedirects: false,
        validateStatus: (_) => true,
        headers: {'Accept-Encoding': 'identity'},
        responseType: ResponseType.stream));
    final cancel = _newRequest();
    try {
      final response = await _request(
          'PROPFIND', _paths!.resolve(probePath, directory: true), cancel,
          headers: {
            'Depth': '0',
            'Content-Type': 'application/xml; charset=utf-8'
          },
          body: _propfind);
      _requireStatus(response, {200, 207});
      if (WebDavPaths.canonical(probePath) == '/' &&
          response.requestOptions.uri !=
              _paths!.resolve('/', directory: true)) {
        _paths = WebDavPaths(response.requestOptions.uri.toString());
      }
      final xml = await _readXml(response);
      // Parse to reject HTML login pages and HTTP 200 error documents.
      await _parse(xml, response.requestOptions.uri);
      if (generation != _generation) throw StateError('WebDAV 连接已取消');
      _connected = true;
      return true;
    } catch (_) {
      if (generation == _generation) await disconnect();
      rethrow;
    } finally {
      _finish(cancel);
    }
  }

  Future<void> disconnect() async {
    _generation++;
    _connected = false;
    for (final token in _requests) {
      token.cancel('WebDAV 连接已关闭');
    }
    _requests.clear();
    _dio?.close(force: true);
    _dio = null;
    _paths = null;
    _digest = null;
    _username = '';
    _password = '';
  }

  CancelToken _newRequest() {
    if (_dio == null) throw StateError('未连接到 WebDAV 服务器');
    final token = CancelToken();
    _requests.add(token);
    return token;
  }

  void _finish(CancelToken token) {
    _requests.remove(token);
    token.cancel('请求结束');
  }

  Future<Response<ResponseBody>> _request(
      String method, Uri uri, CancelToken cancel,
      {Map<String, dynamic> headers = const {}, String? body}) async {
    final dio = _dio;
    final paths = _paths;
    final generation = _generation;
    if (dio == null || paths == null) throw StateError('WebDAV 连接已关闭');
    var current = uri;
    var authRetries = 0;
    final visited = <String>{};
    for (var redirects = 0; redirects <= 5;) {
      if (cancel.isCancelled) throw StateError('WebDAV 请求已取消');
      final authenticated = paths.sameOrigin(current);
      final requestHeaders = <String, dynamic>{...headers};
      if (!authenticated) {
        // ETags belong to the DAV resource, not an unrelated CDN resource.
        // The condition was already sent to the origin that issued this URL.
        requestHeaders.remove('If-Match');
        requestHeaders.remove('If-Unmodified-Since');
      }
      if (authenticated && (_username.isNotEmpty || _password.isNotEmpty)) {
        requestHeaders['Authorization'] = _digest?.authorization(
                _username, _password, method, current,
                body: body ?? '') ??
            'Basic ${base64Encode(utf8.encode('$_username:$_password'))}';
      }
      final response = await dio.requestUri<ResponseBody>(current,
          data: body,
          cancelToken: cancel,
          options: Options(
              method: method,
              headers: requestHeaders,
              responseType: ResponseType.stream));
      if (generation != _generation || cancel.isCancelled) {
        await _discard(response);
        throw StateError('WebDAV 请求已取消');
      }
      if (response.statusCode == 401 && authenticated && authRetries < 2) {
        final digest = WebDavDigest.fromChallenges(
            response.headers['www-authenticate'] ?? []);
        if (digest != null) {
          _digest = digest;
          authRetries++;
          await _discard(response);
          continue;
        }
      }
      if ({301, 302, 303, 307, 308}.contains(response.statusCode)) {
        final location = response.headers.value('location');
        await _discard(response);
        if (location == null || redirects++ == 5)
          throw StateError('WebDAV 重定向次数过多或缺少目标地址');
        final target = current.resolve(location);
        if (!{'http', 'https'}.contains(target.scheme) ||
            target.userInfo.isNotEmpty ||
            (current.scheme == 'https' && target.scheme != 'https')) {
          throw StateError('WebDAV 返回了不安全的重定向地址');
        }
        if (method == 'PROPFIND' &&
            (!paths.sameOrigin(target) || response.statusCode == 303)) {
          throw StateError('WebDAV 目录重定向到其他服务，请将最终 WebDAV URL 填入服务器地址');
        }
        if (!visited.add(target.toString()))
          throw StateError('WebDAV 服务器发生重定向循环');
        current = target;
        continue;
      }
      return response;
    }
    throw StateError('WebDAV 重定向失败');
  }

  Future<void> _discard(Response<ResponseBody> response) async {
    await response.data?.stream.listen((_) {}).cancel();
  }

  void _requireStatus(Response<ResponseBody> response, Set<int> expected) {
    if (expected.contains(response.statusCode)) return;
    final code = response.statusCode;
    final detail = switch (code) {
      401 => '认证失败，请检查用户名、密码或应用专用密码',
      403 => '没有访问权限',
      404 => '路径不存在，请检查 WebDAV 服务路径',
      405 || 501 => '此地址不支持 WebDAV PROPFIND，请检查服务端配置',
      423 => '资源已锁定',
      412 => '远端文件已变化，请刷新目录或重新建立下载任务',
      429 => '服务器请求过于频繁，请稍后重试',
      _ => '服务器请求失败',
    };
    throw StateError('WebDAV $detail（HTTP $code）');
  }

  Future<String> _readXml(Response<ResponseBody> response) async {
    final body = response.data;
    if (body == null) throw StateError('WebDAV 响应为空');
    final builder = BytesBuilder(copy: false);
    await for (final chunk
        in body.stream.timeout(const Duration(seconds: 60))) {
      if (builder.length + chunk.length > 32 * 1024 * 1024)
        throw StateError('WebDAV 目录响应超过 32 MiB，请打开更小的目录');
      builder.add(chunk);
    }
    return decodeWebDavXml(builder.takeBytes(),
        contentType: response.headers.value('content-type'));
  }

  Future<List<WebDavFile>> _parse(String xml, Uri request) {
    final base = _paths!.base.toString();
    final url = request.toString();
    if (xml.length > 256 * 1024)
      return Isolate.run(() => parseWebDavMultiStatus(xml, base, url));
    return Future.value(parseWebDavMultiStatus(xml, base, url));
  }

  Future<List<WebDavFile>> _properties(String path, int depth) async {
    if (!isConnected) throw StateError('未连接到 WebDAV 服务器');
    final cancel = _newRequest();
    try {
      final response = await _request(
          'PROPFIND', _paths!.resolve(path, directory: depth == 1), cancel,
          headers: {
            'Depth': '$depth',
            'Content-Type': 'application/xml; charset=utf-8'
          },
          body: _propfind);
      if (response.statusCode == 404 && depth == 0) {
        await _discard(response);
        return [];
      }
      _requireStatus(response, {200, 207});
      return await _parse(
          await _readXml(response), response.requestOptions.uri);
    } finally {
      _finish(cancel);
    }
  }

  Future<List<WebDavFile>> listFiles(String path) async {
    final files = await _properties(path, 1);
    return files
        .where((file) => WebDavPaths.isDirectChild(path, file.path))
        .toList();
  }

  Future<WebDavFile?> getFileInfo(String path) async {
    path = WebDavPaths.canonical(path);
    final files = await _properties(path, 0);
    final file = files.where((file) => file.path == path).firstOrNull;
    if (file == null || file.sizeKnown) return file;
    // Some servers omit getcontentlength from PROPFIND. Resolve length before
    // the playback proxy commits HTTP headers; zero is not an unknown length.
    final cancel = _newRequest();
    try {
      var response = await _request('HEAD', _paths!.resolve(path), cancel);
      _requireStatus(response, {200, 204, 405, 501});
      var size = {200, 204}.contains(response.statusCode)
          ? int.tryParse(response.headers.value('content-length') ?? '')
          : null;
      await _discard(response);
      if (size == null || size < 0) {
        // A one-byte GET works on servers that implement DAV but reject HEAD.
        // Cancel the body even when Range is ignored; never download the file
        // merely to discover its length.
        response = await _request('GET', _paths!.resolve(path), cancel,
            headers: {'Range': 'bytes=0-0'});
        try {
          _requireStatus(response, {200, 206, 416});
          final range = response.headers.value('content-range') ?? '';
          if (response.statusCode == 206) {
            final match = RegExp(r'^bytes\s+0-0/(\d+)$', caseSensitive: false)
                .firstMatch(range.trim());
            size = int.tryParse(match?.group(1) ?? '');
            if (size == 0) size = null;
          } else if (response.statusCode == 416) {
            size = range.trim().toLowerCase() == 'bytes */0' ? 0 : null;
          } else if ({'', 'identity'}
              .contains(response.headers.value('content-encoding') ?? '')) {
            size = int.tryParse(response.headers.value('content-length') ?? '');
          }
        } finally {
          await _discard(response);
        }
      }
      if (size == null || size < 0)
        throw StateError('WebDAV 服务器未提供文件大小，无法安全定位播放');
      return WebDavFile(
          name: file.name,
          path: path,
          size: size,
          isDirectory: file.isDirectory,
          lastModified: file.lastModified ??
              webDavDate(response.headers.value('last-modified')),
          contentType: file.contentType,
          etag: file.etag ?? response.headers.value('etag'));
    } finally {
      _finish(cancel);
    }
  }

  Future<Stream<Uint8List>> getFileStream(String filePath,
      {int? start,
      int? end,
      String? expectedEtag,
      DateTime? expectedModified}) async {
    if (!isConnected) throw StateError('未连接到 WebDAV 服务器');
    if ((start != null && start < 0) || (end != null && end < (start ?? 0)))
      throw ArgumentError('无效的读取范围');
    final cancel = _newRequest();
    try {
      final ranged = start != null || end != null;
      final response =
          await _request('GET', _paths!.resolve(filePath), cancel, headers: {
        if (ranged) 'Range': 'bytes=${start ?? 0}-${end ?? ''}',
        if (expectedEtag != null && !expectedEtag.startsWith('W/'))
          'If-Match': expectedEtag,
        if ((expectedEtag == null || expectedEtag.startsWith('W/')) &&
            expectedModified != null)
          'If-Unmodified-Since': HttpDate.format(expectedModified),
      });
      _requireStatus(response, {200, 206});
      if (response.data == null) throw StateError('WebDAV 响应为空');
      int? length =
          int.tryParse(response.headers.value('content-length') ?? '');
      if (ranged) {
        if (response.statusCode != 206) throw StateError('WebDAV 服务器不支持范围读取');
        if (!{'', 'identity'}
            .contains(response.headers.value('content-encoding') ?? '')) {
          throw StateError('WebDAV 服务器压缩了范围响应，无法安全定位');
        }
        final match = RegExp(r'^bytes\s+(\d+)-(\d+)/(\d+|\*)$',
                caseSensitive: false)
            .firstMatch((response.headers.value('content-range') ?? '').trim());
        final actualStart = int.tryParse(match?.group(1) ?? '');
        final actualEnd = int.tryParse(match?.group(2) ?? '');
        final total = int.tryParse(match?.group(3) ?? '');
        final expectedEnd = end == null
            ? (total == null ? null : total - 1)
            : (total != null && end >= total ? total - 1 : end);
        if (actualStart != (start ?? 0) ||
            actualEnd == null ||
            actualEnd < (start ?? 0) ||
            (total != null && (total <= actualEnd || total <= 0)) ||
            (expectedEnd != null && actualEnd != expectedEnd)) {
          throw StateError('WebDAV 服务器返回了错误的读取范围，已停止以避免文件损坏');
        }
        final rangeLength = actualEnd - actualStart! + 1;
        if (length != null && length != rangeLength)
          throw StateError('WebDAV 响应长度与读取范围不一致');
        length = rangeLength;
      } else if (response.statusCode == 206) {
        throw StateError('WebDAV 服务器意外返回部分文件');
      } else if (!{'', 'identity'}
          .contains(response.headers.value('content-encoding') ?? '')) {
        // Dio automatically decompresses full responses. Content-Length then
        // describes wire bytes, not the decoded stream checked below.
        length = null;
      }
      return _checkedStream(response.data!.stream, cancel, length);
    } catch (_) {
      _finish(cancel);
      rethrow;
    }
  }

  Stream<Uint8List> _checkedStream(
      Stream<Uint8List> stream, CancelToken cancel, int? length) async* {
    var received = 0;
    try {
      await for (final chunk in stream.timeout(const Duration(seconds: 60))) {
        received += chunk.length;
        if (length != null && received > length)
          throw StateError('WebDAV 服务器返回的数据超出预期长度');
        yield chunk;
      }
      if (length != null && received != length)
        throw StateError('WebDAV 连接提前结束，文件未读取完整');
    } finally {
      _finish(cancel);
    }
  }

  Future<Uint8List> downloadFile(String filePath) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in await getFileStream(filePath)) {
      if (builder.length + chunk.length > 64 * 1024 * 1024)
        throw StateError('文件超过 64 MiB，请使用下载任务保存到本地');
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  String getFileUrl(String filePath) =>
      _paths?.resolve(filePath).toString() ?? '';
}
