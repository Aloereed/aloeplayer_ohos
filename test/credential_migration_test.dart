import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aloeplayer/models/server_config.dart';
import 'package:aloeplayer/services/server_config_service.dart';

ServerConfig _config(String id) => ServerConfig(id: id, name: id, type: ServerType.smb, host: 'nas', username: 'user', password: 'secret-$id', createdAt: DateTime(2026));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secrets = <String, String>{};
  var failWrites = false;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secrets.clear(); failWrites = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      final key = call.arguments['key'] as String;
      if (call.method == 'read') return secrets[key];
      if (call.method == 'write') {
        if (failWrites) throw PlatformException(code: 'LOCKED');
        secrets[key] = call.arguments['value'] as String;
      }
      if (call.method == 'delete') secrets.remove(key);
      return null;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

  test('legacy passwords are removed from preferences only after secure writes succeed', () async {
    final prefs = await SharedPreferences.getInstance();
    final original = jsonEncode([_config('old').toJson()]);
    await prefs.setString('server_configs', original);
    failWrites = true;
    await expectLater(ServerConfigService().getAllConfigs(), throwsA(isA<PlatformException>()));
    expect(prefs.getString('server_configs'), original);
    failWrites = false;
    expect((await ServerConfigService().getAllConfigs()).single.password, 'secret-old');
    expect(prefs.getString('server_configs'), isNot(contains('secret-old')));
    expect((jsonDecode(prefs.getString('server_configs')!) as List).single.containsKey('password'), isFalse);
    expect(secrets['server_configs.old'], 'secret-old');
    expect((await ServerConfigService().getAllConfigs()).single.password, 'secret-old');
  });

  test('concurrent saves across instances keep both configs and deleting removes its secret', () async {
    await Future.wait([ServerConfigService().saveConfig(_config('a')), ServerConfigService().saveConfig(_config('b'))]);
    expect((await ServerConfigService().getAllConfigs()).map((c) => c.id), ['a', 'b']);
    await ServerConfigService().deleteConfig('a');
    expect(secrets.containsKey('server_configs.a'), isFalse);
    expect((await ServerConfigService().getAllConfigs()).single.password, 'secret-b');
  });
}
