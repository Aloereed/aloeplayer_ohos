import 'dart:async';
import 'dart:collection';

/// Bounds expensive native thumbnail requests without moving platform channels
/// off their supported isolate. Failures still release the queue slot.
class WorkQueue {
  final int concurrency;
  final Queue<Future<void> Function()> _pending = Queue();
  int _running = 0;
  WorkQueue({this.concurrency = 2}) : assert(concurrency > 0);
  Future<T> run<T>(Future<T> Function() work) {
    final result = Completer<T>();
    _pending.add(() async {
      try { result.complete(await work()); } catch (error, stack) { result.completeError(error, stack); }
    });
    _pump();
    return result.future;
  }
  void _pump() {
    while (_running < concurrency && _pending.isNotEmpty) {
      _running++;
      final work = _pending.removeFirst();
      work().whenComplete(() { _running--; _pump(); });
    }
  }
}
