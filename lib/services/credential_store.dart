import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Never falls back to plaintext when the platform keystore is unavailable.
class CredentialStore {
  static const _channel = MethodChannel('aloeplayer/credentials');
  static const _storage = FlutterSecureStorage();
  static Future<void> write(String key, String value) async {
    if (Platform.operatingSystem == 'ohos') {
      await _channel.invokeMethod<void>('write', {'key': key, 'value': value});
    } else {
      await _storage.write(key: key, value: value);
    }
  }

  static Future<String?> read(String key) async {
    if (Platform.operatingSystem == 'ohos') {
      return _channel.invokeMethod<String>('read', {'key': key});
    }
    return _storage.read(key: key);
  }

  static Future<void> delete(String key) async {
    if (Platform.operatingSystem == 'ohos') {
      await _channel.invokeMethod<void>('delete', {'key': key});
    } else {
      await _storage.delete(key: key);
    }
  }

  static Future<String> migrateLegacy(String key, SharedPreferences prefs, String legacyKey) async {
    final legacy = prefs.getString(legacyKey);
    if (legacy != null) {
      await write(key, legacy);
      await prefs.remove(legacyKey);
      return legacy;
    }
    return await read(key) ?? '';
  }
}
