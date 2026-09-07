import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:aloeplayer/widgets/audio_track_dialog.dart';

void main() {
  testWidgets('late-discovered tracks appear and the final non-English track is selectable', (tester) async {
    final updates = StreamController<List<AudioTrack>>();
    addTearDown(updates.close);
    AudioTrack? selected;
    final all = [AudioTrack.auto(), AudioTrack.no(),
      for (var i = 1; i <= 48; i++) AudioTrack('$i', i <= 4 ? 'English $i' : '音轨 $i', i <= 4 ? 'eng' : 'zho')];
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () => showDialog<void>(context: context, builder: (_) => AudioTrackDialog(
        initialTracks: all.take(6).toList(), tracks: updates.stream,
        currentTrack: AudioTrack.auto(), onSelect: (track) async { selected = track; })), child: const Text('音轨'))))));
    await tester.tap(find.text('音轨'));
    await tester.pumpAndSettle();
    expect(find.text('选择音轨（4 条）'), findsOneWidget);
    expect(tester.widget<ListTile>(find.byKey(const ValueKey('audio-track-auto'))).selected, isTrue);
    expect(tester.widget<ListTile>(find.byKey(const ValueKey('audio-track-no'))).selected, isFalse);
    updates.add(all);
    await tester.pumpAndSettle();
    expect(find.text('选择音轨（48 条）'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('audio-track-48')), 500);
    await tester.tap(find.byKey(const ValueKey('audio-track-48')));
    await tester.pumpAndSettle();
    expect(selected?.id, '48');
    expect(selected?.language, 'zho');
    expect(find.byType(AudioTrackDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
