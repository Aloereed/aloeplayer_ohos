import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/work_queue.dart';
void main() {
  test('native work is bounded and a failed task releases its slot', () async {
    final queue = WorkQueue(concurrency: 2);
    final gate = Completer<void>();
    var active = 0;
    var peak = 0;
    final jobs = List.generate(8, (index) => queue.run(() async {
      active++;
      if (active > peak) peak = active;
      await gate.future;
      active--;
      if (index == 3) throw StateError('bad media');
      return index;
    }).then<int?>((v) => v, onError: (_) => null));
    expect(active, 2);
    gate.complete();
    expect((await Future.wait(jobs)).whereType<int>().length, 7);
    expect(peak, 2);
  });
}
