// lib/services/http_service.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:path/path.dart' as path;
import 'smb_service.dart';
import 'webdav_service.dart';
import 'file_service.dart';
import '../libsmb2_service/smb_file.dart';
import '../settings.dart';

class HttpService {
  static HttpService? _instance;
  static HttpService get instance => _instance ??= HttpService._();
  HttpService._();

  HttpServer? _server;
  SmbService? _smbService;
  WebDavService? _webdavService;
  int _port = 8080;
  String? _localIp;

  bool get isRunning => _server != null;
  String get baseUrl => 'http://${_localIp ?? 'localhost'}:$_port';

  // 文件信息缓存，避免重复获取元数据
  final Map<String, _FileInfoCache> _fileInfoCache = {};

  // 请求去重，避免并发的重复请求
  final Map<String, Future<Response>> _pendingRequests = {};

  // 设置SMB服务实例
  void setSmbService(SmbService service) {
    _smbService = service;
    _webdavService = null;
    _clearCache(); // 切换服务时清除缓存
  }

  // 设置WebDAV服务实例
  void setWebDavService(WebDavService service) {
    _webdavService = service;
    _smbService = null;
    _clearCache(); // 切换服务时清除缓存
  }

  // 清除缓存
  void _clearCache() {
    _fileInfoCache.clear();
    _pendingRequests.clear();
  }

  // 获取缓存的SMB文件信息
  Future<SmbFile?> _getCachedSmbFile(String filePath) async {
    final cacheKey = 'smb:$filePath';
    final cached = _fileInfoCache[cacheKey];

    // 缓存有效期5分钟
    if (cached != null &&
        DateTime.now().difference(cached.timestamp).inMinutes < 5) {
      return cached.smbFile;
    }

    final file = await _smbService!.getFile(filePath);
    if (file.isExists) {
      _fileInfoCache[cacheKey] = _FileInfoCache(smbFile: file);
    }
    return file;
  }

  // 获取缓存的WebDAV文件信息
  Future<WebDavFile?> _getCachedWebDavFile(String filePath) async {
    final cacheKey = 'webdav:$filePath';
    final cached = _fileInfoCache[cacheKey];

    // 缓存有效期5分钟
    if (cached != null &&
        DateTime.now().difference(cached.timestamp).inMinutes < 5) {
      return cached.webdavFile;
    }

    final file = await _webdavService!.getFileInfo(filePath);
    if (file != null) {
      _fileInfoCache[cacheKey] = _FileInfoCache(webdavFile: file);
    }
    return file;
  }

