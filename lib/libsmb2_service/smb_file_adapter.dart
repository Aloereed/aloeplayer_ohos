// SmbFile 适配器 - 让 Libsmb2File 兼容 SmbFile 接口
import 'smb_file.dart';
import 'libsmb2_file.dart';

/// 适配器类：将 Libsmb2File 包装成 SmbFile 接口
class SmbFileAdapter extends SmbFile {
  final Libsmb2File _libsmb2File;

  SmbFileAdapter(this._libsmb2File)
      : super(
          name: _libsmb2File.name,
          path: _libsmb2File.path,
          size: _libsmb2File.size,
          isExists: true,
          isDirectory: _libsmb2File.isDirectory,
          modifiedTime: _libsmb2File.modifiedTime,
          createdTime: _libsmb2File.createdTime,
        );

  // 获取底层的 Libsmb2File 对象
  Libsmb2File get libsmb2File => _libsmb2File;
}
