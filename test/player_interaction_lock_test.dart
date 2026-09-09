import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/widgets/player_interaction_lock.dart';

void main() {
  testWidgets(
      'locked player blocks touches, drags, keys and back until long press unlock',
      (tester) async {
    var taps = 0, drags = 0, keys = 0;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) => PlayerInteractionLock(
                                    child: Scaffold(
                                        body: CallbackShortcuts(
                                            bindings: {
                                      const SingleActivator(
                                              LogicalKeyboardKey.space):
                                          () => keys++
                                    },
                                            child: Focus(
                                                autofocus: true,
                                                child: GestureDetector(
                                                    behavior:
                                                        HitTestBehavior.opaque,
                                                    onTap: () => taps++,
                                                    onHorizontalDragUpdate:
                                                        (_) => drags++,
                                                    child: const Center(
                                                        child: Text(
                                                            'movie'))))))))),
                    child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('movie'));
    expect(taps, 1);
    await tester.tap(find.byIcon(Icons.lock_open));
    await tester.pumpAndSettle();
    await tester.tap(find.text('movie'), warnIfMissed: false);
    await tester.drag(find.text('movie'), const Offset(100, 0),
        warnIfMissed: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(taps, 1);
    expect(drags, 0);
    expect(keys, 0);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('movie'), findsOneWidget);
    await tester.tap(find.text('长按解锁'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.lock), findsOneWidget);
    await tester.longPress(find.text('长按解锁'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('movie'));
    expect(taps, 2);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });
  testWidgets('legacy return callback respects lock before changing playback state', (tester) async {
    var locked = false; var exits = 0;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => PlayerInteractionLock(
        onLockChanged: (value) => locked = value,
        child: WillPopScope(onWillPop: () async { if (locked) return false; exits++; return true; }, child: const Scaffold(body: Text('legacy')))))),
      child: const Text('open legacy'))))));
    await tester.tap(find.text('open legacy')); await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.lock_open)); await tester.pumpAndSettle();
    await tester.binding.handlePopRoute(); await tester.pumpAndSettle(); expect(exits, 0);
    await tester.longPress(find.text('长按解锁')); await tester.pumpAndSettle();
    await tester.binding.handlePopRoute(); await tester.pumpAndSettle(); expect(exits, 1);
  });

}
