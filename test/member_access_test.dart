import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aloeplayer/services/member_access.dart';
import 'package:aloeplayer/services/mpv_image_enhancement.dart';
import 'mpv_image_enhancement_test.dart' show FakeImageBackend;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('trial requires explicit consent, survives restart and cannot restart at expiry', () async {
    var clock = DateTime.utc(2026, 9, 6);
    final access = MemberAccess(now: () => clock, paid: () => false);
    await access.initialize();
    expect(access.unlocked, isFalse);
    expect(access.canStartTrial, isTrue);
    await Future.wait([access.startTrial(), access.startTrial()]);
    final end = access.trialEnds;
    final restored = MemberAccess(now: () => clock, paid: () => false);
    await restored.initialize();
    expect(restored.trialEnds, end);
    expect(restored.trialActive, isTrue);
    clock = end!;
    expect(restored.unlocked, isFalse);
    expect(await restored.startTrial(), isFalse);
    clock = DateTime.utc(2026, 9, 5);
    expect(restored.trialActive, isFalse);
  });

  test('paid access changes immediately without extending a local trial', () async {
    var paid = false;
    final access = MemberAccess(paid: () => paid);
    await access.initialize();
    await expectLater(access.require(MemberFeature.batchDownload), throwsA(isA<MemberAccessRequired>()));
    paid = true;
    await access.require(MemberFeature.batchDownload);
    expect(access.trialEnds, isNull);
    paid = false;
    expect(access.unlocked, isFalse);
  });

  test('migration preserves saved image options with independent media-server quotas', () async {
    SharedPreferences.setMockInitialValues({
      'server_configs': jsonEncode([{'id': 'a'}, {'id': 'b'}]),
      'media-server.connections': jsonEncode([{'id': 'c', 'kind': 'Emby'}]),
      'mpv.image-enhancement.v1': jsonEncode({'mode': 'fsr4k', 'deband': true}),
    });
    final access = MemberAccess(paid: () => false);
    await access.initialize();
    expect(access.legacyFsr4k, isTrue);
    expect(access.legacyDeband, isTrue);
    expect(await access.canAddSource(kind: 'Emby'), isFalse);
    expect(await access.canAddSource(kind: 'Jellyfin'), isTrue);
    await (await SharedPreferences.getInstance()).setString('server_configs', '[]');
    expect(await access.canAddSource(kind: 'SMB'), isTrue);
    expect(await access.canAddSource(kind: 'WebDAV'), isTrue);
    final restored = MemberAccess(paid: () => false);
    await restored.initialize();
    expect(await restored.canAddSource(kind: 'Emby'), isFalse);
    expect(restored.legacyFsr4k, isTrue);
  });

  test('new free user keeps balanced FSR; protected settings cannot bypass the renderer guard', () async {
    final access = MemberAccess(paid: () => false);
    final engine = MpvImageEnhancer(backend: FakeImageBackend(), access: access);
    await engine.initialize();
    await engine.apply(const ImageEnhancementSettings(mode: UpscaleMode.fsr1080));
    await expectLater(engine.apply(const ImageEnhancementSettings(mode: UpscaleMode.fsr4k)), throwsA(isA<MemberAccessRequired>()));
    await expectLater(engine.apply(const ImageEnhancementSettings(deband: true)), throwsA(isA<MemberAccessRequired>()));
    expect(engine.settings.mode, UpscaleMode.fsr1080);
    engine.dispose();
  });

  test('expiry keeps the current picture but next player falls back without erasing saved preferences', () async {
    var clock = DateTime.utc(2026, 9, 6);
    final access = MemberAccess(now: () => clock, paid: () => false);
    await access.initialize();
    await access.startTrial();
    final engine = MpvImageEnhancer(backend: FakeImageBackend(), access: access);
    await engine.initialize();
    await engine.apply(const ImageEnhancementSettings(mode: UpscaleMode.fsr4k, deband: true));
    clock = clock.add(const Duration(days: 8));
    expect(engine.settings.mode, UpscaleMode.fsr4k);
    engine.dispose();
    final restored = MemberAccess(now: () => clock, paid: () => false);
    final next = MpvImageEnhancer(backend: FakeImageBackend(), access: restored);
    await next.initialize();
    expect(next.settings.mode, UpscaleMode.fsr1080);
    expect(next.settings.deband, isFalse);
    final saved = jsonDecode((await SharedPreferences.getInstance()).getString('mpv.image-enhancement.v1')!);
    expect(saved['mode'], 'fsr4k');
    expect(saved['deband'], isTrue);
    expect(restored.legacyFsr4k, isFalse);
    next.dispose();
  });
}
