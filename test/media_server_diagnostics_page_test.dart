import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/media_server_client.dart';
import 'package:aloeplayer/pages/media_server_diagnostics_page.dart';

void main() {
  testWidgets(
      'narrow diagnostics page shows all permission lines and can rerun',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const connection = MediaServerConnection(
        id: 'c',
        name: 'server',
        url: 'https://example.invalid',
        userId: 'u',
        username: 'u',
        token: 'secret',
        kind: 'Emby');
    final client = MediaServerClient(connection);
    var count = 0;
    client.dio.interceptors
        .add(InterceptorsWrapper(onRequest: (options, handler) {
      count++;
      handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: options.path == 'System/Info/Public'
              ? {'Version': '4.10.0.40'}
              : options.path == 'Users/u'
                  ? {
                      'Policy': {
                        'EnableMediaPlayback': true,
                        'EnableContentDownloading': false,
                        'EnableVideoPlaybackTranscoding': false,
                        'EnableAudioPlaybackTranscoding': true
                      }
                    }
                  : {'Items': []}));
    }));
    addTearDown(client.close);
    await tester.pumpWidget(MaterialApp(
        home: MediaServerDiagnosticsPage(
            connection: connection, client: client)));
    await tester.pumpAndSettle();
    expect(count, 4);
    expect(find.textContaining('原文件下载：未允许'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('重新检查'));
    await tester.pumpAndSettle();
    expect(count, 8);
    expect(tester.takeException(), isNull);
  });
}
