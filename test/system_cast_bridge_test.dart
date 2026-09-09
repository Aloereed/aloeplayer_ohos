import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/screens/castview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('system cast status rejects malformed events and bounds positions', () {
    expect(SystemCastStatus.parse('{bad'), isNull);
    expect(SystemCastStatus.parse(jsonEncode({'state': 10})), isNull);
    expect(
        SystemCastStatus.parse({'state': 'PLAYING', 'positionMs': 63000.5})!
            .position
            .inMilliseconds,
        63001);
    expect(
        SystemCastStatus.parse({'state': 'PAUSED', 'positionMs': -2})!.position,
        Duration.zero);
    expect(
        SystemCastStatus.parse({'state': 'ERROR', 'message': '6600102'})!
            .message,
        '6600102');
  });
  test('native status channel is released; command errors remain actionable',
      () async {
    const channel = MethodChannel('test/aloe/cast');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final controller = CastViewController(channel);
    final states = <SystemCastStatus>[];
    final subscription = controller.statuses.listen(states.add);
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'pause')
        throw PlatformException(
            code: 'CAST_ERROR', message: 'device disconnected');
      return null;
    });
    await controller.sendMessageToOhosView('play', '');
    await expectLater(controller.sendMessageToOhosView('pause', ''),
        throwsA(isA<PlatformException>()));
    await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall(
            'castState', jsonEncode({'state': 'PLAYING', 'positionMs': 2000}))),
        (_) {});
    expect(states.single.state, 'PLAYING');
    controller.dispose();
    controller.dispose();
    await expectLater(
        controller.sendMessageToOhosView('play', ''), throwsStateError);
    await subscription.cancel();
    messenger.setMockMethodCallHandler(channel, null);
  });
}
