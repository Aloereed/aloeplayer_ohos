// FFI bindings for libsmb2.so
import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';

// libsmb2 核心函数类型定义
typedef Smb2InitContextNative = ffi.Pointer<Smb2Context> Function();
typedef Smb2InitContextDart = ffi.Pointer<Smb2Context> Function();

typedef Smb2DestroyContextNative = ffi.Void Function(ffi.Pointer<Smb2Context>);
typedef Smb2DestroyContextDart = void Function(ffi.Pointer<Smb2Context>);

typedef Smb2SetUserNative = ffi.Void Function(ffi.Pointer<Smb2Context>, ffi.Pointer<Utf8>);
typedef Smb2SetUserDart = void Function(ffi.Pointer<Smb2Context>, ffi.Pointer<Utf8>);

typedef Smb2SetPasswordNative = ffi.Void Function(ffi.Pointer<Smb2Context>, ffi.Pointer<Utf8>);
typedef Smb2SetPasswordDart = void Function(ffi.Pointer<Smb2Context>, ffi.Pointer<Utf8>);

typedef Smb2SetDomainNative = ffi.Void Function(ffi.Pointer<Smb2Context>, ffi.Pointer<Utf8>);
typedef Smb2SetDomainDart = void Function(ffi.Pointer<Smb2Context>, ffi.Pointer<Utf8>);

typedef Smb2ConnectShareNative = ffi.Int32 Function(
  ffi.Pointer<Smb2Context>,
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
);
typedef Smb2ConnectShareDart = int Function(
  ffi.Pointer<Smb2Context>,
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
);

typedef Smb2DisconnectShareNative = ffi.Int32 Function(ffi.Pointer<Smb2Context>);
typedef Smb2DisconnectShareDart = int Function(ffi.Pointer<Smb2Context>);

typedef Smb2OpendirNative = ffi.Pointer<Smb2Dir> Function(
  ffi.Pointer<Smb2Context>,
  ffi.Pointer<Utf8>,
);
typedef Smb2OpendirDart = ffi.Pointer<Smb2Dir> Function(
  ffi.Pointer<Smb2Context>,
  ffi.Pointer<Utf8>,
);

typedef Smb2ReaddirNative = ffi.Pointer<Smb2Dirent> Function(
  ffi.Pointer<Smb2Context>,
  ffi.Pointer<Smb2Dir>,
);
typedef Smb2ReaddirDart = ffi.Pointer<Smb2Dirent> Function(
  ffi.Pointer<Smb2Context>,
  ffi.Pointer<Smb2Dir>,
);

typedef Smb2ClosedirNative = ffi.Void Function(
  ffi.Pointer<Smb2Context>,
  ffi.Pointer<Smb2Dir>,
);
typedef Smb2ClosedirDart = void Function(
  ffi.Pointer<Smb2Context>,
  ffi.Pointer<Smb2Dir>,
);

typedef Smb2OpenNative = ffi.Pointer<Smb2Fh> Function(
  ffi.Pointer<Smb2Context>,
  ffi.Pointer<Utf8>,
  ffi.Int32,
);
typedef Smb2OpenDart = ffi.Pointer<Smb2Fh> Function(
  ffi.Pointer<Smb2Context>,
  ffi.Pointer<Utf8>,
  int,
);

typedef Smb2CloseNative = ffi.Int32 Function(
  ffi.Pointer<Smb2Context>,
  ffi.Pointer<Smb2Fh>,
);
typedef Smb2CloseDart = int Function(
  ffi.Pointer<Smb2Context>,
  ffi.Pointer<Smb2Fh>,
);

typedef Smb2PreadNative = ffi.Int32 Function(
  ffi.Pointer<Smb2Context>,
  ffi.Pointer<Smb2Fh>,
  ffi.Pointer<ffi.Uint8>,
  ffi.Uint32,
  ffi.Uint64,
);
typedef Smb2PreadDart = int Function(
  ffi.Pointer<Smb2Context>,
  ffi.Pointer<Smb2Fh>,
  ffi.Pointer<ffi.Uint8>,
  int,
  int,
);

