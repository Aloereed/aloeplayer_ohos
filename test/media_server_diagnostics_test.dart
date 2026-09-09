import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/media_server_client.dart';
import 'package:aloeplayer/services/media_server_diagnostics.dart';

void main() {
  test(
      'diagnostics read only bounded endpoints and never expose request secrets',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var unauthorized = false, html = false, requests = 0;
    Completer<void>? stall, arrived;
    server.listen((request) async {
      requests++;
      expect(request.method, 'GET');
      expect(request.headers.value('X-Emby-Token'), 'private-token');
      if (stall != null) {
        arrived?.complete();
        await stall.future;
      }
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path.endsWith('/System/Info/Public')) {
        request.response.write(html
            ? '"private-token wrong page"'
            : jsonEncode(
                {'Version': '12.0.0', 'ProductName': 'Jellyfin Server'}));
      } else if (request.uri.path.endsWith('/Users/private-user')) {
        request.response.statusCode = unauthorized ? 401 : 200;
        request.response.write(jsonEncode({
          'Policy': {
            'EnableMediaPlayback': true,
            'EnableContentDownloading': false,
            'EnableVideoPlaybackTranscoding': false,
            'EnableAudioPlaybackTranscoding': true
          }
        }));
      } else {
        expect(request.uri.queryParameters['Limit'], '1');
        request.response.write(jsonEncode({
          'Items': [
            {'Id': 'private-item', 'Name': 'private-title', 'Type': 'Folder'}
          ],
          'TotalRecordCount': 1
        }));
      }
      await request.response.close().catchError((_) {});
    });
    final client = MediaServerClient(MediaServerConnection(
        id: 'private-device',
        name: 'private-name',
        url: 'http://127.0.0.1:${server.port}/private-prefix',
        userId: 'private-user',
        username: 'private-user',
        token: 'private-token',
        kind: 'Jellyfin'));
    try {
      final rows =
          await MediaServerDiagnostics(client).run(CancelToken()).toList();
      expect(rows, hasLength(4));
      expect(rows[1].status, MediaServerDiagnosticStatus.warning);
      expect(rows[1].detail, contains('原文件下载：未允许'));
      expect(rows.where((r) => r.status == MediaServerDiagnosticStatus.failed),
          isEmpty);
      final summary =
          mediaServerDiagnosticSummary(client.connection.kind, rows);
      expect(summary, contains('12.0.0'));
      expect(summary, isNot(contains('private-')));
      expect(summary, isNot(contains('127.0.0.1')));
      unauthorized = true;
      html = true;
      final failures =
          await MediaServerDiagnostics(client).run(CancelToken()).toList();
      expect(failures[0].status, MediaServerDiagnosticStatus.failed);
      expect(failures[1].detail, contains('重新登录'));
      expect(mediaServerDiagnosticSummary('Jellyfin', failures),
          isNot(contains('private-')));
      final count = requests;
      expect(
          await MediaServerDiagnostics(client)
              .run(CancelToken()..cancel())
              .toList(),
          isEmpty);
      expect(requests, count);
      stall = Completer<void>();
      arrived = Completer<void>();
      final cancel = CancelToken();
      final canceledRun = MediaServerDiagnostics(client).run(cancel).toList();
      await arrived.future.timeout(const Duration(seconds: 3));
      cancel.cancel('Page closed');
      stall.complete();
      expect(await canceledRun, isEmpty);
      expect(requests, count + 1);
    } finally {
      await client.close();
      await server.close(force: true);
    }
  });
  test('TLS and gateway failures have distinct actionable messages', () {
    final request = RequestOptions(path: 'https://private-host/secret');
    expect(
        mediaServerFailureMessage(DioException(
            requestOptions: request, type: DioExceptionType.badCertificate)),
        contains('证书'));
    expect(
        mediaServerFailureMessage(DioException(
            requestOptions: request,
            response: Response(requestOptions: request, statusCode: 502))),
        contains('反向代理'));
    expect(
        mediaServerFailureMessage(DioException(
            requestOptions: request,
            response: Response(requestOptions: request, statusCode: 503))),
        contains('启动'));
  });
}
