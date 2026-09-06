import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aloeplayer/models/server_config.dart';
import 'package:aloeplayer/services/member_access.dart';
import 'package:aloeplayer/services/media_server_client.dart';
import 'package:aloeplayer/services/server_config_service.dart';

ServerConfig config(String id) => ServerConfig(id: id, name: id, type: ServerType.smb,
  host: 'nas', username: '', password: '', createdAt: DateTime(2026));
MediaServerConnection media(String id, String kind) => MediaServerConnection(id: id, name: kind, url: 'https://example.com',
  userId: 'user', username: 'user', token: 'token', kind: kind);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('SMB and WebDAV are unlimited; each media protocol has one slot, including concurrent edits', () async {
    SharedPreferences.setMockInitialValues({
      'member.access.v1': jsonEncode({'freeSourceSlots': 1, 'trialStarted': '2020-01-01T00:00:00.000Z'}),
      'server_configs': jsonEncode([config('a').toJson(), config('b').toJson()]),
    });
    const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    final secrets = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      final key = call.arguments['key'] as String;
      if (call.method == 'read') return secrets[key];
      if (call.method == 'write') secrets[key] = call.arguments['value'] as String;
      if (call.method == 'delete') secrets.remove(key);
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    final service = ServerConfigService();
    expect((await service.getAllConfigs()).length, 2);
    await service.saveConfig(config('a'));
    await Future.wait(List.generate(5, (i) => service.saveConfig(config('new-$i'))));
    await service.saveConfig(ServerConfig(id: 'webdav', name: 'WebDAV', type: ServerType.webdav,
      host: 'nas', username: '', password: '', createdAt: DateTime(2026)));
    expect((await service.getAllConfigs()).length, 8);
    Future<bool> attempt(Future<void> Function() action) async {
      try { await action(); return true; } on MemberAccessRequired { return false; }
    }
    final results = await Future.wait([
      attempt(() => MediaServerStore.save(media('j1', 'Jellyfin'))),
      attempt(() => MediaServerStore.save(media('j2', 'Jellyfin'))),
      attempt(() => MediaServerStore.save(media('e1', 'Emby'))),
      attempt(() => MediaServerStore.save(media('e2', 'Emby'))),
    ]);
    expect(results.where((success) => success).length, 2);
    expect((await MediaServerStore.load()).length, 2);
    expect(secrets.containsKey('media-server.j2'), isFalse);
    await MediaServerStore.save(media('j1', 'Jellyfin'));
    await expectLater(MediaServerStore.save(media('j1', 'Emby')), throwsA(isA<MemberAccessRequired>()));
    await MediaServerStore.remove('e1');
    await MediaServerStore.save(media('j1', 'Emby'));
    await MediaServerStore.save(media('j2', 'Jellyfin'));
    // Simulate pre-existing over-quota data: preserve edits but reject additions.
    final prefs = await SharedPreferences.getInstance();
    final rows = jsonDecode(prefs.getString('media-server.connections')!) as List;
    rows.add(media('old', 'Jellyfin').toJson());
    await prefs.setString('media-server.connections', jsonEncode(rows));
    await MediaServerStore.save(media('old', 'Jellyfin'));
    await expectLater(MediaServerStore.save(media('j3', 'Jellyfin')), throwsA(isA<MemberAccessRequired>()));
    expect((await MediaServerStore.load()).length, 3);
  });
}
