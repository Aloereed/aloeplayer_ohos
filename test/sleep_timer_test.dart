import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/sleep_timer.dart';

void main() {
  testWidgets('countdown expires once and replacement cancels previous timer', (tester) async {
    final timer = PlaybackSleepTimer();
    var stops = 0;
    timer.attach('player', () async { stops++; });
    timer.start(const Duration(minutes: 15));
    timer.start(const Duration(minutes: 30));
    await tester.pump(const Duration(minutes: 16));
    expect(stops, 0);
    await tester.pump(const Duration(minutes: 15));
    expect(stops, 1);
    expect(timer.active, isFalse);
    timer.dispose();
  });
  test('end-of-item only affects the active owner and consumes once', () {
    final timer = PlaybackSleepTimer();
    var stops = 0;
    timer.attach('audio', () async { stops++; });
    timer.afterCurrentItem();
    expect(timer.consumeEnd('video'), isFalse);
    expect(timer.consumeEnd('audio'), isTrue);
    expect(timer.consumeEnd('audio'), isFalse);
    expect(stops, 1);
    timer.dispose();
  });
}
