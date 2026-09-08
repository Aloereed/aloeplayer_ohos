import 'smb_path.dart';
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

  final Libsmb2Bindings _bindings;
  Libsmb2Service({Libsmb2Bindings? bindings})
      : _bindings = bindings ?? Libsmb2Bindings();
  ffi.Pointer<Smb2Context>? _context;
  String? _currentHost;
  String? _currentShare;
  bool _serverRoot = false;
  Map<String, dynamic>? _options;
  final Map<String, Libsmb2Service> _shares = {};
  String? _basePath; // 连接时指定的基础路径（share之后的路径部分）

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
      'password': await CredentialStore.migrateLegacy(
          _passwordKey, prefs, _passwordKey),
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
      if (_context != null || _shares.isNotEmpty) await disconnect();
      final address = SmbAddress.parse(host);
      _serverRoot = address.share == null;
      _options = {
        'username': username,
        'password': password,
        'domain': domain,
        'signingRequired': signingRequired,
        'anonymousLogin': anonymousLogin,
        'encryption': encryption
      };

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
          securityMode =
              SMB2_NEGOTIATE_SIGNING_ENABLED | SMB2_NEGOTIATE_SIGNING_REQUIRED;
          print('[libsmb2] Security mode set to SIGNING_REQUIRED');
        } else {
          securityMode = SMB2_NEGOTIATE_SIGNING_ENABLED;
          print('[libsmb2] Security mode set to SIGNING_ENABLED');
        }
        _bindings.smb2_set_security_mode(_context!, securityMode);

        _bindings.smb2_set_sign(_context!, signingRequired ? 1 : 0);
        _bindings.smb2_set_seal(_context!, encryption ? 1 : 0);
        _bindings.smb2_set_timeout(_context!, 30);

        final serverName = address.server;
        final shareName = address.share ?? 'IPC\$';
        final basePath = address.basePath;

        final serverPtr = serverName.toNativeUtf8();
        final sharePtr = shareName.toNativeUtf8();

        try {
          // 连接到共享
          print('[libsmb2] Calling smb2_connect_share...');
          final result = _bindings.connectShare(
            _context!,
            serverPtr,
            sharePtr,
            userPtr, // 传递用户名指针
            () {
              _bindings.smb2_destroy_context(_context!);
              _context = null;
            },
          );

          print('[libsmb2] smb2_connect_share returned: $result');

          if (result != 0) {
            final errorPtr = _bindings.smb2_get_error(_context!);
            final errorMsg = errorPtr.toDartString();
            print('[libsmb2] Error details: $errorMsg');
            print('[libsmb2] Error code: $result');
            throw Exception(
                'SMB connection failed: $errorMsg (error code: $result)');
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
      _options = null;
      rethrow;
    }
  }

  // 断开连接
  Future<void> disconnect() async {
    for (final service in _shares.values) {
      await service.disconnect();
    }
    _shares.clear();
    _options = null;
    for (final reader in _rangeReaders.toList()) {
      await reader.close();
    }
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
    final relative = smbPathSegments(requestPath).join('/');
    return [
      if (_basePath?.isNotEmpty == true) _basePath!,
      if (relative.isNotEmpty) relative
    ].join('/');
  }

  Future<Libsmb2Service> _shareService(String share) async {
    final existing = _shares.remove(share);
    if (existing != null) {
      _shares[share] = existing;
      return existing;
    }
    // Evict only idle connections. Active playback/download streams keep their
    // own context even when the browser enters another share.
    if (_shares.length >= 8) {
      final idle = _shares.entries
          .where((entry) =>
              entry.value._rangeReaders.isEmpty &&
              entry.value._streamReaders.isEmpty)
          .firstOrNull;
      if (idle != null) {
        _shares.remove(idle.key);
        await idle.value.disconnect();
      } else {
        throw StateError('正在使用的 SMB 共享过多，请停止部分播放或下载后重试');
      }
    }
    final options = _options!;
    final service = Libsmb2Service(bindings: _bindings);
    await service.connect(
        host: '//$_currentHost/$share',
        username: options['username'],
        password: options['password'],
        domain: options['domain'],
        signingRequired: options['signingRequired'],
        anonymousLogin: options['anonymousLogin'],
        encryption: options['encryption']);
    _shares[share] = service;
    return service;
  }

  Libsmb2File _withPath(Libsmb2File file, String path) => Libsmb2File(
      name: file.name,
      path: path,
      isDirectory: file.isDirectory,
      size: file.size,
      modifiedTime: file.modifiedTime,
      createdTime: file.createdTime);

  // 获取文件列表
  Future<List<Libsmb2File>> listFiles(String path) async {
    if (!isConnected) {
      throw Exception('未连接到SMB服务器');
    }

    print('[libsmb2] listFiles called with path: $path');
    print('[libsmb2] Current share: $_currentShare');
    print('[libsmb2] Base path: $_basePath');

    path = smbCanonicalPath(path);
    if (_serverRoot) {
      final parts = smbPathSegments(path);
      if (parts.isEmpty) {
        final names = _bindings.listShares(_context!, () {
          _bindings.smb2_destroy_context(_context!);
          _context = null;
        });
        return names
            .map((name) => Libsmb2File(
                name: name, path: '/$name', isDirectory: true, size: 0))
            .toList();
      }
      final service = await _shareService(parts.first);
      final files = await service.listFiles('/${parts.skip(1).join('/')}');
      return files
          .map((file) => _withPath(file, '/${parts.first}${file.path}'))
          .toList();
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
  Future<Stream<Uint8List>> getFileStream(String filePath) =>
      getRangeStream(filePath, start: 0);

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

    if (_serverRoot) {
      final parts = smbPathSegments(filePath);
      if (parts.length < 2) throw StateError('请选择共享中的文件');
      return (await _shareService(parts.first))
          .createStreamReader('/${parts.skip(1).join('/')}');
    }

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
  /// [chunkSize] - 读取块上限，默认 1 MiB，实际不超过服务器协商值
  ///
  /// 返回一个数据流，可以直接传给视频播放器
  Future<Stream<Uint8List>> getRangeStream(
    String filePath, {
    required int start,
    int? end,
    int chunkSize = 1024 * 1024,
  }) async {
    if (!isConnected || _context == null) {
      throw Exception('未连接到SMB服务器');
    }

    if (_serverRoot) {
      final parts = smbPathSegments(filePath);
      if (parts.length < 2) throw StateError('请选择共享中的文件');
      return (await _shareService(parts.first)).getRangeStream(
          '/${parts.skip(1).join('/')}',
          start: start,
          end: end,
          chunkSize: chunkSize);
    }

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

  Stream<Uint8List> _readAndClose(
      Libsmb2StreamReader reader, int start, int? end, int chunkSize) async* {
    try {
      yield* reader.readRange(start: start, end: end, chunkSize: chunkSize);
    } finally {
      _rangeReaders.remove(reader);
      await reader.close();
    }
  }

  /// 关闭指定的流式读取器
  Future<void> closeStreamReader(String filePath) async {
    if (_serverRoot) {
      final parts = smbPathSegments(filePath);
      if (parts.isNotEmpty)
        await _shares[parts.first]
            ?.closeStreamReader('/${parts.skip(1).join('/')}');
      return;
    }
    final reader = _streamReaders.remove(filePath);
    if (reader != null) {
      await reader.close();
    }
  }

  // 获取文件
  Future<Libsmb2File> getFile(String path) async {
    if (!isConnected) {
      throw Exception('未连接到SMB服务器');
    }

    path = smbCanonicalPath(path);
    if (_serverRoot) {
      final parts = smbPathSegments(path);
      if (parts.isEmpty)
        return Libsmb2File(
            name: _currentHost!, path: '/', isDirectory: true, size: 0);
      final file = await (await _shareService(parts.first))
          .getFile('/${parts.skip(1).join('/')}');
      return _withPath(file, path);
    }
    final normalizedPath = _combinePaths(path);
    final pathPtr = normalizedPath.toNativeUtf8();
    final stat = calloc<Smb2Stat64>();
    try {
      final result = _bindings.smb2_stat(_context!, pathPtr, stat);
      if (result < 0)
        throw StateError(
            '无法读取 SMB 文件信息：${_bindings.smb2_get_error(_context!).toDartString()}（$result）');
      return Libsmb2File(
          name: smbPathSegments(path).lastOrNull ?? _currentShare!,
          path: path,
          isDirectory: stat.ref.smb2_type == SMB2_TYPE_DIRECTORY,
          size: stat.ref.smb2_size,
          modifiedTime:
              smbStatTime(stat.ref.smb2_mtime, stat.ref.smb2_mtime_nsec),
          createdTime:
              smbStatTime(stat.ref.smb2_btime, stat.ref.smb2_btime_nsec));
    } finally {
      calloc.free(stat);
      malloc.free(pathPtr);
    }
  }

  // 资源清理
  void dispose() {
    disconnect();
  }
}
