import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/widgets/responsive_app_shell.dart';
import 'package:aloeplayer/widgets/video_library_tile.dart';

void main() {
  testWidgets('desktop shell falls back on small windows and supports keyboard navigation', (tester) async {
    var index = 0;
    for (final size in [const Size(320, 700), const Size(900, 400), const Size(1280, 800)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(MaterialApp(home: ResponsiveAppShell(desktop: true, fullScreen: false,
        selectedIndex: index, onSelected: (v) => index = v, child: const Scaffold(body: Text('content')))));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), size.width < 840 ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
      if (size.width >= 840) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        expect(index, 2);
      }
    }
    tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio();
  });
  testWidgets('video tiles preserve tap actions, long names and large text', (tester) async {
    var plays = 0, options = 0;
    for (final list in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        await tester.pumpWidget(MaterialApp(home: MediaQuery(data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: SizedBox(width: list ? 320 : 220, height: list ? 220 : 220 * 9 / 16 + 48 * scale + 44,
            child: VideoLibraryTile(name: '一部很长名字的电影_1080p.mkv', details: '1.2 GB', list: list, shortcut: true,
              thumbnail: Future<Uint8List?>.value(null), info: Future.value(const VideoTileInfo(duration: Duration(minutes: 45), progress: .35, hdr: true)),
              onPlay: () => plays++, onOptions: () => options++, onFavorite: () {}))))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('一部很长名字的电影_1080p.mkv'));
        await tester.tap(find.byTooltip('更多操作'));
      }
    }
    expect(plays, 4); expect(options, 4);
  });
}
