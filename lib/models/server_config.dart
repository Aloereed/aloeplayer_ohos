// lib/models/server_config.dart
import 'dart:convert';

enum ServerType {
  smb,
  webdav,
}

class ServerConfig {
  final String id;
  final String name;
  final ServerType type;
  final String host;
  final String username;
  final String password;
  final String domain; // SMB only
  final String initialPath;
  final DateTime createdAt;
  final DateTime? lastConnected;
  final int? port; // WebDAV端口 (默认80/443)
  final bool useHttps; // WebDAV是否使用HTTPS

  ServerConfig({
    required this.id,
    required this.name,
    required this.type,
    required this.host,
    required this.username,
    required this.password,
    this.domain = '',
    this.initialPath = '/',
    required this.createdAt,
    this.lastConnected,
    this.port,
    this.useHttps = false,
  });

  // 从JSON创建
  factory ServerConfig.fromJson(Map<String, dynamic> json) {
    return ServerConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      type: ServerType.values.firstWhere(
        (e) => e.toString() == 'ServerType.${json['type']}',
        orElse: () => ServerType.smb,
      ),
      host: json['host'] as String,
      username: json['username'] as String,
      password: json['password'] as String,
      domain: json['domain'] as String? ?? '',
      initialPath: json['initialPath'] as String? ?? '/',
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastConnected: json['lastConnected'] != null
          ? DateTime.parse(json['lastConnected'] as String)
          : null,
      port: json['port'] as int?,
      useHttps: json['useHttps'] as bool? ?? false,
    );
  }

  // 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.toString().split('.').last,
      'host': host,
      'username': username,
      'password': password,
      'domain': domain,
      'initialPath': initialPath,
      'createdAt': createdAt.toIso8601String(),
      'lastConnected': lastConnected?.toIso8601String(),
      'port': port,
      'useHttps': useHttps,
    };
  }

  // 复制并更新
  ServerConfig copyWith({
    String? id,
    String? name,
    ServerType? type,
    String? host,
    String? username,
    String? password,
    String? domain,
    String? initialPath,
    DateTime? createdAt,
    DateTime? lastConnected,
    int? port,
    bool? useHttps,
  }) {
    return ServerConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      host: host ?? this.host,
      username: username ?? this.username,
      password: password ?? this.password,
      domain: domain ?? this.domain,
      initialPath: initialPath ?? this.initialPath,
      createdAt: createdAt ?? this.createdAt,
      lastConnected: lastConnected ?? this.lastConnected,
      port: port ?? this.port,
      useHttps: useHttps ?? this.useHttps,
    );
  }

  // 获取WebDAV的完整URL
  String get webdavUrl {
    if (type != ServerType.webdav) return '';
    final scheme = useHttps ? 'https' : 'http';
    final actualPort = port ?? (useHttps ? 443 : 80);
    final portStr = (useHttps && actualPort == 443) || (!useHttps && actualPort == 80)
        ? ''
        : ':$actualPort';
    return '$scheme://$host$portStr';
  }

  @override
  String toString() {
    return 'ServerConfig(name: $name, type: $type, host: $host)';
  }
}
