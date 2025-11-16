// lib/services/smb_config_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/smb_server_config.dart';

class SmbConfigService {
  static const String _configsKey = 'smb_server_configs';
  static const String _activeConfigIdKey = 'active_smb_config_id';

  // 获取所有服务器配置
  Future<List<SmbServerConfig>> getAllConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    final configsJson = prefs.getString(_configsKey);

    if (configsJson == null || configsJson.isEmpty) {
      return [];
    }

    try {
      final List<dynamic> jsonList = json.decode(configsJson);
      return jsonList.map((json) => SmbServerConfig.fromJson(json)).toList();
    } catch (e) {
      print('解析配置失败: $e');
      return [];
    }
  }

  // 保存服务器配置
  Future<void> saveConfig(SmbServerConfig config) async {
    final configs = await getAllConfigs();

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
  }

  // 删除服务器配置
  Future<void> deleteConfig(String configId) async {
    final configs = await getAllConfigs();
    configs.removeWhere((c) => c.id == configId);
    await _saveAllConfigs(configs);

    // 如果删除的是当前活动配置,清除活动配置ID
    final activeId = await getActiveConfigId();
    if (activeId == configId) {
      await setActiveConfigId(null);
    }
  }

  // 更新配置的最后连接时间
  Future<void> updateLastConnected(String configId) async {
    final configs = await getAllConfigs();
    final index = configs.indexWhere((c) => c.id == configId);

    if (index >= 0) {
      configs[index] = configs[index].copyWith(
        lastConnected: DateTime.now(),
      );
      await _saveAllConfigs(configs);
    }
  }

  // 获取单个配置
  Future<SmbServerConfig?> getConfig(String configId) async {
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
  Future<SmbServerConfig?> getActiveConfig() async {
    final activeId = await getActiveConfigId();
    if (activeId == null) return null;
    return await getConfig(activeId);
  }

  // 保存所有配置
  Future<void> _saveAllConfigs(List<SmbServerConfig> configs) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = configs.map((c) => c.toJson()).toList();
    await prefs.setString(_configsKey, json.encode(jsonList));
  }

  // 清除所有配置
  Future<void> clearAllConfigs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_configsKey);
    await prefs.remove(_activeConfigIdKey);
  }
}
