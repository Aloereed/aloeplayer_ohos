// lib/services/file_service.dart
import 'dart:typed_data';
import '../libsmb2_service/smb_file.dart';
import '../libsmb2_service/smb_path.dart';
import '../libsmb2_service/smb_operation_error.dart';
import 'smb_service.dart';
import 'webdav_service.dart';
import '../models/server_config.dart';

// 统一的文件接口
abstract class FileItem {
  String get name;
  String get path;
  int get size;
  DateTime? get modified;
  bool get isDirectory;
}

// SMB文件包装器
class SmbFileItem implements FileItem {
  final SmbFile _file;

  SmbFileItem(this._file);

  @override
  String get name => _file.name;

  @override
  String get path => _file.path;

  @override
  int get size => _file.size;

  @override
  bool get isDirectory => _file.isDirectory();

  DateTime? get modified => _file.modifiedTime;

  SmbFile get smbFile => _file;
}

// WebDAV文件包装器
class WebDavFileItem implements FileItem {
  final WebDavFile _file;

  WebDavFileItem(this._file);

  @override
  String get name => _file.name;

  @override
  String get path => _file.path;

  @override
  int get size => _file.size;

  @override
  bool get isDirectory => _file.isDirectory;

  DateTime? get modified => _file.lastModified;

  WebDavFile get webdavFile => _file;
}

// 统一的文件服务接口
abstract class FileService {
  bool get isConnected;
  Future<bool> connect(ServerConfig config);
  Future<void> disconnect();
  Future<List<FileItem>> listFiles(String path);
  Future<Stream<Uint8List>> getFileStream(String filePath,
      {int? start, int? end});
  Future<FileItem?> getFile(String path);
}

bool hasKnownFileSize(FileItem file) =>
    file.size >= 0 && (file is! WebDavFileItem || file.webdavFile.sizeKnown);
String? fileEtag(FileItem file) =>
    file is WebDavFileItem ? file.webdavFile.etag : null;

Future<FileItem> resolveFileSize(FileService service, FileItem file) async {
  if (hasKnownFileSize(file)) return file;
  final resolved = await service.getFile(file.path);
  if (resolved == null || !hasKnownFileSize(resolved))
    throw StateError('无法获取 ${file.name} 的文件大小');
  return resolved;
}

/// Sources that can atomically condition the GET on previously observed
/// metadata prevent replacing a file between the stat and the read.
abstract class RevisionAwareFileService {
  Future<Stream<Uint8List>> getFileStreamForRevision(FileItem file,
      {int? start, int? end});
}

// SMB文件服务实现
class SmbFileService implements FileService {
  final SmbService _smbService;
  SmbFileService({SmbService? service}) : _smbService = service ?? SmbService();

  @override
  bool get isConnected => _smbService.isConnected;

  @override
  Future<bool> connect(ServerConfig config) async {
    if (config.type != ServerType.smb) {
      throw Exception('配置类型不是SMB');
    }

    final fullHost = smbConnectionAddress(config.host, config.initialPath);

    return await _smbService.connect(
      host: fullHost,
      username: config.username,
      password: config.password,
      domain: config.domain,
      signingRequired: config.smbSigningRequired,
      anonymousLogin: config.smbAnonymousLogin,
      encryption: config.smbEncryption,
    );
  }

  @override
  Future<void> disconnect() async {
    await _smbService.disconnect();
  }

  @override
  Future<List<FileItem>> listFiles(String path) async {
    final files = await _smbService.listFiles(path);
    return files.map((f) => SmbFileItem(f)).toList();
  }

  @override
  Future<Stream<Uint8List>> getFileStream(String filePath,
      {int? start, int? end}) async {
    return await _smbService.libsmb2Service.getRangeStream(filePath,
        start: start ?? 0, end: end == null ? null : end + 1);
  }

  @override
  Future<FileItem?> getFile(String path) async {
    try {
      final file = await _smbService.getFile(path);
      return file.isExists ? SmbFileItem(file) : null;
    } on SmbOperationError catch (error) {
      if (error.isMissing) return null;
      rethrow;
    }
  }

  // 获取底层SMB服务（用于HTTP服务）
  SmbService get smbService => _smbService;
}

// WebDAV文件服务实现
class WebDavFileService implements FileService, RevisionAwareFileService {
  final WebDavService _webdavService;
  WebDavFileService({WebDavService? service})
      : _webdavService = service ?? WebDavService();

  @override
  bool get isConnected => _webdavService.isConnected;

  @override
  Future<bool> connect(ServerConfig config) async {
    if (config.type != ServerType.webdav) {
      throw Exception('配置类型不是WebDAV');
    }

    return await _webdavService.connect(
      baseUrl: config.webdavUrl,
      username: config.username,
      password: config.password,
      probePath: config.initialPath,
    );
  }

  @override
  Future<void> disconnect() async {
    await _webdavService.disconnect();
  }

  @override
  Future<List<FileItem>> listFiles(String path) async {
    final files = await _webdavService.listFiles(path);
    return files.map((f) => WebDavFileItem(f)).toList();
  }

  @override
  Future<Stream<Uint8List>> getFileStream(String filePath,
      {int? start, int? end}) async {
    return await _webdavService.getFileStream(filePath, start: start, end: end);
  }

  @override
  Future<Stream<Uint8List>> getFileStreamForRevision(FileItem file,
          {int? start, int? end}) =>
      _webdavService.getFileStream(file.path,
          start: start,
          end: end,
          expectedEtag: fileEtag(file),
          expectedModified: file.modified);

  @override
  Future<FileItem?> getFile(String path) async {
    final file = await _webdavService.getFileInfo(path);
    return file != null ? WebDavFileItem(file) : null;
  }

  // 获取底层WebDAV服务（用于HTTP服务）
  WebDavService get webdavService => _webdavService;
}

// 文件服务工厂
class FileServiceFactory {
  static FileService createService(ServerType type) {
    switch (type) {
      case ServerType.smb:
        return SmbFileService();
      case ServerType.webdav:
        return WebDavFileService();
    }
  }
}
