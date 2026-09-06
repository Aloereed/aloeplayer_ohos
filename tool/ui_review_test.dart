// Host-side widget previews. These do not exercise HarmonyOS or a video GPU.
// Run: flutter test --no-pub tool/ui_review_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aloeplayer/theme/app_theme.dart';
import 'package:aloeplayer/pages/servers_page.dart';
import 'package:aloeplayer/widgets/responsive_app_shell.dart';
import 'package:aloeplayer/widgets/local_import_sheet.dart';
import 'package:aloeplayer/widgets/video_library_tile.dart';
import 'package:aloeplayer/widgets/video_file_actions_sheet.dart';
import 'package:aloeplayer/widgets/image_enhancement_sheet.dart';
import 'package:aloeplayer/services/mpv_image_enhancement.dart';

class PreviewBackend implements MpvImageBackend {
  final values = {'scale': 'bilinear', 'cscale': 'bilinear', 'deband': 'no', 'glsl-shaders': '',
    'brightness': '0', 'contrast': '0', 'saturation': '0', 'gamma': '0'};
  @override Future<String> read(String key) async => values[key] ?? '';
  @override Future<void> write(String key, String value) async { values[key] = value; }
  @override Future<void> resize(int? width, int? height) async {}
}
void main() {
  testWidgets('render review screens using production widgets', (tester) async {
    final previousShadows = debugDisableShadows;
    debugDisableShadows = false;
    try {
    await tester.runAsync(() async {
      final font = File(Platform.environment['UI_REVIEW_FONT'] ?? 'C:/Windows/Fonts/msyh.ttc');
      if (await font.exists()) {
        final loader = FontLoader('ReviewChinese')..addFont(font.readAsBytes().then(ByteData.sublistView));
        await loader.load();
      }
      await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'))).load();
      await Directory('build/ui-review').create(recursive: true);
    });
    SharedPreferences.setMockInitialValues({
      'server_configs': jsonEncode([
        {'id': 'nas', 'name': '家里的 NAS', 'type': 'webdav', 'host': 'nas.home', 'username': 'family', 'password': '', 'createdAt': '2026-09-06T00:00:00.000'},
        {'id': 'pc', 'name': '书房电脑', 'type': 'smb', 'host': '192.168.1.20', 'username': 'family', 'password': '', 'createdAt': '2026-09-06T00:00:00.000'},
      ]),
      'media-server.connections': jsonEncode([
        {'id': 'j', 'name': '家庭影院', 'url': 'https://jellyfin.home', 'userId': '1', 'username': 'family', 'kind': 'Jellyfin'},
        {'id': 'e', 'name': '我的影视收藏', 'url': 'https://emby.home', 'userId': '1', 'username': 'family', 'kind': 'Emby'},
      ]),
    });
    FlutterSecureStorage.setMockInitialValues({});
    final captures = <String>[];
    Future<void> capture(String name, Size size, Brightness brightness, Widget child) async {
      tester.view.physicalSize = size; tester.view.devicePixelRatio = 1;
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(key: key, child: MaterialApp(
        debugShowCheckedModeBanner: false, theme: buildAloeTheme(brightness, desktop: size.width > 800, fontFamily: 'ReviewChinese'), home: child)));
      await tester.pumpAndSettle();
      await tester.runAsync(() => precacheImage(const AssetImage('Assets/icon.png'), key.currentContext!));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('build/ui-review/$name.png').writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
      captures.add(name);
      await tester.pumpWidget(const SizedBox()); await tester.pumpAndSettle();
    }
    await capture('mobile-library-light', const Size(390, 844), Brightness.light,
      ResponsiveAppShell(desktop: false, fullScreen: false, selectedIndex: 2, onSelected: (_) {}, child: const ServersPage()));
    await capture('desktop-library-dark', const Size(1440, 960), Brightness.dark,
      ResponsiveAppShell(desktop: true, fullScreen: false, selectedIndex: 2, onSelected: (_) {}, child: const ServersPage()));
    await capture('desktop-import-light', const Size(860, 860), Brightness.light,
      const Scaffold(body: LocalImportSheet(destination: 'Downloads/com.aloereed.aloeplayer/Videos')));
    await capture('mobile-import-light', const Size(390, 844), Brightness.light,
      const Scaffold(body: LocalImportSheet(destination: 'Downloads/com.aloereed.aloeplayer/Videos')));
    final enhancer = MpvImageEnhancer(backend: PreviewBackend(), shaderPath: () async => '/preview/FSR.glsl');
    enhancer.videoChanged(width: 1280, height: 720, gamma: 'bt.1886');
    await enhancer.apply(const ImageEnhancementSettings(mode: UpscaleMode.fsr1080));
    await capture('mobile-enhancement-dark', const Size(390, 844), Brightness.dark,
      Scaffold(body: ImageEnhancementSheet(enhancer: enhancer)));
    enhancer.dispose();
    await capture('video-cards-light', const Size(900, 600), Brightness.light, Scaffold(
      appBar: AppBar(title: const Text('视频卡片组件预览')),
      body: GridView.count(crossAxisCount: 3, padding: const EdgeInsets.all(24), mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 1,
        children: [for (var i = 0; i < 6; i++) VideoLibraryTile(name: ['周末的旅行 · 山与海.mp4', '自然纪录片 第一集.mkv', '家庭影像 2026.mp4'][i % 3],
          details: '1.28 GB', shortcut: i == 2, favorite: i == 0, thumbnail: Future.value(null),
          info: Future.value(VideoTileInfo(duration: const Duration(minutes: 42, seconds: 18), progress: i == 0 ? .4 : 0, hdr: i == 1)),
          onPlay: () {}, onOptions: () {}, onFavorite: () {})])));
    await capture('mobile-video-actions-light', const Size(390, 844), Brightness.light,
      Scaffold(body: VideoFileActionsSheet(name: '周末的旅行 · 山与海.mp4', details: '快捷方式 · 3 天前',
        thumbnail: Future.value(null), shortcut: true)));
    await tester.runAsync(() async {
      await File('build/ui-review/index.html').writeAsString('<!doctype html><meta charset="utf-8"><title>AloePlayer UI review</title>'
        '<style>body{font:16px system-ui;background:#edf2f7;color:#17212f;margin:32px}img{max-width:100%;border-radius:16px}section{margin:32px 0;max-width:1440px}</style>'
        '<h1>AloePlayer 界面预览</h1><p>桌面 widget 渲染，示例数据；不代表鸿蒙实机或 GPU 验证。</p>'
        '${captures.map((name) => '<section><h2>$name</h2><img src="$name.png"></section>').join()}');
    });
    } finally {
      debugDisableShadows = previousShadows;
      tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio();
    }
  });
}
