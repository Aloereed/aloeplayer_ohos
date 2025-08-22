// lib/services/http_service.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:path/path.dart' as path;
import 'smb_service.dart';
import 'package:smb_connect/smb_connect.dart';

class HttpService {
  static HttpService? _instance;
  static HttpService get instance => _instance ??= HttpService._();
  HttpService._();

  HttpServer? _server;
  final SmbService _smbService = SmbService();
  int _port = 8080;
  String? _localIp;

  bool get isRunning => _server != null;
  String get baseUrl => 'http://${_localIp ?? 'localhost'}:$_port';

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
      final filePath = '/${request.params['path']}';
      
      if (!_smbService.isConnected) {
        return Response.notFound('SMB未连接');
      }

      final file = await _smbService.getFile(filePath);
      if (!file.isExists) {
        return Response.notFound('文件不存在');
      }

      // 获取文件扩展名确定MIME类型
      final ext = path.extension(filePath).toLowerCase();
      final mimeType = _getMimeType(ext);

      // 处理Range请求（支持视频播放等）
      final rangeHeader = request.headers['range'];
      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        return await _handleRangeRequest(request, file, mimeType, rangeHeader);
      }

      // 创建文件流
      final stream = _smbService.getFileStream(filePath);
      
      return Response.ok(
        stream,
        headers: {
          'Content-Type': mimeType,
          'Content-Length': file.size.toString(),
          'Accept-Ranges': 'bytes',
          'Cache-Control': 'public, max-age=3600',
          'Access-Control-Expose-Headers': 'Content-Length, Content-Range',
        },
      );
    } catch (e) {
      print('文件请求处理失败: $e');
      return Response.internalServerError(body: '服务器错误: $e');
    }
  }

  // 处理Range请求（支持断点续传和流媒体）
  Future<Response> _handleRangeRequest(
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
      
      // 确保范围有效
      if (start > end || start >= fileSize) {
        return Response(416, body: 'Range Not Satisfiable');
      }
      
      end = end.clamp(start, fileSize - 1);
      final contentLength = end - start + 1;

      // 创建范围流
      final stream = (await _smbService.getFileStream(file.path))
          .skip(start)
          .take(contentLength);

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
      print('Range请求处理失败: $e');
      return Response.internalServerError(body: '服务器错误');
    }
  }

  // 处理状态请求
  Future<Response> _handleStatusRequest(Request request) async {
    final status = {
      'status': 'running',
      'smb_connected': _smbService.isConnected,
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
      final filePath = '/${request.params['path']}';
      
      if (!_smbService.isConnected) {
        return Response.notFound('SMB未连接');
      }

      final file = await _smbService.getFile(filePath);
      if (!file.isExists) {
        return Response.notFound('文件不存在');
      }

      final info = {
        'name': file.name,
        'path': file.path,
        'size': file.size,
        'is_directory': file.isDirectory(),
        'url': getFileUrl(file.path),
      };

      return Response.ok(
        info.toString(),
        headers: {'Content-Type': 'application/json'},
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
    return '$baseUrl/file/$cleanPath';
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