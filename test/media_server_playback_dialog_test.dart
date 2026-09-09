import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/media_server_playback.dart';
import 'package:aloeplayer/widgets/media_server_playback_dialog.dart';

void main() {
  testWidgets(
      'switching versions resets stream indices to the new source on a narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    MediaServerPlaybackOptions? result;
    final sources = [
      MediaServerSource({
        'Id': 'first',
        'Name': 'First version',
        'DefaultAudioStreamIndex': 1,
        'MediaStreams': [
          {'Index': 1, 'Type': 'Audio', 'DisplayTitle': 'English'}
        ]
      }),
      MediaServerSource({
        'Id': 'second',
        'Name': 'Second version',
        'DefaultAudioStreamIndex': 8,
        'MediaStreams': [
          {'Index': 8, 'Type': 'Audio', 'DisplayTitle': '中文'}
        ]
      }),
    ];
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      result = await showDialog<MediaServerPlaybackOptions>(
                          context: context,
                          builder: (_) =>
                              MediaServerPlaybackDialog(sources: sources));
                    },
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second version').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(result!.sourceId, 'second');
    expect(result!.audioIndex, 8);
    expect(result!.subtitleIndex, -1);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'removed track selections are cleared instead of submitting invisible stale indices',
      (tester) async {
    MediaServerPlaybackOptions? result;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      result = await showDialog<MediaServerPlaybackOptions>(
                          context: context,
                          builder: (_) => MediaServerPlaybackDialog(
                                  sources: [
                                    MediaServerSource(
                                        {'Id': 'v', 'Name': 'Version'})
                                  ],
                                  initial: const MediaServerPlaybackOptions(
                                      sourceId: 'v',
                                      audioIndex: 99,
                                      subtitleIndex: 98,
                                      maxBitrate: 5000000)));
                    },
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(result!.audioIndex, isNull);
    expect(result!.subtitleIndex, -1);
    expect(result!.maxBitrate, 5000000);
    expect(tester.takeException(), isNull);
  });
}
