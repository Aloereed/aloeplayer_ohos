import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:dio/dio.dart';
import '../models/server_config.dart';
import 'file_service.dart';
import 'media_server_catalog.dart';
import 'media_server_client.dart';
import 'media_server_playback.dart';
import 'cast_media_relay.dart';

String mediaServerDownloadError(Object error) {
  if (error is StateError) return error.message.toString();
  if (error is FileSystemException) return '无法写入文件，请检查存储空间和访问权限';
  if (error is DioException && error.response?.statusCode == 401)
    return '登录已失效，请重新登录后继续下载';
  if (error is DioException && error.response?.statusCode == 403)
    return '服务器未允许此账号下载媒体';
  return '下载连接失败，请检查服务器后重试';
}

class MediaServerDownloadFile implements RevisionFileItem {
  @override
  final String name, path;
  @override
  final int size;
  @override
  final DateTime? modified;
  @override
  final String? etag;
  @override
  bool get isDirectory => false;
  const MediaServerDownloadFile(
      {required this.name,
      required this.path,
      required this.size,
      this.modified,
      this.etag});
}

/// A saved task contains only server/item/source identifiers. Authentication is
/// resolved from the secure server store each time it resumes.
class MediaServerDownloadSource
    implements FileService, RevisionAwareFileService {
  static const serverPrefix = 'media-server:';
  final MediaServerClient client;
  final _cancel = CancelToken();
  final _reader = HttpClient()..autoUncompress = false;
  CastMediaRelay? _relay;
  MediaServerDownloadFile? _file;
  MediaServerSource? _source;
  String? _itemId;
  bool _closed = false;
  MediaServerDownloadSource(MediaServerConnection connection)
      : client = MediaServerClient(connection);

  static String taskServerId(String id) => '$serverPrefix$id';
  static Future<MediaServerDownloadSource> restore(String taskServerId) async {
    if (!taskServerId.startsWith(serverPrefix) ||
        taskServerId.length == serverPrefix.length) {
      throw StateError('下载服务器标识无效');
    }
    final id = taskServerId.substring(serverPrefix.length);
    final connection =
        (await MediaServerStore.load()).where((c) => c.id == id).firstOrNull;
    if (connection == null) throw StateError('媒体服务器配置已删除，请重新添加后下载');
    return MediaServerDownloadSource(connection);
  }

  @override
  bool get isConnected => !_closed;
  @override
  Future<bool> connect(ServerConfig config) async => !_closed;
  @override
  Future<List<FileItem>> listFiles(String path) async =>
      throw UnsupportedError('Download source only');

  Future<MediaServerDownloadFile> prepare(MediaServerItem item,
      {String? sourceId}) async {
    if (_closed) throw StateError('下载连接已关闭');
    final user = await client.dio.get<Map<String, dynamic>>(
        'Users/${Uri.encodeComponent(client.connection.userId)}',
        cancelToken: _cancel);
    if (user.data?['Policy']?['EnableContentDownloading'] == false) {
      throw StateError('服务器管理员未允许此账号下载媒体');
    }
    if (!['Movie', 'Episode', 'Video', 'MusicVideo', 'Audio']
            .contains(item.type) ||
        item.metadata['CanDownload'] == false) throw StateError('此媒体不支持下载原文件');
    final sources = await client.playbackSources(item, cancelToken: _cancel);
    final source = sourceId == null
        ? sources.firstOrNull
        : sources.where((s) => s.id == sourceId).firstOrNull;
    if (source == null ||
        source.id.isEmpty ||
        source.data['IsInfiniteStream'] == true ||
        source.data['RequiresOpening'] == true)
      throw StateError('所选版本没有可下载的原文件');
    var extension = (source.data['Container'] as String? ?? '')
        .split(',')
        .first
        .toLowerCase();
    if (extension == 'matroska') extension = 'mkv';
    if (!RegExp(r'^[a-z0-9]{1,10}$').hasMatch(extension) ||
        ['m3u8', 'm3u', 'mpd', 'strm', 'pls'].contains(extension))
      throw StateError('此媒体不是可直接下载的原文件');
    final logicalPath =
        Uri(pathSegments: [item.id, source.id, 'media.$extension']).path;
    final upstream = resolveMediaServerUrl(
        client.connection.url,
        Uri(pathSegments: [
          item.type == 'Audio' ? 'Audio' : 'Videos',
          item.id,
          'stream'
        ], queryParameters: {
          'Static': 'true',
          'MediaSourceId': source.id
        }).toString());
    await _relay?.close();
    _relay = await CastMediaRelay.start(upstream.toString(),
        host: '127.0.0.1',
        bindAddress: InternetAddress.loopbackIPv4,
        headers: client.headers);
    if (_closed) {
      await _relay?.close();
      throw StateError('下载连接已关闭');
    }
    var response = await _request('HEAD');
    if ([405, 501].contains(response.statusCode) ||
        (response.statusCode == 200 && response.contentLength < 0)) {
      await response.listen((_) {}).cancel();
      response = await _request('GET', headers: {'Range': 'bytes=0-0'});
    }
    try {
      var size = response.contentLength;
      if (response.statusCode == 206) {
        final range = RegExp(r'^bytes 0-0/(\d+)$')
            .firstMatch(response.headers.value('content-range') ?? '');
        size = range == null ? -1 : int.parse(range[1]!);
      }
      if (![200, 206].contains(response.statusCode) || size < 0) {
        throw StateError('服务器未提供可校验的原文件大小（HTTP ${response.statusCode}）');
      }
      final encoding =
          response.headers.value(HttpHeaders.contentEncodingHeader);
      if (encoding != null && encoding != 'identity')
        throw StateError('服务器压缩响应不支持原文件续传');
      final rawTag = response.headers.value(HttpHeaders.etagHeader);
      final etag = rawTag != null && !rawTag.startsWith('W/') ? rawTag : null;
      DateTime? modified;
      final date = response.headers.value(HttpHeaders.lastModifiedHeader);
      if (date != null) {
        try {
          modified = HttpDate.parse(date);
        } catch (_) {}
      }
      final file = MediaServerDownloadFile(
          name: item.name.toLowerCase().endsWith('.$extension')
              ? item.name
              : '${item.name}.$extension',
          path: logicalPath,
          size: size,
          etag: etag,
          modified: modified);
      _file = file;
      _source = source;
      _itemId = item.id;
      return file;
    } finally {
      await response.listen((_) {}).cancel();
    }
  }

  Future<({Map<String, int> files, String? error})> saveSubtitles(
      String destination,
      {Map<String, int> existing = const {}}) async {
    final source = _source;
    if (_closed || source == null || _itemId == null || _relay == null) {
      throw StateError('请重新连接后下载字幕');
    }
    final saved = <String, int>{};
    for (final entry in existing.entries) {
      final file = File(entry.key);
      if (await file.exists() &&
          await file.length() == entry.value &&
          entry.value > 0) saved[entry.key] = entry.value;
    }
    var failures = 0, total = saved.values.fold<int>(0, (a, b) => a + b);
    final streams = source.streams
        .where((s) => s.type == 'Subtitle' && s.external)
        .toList();
    final deadline = Timer(const Duration(seconds: 45), () {
      unawaited(disconnect().catchError((_) {}));
    });
    try {
      for (final stream in streams.take(32)) {
        File? partial;
        RandomAccessFile? writer;
        try {
          if (_closed) throw StateError('字幕下载已中断');
          final codec = (stream.data['Codec'] as String? ?? '').toLowerCase();
          final extension = switch (codec) {
            'srt' || 'subrip' || 'ttml' || 'mov_text' => 'srt',
            'webvtt' || 'vtt' => 'vtt',
            'ass' => 'ass',
            'ssa' => 'ssa',
            _ => null,
          };
          if (extension == null) {
            failures++;
            continue;
          }
          var language = (stream.data['Language'] as String? ?? 'und')
              .replaceAll(RegExp('[^a-zA-Z0-9_-]'), '_');
          if (language.isEmpty) language = 'und';
          if (language.length > 24) language = language.substring(0, 24);
          final prefix =
              '${path.withoutExtension(destination)}.aloe-sub.$language.${stream.index}.';
          if (saved.keys.any((name) =>
              name.startsWith(prefix) && name.endsWith('.$extension')))
            continue;
          final upstream = resolveMediaServerUrl(
              client.connection.url,
              (!['ttml', 'mov_text'].contains(codec)
                      ? stream.data['DeliveryUrl'] as String?
                      : null) ??
                  'Videos/${Uri.encodeComponent(_itemId!)}/${Uri.encodeComponent(source.id)}/Subtitles/${stream.index}/Stream.$extension');
          final address = _relay!.grantRemote(upstream,
              headers:
                  upstream.origin == Uri.parse(client.connection.url).origin
                      ? client.headers
                      : const {});
          final request = await _reader
              .getUrl(Uri.parse(address))
              .timeout(const Duration(seconds: 8));
          request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
          final response =
              await request.close().timeout(const Duration(seconds: 10));
          final encoding =
              response.headers.value(HttpHeaders.contentEncodingHeader);
          final contentType = response.headers.contentType?.mimeType;
          if (response.statusCode != 200 ||
              (encoding != null && encoding != 'identity') ||
              contentType == 'text/html' ||
              contentType == 'application/json' ||
              response.contentLength > 32 * 1024 * 1024) {
            await response.listen((_) {}).cancel();
            throw StateError('服务器未返回可保存的字幕');
          }
          final target = '$prefix${const Uuid().v4()}.$extension';
          partial = File('$target.aloe-part');
          writer = await partial.open(mode: FileMode.write);
          var size = 0;
          await for (final bytes
              in response.timeout(const Duration(seconds: 10))) {
            if (size == 0 &&
                RegExp(r'^\s*(<!doctype|<html)', caseSensitive: false).hasMatch(
                    utf8.decode(bytes.take(512).toList(),
                        allowMalformed: true))) {
              throw StateError('服务器返回了网页');
            }
            size += bytes.length;
            if (size > 32 * 1024 * 1024 || total + size > 128 * 1024 * 1024) {
              throw StateError('字幕文件过大');
            }
            await writer.writeFrom(bytes);
          }
          if (size == 0 ||
              (response.contentLength >= 0 && size != response.contentLength)) {
            throw StateError('字幕下载不完整');
          }
          await writer.flush();
          await writer.close();
          writer = null;
          await partial.rename(target);
          saved[target] = size;
          total += size;
        } catch (_) {
          failures++;
        } finally {
          try {
            await writer?.close();
          } finally {
            if (partial != null && await partial.exists())
              await partial.delete();
          }
        }
        if (_closed) {
          failures += streams.length;
          break;
        }
      }
    } finally {
      deadline.cancel();
    }
    return (
      files: saved,
      error: failures > 0 || streams.length > 32
          ? '部分外挂字幕未保存，可重试；图片字幕暂不支持独立下载'
          : null
    );
  }

  @override
  Future<FileItem?> getFile(String path) async {
    final uri = Uri.parse(path);
    final parts = uri.pathSegments;
    if (uri.hasScheme ||
        uri.hasQuery ||
        uri.hasFragment ||
        parts.length != 3 ||
        parts.any((s) => s.isEmpty || s == '..')) {
      throw StateError('下载媒体标识无效');
    }
    final item = await client.details(parts[0], cancelToken: _cancel);
    final file = await prepare(item, sourceId: parts[1]);
    if (file.path != path) throw StateError('媒体原文件格式已变化，请重新下载');
    return file;
  }

  Future<HttpClientResponse> _request(String method,
      {Map<String, String> headers = const {}}) async {
    if (_closed || _relay == null) throw StateError('下载连接已关闭');
    final request = await _reader
        .openUrl(method, Uri.parse(_relay!.url))
        .timeout(const Duration(seconds: 20));
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    headers.forEach(request.headers.set);
    try {
      return await request.close().timeout(const Duration(seconds: 25));
    } catch (_) {
      request.abort();
      rethrow;
    }
  }

  @override
  Future<Stream<Uint8List>> getFileStream(String path,
      {int? start, int? end}) async {
    final file = _file?.path == path ? _file! : (await getFile(path))!;
    return getFileStreamForRevision(file, start: start, end: end);
  }

  @override
  Future<Stream<Uint8List>> getFileStreamForRevision(FileItem file,
      {int? start, int? end}) async {
    if (file is! MediaServerDownloadFile || _file?.path != file.path)
      throw StateError('下载源未准备好');
    final offset = start ?? 0, last = end ?? file.size - 1;
    if (offset < 0 || last < offset || last >= file.size)
      throw RangeError('Invalid download range');
    final headers = <String, String>{};
    final ranged = start != null || end != null;
    if (ranged) headers['Range'] = 'bytes=$offset-$last';
    if (file.etag != null) {
      headers[ranged ? 'If-Range' : 'If-Match'] = file.etag!;
    } else if (file.modified != null) {
      headers[ranged ? 'If-Range' : 'If-Unmodified-Since'] =
          HttpDate.format(file.modified!);
    } else if (offset > 0) {
      throw StateError('服务器缺少文件版本标识，无法安全续传，请取消后重新下载');
    }
    final response = await _request('GET', headers: headers);
    try {
      if (response.statusCode == 206) {
        final match = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$')
            .firstMatch(response.headers.value('content-range') ?? '');
        if (match == null ||
            int.parse(match[1]!) != offset ||
            int.parse(match[2]!) != last ||
            int.parse(match[3]!) != file.size) throw StateError('服务器返回的续传范围不符');
      } else if (response.statusCode != 200 ||
          offset != 0 ||
          last != file.size - 1) {
        throw StateError('服务器不接受此续传范围或原文件已变化（HTTP ${response.statusCode}）');
      }
      if (response.contentLength >= 0 &&
          response.contentLength != last - offset + 1)
        throw StateError('原文件大小已变化');
      final actualTag = response.headers.value('etag');
      if (file.etag != null && actualTag != null && actualTag != file.etag)
        throw StateError('原文件版本已变化');
      final encoding = response.headers.value('content-encoding');
      if (encoding != null && encoding != 'identity')
        throw StateError('压缩响应不能用于原文件续传');
    } catch (_) {
      await response.listen((_) {}).cancel();
      rethrow;
    }
    return response
        .timeout(const Duration(seconds: 25))
        .map((bytes) => bytes is Uint8List ? bytes : Uint8List.fromList(bytes));
  }

  @override
  Future<void> disconnect() async {
    if (_closed) return;
    _closed = true;
    _cancel.cancel('Download closed');
    _reader.close(force: true);
    await _relay?.close();
    await client.close();
  }
}