typedef Smb2FstatNative = ffi.Int32 Function(
  ffi.Pointer<Smb2Context>,
  ffi.Pointer<Smb2Fh>,
  ffi.Pointer<Smb2Stat64>,
);
typedef Smb2FstatDart = int Function(
  ffi.Pointer<Smb2Context>,
  ffi.Pointer<Smb2Fh>,
  ffi.Pointer<Smb2Stat64>,
);

typedef Smb2LseekNative = ffi.Int64 Function(
  ffi.Pointer<Smb2Context>,
  ffi.Pointer<Smb2Fh>,
  ffi.Int64,
  ffi.Int32,
  ffi.Pointer<ffi.Uint64>,
);
typedef Smb2LseekDart = int Function(
  ffi.Pointer<Smb2Context>,
  ffi.Pointer<Smb2Fh>,
  int,
  int,
  ffi.Pointer<ffi.Uint64>,
);

typedef Smb2GetErrorNative = ffi.Pointer<Utf8> Function(ffi.Pointer<Smb2Context>);
typedef Smb2GetErrorDart = ffi.Pointer<Utf8> Function(ffi.Pointer<Smb2Context>);

typedef Smb2SetSecurityModeNative = ffi.Void Function(ffi.Pointer<Smb2Context>, ffi.Uint16);
typedef Smb2SetSecurityModeDart = void Function(ffi.Pointer<Smb2Context>, int);

// Opaque 类型定义
final class Smb2Context extends ffi.Opaque {}
final class Smb2Dir extends ffi.Opaque {}
final class Smb2Fh extends ffi.Opaque {}

// smb2_stat_64 结构体
final class Smb2Stat64 extends ffi.Struct {
  @ffi.Uint32()
  external int smb2_type;

  @ffi.Uint32()
  external int smb2_nlink;

  @ffi.Uint64()
  external int smb2_ino;

  @ffi.Uint64()
  external int smb2_size;

  @ffi.Uint64()
  external int smb2_atime;

  @ffi.Uint64()
  external int smb2_atime_nsec;

  @ffi.Uint64()
  external int smb2_mtime;

  @ffi.Uint64()
  external int smb2_mtime_nsec;

  @ffi.Uint64()
  external int smb2_ctime;

  @ffi.Uint64()
  external int smb2_ctime_nsec;

  @ffi.Uint64()
  external int smb2_btime;

  @ffi.Uint64()
  external int smb2_btime_nsec;
}

// smb2_dirent 结构体
final class Smb2Dirent extends ffi.Struct {
  external ffi.Pointer<Utf8> name;
  external Smb2Stat64 st;
}

// Libsmb2 绑定类
class Libsmb2Bindings {
  late final ffi.DynamicLibrary _lib;

  // 函数指针
  late final Smb2InitContextDart smb2_init_context;
  late final Smb2DestroyContextDart smb2_destroy_context;
  late final Smb2SetUserDart smb2_set_user;
  late final Smb2SetPasswordDart smb2_set_password;
  late final Smb2SetDomainDart smb2_set_domain;
  late final Smb2ConnectShareDart smb2_connect_share;
  late final Smb2DisconnectShareDart smb2_disconnect_share;
  late final Smb2OpendirDart smb2_opendir;
  late final Smb2ReaddirDart smb2_readdir;
  late final Smb2ClosedirDart smb2_closedir;
  late final Smb2OpenDart smb2_open;
  late final Smb2CloseDart smb2_close;
  late final Smb2PreadDart smb2_pread;
  late final Smb2FstatDart smb2_fstat;
  late final Smb2LseekDart smb2_lseek;
  late final Smb2GetErrorDart smb2_get_error;
  late final Smb2SetSecurityModeDart smb2_set_security_mode;

