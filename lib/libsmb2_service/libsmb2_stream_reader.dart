// Libsmb2 流式文件读取器 - 支持范围请求和视频播放
import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'libsmb2_bindings.dart';

/// SMB 文件流式读取器
///
/// 支持:
/// - 范围读取 (Range Request) - 用于视频播放器跳转
/// - 流式传输 - 边读边传，避免内存占用过大
/// - 并发读取 - 支持多个读取器同时工作
class Libsmb2StreamReader {
  final Libsmb2Bindings _bindings;
  final ffi.Pointer<Smb2Context> _context;
  final String _filePath;

  ffi.Pointer<Smb2Fh>? _fileHandle;
  int _fileSize = 0;
  int _currentOffset = 0;
  bool _isOpen = false;

  Libsmb2StreamReader(this._bindings, this._context, this._filePath);

  /// 打开文件并获取文件大小
  Future<void> open() async {
    if (_isOpen) {
      return;
    }

    final pathPtr = _filePath.toNativeUtf8();
    try {
      print('[Libsmb2StreamReader] Opening file: $_filePath');
      _fileHandle = _bindings.smb2_open(_context, pathPtr, O_RDONLY);

      if (_fileHandle == null || _fileHandle!.address == 0) {
        final errorPtr = _bindings.smb2_get_error(_context);
        final errorMsg = errorPtr.toDartString();
        throw Exception('Failed to open file: $errorMsg');
      }

      // 获取文件大小
      final stat = malloc<Smb2Stat64>();
      try {
        final statResult = _bindings.smb2_fstat(_context, _fileHandle!, stat);
        if (statResult < 0) {
          throw Exception('Failed to stat file, error code: $statResult');
        }
        _fileSize = stat.ref.smb2_size;
        print('[Libsmb2StreamReader] File opened, size: $_fileSize bytes');
      } finally {
        malloc.free(stat);
      }

      _isOpen = true;
      _currentOffset = 0;
    } finally {
      malloc.free(pathPtr);
    }
  }

  /// 获取文件大小
  int get fileSize => _fileSize;

  /// 获取当前偏移位置
  int get currentOffset => _currentOffset;

  /// 是否已打开
  bool get isOpen => _isOpen;

  /// 移动文件指针到指定位置
  Future<int> seek(int offset, {int whence = SEEK_SET}) async {
    if (!_isOpen || _fileHandle == null) {
      throw Exception('File not opened');
    }

    final currentOffsetPtr = malloc<ffi.Uint64>();
    try {
      final result = _bindings.smb2_lseek(
        _context,
        _fileHandle!,
        offset,
        whence,
        currentOffsetPtr,
      );

      if (result < 0) {
        final errorPtr = _bindings.smb2_get_error(_context);
        final errorMsg = errorPtr.toDartString();
        throw Exception('Seek failed: $errorMsg (error code: $result)');
      }

      _currentOffset = currentOffsetPtr.value;
      return _currentOffset;
    } finally {
      malloc.free(currentOffsetPtr);
    }
  }

  /// 读取指定范围的数据流
  ///
  /// [start] - 起始位置（字节偏移）
  /// [end] - 结束位置（字节偏移，可选，null 表示读到文件末尾）
  /// [chunkSize] - 每次读取的块大小，默认 64KB
  Stream<Uint8List> readRange({
    required int start,
    int? end,
    int chunkSize = 65536,
  }) async* {
    if (!_isOpen || _fileHandle == null) {
      throw Exception('File not opened');
    }

    final actualEnd = end ?? _fileSize;

    if (start < 0 || start >= _fileSize) {
      throw Exception('Invalid start offset: $start');
    }

    if (actualEnd > _fileSize) {
      throw Exception('End offset exceeds file size: $actualEnd > $_fileSize');
    }

    if (start >= actualEnd) {
      print('[Libsmb2StreamReader] Start >= End, nothing to read');
      return;
    }

    print('[Libsmb2StreamReader] Reading range: $start - $actualEnd (${actualEnd - start} bytes)');

    int offset = start;
    int totalBytesToRead = actualEnd - start;
    int totalBytesRead = 0;

    while (offset < actualEnd) {
      final readSize = (actualEnd - offset) < chunkSize
          ? (actualEnd - offset).toInt()
          : chunkSize;

      final buffer = malloc<ffi.Uint8>(readSize);
      try {
        final bytesRead = _bindings.smb2_pread(
          _context,
          _fileHandle!,
          buffer,
          readSize,
          offset,
        );

        if (bytesRead < 0) {
          final errorPtr = _bindings.smb2_get_error(_context);
          final errorMsg = errorPtr.toDartString();
          throw Exception('Read failed at offset $offset: $errorMsg');
        }

        if (bytesRead == 0) {
          print('[Libsmb2StreamReader] EOF reached at offset $offset');
          break;
        }

        final data = Uint8List.fromList(buffer.asTypedList(bytesRead));
        yield data;

        offset += bytesRead;
        totalBytesRead += bytesRead;
        _currentOffset = offset;

        // 每读取一定量数据后让出控制权，避免阻塞
        if (totalBytesRead % (chunkSize * 5) == 0) {
          await Future.delayed(Duration.zero);
        }
      } finally {
        malloc.free(buffer);
      }
    }

    print('[Libsmb2StreamReader] Range read complete: $totalBytesRead / $totalBytesToRead bytes');
  }

  /// 读取整个文件的数据流
  Stream<Uint8List> readAll({int chunkSize = 65536}) {
    return readRange(start: 0, end: _fileSize, chunkSize: chunkSize);
  }

  /// 从当前位置读取指定长度的数据
  Future<Uint8List?> read(int length) async {
    if (!_isOpen || _fileHandle == null) {
      throw Exception('File not opened');
    }

    if (_currentOffset >= _fileSize) {
      return null; // EOF
    }

    final actualLength = (_currentOffset + length > _fileSize)
        ? (_fileSize - _currentOffset).toInt()
        : length;

    final buffer = malloc<ffi.Uint8>(actualLength);
    try {
      final bytesRead = _bindings.smb2_pread(
        _context,
        _fileHandle!,
        buffer,
        actualLength,
        _currentOffset,
      );

      if (bytesRead < 0) {
        final errorPtr = _bindings.smb2_get_error(_context);
        final errorMsg = errorPtr.toDartString();
        throw Exception('Read failed: $errorMsg');
      }

      if (bytesRead == 0) {
        return null; // EOF
      }

      _currentOffset += bytesRead;
      return Uint8List.fromList(buffer.asTypedList(bytesRead));
    } finally {
      malloc.free(buffer);
    }
  }

  /// 关闭文件
  Future<void> close() async {
    if (_isOpen && _fileHandle != null && _fileHandle!.address != 0) {
      try {
        _bindings.smb2_close(_context, _fileHandle!);
        print('[Libsmb2StreamReader] File closed');
      } catch (e) {
        print('[Libsmb2StreamReader] Error closing file: $e');
      } finally {
        _fileHandle = null;
        _isOpen = false;
        _currentOffset = 0;
      }
    }
  }

  /// 资源清理
  void dispose() {
    close();
  }
}
