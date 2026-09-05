import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import '../services/serial_executor.dart';
import 'libsmb2_file.dart';
import 'libsmb2_service.dart';

abstract class SmbWorkerBackend {
  Future<bool> connect(Map<String, dynamic> options);
  Future<List<Libsmb2File>> list(String path);
  Future<Libsmb2File> stat(String path);
  Future<Stream<Uint8List>> range(String path, int start, int? end);
  Future<void> disconnect();
}

class _NativeBackend implements SmbWorkerBackend {
  final _service = Libsmb2Service();
  @override Future<bool> connect(Map<String, dynamic> options) => _service.connect(
    host: options['host'], username: options['username'], password: options['password'], domain: options['domain'],
    signingRequired: options['signingRequired'], anonymousLogin: options['anonymousLogin'], encryption: options['encryption']);
  @override Future<List<Libsmb2File>> list(String path) => _service.listFiles(path);
  @override Future<Libsmb2File> stat(String path) => _service.getFile(path);
  @override Future<Stream<Uint8List>> range(String path, int start, int? end) => _service.getRangeStream(path, start: start, end: end);
  @override Future<void> disconnect() => _service.disconnect();
}
void _nativeEntry(SendPort output) => serveSmbWorker(output, _NativeBackend());

/// One worker owns the native context and its readers. Pull-based requests keep
/// only one chunk per consumer in flight, without sending native pointers.
void serveSmbWorker(SendPort output, SmbWorkerBackend backend) {
  final inbox = ReceivePort();
  final serial = SerialExecutor();
  final readers = <int, StreamIterator<Uint8List>>{};
  var nextReader = 0;
  output.send(inbox.sendPort);
  inbox.listen((dynamic message) {
    final request = message as Map;
    unawaited(serial.run(() async {
      final id = request['id'] as int;
      final command = request['command'] as String;
      final args = Map<String, dynamic>.from(request['args'] as Map);
      try {
        Object? value;
        switch (command) {
          case 'connect': value = await backend.connect(args); break;
          case 'list': value = await backend.list(args['path']); break;
          case 'stat': value = await backend.stat(args['path']); break;
          case 'open':
            final stream = await backend.range(args['path'], args['start'], args['end']);
            final reader = ++nextReader;
            readers[reader] = StreamIterator(stream);
            value = reader;
            break;
          case 'next':
            final reader = readers[args['reader']];
            if (reader == null) throw StateError('SMB reader closed');
            value = await reader.moveNext() ? TransferableTypedData.fromList([reader.current]) : null;
            break;
          case 'close': await readers.remove(args['reader'])?.cancel(); break;
          case 'disconnect':
            for (final reader in readers.values) { try { await reader.cancel(); } catch (_) {} }
            readers.clear();
            await backend.disconnect();
            break;
          default: throw StateError('Unknown SMB operation');
        }
        output.send({'id': id, 'value': value});
      } catch (error) { output.send({'id': id, 'error': error.toString()}); }
      finally { if (command == 'disconnect') inbox.close(); }
    }));
  });
}

class SmbWorker {
  final void Function(SendPort) _entry;
  SmbWorker() : _entry = _nativeEntry;
  SmbWorker.forTesting(void Function(SendPort) entry) : _entry = entry;
  Isolate? _isolate;
  ReceivePort? _events;
  SendPort? _port;
  Future<void>? _starting;
  Completer<SendPort>? _ready;
  final Map<int, Completer<Object?>> _pending = {};
  final _connections = SerialExecutor();
  var _sequence = 0;
  bool _connected = false, _closing = false;
  bool get isConnected => _connected && !_closing;

  void _failed(Object error) {
    if (_ready != null && !_ready!.isCompleted) _ready!.completeError(error);
    for (final request in _pending.values) { request.completeError(error); }
    _pending.clear();
    _connected = false;
    _port = null;
    _events?.close();
    _events = null;
    _isolate = null;
  }
  Future<void> _launch() async {
    _ready = Completer<SendPort>();
    final ready = _ready!.future;
    final events = ReceivePort();
    _events = events;
    events.listen((dynamic message) {
      if (message is SendPort) { _ready!.complete(message); }
      else if (message is Map) {
        final pending = _pending.remove(message['id']);
        if (message['error'] != null) pending?.completeError(StateError(message['error']));
        else pending?.complete(message['value']);
      } else { _failed(StateError('SMB 后台连接已结束')); }
    });
    try {
      _isolate = await Isolate.spawn(_entry, events.sendPort, onError: events.sendPort, onExit: events.sendPort, errorsAreFatal: true);
      _port = await ready.timeout(const Duration(seconds: 10));
    } catch (_) { _isolate?.kill(priority: Isolate.immediate); events.close(); _events = null; rethrow; }
  }
  Future<Object?> _request(String command, Map<String, dynamic> args) async {
    if (!{'connect', 'disconnect'}.contains(command) && !isConnected) throw StateError('SMB 连接已关闭');
    final port = _port;
    if (port == null) throw StateError('SMB 连接已关闭');
    final id = ++_sequence;
    final response = Completer<Object?>();
    _pending[id] = response;
    port.send({'id': id, 'command': command, 'args': args});
    try { return await response.future; }
    finally { _pending.remove(id); }
  }
  Future<bool> connect({required String host, required String username, required String password, required String domain,
    bool signingRequired = false, bool anonymousLogin = false, bool encryption = false}) => _connections.run(() async {
    await _disconnect();
    _closing = false;
    await (_starting = _launch());
    _starting = null;
    try {
      _connected = await _request('connect', {'host': host, 'username': username, 'password': password, 'domain': domain,
        'signingRequired': signingRequired, 'anonymousLogin': anonymousLogin, 'encryption': encryption}) == true;
      if (!_connected) await _disconnect();
      return _connected;
    } catch (_) { await _disconnect(); rethrow; }
  });
  Future<List<Libsmb2File>> listFiles(String path) async => (await _request('list', {'path': path}) as List).cast<Libsmb2File>();
  Future<Libsmb2File> getFile(String path) async => await _request('stat', {'path': path}) as Libsmb2File;
  Future<Stream<Uint8List>> getFileStream(String path) => getRangeStream(path, start: 0);
  Future<Stream<Uint8List>> getRangeStream(String path, {required int start, int? end}) async => _range(path, start, end);
  Stream<Uint8List> _range(String path, int start, int? end) async* {
    if (!isConnected) throw StateError('SMB 未连接');
    final reader = await _request('open', {'path': path, 'start': start, 'end': end}) as int;
    try {
      while (isConnected) {
        final chunk = await _request('next', {'reader': reader});
        if (chunk == null) break;
        yield (chunk as TransferableTypedData).materialize().asUint8List();
      }
    } finally {
      if (_port != null && !_closing) { try { await _request('close', {'reader': reader}); } catch (_) {} }
    }
  }
  Future<void> disconnect() => _connections.run(_disconnect);
  Future<void> _disconnect() async {
    _closing = true;
    _connected = false;
    try { await _starting; } catch (_) {}
    _starting = null;
    if (_port != null) {
      try { await _request('disconnect', {}); }
      finally { _port = null; _events?.close(); _events = null; _isolate = null; _ready = null; }
    }
  }
}
