/// Serializes read-modify-write operations across service instances. A failed
/// operation is reported to its caller without blocking the following one.
class SerialExecutor {
  Future<void> _tail = Future.value();
  Future<T> run<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
}
