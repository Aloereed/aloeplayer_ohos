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
import '../libsmb2_service/libsmb2_service.dart';
import '../libsmb2_service/smb_file.dart';
import '../libsmb2_service/smb_file_adapter.dart';

class SmbService {
  // 使用 Libsmb2Service 作为底层实现
  final Libsmb2Service _libsmb2Service = Libsmb2Service();

  bool get isConnected => _libsmb2Service.isConnected;

  // 保存登录信息
  Future<void> saveCredentials({
    required String host,
    required String username,
    required String password,
    required String domain,
  }) async {
    await _libsmb2Service.saveCredentials(
      host: host,
      username: username,
      password: password,
      domain: domain,
    );
  }

  // 获取保存的登录信息
  Future<Map<String, String>> getSavedCredentials() async {
    return await _libsmb2Service.getSavedCredentials();
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
    return await _libsmb2Service.connect(
      host: host,
      username: username,
      password: password,
      domain: domain,
      signingRequired: signingRequired,
      anonymousLogin: anonymousLogin,
      encryption: encryption,
    );
  }

  // 断开连接
  Future<void> disconnect() async {
    await _libsmb2Service.disconnect();
  }

  // 获取文件列表
  Future<List<SmbFile>> listFiles(String path) async {
    final libsmb2Files = await _libsmb2Service.listFiles(path);
    // 将 Libsmb2File 转换为 SmbFile 适配器
    return libsmb2Files.map((f) => SmbFileAdapter(f)).toList();
  }

  // 获取文件流
  Future<Stream<Uint8List>> getFileStream(String filePath) async {
    return await _libsmb2Service.getFileStream(filePath);
  }

  // 获取文件
  Future<SmbFile> getFile(String path) async {
    final libsmb2File = await _libsmb2Service.getFile(path);
    return SmbFileAdapter(libsmb2File);
  }

  // 获取底层的 Libsmb2Service（如果需要直接访问）
  Libsmb2Service get libsmb2Service => _libsmb2Service;
}