import 'smb_stat_time.dart';
import '../services/credential_store.dart';
// Libsmb2 Service - 兼容 smb_service.dart 接口的实现
import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'libsmb2_bindings.dart';
import 'libsmb2_file.dart';
import 'libsmb2_stream_reader.dart';

class Libsmb2Service {
  static const String _hostKey = 'smb_host';
  static const String _usernameKey = 'smb_username';
  static const String _passwordKey = 'smb_password';
  static const String _domainKey = 'smb_domain';

  final Libsmb2Bindings _bindings = Libsmb2Bindings();
  ffi.Pointer<Smb2Context>? _context;
  String? _currentHost;
  String? _currentShare;
  String? _basePath;  // 连接时指定的基础路径（share之后的路径部分）

  // 文件句柄管理 - 用于支持多个并发流式读取
  final Map<String, Libsmb2StreamReader> _streamReaders = {};
  final Set<Libsmb2StreamReader> _rangeReaders = {};

  bool get isConnected => _context != null && _context!.address != 0;

  // 保存登录信息
  Future<void> saveCredentials({
    required String host,
    required String username,
    required String password,
    required String domain,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hostKey, host);
    await prefs.setString(_usernameKey, username);
    await CredentialStore.write(_passwordKey, password);
    await prefs.remove(_passwordKey);
    await prefs.setString(_domainKey, domain);
  }

