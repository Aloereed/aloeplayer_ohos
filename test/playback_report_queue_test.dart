import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/playback_report_queue.dart';

void main() {
  test('slow server receives only current and latest state, then terminal stop',
      () async {
    final first = Completer<void>();
    final sent = <PlaybackReport>[];
    final queue = PlaybackReportQueue((report) async {
      sent.add(report);
      if (sent.length == 1) await first.future;
    });
    final drained = queue.add(const PlaybackReport(0, false, true));
    for (var position = 1; position <= 10000; position++) {
      expect(
          identical(queue.add(PlaybackReport(position, false, true)), drained),
          isTrue);
    }
    queue.add(const PlaybackReport(12000, true, false));
    queue.add(const PlaybackReport(100, false, true));
    expect(sent.length, 1);
    first.complete();
    await drained;
    expect(sent.map((s) => s.positionMs), [0, 12000]);
    expect(sent.last.stopped, isTrue);
    await queue.add(const PlaybackReport(0, false, true));
    expect(sent.length, 2);
  });

  test(
      'failed old update does not discard newer position or poison future flushes',
      () async {
    final first = Completer<void>();
    final sent = <int>[];
    final queue = PlaybackReportQueue((report) async {
      sent.add(report.positionMs);
      if (sent.length == 1) {
        await first.future;
        throw StateError('temporary network failure');
      }
    });
    final drained = queue.add(const PlaybackReport(1000, false, true));
    queue.add(const PlaybackReport(8000, false, false));
    first.complete();
    await drained;
    await queue.add(const PlaybackReport(9000, false, true));
    expect(sent, [1000, 8000, 9000]);
  });

  test('last failure is observable and a later update can recover', () async {
    var fail = true;
    final queue = PlaybackReportQueue((report) async {
      if (fail) throw StateError('offline');
    });
    await expectLater(
        queue.add(const PlaybackReport(1, false, true)), throwsStateError);
    fail = false;
    await queue.add(const PlaybackReport(2, false, true));
  });

  test('independent sessions do not block one another', () async {
    final slow = Completer<void>();
    final a = PlaybackReportQueue((_) => slow.future);
    var secondSent = false;
    final b = PlaybackReportQueue((_) async {
      secondSent = true;
    });
    final pending = a.add(const PlaybackReport(1, false, true));
    await b.add(const PlaybackReport(2, true, false));
    expect(secondSent, isTrue);
    slow.complete();
    await pending;
  });
}
