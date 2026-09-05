import 'serial_executor.dart';
import 'credential_store.dart';
// lib/services/server_config_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/server_config.dart';

class ServerConfigService {
  static final _serial = SerialExecutor();
  static const String _configsKey = 'server_configs';
  static const String _activeConfigIdKey = 'active_server_config_id';

  // 获取所有服务器配置
  Future<List<ServerConfig>> getAllConfigs() => _serial.run(_readAllConfigs);

  Future<List<ServerConfig>> _readAllConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    final configsJson = prefs.getString(_configsKey);

    if (configsJson == null || configsJson.isEmpty) {
      return [];
    }

    try {
      final List<dynamic> jsonList = json.decode(configsJson);
      final configs = <ServerConfig>[];
      bool migrated = false;
      for (final raw in jsonList) {
        final data = Map<String, dynamic>.from(raw as Map);
        final key = '$_configsKey.${data['id']}';
        if (data.containsKey('password')) {
          await CredentialStore.write(key, data['password'] as String? ?? '');
          migrated = true;
        } else {
          data['password'] = await CredentialStore.read(key) ?? '';
        }
        configs.add(ServerConfig.fromJson(data));
      }
      if (migrated) {
        final sanitized = configs.map((c) => c.toJson()..remove('password')).toList();
        await prefs.setString(_configsKey, json.encode(sanitized));
      }
      return configs;
    } catch (e) {
      // Preserve the saved list on a keystore or decoding failure.
      rethrow;
    }
  }

  // 保存服务器配置
  Future<void> saveConfig(ServerConfig config) => _serial.run(() async {
    final configs = await _readAllConfigs();

    // 检查是否已存在相同ID的配置
    final existingIndex = configs.indexWhere((c) => c.id == config.id);

    if (existingIndex >= 0) {
      // 更新现有配置
      configs[existingIndex] = config;
    } else {
      // 添加新配置
      configs.add(config);
    }

    await _saveAllConfigs(configs);
  });

  // 删除服务器配置
  Future<void> deleteConfig(String configId) => _serial.run(() async {
    final configs = await _readAllConfigs();
    configs.removeWhere((c) => c.id == configId);
    await _saveAllConfigs(configs);
    await CredentialStore.delete('$_configsKey.$configId');

    // 如果删除的是当前活动配置,清除活动配置ID
    final activeId = await getActiveConfigId();
    if (activeId == configId) {
      await setActiveConfigId(null);
    }
  });

  // 更新配置的最后连接时间
  Future<void> updateLastConnected(String configId) => _serial.run(() async {
    final configs = await _readAllConfigs();
    final index = configs.indexWhere((c) => c.id == configId);

    if (index >= 0) {
      configs[index] = configs[index].copyWith(
        lastConnected: DateTime.now(),
      );
      await _saveAllConfigs(configs);
    }
  });

  // 获取单个配置
  Future<ServerConfig?> getConfig(String configId) async {
    final configs = await getAllConfigs();
    try {
      return configs.firstWhere((c) => c.id == configId);
    } catch (e) {
      return null;
    }
  }

  // 设置活动配置ID
  Future<void> setActiveConfigId(String? configId) async {
    final prefs = await SharedPreferences.getInstance();
    if (configId == null) {
      await prefs.remove(_activeConfigIdKey);
    } else {
      await prefs.setString(_activeConfigIdKey, configId);
    }
  }

  // 获取活动配置ID
  Future<String?> getActiveConfigId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeConfigIdKey);
  }

  // 获取活动配置
  Future<ServerConfig?> getActiveConfig() async {
    final activeId = await getActiveConfigId();
    if (activeId == null) return null;
    return await getConfig(activeId);
  }

  // 保存所有配置
  Future<void> _saveAllConfigs(List<ServerConfig> configs) async {
    final prefs = await SharedPreferences.getInstance();
    for (final config in configs) {
      await CredentialStore.write('$_configsKey.${config.id}', config.password);
    }
    final jsonList = configs.map((c) => c.toJson()..remove('password')).toList();
    await prefs.setString(_configsKey, json.encode(jsonList));
  }

  // 清除所有配置
  Future<void> clearAllConfigs() => _serial.run(() async {
    for (final config in await _readAllConfigs()) {
      await CredentialStore.delete('$_configsKey.${config.id}');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_configsKey);
    await prefs.remove(_activeConfigIdKey);
  });
}
