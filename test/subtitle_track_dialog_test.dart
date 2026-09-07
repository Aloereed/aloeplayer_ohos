import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:aloeplayer/widgets/subtitle_track_dialog.dart';

void main() {
  testWidgets('late-discovered tracks appear and the final non-English track is selectable', (tester) async {
    final updates = StreamController<List<SubtitleTrack>>();
    addTearDown(updates.close);
    SubtitleTrack? selected;
    final all = [SubtitleTrack.auto(), SubtitleTrack.no(),
      for (var i = 1; i <= 48; i++) SubtitleTrack('$i', i <= 4 ? 'English $i' : '字幕 $i', i <= 4 ? 'eng' : 'zho')];
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () => showDialog<void>(context: context, builder: (_) => SubtitleTrackDialog(
        initialTracks: all.take(6).toList(), tracks: updates.stream,
        currentTrack: SubtitleTrack.auto(), onSelect: (track) async { selected = track; },
        onOpenExternal: () {})), child: const Text('字幕'))))));
    await tester.tap(find.text('字幕'));
    await tester.pumpAndSettle();
    expect(find.text('选择字幕轨道（4 条）'), findsOneWidget);
    expect(tester.widget<ListTile>(find.byKey(const ValueKey('subtitle-track-auto'))).selected, isTrue);
    expect(tester.widget<ListTile>(find.byKey(const ValueKey('subtitle-track-no'))).selected, isFalse);
    updates.add(all);
    await tester.pumpAndSettle();
    expect(find.text('选择字幕轨道（48 条）'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('subtitle-track-48')), 500);
    await tester.tap(find.byKey(const ValueKey('subtitle-track-48')));
    await tester.pumpAndSettle();
    expect(selected?.id, '48');
    expect(selected?.language, 'zho');
    expect(find.byType(SubtitleTrackDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
