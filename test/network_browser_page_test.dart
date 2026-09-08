import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aloeplayer/pages/browser_page.dart';
import 'package:aloeplayer/services/file_service.dart';
import 'package:aloeplayer/services/http_service.dart';
import 'package:aloeplayer/services/webdav_service.dart';
import 'package:aloeplayer/models/server_config.dart';

class _Source implements FileService {
  bool connected = false;
  bool failConnect = false;
  bool requireKnownProbe = false;
  @override
  bool get isConnected => connected;
  @override
  Future<bool> connect(ServerConfig config) async {
    if (requireKnownProbe && config.initialPath != '/Known')
      throw StateError('root forbidden');
    if (failConnect) throw StateError('authentication failed');
    return connected = true;
  }

  @override
  Future<void> disconnect() async {
    connected = false;
  }

  @override
  Future<FileItem?> getFile(String path) async => null;
  @override
  Future<Stream<Uint8List>> getFileStream(String path,
          {int? start, int? end}) async =>
      const Stream.empty();
  @override
  Future<List<FileItem>> listFiles(String path) async {
    if (path != '/Known') throw StateError('服务器禁止枚举共享');
    return [
      WebDavFileItem(const WebDavFile(
          name: '测试影片', path: '/Known/clip.m2ts', size: 6, isDirectory: false))
    ];
  }
}

class _Proxy extends HttpService {
  _Proxy(super.source) : super.forTesting();
  @override
  Future<bool> startServer({String? bindAddress}) async => true;
}

void main() {
  final config = ServerConfig(
      id: 'test',
      name: '测试 NAS',
      type: ServerType.smb,
      host: 'nas',
      username: '',
      password: '',
      createdAt: DateTime(2026));
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  testWidgets(
      'known DAV path reconnects when the initial root probe is forbidden',
      (tester) async {
    final source = _Source()..requireKnownProbe = true;
    await tester.pumpWidget(MaterialApp(
        home: BrowserPage(
            serverConfig: config.copyWith(type: ServerType.webdav),
            fileService: source,
            httpService: _Proxy(source))));
    await tester.pumpAndSettle();
    expect(find.text('无法连接服务器'), findsOneWidget);
    await tester.tap(find.text('打开路径'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '/Known');
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('无法连接服务器'), findsNothing);
    expect(find.text('测试影片'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'root enumeration failure stays visible and known shares can be opened directly',
      (tester) async {
    final source = _Source();
    await tester.pumpWidget(MaterialApp(
        home: BrowserPage(
            serverConfig: config,
            fileService: source,
            httpService: _Proxy(source))));
    await tester.pumpAndSettle();
    expect(find.text('无法读取目录'), findsOneWidget);
    expect(find.text('此文件夹为空'), findsNothing);
    await tester.tap(find.text('打开路径'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '/Known');
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('无法读取目录'), findsNothing);
    expect(find.text('测试影片'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('connection errors remain on the page with a retry action',
      (tester) async {
    final source = _Source()..failConnect = true;
    await tester.pumpWidget(MaterialApp(
        home: BrowserPage(
            serverConfig: config,
            fileService: source,
            httpService: _Proxy(source))));
    await tester.pumpAndSettle();
    expect(find.text('无法连接服务器'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    source.failConnect = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('无法连接服务器'), findsNothing);
    expect(find.text('无法读取目录'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
