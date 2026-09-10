import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/widgets/audio_artwork_builder.dart';

void main() {
  testWidgets('missing artwork is not probed again on parent rebuild', (tester) async {
    var requests = 0;
    Widget tile(String source) => MaterialApp(home: AudioArtworkBuilder(
      source: source, load: () async { requests++; return null; },
      builder: (_, snapshot) => Text(snapshot.connectionState.name)));
    await tester.pumpWidget(tile('one.mp3'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(tile('one.mp3'));
    await tester.pumpAndSettle();
    expect(requests, 1);
    await tester.pumpWidget(tile('two.mp3'));
    await tester.pumpAndSettle();
    expect(requests, 2);
  });

  testWidgets('leaving a tile while artwork loads does not update disposed state', (tester) async {
    final pending = Completer<Uint8List?>();
    await tester.pumpWidget(MaterialApp(home: AudioArtworkBuilder(
      source: 'one.mp3', load: () => pending.future,
      builder: (_, __) => const SizedBox())));
    await tester.pumpWidget(const SizedBox());
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
