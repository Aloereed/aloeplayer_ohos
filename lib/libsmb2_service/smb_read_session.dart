import 'smb_worker.dart';

class SmbConnectionSettings {
  final String host, username, password, domain;
  final bool signingRequired, anonymousLogin, encryption;
  const SmbConnectionSettings(
      {required this.host,
      required this.username,
      required this.password,
      required this.domain,
      this.signingRequired = false,
      this.anonymousLogin = false,
      this.encryption = false});

  Future<bool> connect(SmbWorker worker) => worker.connect(
      host: host,
      username: username,
      password: password,
      domain: domain,
      signingRequired: signingRequired,
      anonymousLogin: anonymousLogin,
      encryption: encryption);
}

/// A lazy, independently owned reader worker keeps synchronous directory/stat
/// operations from blocking media bytes. Closing also closes an opening worker.
class SmbReadSession {
  final SmbConnectionSettings settings;
  final SmbWorker Function() createWorker;
  SmbReadSession(this.settings, this.createWorker);
  SmbWorker? _worker;
  Future<SmbWorker>? _opening;
  bool _closed = false;

  Future<SmbWorker> worker() {
    if (_closed) return Future.error(StateError('SMB 读取连接已关闭'));
    return _opening ??= _open();
  }

  Future<SmbWorker> _open() async {
    final worker = createWorker();
    _worker = worker;
    try {
      if (!await settings.connect(worker)) throw StateError('SMB 读取连接失败');
      if (_closed) throw StateError('SMB 读取连接已关闭');
      return worker;
    } catch (_) {
      await worker.disconnect();
      if (identical(_worker, worker)) _worker = null;
      _opening = null;
      rethrow;
    }
  }

  Future<void> close() async {
    _closed = true;
    final worker = _worker;
    _worker = null;
    await worker?.disconnect();
  }
}
