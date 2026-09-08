/*
 * @Author:
 * @Date: 2025-08-17 20:21:25
 * @LastEditors: Please set LastEditors
 * @LastEditTime: 2025-12-06 22:00:00
 * @Description: SMB Service - 使用 libsmb2 FFI 实现
 */
// lib/services/smb_service.dart
// 使用 libsmb2 的实现，完全解耦 smb_connect
import 'dart:typed_data';
import '../libsmb2_service/smb_worker.dart';
import '../libsmb2_service/smb_read_session.dart';
import 'serial_executor.dart';
import 'credential_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../libsmb2_service/smb_file.dart';
import '../libsmb2_service/smb_file_adapter.dart';

class SmbService {
  // Native calls live in one dedicated worker isolate, never in the UI isolate.
  final SmbWorker _libsmb2Service;
  final SmbWorker Function() _readerFactory;
  final _lifecycle = SerialExecutor();
  SmbReadSession? _reads;
  bool _closing = false;
  SmbService()
      : _libsmb2Service = SmbWorker(),
        _readerFactory = SmbWorker.new;
  SmbService.forTesting(SmbWorker worker,
      {required SmbWorker Function() readerFactory})
      : _libsmb2Service = worker,
        _readerFactory = readerFactory;

  bool get isConnected => !_closing && _libsmb2Service.isConnected;

  // 保存登录信息
  Future<void> saveCredentials({
    required String host,
    required String username,
    required String password,
    required String domain,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await CredentialStore.write('smb_password', password);
    await prefs.remove('smb_password');
    await prefs.setString('smb_host', host);
    await prefs.setString('smb_username', username);
    await prefs.setString('smb_domain', domain);
  }

  // 获取保存的登录信息
  Future<Map<String, String>> getSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'host': prefs.getString('smb_host') ?? '',
      'username': prefs.getString('smb_username') ?? '',
      'domain': prefs.getString('smb_domain') ?? '',
      'password': await CredentialStore.migrateLegacy(
          'smb_password', prefs, 'smb_password')
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
  }) =>
      _lifecycle.run(() async {
        _closing = true;
        final previous = _reads;
        _reads = null;
        await previous?.close();
        final settings = SmbConnectionSettings(
            host: host,
            username: username,
            password: password,
            domain: domain,
            signingRequired: signingRequired,
            anonymousLogin: anonymousLogin,
            encryption: encryption);
        final connected = await settings.connect(_libsmb2Service);
        if (connected) _reads = SmbReadSession(settings, _readerFactory);
        _closing = !connected;
        return connected;
      });

  // 断开连接
  Future<void> disconnect() {
    _closing = true;
    return _lifecycle.run(() async {
      final reads = _reads;
      _reads = null;
      await Future.wait(
          [_libsmb2Service.disconnect(), if (reads != null) reads.close()]);
    });
  }

  // 获取文件列表
  Future<List<SmbFile>> listFiles(String path) async {
    final libsmb2Files = await _libsmb2Service.listFiles(path);
    // 将 Libsmb2File 转换为 SmbFile 适配器
    return libsmb2Files.map((f) => SmbFileAdapter(f)).toList();
  }

  // 获取文件流
  Future<Stream<Uint8List>> getFileStream(String filePath) async {
    return getRangeStream(filePath, start: 0);
  }

  Future<Stream<Uint8List>> getRangeStream(String path,
      {required int start, int? end}) async {
    if (start < 0 || (end != null && end < start))
      throw ArgumentError('无效的 SMB 读取范围');
    final reads = _reads;
    if (!isConnected || reads == null) throw StateError('SMB 连接已关闭');
    final worker = await reads.worker();
    if (!isConnected || !identical(reads, _reads))
      throw StateError('SMB 连接已变化');
    return worker.getRangeStream(path, start: start, end: end);
  }

  // 获取文件
  Future<SmbFile> getFile(String path) async {
    final libsmb2File = await _libsmb2Service.getFile(path);
    return SmbFileAdapter(libsmb2File);
  }

  // 获取底层的 Libsmb2Service（如果需要直接访问）
  SmbWorker get libsmb2Service => _libsmb2Service;
}