  // 获取保存的登录信息
  Future<Map<String, String>> getSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'host': prefs.getString(_hostKey) ?? '',
      'username': prefs.getString(_usernameKey) ?? '',
      'password': await CredentialStore.migrateLegacy(_passwordKey, prefs, _passwordKey),
      'domain': prefs.getString(_domainKey) ?? '',
    };
  }

  // 连接SMB
  Future<bool> connect({
    required String host,
    required String username,
    required String password,
    required String domain,
    bool signingRequired = false,
    bool anonymousLogin = false,
    bool encryption = false,
  }) async {
    try {
      if (_context != null) await disconnect();
      print('[libsmb2] Starting connection...');
      print('[libsmb2] Host: $host');
      print('[libsmb2] Username: $username');
      print('[libsmb2] Domain: $domain');
      print('[libsmb2] Signing Required: $signingRequired');
      print('[libsmb2] Anonymous Login: $anonymousLogin');
      print('[libsmb2] Encryption: $encryption');

      // 初始化 SMB2 context
      _context = _bindings.smb2_init_context();
      if (_context == null || _context!.address == 0) {
        throw Exception('Failed to initialize SMB2 context');
      }
      print('[libsmb2] Context initialized: ${_context!.address}');

      // 设置认证信息
      final userPtr = (anonymousLogin ? 'guest' : username).toNativeUtf8();
      final passPtr = (anonymousLogin ? '' : password).toNativeUtf8();
      final domainPtr = domain.toNativeUtf8();

      try {
        // 设置认证信息
        print('[libsmb2] Setting credentials...');
        _bindings.smb2_set_user(_context!, userPtr);
        _bindings.smb2_set_password(_context!, passPtr);
        if (domain.isNotEmpty) {
          _bindings.smb2_set_domain(_context!, domainPtr);
          print('[libsmb2] Domain set: $domain');
        }

        // 设置安全模式 - 根据配置启用或要求签名
        int securityMode;
        if (signingRequired) {
          securityMode = SMB2_NEGOTIATE_SIGNING_ENABLED | SMB2_NEGOTIATE_SIGNING_REQUIRED;
          print('[libsmb2] Security mode set to SIGNING_REQUIRED');
        } else {
          securityMode = SMB2_NEGOTIATE_SIGNING_ENABLED;
          print('[libsmb2] Security mode set to SIGNING_ENABLED');
        }
        _bindings.smb2_set_security_mode(_context!, securityMode);

        _bindings.smb2_set_sign(_context!, signingRequired ? 1 : 0);
        _bindings.smb2_set_seal(_context!, encryption ? 1 : 0);
        _bindings.smb2_set_timeout(_context!, 30);

        // 解析 host 和 share
        // 格式: //server/share 或 server/share
        String cleanHost = host.replaceFirst(RegExp(r'^//'), '');
        final parts = cleanHost.split('/');

        if (parts.isEmpty) {
          throw Exception('Invalid host format');
        }

        final serverName = parts[0];
        // 如果没有提供共享名，使用 IPC$ (用于枚举共享)
        final shareName = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : 'IPC\$';

        // 提取 share 之后的路径部分（如果有）
        // 例如: 192.168.1.1/share/folder/subfolder -> basePath = "folder/subfolder"
        String? basePath;
        if (parts.length > 2) {
          basePath = parts.sublist(2).join('/');
        }

        print('[libsmb2] Server: $serverName');
        print('[libsmb2] Share: $shareName');
        if (basePath != null && basePath.isNotEmpty) {
          print('[libsmb2] Base path: $basePath');
        }

        final serverPtr = serverName.toNativeUtf8();
        final sharePtr = shareName.toNativeUtf8();

        try {
          // 连接到共享
          print('[libsmb2] Calling smb2_connect_share...');
          final result = _bindings.smb2_connect_share(
            _context!,
            serverPtr,
            sharePtr,
            userPtr,  // 传递用户名指针
          );

          print('[libsmb2] smb2_connect_share returned: $result');

          if (result < 0) {
            final errorPtr = _bindings.smb2_get_error(_context!);
            final errorMsg = errorPtr.toDartString();
            print('[libsmb2] Error details: $errorMsg');
            print('[libsmb2] Error code: $result');
            throw Exception('SMB connection failed: $errorMsg (error code: $result)');
          }

          _currentHost = serverName;
          _currentShare = shareName;
          _basePath = basePath;
          print('[libsmb2] Connection successful!');
          return true;
        } finally {
          malloc.free(serverPtr);
          malloc.free(sharePtr);
        }
      } finally {
        malloc.free(userPtr);
        malloc.free(passPtr);
        malloc.free(domainPtr);
      }
    } catch (e) {
      print('SMB连接失败: $e');
      if (_context != null) {
        _bindings.smb2_destroy_context(_context!);
        _context = null;
      }
      return false;
    }
  }

  // 断开连接
  Future<void> disconnect() async {
    for (final reader in _rangeReaders.toList()) { await reader.close(); }
    _rangeReaders.clear();
    // 先关闭所有打开的流式读取器
    for (var reader in _streamReaders.values) {
      await reader.close();
    }
    _streamReaders.clear();

    if (_context != null) {
      try {
        _bindings.smb2_disconnect_share(_context!);
        _bindings.smb2_destroy_context(_context!);
      } catch (e) {
        print('Error during disconnect: $e');
      } finally {
        _context = null;
        _currentHost = null;
        _currentShare = null;
        _basePath = null;
      }
    }
  }

  // 组合基础路径和请求路径
  // 例如: _basePath = "Bangumi", requestPath = "/subfolder" -> "Bangumi/subfolder"
  //      _basePath = null, requestPath = "/file.txt" -> "file.txt"
  String _combinePaths(String requestPath) {
    // 移除请求路径开头的斜杠
    String cleanRequest = requestPath;
    if (cleanRequest.startsWith('/')) {
      cleanRequest = cleanRequest.substring(1);
    }

    // 如果有基础路径，拼接
    if (_basePath != null && _basePath!.isNotEmpty) {
      if (cleanRequest.isEmpty || cleanRequest == '.') {
        return _basePath!;
      }
      return '$_basePath/$cleanRequest';
    }

    // 没有基础路径，返回清理后的请求路径
    // 空路径返回空字符串，libsmb2 会将其视为共享根目录
    return cleanRequest;
  }

  // 获取文件列表
  Future<List<Libsmb2File>> listFiles(String path) async {
    if (!isConnected) {
      throw Exception('未连接到SMB服务器');
    }

    print('[libsmb2] listFiles called with path: $path');
    print('[libsmb2] Current share: $_currentShare');
    print('[libsmb2] Base path: $_basePath');

    // 如果当前连接的是 IPC$，且用户尝试列出根目录，返回提示信息
    if (_currentShare == 'IPC\$' && (path == '/' || path.isEmpty || path == '.')) {
      print('[libsmb2] Connected to IPC\$, cannot list files. User needs to specify a share.');
      // 返回一个提示性的假条目，告诉用户需要指定共享名
      return [
        Libsmb2File(
          name: '⚠️ 请在连接地址中指定共享名',
          path: '/',
          isDirectory: false,
          size: 0,
          modifiedTime: DateTime.now(),
          createdTime: DateTime.now(),
        ),
        Libsmb2File(
          name: '例如: 192.168.x.x/share',
          path: '/',
          isDirectory: false,
          size: 0,
          modifiedTime: DateTime.now(),
          createdTime: DateTime.now(),
        ),
      ];
    }

    // 组合基础路径和请求路径
    final normalizedPath = _combinePaths(path);
    print('[libsmb2] Combined path: $normalizedPath');

    final pathPtr = normalizedPath.toNativeUtf8();
    try {
      print('[libsmb2] Calling smb2_opendir with path: $normalizedPath');
      final dir = _bindings.smb2_opendir(_context!, pathPtr);
      if (dir.address == 0) {
        final errorPtr = _bindings.smb2_get_error(_context!);
        final errorMsg = errorPtr.toDartString();
        print('[libsmb2] smb2_opendir failed: $errorMsg');
        throw Exception('Failed to open directory: $errorMsg');
      }
      print('[libsmb2] smb2_opendir successful');

      final files = <Libsmb2File>[];
      try {
        while (true) {
          final dirent = _bindings.smb2_readdir(_context!, dir);
          if (dirent.address == 0) {
            break; // 没有更多条目
          }

          final name = dirent.ref.name.toDartString();
          // 跳过 . 和 ..
          if (name == '.' || name == '..') {
            continue;
          }

          final stat = dirent.ref.st;

          // 构建文件路径 - 保持原始格式（带前导斜杠）以便与应用层兼容
          String filePath;
          if (path == '/' || path.isEmpty) {
            // 根目录：添加前导斜杠
            filePath = '/$name';
          } else if (path.endsWith('/')) {
            filePath = '$path$name';
          } else {
            filePath = '$path/$name';
          }

          print('[libsmb2] Found entry: $name (path: $filePath, isDir: ${stat.smb2_type == SMB2_TYPE_DIRECTORY})');

          final file = Libsmb2File(
            name: name,
            path: filePath,
            isDirectory: stat.smb2_type == SMB2_TYPE_DIRECTORY,
            size: stat.smb2_size,
            modifiedTime: smbStatTime(stat.smb2_mtime, stat.smb2_mtime_nsec),
            createdTime: smbStatTime(stat.smb2_btime, stat.smb2_btime_nsec),
          );
          files.add(file);
        }
      } finally {
        _bindings.smb2_closedir(_context!, dir);
      }

      return files;
    } finally {
      malloc.free(pathPtr);
    }
  }

  // 获取文件流（完整文件）
  Future<Stream<Uint8List>> getFileStream(String filePath) => getRangeStream(filePath, start: 0);

  /// 创建流式文件读取器 - 支持范围读取和视频播放
  ///
  /// 这个方法创建一个 [Libsmb2StreamReader] 实例，支持:
  /// - 范围读取 (Range Request) - 视频播放器可以跳转到任意位置
  /// - 流式传输 - 边读边播，无需下载整个文件
  /// - 并发读取 - 多个读取器可以同时读取不同文件
  ///
  /// 使用示例:
  /// ```dart
  /// final reader = await smbService.createStreamReader('/video.mp4');
  /// await reader.open();
  ///
  /// // 读取完整文件
  /// await for (var chunk in reader.readAll()) {
  ///   // 处理数据块
  /// }
  ///
  /// // 或者读取指定范围（例如视频跳转到第10MB开始播放）
  /// await for (var chunk in reader.readRange(start: 10 * 1024 * 1024)) {
  ///   // 处理数据块
  /// }
  ///
  /// await reader.close();
  /// ```
  Future<Libsmb2StreamReader> createStreamReader(String filePath) async {
    if (!isConnected || _context == null) {
      throw Exception('未连接到SMB服务器');
    }

    print('[libsmb2] createStreamReader called with path: $filePath');

    // 组合基础路径和请求路径
    final normalizedPath = _combinePaths(filePath);
    print('[libsmb2] Combined path for stream reader: $normalizedPath');

    // 创建流式读取器
    final reader = Libsmb2StreamReader(_bindings, _context!, normalizedPath);

    // 保存到管理器中
    final previous = _streamReaders[filePath];
    if (previous != null) await previous.close();
    _streamReaders[filePath] = reader;

    return reader;
  }

  /// 获取文件的范围流 - 支持视频播放和断点续传
  ///
  /// [filePath] - 文件路径
  /// [start] - 起始字节位置
  /// [end] - 结束字节位置（可选，null 表示读到文件末尾）
  /// [chunkSize] - 每次读取的块大小，默认 64KB
  ///
  /// 返回一个数据流，可以直接传给视频播放器
  Future<Stream<Uint8List>> getRangeStream(
    String filePath, {
    required int start,
    int? end,
    int chunkSize = 65536,
  }) async {
    if (!isConnected || _context == null) {
      throw Exception('未连接到SMB服务器');
    }

    print('[libsmb2] getRangeStream called: $filePath, start=$start, end=$end');

    // 组合基础路径和请求路径
    final normalizedPath = _combinePaths(filePath);

    // 创建临时的流式读取器
    final reader = Libsmb2StreamReader(_bindings, _context!, normalizedPath);

    try {
      await reader.open();
      _rangeReaders.add(reader);
      return _readAndClose(reader, start, end, chunkSize);
    } catch (e) {
      await reader.close();
      rethrow;
    }
  }

  Stream<Uint8List> _readAndClose(Libsmb2StreamReader reader, int start, int? end, int chunkSize) async* {
    try {
      yield* reader.readRange(start: start, end: end, chunkSize: chunkSize);
    } finally {
      _rangeReaders.remove(reader);
      await reader.close();
    }
  }

  /// 关闭指定的流式读取器
  Future<void> closeStreamReader(String filePath) async {
    final reader = _streamReaders.remove(filePath);
    if (reader != null) {
      await reader.close();
    }
  }

  Future<void> _readFileAsync(String filePath, StreamController<Uint8List> controller) async {
    ffi.Pointer<Smb2Fh>? fh;
    ffi.Pointer<Utf8>? pathPtr;

    try {
      print('[libsmb2] Opening file: $filePath');
      pathPtr = filePath.toNativeUtf8();
      fh = _bindings.smb2_open(_context!, pathPtr, O_RDONLY);

      if (fh.address == 0) {
        final errorPtr = _bindings.smb2_get_error(_context!);
        final errorMsg = errorPtr.toDartString();
        print('[libsmb2] Failed to open file: $errorMsg');
        controller.addError(Exception('Failed to open file: $errorMsg'));
        await controller.close();
        return;
      }
      print('[libsmb2] File opened successfully');

      // 获取文件大小
      final stat = malloc<Smb2Stat64>();
      try {
        final statResult = _bindings.smb2_fstat(_context!, fh, stat);
        if (statResult < 0) {
          print('[libsmb2] Failed to stat file, error code: $statResult');
          throw Exception('Failed to stat file');
        }

        final fileSize = stat.ref.smb2_size;
        print('[libsmb2] File size: $fileSize bytes');
        const chunkSize = 65536; // 64KB chunks
        int offset = 0;
        int chunkCount = 0;

        while (offset < fileSize) {
          final readSize = (fileSize - offset) < chunkSize
              ? (fileSize - offset).toInt()
              : chunkSize;

          final buffer = malloc<ffi.Uint8>(readSize);
          try {
            final bytesRead = _bindings.smb2_pread(
              _context!,
              fh,
              buffer,
              readSize,
              offset,
            );

            if (bytesRead < 0) {
              print('[libsmb2] Read failed at offset $offset, error code: $bytesRead');
              throw Exception('Read failed at offset $offset');
            }

            if (bytesRead == 0) {
              print('[libsmb2] EOF reached at offset $offset');
              break; // EOF
            }

            final data = Uint8List.fromList(
              buffer.asTypedList(bytesRead),
            );
            controller.add(data);
            offset += bytesRead;
            chunkCount++;

            if (offset % (chunkSize * 10) == 0) {
              print('[libsmb2] Read progress: $offset / $fileSize bytes');
            }

            // 每读取几个块就让出控制权，避免阻塞 UI 线程
            // 这样可以让 Flutter 处理其他事件（如 UI 更新）
            if (chunkCount % 5 == 0) {
              await Future.delayed(Duration.zero);
            }
          } finally {
            malloc.free(buffer);
          }
        }
        print('[libsmb2] File read complete: $offset bytes total');
      } finally {
        malloc.free(stat);
      }

      await controller.close();
    } catch (e) {
      controller.addError(e);
      await controller.close();
    } finally {
      if (fh != null && fh.address != 0) {
        _bindings.smb2_close(_context!, fh);
      }
      if (pathPtr != null) {
        malloc.free(pathPtr);
      }
    }
  }

  // 获取文件
  Future<Libsmb2File> getFile(String path) async {
    if (!isConnected) {
      throw Exception('未连接到SMB服务器');
    }

    print('[libsmb2] getFile called with path: $path');

    // 组合基础路径和请求路径
    final normalizedPath = _combinePaths(path);
    print('[libsmb2] Combined path for getFile: $normalizedPath');

    final pathPtr = normalizedPath.toNativeUtf8();
    try {
      print('[libsmb2] Opening file for stat: $normalizedPath');
      final fh = _bindings.smb2_open(_context!, pathPtr, O_RDONLY);
      if (fh.address == 0) {
        final errorPtr = _bindings.smb2_get_error(_context!);
        final errorMsg = errorPtr.toDartString();
        print('[libsmb2] Failed to open file for stat: $errorMsg');
        throw Exception('Failed to open file: $errorMsg');
      }

      try {
        final stat = malloc<Smb2Stat64>();
        try {
          final result = _bindings.smb2_fstat(_context!, fh, stat);
          if (result < 0) {
            print('[libsmb2] Failed to fstat file, error code: $result');
            throw Exception('Failed to stat file');
          }

          final fileName = normalizedPath.split('/').last;
          print('[libsmb2] getFile successful: $fileName, size: ${stat.ref.smb2_size}');
          return Libsmb2File(
            name: fileName,
            path: path,  // 保持原始路径格式
            isDirectory: stat.ref.smb2_type == SMB2_TYPE_DIRECTORY,
            size: stat.ref.smb2_size,
            modifiedTime: smbStatTime(stat.ref.smb2_mtime, stat.ref.smb2_mtime_nsec),
            createdTime: smbStatTime(stat.ref.smb2_btime, stat.ref.smb2_btime_nsec),
          );
        } finally {
          malloc.free(stat);
        }
      } finally {
        _bindings.smb2_close(_context!, fh);
      }
    } finally {
      malloc.free(pathPtr);
    }
  }

  // 资源清理
  void dispose() {
    disconnect();
  }
}
