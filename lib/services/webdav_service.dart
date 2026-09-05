// lib/services/webdav_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

class WebDavFile {
  final String name;
  final String path;
  final int size;
  final bool isDirectory;
  final DateTime? lastModified;
  final String? contentType;

  WebDavFile({
    required this.name,
    required this.path,
    required this.size,
    required this.isDirectory,
    this.lastModified,
    this.contentType,
  });

  @override
  String toString() => 'WebDavFile(name: $name, path: $path, isDir: $isDirectory)';
}

class WebDavService {
  Dio? _dio;
  String? _baseUrl;
  bool get isConnected => _dio != null;

  // 连接到WebDAV服务器
  Future<bool> connect({
    required String baseUrl,
    required String username,
    required String password,
  }) async {
    try {
      _baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

      print('WebDAV 连接到: $_baseUrl');
      print('用户名: $username');

      // 创建Dio实例with基础认证
      _dio = Dio(
        BaseOptions(
          baseUrl: _baseUrl!,
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 60),
          headers: {
            'Authorization': 'Basic ${base64Encode(utf8.encode('$username:$password'))}',
          },
          validateStatus: (status) => status != null && status < 500,
          responseType: ResponseType.plain, // 使用 plain 以确保能正确接收 XML
        ),
      );

      // 测试连接
      print('发送测试 PROPFIND 请求到 /');
      final response = await _dio!.request(
        '/',
        options: Options(
          method: 'PROPFIND',
          headers: {
            'Depth': '0',
          },
        ),
      );

      print('测试连接响应状态码: ${response.statusCode}');
      final success = response.statusCode == 207 || response.statusCode == 200;

      if (!success) {
        print('连接测试失败，响应数据: ${response.data}');
      }

      return success;
    } catch (e) {
      print('WebDAV连接失败: $e');
      _dio = null;
      return false;
    }
  }

  // 断开连接
  Future<void> disconnect() async {
    _dio?.close();
    _dio = null;
    _baseUrl = null;
  }

  // 列出目录中的文件
  Future<List<WebDavFile>> listFiles(String path) async {
    if (_dio == null) throw Exception('未连接到WebDAV服务器');

    try {
      // 确保路径格式正确
      final cleanPath = _cleanPath(path);

      // 发送PROPFIND请求
      final response = await _dio!.request(
        cleanPath,
        options: Options(
          method: 'PROPFIND',
          headers: {
            'Depth': '1',
            'Content-Type': 'application/xml; charset=utf-8',
          },
        ),
        data: '''<?xml version="1.0" encoding="utf-8" ?>
<D:propfind xmlns:D="DAV:">
  <D:prop>
    <D:displayname/>
    <D:getcontentlength/>
    <D:getlastmodified/>
    <D:resourcetype/>
    <D:getcontenttype/>
  </D:prop>
</D:propfind>''',
      );

      print('WebDAV PROPFIND 响应状态码: ${response.statusCode}');

      if (response.statusCode != 207) {
        print('WebDAV PROPFIND 错误响应: ${response.data}');
        throw Exception('PROPFIND请求失败: ${response.statusCode}');
      }

      print('WebDAV PROPFIND 响应数据: ${response.data}');

      // 解析XML响应
      final files = _parseMultiStatusResponse(response.data, cleanPath);
      print('WebDAV 解析到 ${files.length} 个文件');
      return files;
    } catch (e) {
      throw Exception('获取文件列表失败: $e');
    }
  }

  // 解析WebDAV多状态响应
  List<WebDavFile> _parseMultiStatusResponse(String xmlData, String currentPath) {
    final files = <WebDavFile>[];

    try {
      print('开始解析 XML 响应...');
      final document = XmlDocument.parse(xmlData);

      // 尝试多种方式查找 response 元素
      var responses = document.findAllElements('response');
      if (responses.isEmpty) {
        responses = document.findAllElements('D:response');
      }
      if (responses.isEmpty) {
        responses = document.findAllElements('d:response');
      }

      print('找到 ${responses.length} 个 response 元素');

      for (final response in responses) {
        try {
          // 尝试多种方式查找 href
          var hrefElements = response.findElements('href');
          if (hrefElements.isEmpty) hrefElements = response.findElements('D:href');
          if (hrefElements.isEmpty) hrefElements = response.findElements('d:href');

          if (hrefElements.isEmpty) {
            print('警告: 找不到 href 元素');
            continue;
          }

          final href = hrefElements.first.innerText;
          final decodedHref = Uri.decodeFull(href);
          print('处理文件 href: $href -> $decodedHref');

          // 解码路径
          final filePath = _normalizeHref(decodedHref);
          print('标准化路径: $filePath (当前路径: $currentPath)');

          // 跳过当前目录本身
          if (_isSameOrParentPath(filePath, currentPath)) {
            print('跳过当前目录: $filePath');
            continue;
          }

          // 尝试查找 propstat
          var propstatElements = response.findElements('propstat');
          if (propstatElements.isEmpty) propstatElements = response.findElements('D:propstat');
          if (propstatElements.isEmpty) propstatElements = response.findElements('d:propstat');

          if (propstatElements.isEmpty) {
            print('警告: 找不到 propstat 元素');
            continue;
          }

          final propstat = propstatElements.first;

          // 尝试查找 prop
          var propElements = propstat.findElements('prop');
          if (propElements.isEmpty) propElements = propstat.findElements('D:prop');
          if (propElements.isEmpty) propElements = propstat.findElements('d:prop');

          if (propElements.isEmpty) {
            print('警告: 找不到 prop 元素');
            continue;
          }

          final prop = propElements.first;

          // 获取文件名
          var fileName = filePath.split('/').where((s) => s.isNotEmpty).last;

          // 尝试从displayname获取文件名
          var displayNameElements = prop.findElements('displayname');
          if (displayNameElements.isEmpty) displayNameElements = prop.findElements('D:displayname');
          if (displayNameElements.isEmpty) displayNameElements = prop.findElements('d:displayname');

          if (displayNameElements.isNotEmpty) {
            final displayName = displayNameElements.first.innerText.trim();
            if (displayName.isNotEmpty) {
              fileName = displayName;
            }
          }

          // 检查是否为目录
          var resourceTypeElements = prop.findElements('resourcetype');
          if (resourceTypeElements.isEmpty) resourceTypeElements = prop.findElements('D:resourcetype');
          if (resourceTypeElements.isEmpty) resourceTypeElements = prop.findElements('d:resourcetype');

          bool isDir = false;
          if (resourceTypeElements.isNotEmpty) {
            final resourceType = resourceTypeElements.first;
            var collectionElements = resourceType.findElements('collection');
            if (collectionElements.isEmpty) collectionElements = resourceType.findElements('D:collection');
            if (collectionElements.isEmpty) collectionElements = resourceType.findElements('d:collection');
            isDir = collectionElements.isNotEmpty;
          }

          // 获取文件大小
          int size = 0;
          var contentLengthElements = prop.findElements('getcontentlength');
          if (contentLengthElements.isEmpty) contentLengthElements = prop.findElements('D:getcontentlength');
          if (contentLengthElements.isEmpty) contentLengthElements = prop.findElements('d:getcontentlength');

          if (contentLengthElements.isNotEmpty) {
            final sizeStr = contentLengthElements.first.innerText;
            size = int.tryParse(sizeStr) ?? 0;
          }

          // 获取最后修改时间
          DateTime? lastModified;
          var lastModifiedElements = prop.findElements('getlastmodified');
          if (lastModifiedElements.isEmpty) lastModifiedElements = prop.findElements('D:getlastmodified');
          if (lastModifiedElements.isEmpty) lastModifiedElements = prop.findElements('d:getlastmodified');

          if (lastModifiedElements.isNotEmpty) {
            try {
              lastModified = HttpDate.parse(lastModifiedElements.first.innerText);
            } catch (e) {
              print('解析修改时间失败: $e');
            }
          }

          // 获取内容类型
          String? contentType;
          var contentTypeElements = prop.findElements('getcontenttype');
          if (contentTypeElements.isEmpty) contentTypeElements = prop.findElements('D:getcontenttype');
          if (contentTypeElements.isEmpty) contentTypeElements = prop.findElements('d:getcontenttype');

          if (contentTypeElements.isNotEmpty) {
            contentType = contentTypeElements.first.innerText;
          }

          final file = WebDavFile(
            name: fileName,
            path: filePath,
            size: size,
            isDirectory: isDir,
            lastModified: lastModified,
            contentType: contentType,
          );

          print('添加文件: $fileName (目录: $isDir, 大小: $size)');
          files.add(file);
        } catch (e) {
          print('解析文件条目失败: $e');
          continue;
        }
      }
    } catch (e) {
      print('解析XML响应失败: $e');
      print('XML 数据: $xmlData');
    }

    print('最终解析到 ${files.length} 个文件');
    return files;
  }

  // 获取文件流（用于播放和下载）
  Future<Stream<Uint8List>> getFileStream(String filePath, {int? start, int? end}) async {
    if (_dio == null) throw Exception('未连接到WebDAV服务器');

    try {
      final cleanPath = _cleanPath(filePath);

      final headers = <String, dynamic>{};
      if (start != null || end != null) {
        final startStr = start?.toString() ?? '0';
        final endStr = end?.toString() ?? '';
        headers['Range'] = 'bytes=$startStr-$endStr';
      }

      final response = await _dio!.get<ResponseBody>(
        cleanPath,
        options: Options(
          responseType: ResponseType.stream,
          headers: headers,
        ),
      );

      if (response.statusCode != 200 && response.statusCode != 206) {
        await response.data?.stream.listen((_) {}).cancel();
        throw Exception('文件请求失败: ${response.statusCode}');
      }
      if ((start != null || end != null) && response.statusCode != 206) {
        await response.data?.stream.listen((_) {}).cancel();
        throw Exception('服务器不支持范围读取');
      }
      if (response.data == null) throw Exception('响应数据为空');

      return response.data!.stream;
    } catch (e) {
      throw Exception('获取文件流失败: $e');
    }
  }

  // 获取文件信息
  Future<WebDavFile?> getFileInfo(String filePath) async {
    if (_dio == null) throw Exception('未连接到WebDAV服务器');

    try {
      final cleanPath = _cleanPath(filePath);

      final response = await _dio!.request(
        cleanPath,
        options: Options(
          method: 'PROPFIND',
          headers: {
            'Depth': '0',
            'Content-Type': 'application/xml; charset=utf-8',
          },
        ),
        data: '''<?xml version="1.0" encoding="utf-8" ?>
<D:propfind xmlns:D="DAV:">
  <D:prop>
    <D:displayname/>
    <D:getcontentlength/>
    <D:getlastmodified/>
    <D:resourcetype/>
    <D:getcontenttype/>
  </D:prop>
</D:propfind>''',
      );

      if (response.statusCode != 207) {
        return null;
      }

      final files = _parseMultiStatusResponse(response.data, '');
      return files.isNotEmpty ? files.first : null;
    } catch (e) {
      print('获取文件信息失败: $e');
      return null;
    }
  }

  // 清理路径
  String _cleanPath(String path) {
    // 确保路径以/开头
    if (!path.startsWith('/')) {
      path = '/$path';
    }
    return path;
  }

  // 规范化href
  String _normalizeHref(String href) {
    print('_normalizeHref 输入: $href, baseUrl: $_baseUrl');

    // 移除基础URL部分（如果存在）
    if (_baseUrl != null) {
      final uri = Uri.parse(_baseUrl!);
      print('baseUrl URI path: ${uri.path}');

      // 如果 href 是完整 URL，解析它
      if (href.startsWith('http://') || href.startsWith('https://')) {
        final hrefUri = Uri.parse(href);
        href = hrefUri.path;
        print('从完整 URL 提取路径: $href');
      }

      // 如果 baseUrl 有路径部分，且 href 以该路径开始，则移除
      if (uri.path.isNotEmpty && uri.path != '/' && href.startsWith(uri.path)) {
        href = href.substring(uri.path.length);
        print('移除 baseUrl 路径后: $href');
      }
    }

    // 确保以/开头
    if (!href.startsWith('/')) {
      href = '/$href';
    }

    print('_normalizeHref 输出: $href');
    return href;
  }

  // 检查是否为相同或父路径
  bool _isSameOrParentPath(String path1, String path2) {
    final p1 = path1.endsWith('/') ? path1.substring(0, path1.length - 1) : path1;
    final p2 = path2.endsWith('/') ? path2.substring(0, path2.length - 1) : path2;
    final result = p1 == p2;
    if (result) {
      print('路径相同，跳过: "$p1" == "$p2"');
    }
    return result;
  }

  // 直接下载文件字节（用于小文件）
  Future<Uint8List> downloadFile(String filePath) async {
    if (_dio == null) throw Exception('未连接到WebDAV服务器');

    try {
      final cleanPath = _cleanPath(filePath);

      final response = await _dio!.get<List<int>>(
        cleanPath,
        options: Options(responseType: ResponseType.bytes),
      );

      return Uint8List.fromList(response.data!);
    } catch (e) {
      throw Exception('下载文件失败: $e');
    }
  }

  // 获取WebDAV服务器的完整文件URL（用于生成HTTP代理URL）
  String getFileUrl(String filePath) {
    if (_baseUrl == null) return '';
    final cleanPath = _cleanPath(filePath);
    return '$_baseUrl$cleanPath';
  }
}
