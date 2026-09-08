import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/network_directory_controller.dart';
import 'package:aloeplayer/services/file_service.dart';
import 'package:aloeplayer/models/server_config.dart';

class _Source implements FileService {
  final requests = <String, Completer<List<FileItem>>>{};
  @override
  bool get isConnected => true;
  @override
  Future<bool> connect(ServerConfig config) async => true;
  @override
  Future<void> disconnect() async {}
  @override
  Future<FileItem?> getFile(String path) async => null;
  @override
  Future<Stream<Uint8List>> getFileStream(String path,
          {int? start, int? end}) async =>
      const Stream.empty();
  @override
  Future<List<FileItem>> listFiles(String path) =>
      (requests[path] = Completer<List<FileItem>>()).future;
}

void main() {
  test(
      'latest navigation wins and failed navigation leaves the current folder/history intact',
      () async {
    final source = _Source();
    final controller = NetworkDirectoryController(source);
    final slow = controller.open('/slow', remember: true);
    final latest = controller.open('/latest', remember: true);
    source.requests['/latest']!.complete([]);
    expect(await latest, isTrue);
    source.requests['/slow']!.complete([]);
    expect(await slow, isFalse);
    expect(controller.path, '/latest');
    expect(controller.history, ['/']);
    final denied = controller.open('/denied', remember: true);
    source.requests['/denied']!.completeError(StateError('access denied'));
    expect(await denied, isFalse);
    expect(controller.path, '/latest');
    expect(controller.history, ['/']);
    expect(controller.failedPath, '/denied');
    final back = controller.back();
    source.requests['/']!.complete([]);
    expect(await back, isTrue);
    expect(controller.path, '/');
    expect(controller.history, isEmpty);
    expect(controller.error, isNull);
    controller.dispose();
  });
  test(
      'disposing while a listing is pending suppresses late state and notifications',
      () async {
    final source = _Source();
    final controller = NetworkDirectoryController(source);
    var updates = 0;
    controller.addListener(() => updates++);
    final loading = controller.open('/slow');
    controller.dispose();
    source.requests['/slow']!.completeError(StateError('closed'));
    expect(await loading, isFalse);
    expect(updates, 1);
    expect(controller.path, '/');
  });
}
