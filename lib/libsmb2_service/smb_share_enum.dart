import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'libsmb2_bindings.dart';

// Layouts follow the bundled libsmb2-dcerpc[-srvsvc].h (native alignment).
final class DcerpcString extends ffi.Struct {
  @ffi.Uint32()
  external int maxCount;
  @ffi.Uint32()
  external int offset;
  @ffi.Uint32()
  external int actualCount;
  external ffi.Pointer<ffi.Void> utf16;
  external ffi.Pointer<Utf8> utf8;
}

final class ShareInfo1 extends ffi.Struct {
  external DcerpcString name;
  @ffi.Uint32()
  external int type;
  external DcerpcString remark;
}

final class ShareArray extends ffi.Struct {
  @ffi.Uint32()
  external int maxCount;
  external ffi.Pointer<ShareInfo1> entries;
}

final class ShareContainer extends ffi.Struct {
  @ffi.Uint32()
  external int count;
  external ffi.Pointer<ShareArray> buffer;
}

final class ShareUnion extends ffi.Struct {
  @ffi.Uint32()
  external int level;
  external ShareContainer container;
}

final class ShareEnumStruct extends ffi.Struct {
  @ffi.Uint32()
  external int level;
  external ShareUnion info;
}

final class ShareEnumReply extends ffi.Struct {
  @ffi.Uint32()
  external int status;
  external ShareEnumStruct shares;
  @ffi.Uint32()
  external int total;
  @ffi.Uint32()
  external int resume;
}

final class SmbPollFd extends ffi.Struct {
  @ffi.Int32()
  external int fd;
  @ffi.Int16()
  external int events;
  @ffi.Int16()
  external int revents;
}

final class SmbWindowsPollFd extends ffi.Struct {
  @ffi.UintPtr()
  external int fd;
  @ffi.Int16()
  external int events;
  @ffi.Int16()
  external int revents;
}

typedef WindowsFdNative = ffi.UintPtr Function(ffi.Pointer<Smb2Context>);
typedef WindowsPollNative = ffi.Int32 Function(
    ffi.Pointer<SmbWindowsPollFd>, ffi.Uint32, ffi.Int32);
typedef WindowsPollDart = int Function(ffi.Pointer<SmbWindowsPollFd>, int, int);

typedef ShareCallback = ffi.Void Function(ffi.Pointer<Smb2Context>, ffi.Int32,
    ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Void>);
typedef EnumNative = ffi.Int32 Function(ffi.Pointer<Smb2Context>, ffi.Int32,
    ffi.Pointer<ffi.NativeFunction<ShareCallback>>, ffi.Pointer<ffi.Void>);
typedef EnumDart = int Function(ffi.Pointer<Smb2Context>, int,
    ffi.Pointer<ffi.NativeFunction<ShareCallback>>, ffi.Pointer<ffi.Void>);
typedef ContextIntNative = ffi.Int32 Function(ffi.Pointer<Smb2Context>);
typedef ContextIntDart = int Function(ffi.Pointer<Smb2Context>);
typedef ServiceNative = ffi.Int32 Function(ffi.Pointer<Smb2Context>, ffi.Int32);
typedef ServiceDart = int Function(ffi.Pointer<Smb2Context>, int);
typedef FreeNative = ffi.Void Function(
    ffi.Pointer<Smb2Context>, ffi.Pointer<ffi.Void>);
typedef FreeDart = void Function(
    ffi.Pointer<Smb2Context>, ffi.Pointer<ffi.Void>);
typedef PollNative = ffi.Int32 Function(
    ffi.Pointer<SmbPollFd>, ffi.UnsignedLong, ffi.Int32);
typedef PollDart = int Function(ffi.Pointer<SmbPollFd>, int, int);

