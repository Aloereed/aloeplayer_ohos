// Libsmb2File - 文件信息类，兼容 SmbFile 接口
class Libsmb2File {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime? modifiedTime;
  final DateTime? createdTime;

  Libsmb2File({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size = 0,
    this.modifiedTime,
    this.createdTime,
  });

  @override
  String toString() {
    return 'Libsmb2File(name: $name, path: $path, isDirectory: $isDirectory, size: $size)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Libsmb2File &&
        other.path == path &&
        other.isDirectory == isDirectory;
  }

  @override
  int get hashCode => path.hashCode ^ isDirectory.hashCode;
}