  // 获取本机局域网IP地址
  Future<String?> _getLocalIpAddress() async {
    try {
      // 获取所有网络接口
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
        includeLoopback: false,
      );

      // 优先选择常见的局域网网段
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          final ip = addr.address;
          // 检查是否为常见的局域网IP段
          if (ip.startsWith('192.168.') || 
              ip.startsWith('10.') || 
              ip.startsWith('172.')) {
            return ip;
          }
        }
      }

      // 如果没有找到局域网IP，返回第一个可用的IP
      if (interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty) {
        return interfaces.first.addresses.first.address;
      }
    } catch (e) {
      print('获取本机IP失败: $e');
    }
    return null;
  }

  Future<bool> startServer({String? bindAddress}) async {
    if (_server != null) return true;

    try {
      // 获取本机IP地址
      _localIp = await _getLocalIpAddress();
      
      // 如果没有指定绑定地址，则绑定到所有接口
      final host = bindAddress ?? InternetAddress.anyIPv4;

      final router = Router();

      // 文件服务路由
      router.get('/file/<path|.*>', _handleFileRequest);
      
      // 添加状态检查路由
      router.get('/status', _handleStatusRequest);
      
      // 添加文件信息路由
      router.get('/info/<path|.*>', _handleFileInfoRequest);

      final handler = Pipeline()
          .addMiddleware(logRequests())
          .addMiddleware(_corsMiddleware)
          .addHandler(router);

      _server = await shelf_io.serve(handler, host, _port);
      print('HTTP服务已启动');
      print('本地访问: http://localhost:$_port');
      if (_localIp != null) {
        print('局域网访问: http://$_localIp:$_port');
      }
      return true;
    } catch (e) {
      print('启动HTTP服务失败: $e');
      // 如果端口被占用，尝试其他端口
      if (e.toString().contains('Address already in use')) {
        _port++;
        if (_port < 8090) {
          return await startServer(bindAddress: bindAddress);
        }
      }
      return false;
    }
  }

  Future<void> stopServer() async {
    if (_server != null) {
      await _server!.close();
      _server = null;
      print('HTTP服务已停止');
    }
  }

  // 处理文件请求
  Future<Response> _handleFileRequest(Request request) async {
    try {
      // 获取并解码URL路径（处理中文和特殊字符）
      final encodedPath = request.params['path'] ?? '';
      final decodedPath = Uri.decodeComponent(encodedPath);
      final filePath = '/$decodedPath';

      // 直接处理请求，不使用去重机制（避免阻塞Range请求）
      return await _handleFileRequestInternal(filePath, request);
    } catch (e) {
      return Response.internalServerError(body: '服务器错误: $e');
    }
  }

  // 内部文件请求处理
  Future<Response> _handleFileRequestInternal(String filePath, Request request) async {
    try {
      // 检查是否有可用的文件服务
      if (_smbService == null && _webdavService == null) {
        return Response.notFound('未连接到任何文件服务器');
      }

      if (_smbService != null && _smbService!.isConnected) {
        return await _handleSmbFileRequest(filePath, request);
      } else if (_webdavService != null && _webdavService!.isConnected) {
        return await _handleWebDavFileRequest(filePath, request);
      } else {
        return Response.notFound('文件服务器未连接');
      }
    } catch (e) {
      return Response.internalServerError(body: '服务器错误: $e');
    }
  }

  // 处理SMB文件请求
  Future<Response> _handleSmbFileRequest(String filePath, Request request) async {
    try {
      // 使用缓存获取文件信息
      final file = await _getCachedSmbFile(filePath);
      if (file == null || !file.isExists) {
        return Response.notFound('文件不存在: $filePath');
      }

      // 获取文件扩展名确定MIME类型
      final ext = path.extension(filePath).toLowerCase();
      final mimeType = _getMimeType(ext);

      // 处理Range请求（支持视频播放等）
      final rangeHeader = request.headers['range'];
      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        return await _handleSmbRangeRequest(request, file, mimeType, rangeHeader);
      }

      // 创建文件流 - 需要await
      final stream = await _smbService!.getFileStream(filePath);

      return Response.ok(
        stream,
        headers: {
          'Content-Type': '$mimeType; charset=utf-8',
          'Content-Length': file.size.toString(),
          'Accept-Ranges': 'bytes',
          'Cache-Control': 'public, max-age=3600',
          'Access-Control-Expose-Headers': 'Content-Length, Content-Range',
          // 添加Content-Disposition支持中文文件名下载
          'Content-Disposition': 'inline; filename*=UTF-8\'\'${Uri.encodeComponent(path.basename(filePath))}',
        },
      );
    } catch (e) {
      return Response.internalServerError(body: '服务器错误: $e');
    }
  }

  // 处理WebDAV文件请求
  Future<Response> _handleWebDavFileRequest(String filePath, Request request) async {
    try {
      // 使用缓存获取文件信息
      final fileInfo = await _getCachedWebDavFile(filePath);
      if (fileInfo == null) {
        return Response.notFound('文件不存在: $filePath');
      }

      // 获取文件扩展名确定MIME类型
      final ext = path.extension(filePath).toLowerCase();
      final mimeType = _getMimeType(ext);

      // 处理Range请求（支持视频播放等）
      final rangeHeader = request.headers['range'];
      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        return await _handleWebDavRangeRequest(request, fileInfo, mimeType, rangeHeader);
      }

      // 创建文件流
      final stream = await _webdavService!.getFileStream(filePath);

      return Response.ok(
        stream,
        headers: {
          'Content-Type': '$mimeType; charset=utf-8',
          'Content-Length': fileInfo.size.toString(),
          'Accept-Ranges': 'bytes',
          'Cache-Control': 'public, max-age=3600',
          'Access-Control-Expose-Headers': 'Content-Length, Content-Range',
          'Content-Disposition': 'inline; filename*=UTF-8\'\'${Uri.encodeComponent(path.basename(filePath))}',
        },
      );
    } catch (e) {
      return Response.internalServerError(body: '服务器错误: $e');
    }
  }

  // 处理SMB Range请求（支持断点续传和流媒体）
  Future<Response> _handleSmbRangeRequest(
    Request request,
    SmbFile file,
    String mimeType,
    String rangeHeader
  ) async {
    try {
      final fileSize = file.size;

      // 解析Range头
      final rangeMatch = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(rangeHeader);
      if (rangeMatch == null) {
        return Response(416, body: 'Invalid Range');
      }

      final startStr = rangeMatch.group(1);
      final endStr = rangeMatch.group(2);

      int start = 0;
      int end = fileSize - 1;

      if (startStr != null && startStr.isNotEmpty) {
        start = int.parse(startStr);
      }
      if (endStr != null && endStr.isNotEmpty) {
        end = int.parse(endStr);
      }

      // 限制单次 Range 请求的最大长度
      // 对于视频流播放，通常播放器会请求较小的块（如 2-10MB）
      // 限制最大长度可以：
      // 1. 节省带宽 - 用户跳转时不会浪费大量流量
      // 2. 快速响应 - 播放器可以快速开始播放
      // 3. 支持跳转 - 用户可以随时中断当前请求
      final maxRangeLength = HttpServiceSettings.maxRangeLength;
      final requestedLength = end - start + 1;

      // 如果设置了限制（maxRangeLength > 0）且请求范围超过限制
      if (maxRangeLength > 0 && requestedLength > maxRangeLength) {
        // 如果请求的范围太大，只返回配置的最大范围
        print('[HTTP] Range request too large: ${requestedLength ~/ (1024 * 1024)}MB, limiting to ${maxRangeLength ~/ (1024 * 1024)}MB');
        end = start + maxRangeLength - 1;
      }

      // 确保范围有效
      if (start > end || start >= fileSize) {
        return Response(416, body: 'Range Not Satisfiable');
      }

      end = end.clamp(start, fileSize - 1).toInt();

      final contentLength = end - start + 1;

      // 使用底层的 getRangeStream 直接读取指定范围
      // 这样可以避免读取整个文件,只读取需要的部分,大幅提升性能和响应速度
      // 特别是对于大文件和视频文件的跳转播放场景
      final rangeStream = await _smbService!.libsmb2Service.getRangeStream(
        file.path,
        start: start,
        end: end,
      );

      return Response(
        206, // Partial Content
        body: rangeStream,
        headers: {
          'Content-Type': mimeType,
          'Content-Length': contentLength.toString(),
          'Content-Range': 'bytes $start-$end/$fileSize',
          'Accept-Ranges': 'bytes',
          'Cache-Control': 'public, max-age=3600',
          'Access-Control-Expose-Headers': 'Content-Length, Content-Range',
        },
      );
    } catch (e) {
      return Response.internalServerError(body: '服务器错误: $e');
    }
  }

  // 处理WebDAV Range请求（支持断点续传和流媒体）
  Future<Response> _handleWebDavRangeRequest(
    Request request,
    WebDavFile file,
    String mimeType,
    String rangeHeader
  ) async {
    try {
      final fileSize = file.size;

      // 解析Range头
      final rangeMatch = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(rangeHeader);
      if (rangeMatch == null) {
        return Response(416, body: 'Invalid Range');
      }

      final startStr = rangeMatch.group(1);
      final endStr = rangeMatch.group(2);

      int start = 0;
      int end = fileSize - 1;

      if (startStr != null && startStr.isNotEmpty) {
        start = int.parse(startStr);
      }
      if (endStr != null && endStr.isNotEmpty) {
        end = int.parse(endStr);
      }

      // 确保范围有效
      if (start > end || start >= fileSize) {
        return Response(416, body: 'Range Not Satisfiable');
      }

      end = end.clamp(start, fileSize - 1).toInt();

      final contentLength = end - start + 1;

      // WebDAV可以直接使用Range参数请求
      final stream = await _webdavService!.getFileStream(file.path, start: start, end: end);

      return Response(
        206, // Partial Content
        body: stream,
        headers: {
          'Content-Type': mimeType,
          'Content-Length': contentLength.toString(),
          'Content-Range': 'bytes $start-$end/$fileSize',
          'Accept-Ranges': 'bytes',
          'Cache-Control': 'public, max-age=3600',
          'Access-Control-Expose-Headers': 'Content-Length, Content-Range',
        },
      );
    } catch (e) {
      return Response.internalServerError(body: '服务器错误: $e');
    }
  }

  // 处理状态请求
  Future<Response> _handleStatusRequest(Request request) async {
    final status = {
      'status': 'running',
      'smb_connected': _smbService?.isConnected ?? false,
      'webdav_connected': _webdavService?.isConnected ?? false,
      'local_ip': _localIp,
      'port': _port,
      'base_url': baseUrl,
    };

    return Response.ok(
      '${status.toString()}',
      headers: {'Content-Type': 'application/json'},
    );
  }

  // 处理文件信息请求
  Future<Response> _handleFileInfoRequest(Request request) async {
    try {
      // 获取并解码URL路径（处理中文和特殊字符）
      final encodedPath = request.params['path'] ?? '';
      final decodedPath = Uri.decodeComponent(encodedPath);
      final filePath = '/$decodedPath';

      if (_smbService == null && _webdavService == null) {
        return Response.notFound('未连接到任何文件服务器');
      }

      Map<String, dynamic>? info;

      if (_smbService != null && _smbService!.isConnected) {
        final file = await _smbService!.getFile(filePath);
        if (!file.isExists) {
          return Response.notFound('文件不存在');
        }
        info = {
          'name': file.name,
          'path': file.path,
          'size': file.size,
          'is_directory': file.isDirectory(),
          'url': getFileUrl(file.path),
        };
      } else if (_webdavService != null && _webdavService!.isConnected) {
        final file = await _webdavService!.getFileInfo(filePath);
        if (file == null) {
          return Response.notFound('文件不存在');
        }
        info = {
          'name': file.name,
          'path': file.path,
          'size': file.size,
          'is_directory': file.isDirectory,
          'url': getFileUrl(file.path),
        };
      }

      if (info == null) {
        return Response.notFound('文件不存在');
      }

      return Response.ok(
        info.toString(),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return Response.internalServerError(body: '获取文件信息失败: $e');
    }
  }

  // CORS中间件
  Middleware get _corsMiddleware {
    return (Handler handler) {
      return (Request request) async {
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: _corsHeaders);
        }

        final response = await handler(request);
        return response.change(headers: _corsHeaders);
      };
    };
  }

  Map<String, String> get _corsHeaders => {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Origin, Content-Type, X-Requested-With, Accept, Range',
    'Access-Control-Expose-Headers': 'Content-Length, Content-Range, Accept-Ranges',
  };

  // 获取MIME类型
  String _getMimeType(String extension) {
    switch (extension) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.bmp':
        return 'image/bmp';
      case '.svg':
        return 'image/svg+xml';
      case '.mp4':
        return 'video/mp4';
      case '.avi':
        return 'video/avi';
      case '.mov':
        return 'video/quicktime';
      case '.mkv':
        return 'video/x-matroska';
      case '.wmv':
        return 'video/x-ms-wmv';
      case '.flv':
        return 'video/x-flv';
      case '.webm':
        return 'video/webm';
      case '.mp3':
        return 'audio/mpeg';
      case '.wav':
        return 'audio/wav';
      case '.flac':
        return 'audio/flac';
      case '.aac':
        return 'audio/aac';
      case '.ogg':
        return 'audio/ogg';
      case '.m4a':
        return 'audio/mp4';
      case '.pdf':
        return 'application/pdf';
      case '.txt':
        return 'text/plain; charset=utf-8';
      case '.html':
        return 'text/html; charset=utf-8';
      case '.css':
        return 'text/css';
      case '.js':
        return 'application/javascript';
      case '.json':
        return 'application/json';
      case '.xml':
        return 'application/xml';
      case '.zip':
        return 'application/zip';
      case '.rar':
        return 'application/x-rar-compressed';
      case '.7z':
        return 'application/x-7z-compressed';
      default:
        return 'application/octet-stream';
    }
  }

  // 生成文件的HTTP URL
  String getFileUrl(String smbPath) {
    // 移除开头的斜杠（如果有的话）
    final cleanPath = smbPath.startsWith('/') ? smbPath.substring(1) : smbPath;

    // 对路径的每个部分分别进行URL编码，保留路径分隔符
    final pathSegments = cleanPath.split('/');
    final encodedSegments = pathSegments.map((segment) => Uri.encodeComponent(segment)).toList();
    final encodedPath = encodedSegments.join('/');

    return '$baseUrl/file/$encodedPath';
  }

  String getFileUrlLocalhost(String smbPath) {
    // 移除开头的斜杠（如果有的话）
    final cleanPath = smbPath.startsWith('/') ? smbPath.substring(1) : smbPath;

    // 对路径的每个部分分别进行URL编码，保留路径分隔符
    final pathSegments = cleanPath.split('/');
    final encodedSegments = pathSegments.map((segment) => Uri.encodeComponent(segment)).toList();
    final encodedPath = encodedSegments.join('/');

    return 'http://localhost:$_port/file/$encodedPath';
  }

  // 获取本机IP地址（供外部调用）
  String? get localIpAddress => _localIp;
  
  // 获取所有可用的访问地址
  List<String> getAccessUrls() {
    final urls = <String>[];
    urls.add('http://localhost:$_port');
    if (_localIp != null) {
      urls.add('http://$_localIp:$_port');
    }
    return urls;
  }
}

// 文件信息缓存类
class _FileInfoCache {
  final SmbFile? smbFile;
  final WebDavFile? webdavFile;
  final DateTime timestamp;

  _FileInfoCache({this.smbFile, this.webdavFile}) : timestamp = DateTime.now();
}