/// Must run on the SMB worker. The callback is invoked synchronously by
/// smb2_service; abort must destroy the context before we release the callback.
List<String> enumerateSmbShares(ffi.DynamicLibrary library,
    ffi.Pointer<Smb2Context> context, void Function() abort) {
  final enumerate =
      library.lookupFunction<EnumNative, EnumDart>('smb2_share_enum_async');
  final windowsPoll = Platform.isWindows && !library.providesSymbol('poll');
  final getFd = windowsPoll
      ? library.lookupFunction<WindowsFdNative, ContextIntDart>('smb2_get_fd')
      : library.lookupFunction<ContextIntNative, ContextIntDart>('smb2_get_fd');
  final events = library
      .lookupFunction<ContextIntNative, ContextIntDart>('smb2_which_events');
  final service =
      library.lookupFunction<ServiceNative, ServiceDart>('smb2_service');
  final free = library.lookupFunction<FreeNative, FreeDart>('smb2_free_data');
  // Windows native integration tests can export poll from their fixture DLL.
  final libc = Platform.isWindows ? library : ffi.DynamicLibrary.process();
  final poll =
      windowsPoll ? null : libc.lookupFunction<PollNative, PollDart>('poll');
  final wsaPoll = windowsPoll
      ? ffi.DynamicLibrary.open('ws2_32.dll')
          .lookupFunction<WindowsPollNative, WindowsPollDart>('WSAPoll')
      : null;
  final names = <String>{};
  var finished = false;
  Object? failure;
  void onReply(ffi.Pointer<Smb2Context> ctx, int status,
      ffi.Pointer<ffi.Void> data, ffi.Pointer<ffi.Void> private) {
    try {
      if (status != 0)
        throw StateError('共享枚举失败（$status）。服务器可能禁止枚举，请在起始路径填写共享名。');
      if (data == ffi.nullptr) throw StateError('服务器返回了空的共享枚举响应');
      final reply = data.cast<ShareEnumReply>().ref;
      if (reply.status != 0 ||
          reply.shares.level != 1 ||
          reply.shares.info.level != 1) {
        throw StateError('服务器返回了无效的共享枚举响应');
      }
      final container = reply.shares.info.container;
      if (container.count > 100000 ||
          (container.count > 0 && container.buffer == ffi.nullptr)) {
        throw StateError('服务器返回了无效的共享数量');
      }
      if (container.count > 0) {
        final array = container.buffer.ref;
        if (array.maxCount < container.count || array.entries == ffi.nullptr) {
          throw StateError('服务器返回了不完整的共享列表');
        }
        for (var i = 0; i < container.count; i++) {
          final entry = array.entries[i];
          if ((entry.type & 3) != 0 || entry.name.utf8 == ffi.nullptr) continue;
          final name = entry.name.utf8.toDartString();
          if (name.isNotEmpty &&
              name != '.' &&
              name != '..' &&
              !name.contains('/') &&
              !name.contains('\\')) names.add(name);
        }
      }
    } catch (error) {
      failure = error;
    } finally {
      if (data != ffi.nullptr) free(ctx, data);
      finished = true;
    }
  }

  final callback = ffi.NativeCallable<ShareCallback>.isolateLocal(onReply);
  final fd = calloc<SmbPollFd>();
  final winFd = windowsPoll ? calloc<SmbWindowsPollFd>() : null;
  var started = false;
  try {
    final result = enumerate(context, 1, callback.nativeFunction, ffi.nullptr);
    if (result != 0) throw StateError('无法开始 SMB 共享枚举（$result）');
    started = true;
    final clock = Stopwatch()..start();
    while (!finished) {
      if (clock.elapsed > const Duration(seconds: 30))
        throw StateError('SMB 共享枚举超时，请重连或直接填写共享名');
      int readyEvents;
      if (winFd != null) {
        winFd.ref.fd = getFd(context);
        winFd.ref.events = events(context);
        winFd.ref.revents = 0;
        if (wsaPoll!(winFd, 1, 250) < 0) throw StateError('SMB 共享枚举网络轮询失败');
        readyEvents = winFd.ref.revents;
      } else {
        fd.ref.fd = getFd(context);
        fd.ref.events = events(context);
        fd.ref.revents = 0;
        if (poll!(fd, 1, 250) < 0) throw StateError('SMB 共享枚举网络轮询失败');
        readyEvents = fd.ref.revents;
      }
      if (service(context, readyEvents) < 0 && !finished)
        throw StateError('SMB 共享枚举连接中断');
    }
    if (failure != null) throw failure!;
    return names.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  } finally {
    // An in-flight native request retains the callback. Destroy it first on
    // timeout/network failure, including any cancellation callback it invokes.
    if (started && !finished) abort();
    calloc.free(fd);
    if (winFd != null) calloc.free(winFd);
    callback.close();
  }
}
