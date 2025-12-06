// 自定义 SmbFile 类 - 不依赖 smb_connect 包
class SmbFile {
  final String name;
  final String path;
  final int size;
  final bool isExists;
  final bool _isDirectory;
  final DateTime? modifiedTime;
  final DateTime? createdTime;

  SmbFile({
    required this.name,
    required this.path,
    this.size = 0,
    this.isExists = true,
    bool isDirectory = false,
    this.modifiedTime,
    this.createdTime,
  }) : _isDirectory = isDirectory;

  bool isDirectory() => _isDirectory;

  @override
  String toString() {
    return 'SmbFile(name: $name, path: $path, size: $size, isDirectory: $_isDirectory)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SmbFile &&
        other.path == path &&
        other.name == name;
  }

  @override
  int get hashCode => path.hashCode ^ name.hashCode;
}
