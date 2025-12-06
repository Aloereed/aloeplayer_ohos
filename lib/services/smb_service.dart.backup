/*
 * @Author: 
 * @Date: 2025-08-17 20:21:25
 * @LastEditors: Please set LastEditors
 * @LastEditTime: 2025-08-17 20:24:32
 * @Description: file content
 */
// lib/services/smb_service.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:smb_connect/smb_connect.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SmbService {
  static const String _hostKey = 'smb_host';
  static const String _usernameKey = 'smb_username';
  static const String _passwordKey = 'smb_password';
  static const String _domainKey = 'smb_domain';

  SmbConnect? _connection;
  bool get isConnected => _connection != null;

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
    await prefs.setString(_passwordKey, password);
    await prefs.setString(_domainKey, domain);
  }

  // 获取保存的登录信息
  Future<Map<String, String>> getSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'host': prefs.getString(_hostKey) ?? '',
      'username': prefs.getString(_usernameKey) ?? '',
      'password': prefs.getString(_passwordKey) ?? '',
      'domain': prefs.getString(_domainKey) ?? '',
    };
  }

  // 连接SMB
  Future<bool> connect({
    required String host,
    required String username,
    required String password,
    required String domain,
  }) async {
    try {
      _connection = await SmbConnect.connectAuth(
        host: host,
        domain: domain,
        username: username,
        password: password,
      );
      return true;
    } catch (e) {
      print('SMB连接失败: $e');
      return false;
    }
  }

  // 断开连接
  Future<void> disconnect() async {
    if (_connection != null) {
      await _connection!.close();
      _connection = null;
    }
  }

  // 获取文件列表
  Future<List<SmbFile>> listFiles(String path) async {
    if (_connection == null) throw Exception('未连接到SMB服务器');
    
    try {
      SmbFile folder = await _connection!.file(path);
      return await _connection!.listFiles(folder);
    } catch (e) {
      throw Exception('获取文件列表失败: $e');
    }
  }

  // 获取文件流
  Future<Stream<Uint8List>> getFileStream(String filePath) async {
    if (_connection == null) throw Exception('未连接到SMB服务器');
    
    return await _connection!.openRead(await _connection!.file(filePath));
  }

  // 获取文件
  Future<SmbFile> getFile(String path) async {
    if (_connection == null) throw Exception('未连接到SMB服务器');
    return await _connection!.file(path);
  }
}