  Libsmb2Bindings() {
    // 根据平台加载不同的库
    if (Platform.isLinux || Platform.isAndroid) {
      _lib = ffi.DynamicLibrary.open('libsmb2.so');
    } else if (Platform.isMacOS) {
      _lib = ffi.DynamicLibrary.open('libsmb2.dylib');
    } else if (Platform.isWindows) {
      _lib = ffi.DynamicLibrary.open('libsmb2.dll');
    } else if (Platform.isOhos) {
      _lib = ffi.DynamicLibrary.open('/data/storage/el1/bundle/libs/arm64/libsmb2.so');
    }else {
      throw UnsupportedError('Unsupported platform');
    }

    // 绑定函数
    smb2_init_context = _lib
        .lookup<ffi.NativeFunction<Smb2InitContextNative>>('smb2_init_context')
        .asFunction();

    smb2_destroy_context = _lib
        .lookup<ffi.NativeFunction<Smb2DestroyContextNative>>('smb2_destroy_context')
        .asFunction();

    smb2_set_user = _lib
        .lookup<ffi.NativeFunction<Smb2SetUserNative>>('smb2_set_user')
        .asFunction();

    smb2_set_password = _lib
        .lookup<ffi.NativeFunction<Smb2SetPasswordNative>>('smb2_set_password')
        .asFunction();

    smb2_set_domain = _lib
        .lookup<ffi.NativeFunction<Smb2SetDomainNative>>('smb2_set_domain')
        .asFunction();

    smb2_connect_share = _lib
        .lookup<ffi.NativeFunction<Smb2ConnectShareNative>>('smb2_connect_share')
        .asFunction();

    smb2_disconnect_share = _lib
        .lookup<ffi.NativeFunction<Smb2DisconnectShareNative>>('smb2_disconnect_share')
        .asFunction();

    smb2_opendir = _lib
        .lookup<ffi.NativeFunction<Smb2OpendirNative>>('smb2_opendir')
        .asFunction();

    smb2_readdir = _lib
        .lookup<ffi.NativeFunction<Smb2ReaddirNative>>('smb2_readdir')
        .asFunction();

    smb2_closedir = _lib
        .lookup<ffi.NativeFunction<Smb2ClosedirNative>>('smb2_closedir')
        .asFunction();

    smb2_open = _lib
        .lookup<ffi.NativeFunction<Smb2OpenNative>>('smb2_open')
        .asFunction();

    smb2_close = _lib
        .lookup<ffi.NativeFunction<Smb2CloseNative>>('smb2_close')
        .asFunction();

    smb2_pread = _lib
        .lookup<ffi.NativeFunction<Smb2PreadNative>>('smb2_pread')
        .asFunction();

    smb2_fstat = _lib
        .lookup<ffi.NativeFunction<Smb2FstatNative>>('smb2_fstat')
        .asFunction();

    smb2_lseek = _lib
        .lookup<ffi.NativeFunction<Smb2LseekNative>>('smb2_lseek')
        .asFunction();

    smb2_get_error = _lib
        .lookup<ffi.NativeFunction<Smb2GetErrorNative>>('smb2_get_error')
        .asFunction();

    smb2_set_security_mode = _lib
        .lookup<ffi.NativeFunction<Smb2SetSecurityModeNative>>('smb2_set_security_mode')
        .asFunction();
  }
}

// 常量定义
const int SMB2_TYPE_FILE = 0x00000000;
const int SMB2_TYPE_DIRECTORY = 0x00000001;
const int SMB2_TYPE_LINK = 0x00000002;

// Security mode flags
const int SMB2_NEGOTIATE_SIGNING_ENABLED = 0x0001;
const int SMB2_NEGOTIATE_SIGNING_REQUIRED = 0x0002;

// Open flags (from fcntl.h)
const int O_RDONLY = 0x0000;
const int O_WRONLY = 0x0001;
const int O_RDWR = 0x0002;

// Seek whence values
const int SEEK_SET = 0;
const int SEEK_CUR = 1;
const int SEEK_END = 2;
