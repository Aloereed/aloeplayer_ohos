// lib/models/smb_server_config.dart
import 'dart:convert';

class SmbServerConfig {
  final String id;
  final String name;
  final String host;
  final String username;
  final String password;
  final String domain;
  final String initialPath;
  final DateTime createdAt;
  final DateTime? lastConnected;

  SmbServerConfig({
    required this.id,
    required this.name,
    required this.host,
    required this.username,
    required this.password,
    this.domain = '',
    this.initialPath = '/',
    required this.createdAt,
    this.lastConnected,
  });

  // 从JSON创建
  factory SmbServerConfig.fromJson(Map<String, dynamic> json) {
    return SmbServerConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      host: json['host'] as String,
      username: json['username'] as String,
      password: json['password'] as String,
      domain: json['domain'] as String? ?? '',
      initialPath: json['initialPath'] as String? ?? '/',
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastConnected: json['lastConnected'] != null
          ? DateTime.parse(json['lastConnected'] as String)
          : null,
    );
  }

  // 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'username': username,
      'password': password,
      'domain': domain,
      'initialPath': initialPath,
      'createdAt': createdAt.toIso8601String(),
      'lastConnected': lastConnected?.toIso8601String(),
    };
  }

  // 复制并更新
  SmbServerConfig copyWith({
    String? id,
    String? name,
    String? host,
    String? username,
    String? password,
    String? domain,
    String? initialPath,
    DateTime? createdAt,
    DateTime? lastConnected,
  }) {
    return SmbServerConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      username: username ?? this.username,
      password: password ?? this.password,
      domain: domain ?? this.domain,
      initialPath: initialPath ?? this.initialPath,
      createdAt: createdAt ?? this.createdAt,
      lastConnected: lastConnected ?? this.lastConnected,
    );
  }

  @override
  String toString() {
    return 'SmbServerConfig(name: $name, host: $host)';
  }
}
