import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/media_server_client.dart';

void main() {
  test('server URL validation preserves reverse-proxy prefixes and rejects credentials', () {
    expect(MediaServerConnection.normalizeUrl('https://nas.example/jellyfin/'), 'https://nas.example/jellyfin');
    expect(() => MediaServerConnection.normalizeUrl('https://user:pass@nas/'), throwsFormatException);
    expect(() => MediaServerConnection.normalizeUrl('file:///movie'), throwsFormatException);
  });
  test('login, browsing, header-authenticated stream and tick-based progress use server protocol', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final events = <String>[];
    final positions = <int>[];
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final route = request.uri.path;
      events.add(route);
      request.response.headers.contentType = ContentType.json;
      Object response = {};
      if (route == '/jellyfin/Users/AuthenticateByName') {
        expect((jsonDecode(body) as Map)['Pw'], 'test-password');
        expect(request.headers.value('X-Emby-Authorization'), contains('AloePlayer'));
        response = {'AccessToken': 'test-token', 'User': {'Id': 'user'}};
      } else {
        expect(request.headers.value('X-Emby-Token'), 'test-token');
        if (route.endsWith('/Items')) response = {'Items': [{'Id': 'movie', 'Name': 'Movie', 'Type': 'Movie', 'UserData': {'PlaybackPositionTicks': 120000000}}]};
        if (route.endsWith('/PlaybackInfo')) response = {'PlaySessionId': 'session', 'MediaSources': [{'Id': 'source'}]};
        if (route.contains('/Sessions/')) positions.add((jsonDecode(body) as Map)['PositionTicks'] as int);
      }
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    MediaServerClient? client;
    try {
      final connection = await MediaServerClient.login(url: 'http://127.0.0.1:${server.port}/jellyfin', username: 'test-user', password: 'test-password', kind: 'Jellyfin');
      expect(connection.toJson().containsKey('token'), isFalse);
      client = MediaServerClient(connection);
      final items = await client.items();
      expect(items.single.resumeMs, 12000);
      final media = await client.playback(items.single);
      expect(Uri.parse(media.url).queryParameters['static'], 'true');
      expect(Uri.parse(media.url).queryParameters.containsKey('api_key'), isFalse);
      expect(media.httpHeaders['X-Emby-Token'], 'test-token');
      await client.report(media, 15000, false, true);
      await client.report(media, 18000, true, false);
      expect(positions, [150000000, 150000000, 180000000]);
      expect(events.last, '/jellyfin/Sessions/Playing/Stopped');
    } finally { await client?.close(); await server.close(force: true); }
  });
}
