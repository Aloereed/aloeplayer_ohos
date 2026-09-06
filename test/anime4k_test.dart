import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aloeplayer/services/anime4k_shaders.dart';
import 'package:aloeplayer/services/fsr_diagnostics.dart';
import 'package:aloeplayer/services/member_access.dart';
import 'package:aloeplayer/services/mpv_image_enhancement.dart';
import 'mpv_image_enhancement_test.dart' show FakeImageBackend;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final animePaths = Anime4kShaders.files.keys.map((name) => '/app/$name').toList();
  MpvImageEnhancer engine(FakeImageBackend backend, {MemberAccess? access,
      Future<List<String>> Function()? load}) => MpvImageEnhancer(backend: backend,
    access: access ?? MemberAccess(paid: () => true), anime4kPaths: load ?? (() async => animePaths),
    shaderPath: () async => '/app/FSR.glsl', diagnosticLog: (_, __) {});

  test('bundled upstream shader bytes match pinned manifest and reject corruption', () async {
    final manifest = jsonDecode(await File('Assets/shaders/anime4k/manifest.json').readAsString());
    expect(manifest['revision'], Anime4kShaders.revision);
    expect(Anime4kShaders.files.length, 6);
    for (final name in Anime4kShaders.files.keys) {
      final bytes = await File('Assets/shaders/anime4k/$name').readAsBytes();
      expect(Anime4kShaders.valid(name, bytes), isTrue, reason: name);
      expect(Anime4kShaders.valid(name, [...bytes, 0]), isFalse);
    }
    expect(await File('Assets/shaders/anime4k/LICENSE').exists(), isTrue);
  });
  test('Anime4K respects 2x/4K budget, portrait dimensions and the upstream 1.2x hook threshold', () {
    expect(enhancedOutputSize(UpscaleMode.anime4kFast, 1920, 1080), (width: 3840, height: 2160));
    expect(enhancedOutputSize(UpscaleMode.anime4kFast, 720, 1280), (width: 1440, height: 2560));
    expect(enhancedOutputSize(UpscaleMode.anime4kFast, 3840, 2160), isNull);
    expect(enhancedOutputSize(UpscaleMode.anime4kFast, 3500, 2000), isNull);
  });
  test('member-only Anime4K cannot be activated through the service, including saved-mode migration', () async {
    SharedPreferences.setMockInitialValues({'mpv.image-enhancement.v1': jsonEncode({'mode': 'anime4kFast'})});
    var paid = false;
    final enhancer = engine(FakeImageBackend(), access: MemberAccess(paid: () => paid));
    await enhancer.initialize();
    expect(enhancer.settings.mode, UpscaleMode.highQuality);
    await expectLater(enhancer.apply(const ImageEnhancementSettings(mode: UpscaleMode.anime4kFast)), throwsA(isA<MemberAccessRequired>()));
    paid = true;
    await enhancer.apply(const ImageEnhancementSettings(mode: UpscaleMode.anime4kFast));
    expect(enhancer.settings.mode, UpscaleMode.anime4kFast);
    enhancer.dispose();
  });
  test('Anime4K loads official chain in order and switching FSR/off removes it without stacking', () async {
    final backend = FakeImageBackend();
    backend.values['glsl-shaders'] = '/app/existing.glsl';
    final enhancer = engine(backend);
    enhancer.videoChanged(width: 1920, height: 1080, gamma: 'bt.1886', format: 'yuv420p');
    await enhancer.apply(const ImageEnhancementSettings(mode: UpscaleMode.anime4kFast));
    final separator = Platform.isWindows ? ';' : ':';
    expect(backend.values['glsl-shaders'], ['/app/existing.glsl', ...animePaths].join(separator));
    expect(backend.size, (width: 3840, height: 2160));
    await enhancer.apply(const ImageEnhancementSettings(mode: UpscaleMode.fsr4k));
    expect(backend.values['glsl-shaders'], '/app/existing.glsl$separator/app/FSR.glsl');
    await enhancer.apply(const ImageEnhancementSettings(mode: UpscaleMode.anime4kFast));
    expect(backend.values['glsl-shaders'], isNot(contains('FSR.glsl')));
    await enhancer.apply(const ImageEnhancementSettings());
    expect(backend.values['glsl-shaders'], '/app/existing.glsl');
    expect(backend.size, (width: null, height: null));
    enhancer.dispose();
  });
  test('HDR and RGB bypass Anime4K assets', () async {
    var loads = 0;
    final enhancer = engine(FakeImageBackend(), load: () async { loads++; return animePaths; });
    enhancer.videoChanged(width: 1280, height: 720, gamma: 'pq', format: 'yuv420p10');
    await enhancer.apply(const ImageEnhancementSettings(mode: UpscaleMode.anime4kFast));
    expect(enhancer.status, contains('HDR'));
    enhancer.videoChanged(width: 1280, height: 720, gamma: 'srgb', format: 'rgb24');
    await enhancer.apply(const ImageEnhancementSettings(mode: UpscaleMode.anime4kFast));
    expect(enhancer.status, contains('RGB'));
    expect(loads, 0);
    enhancer.dispose();
  });
  test('incomplete or failed shader chain restores defaults and clears saved failed mode', () async {
    final backend = FakeImageBackend();
    final enhancer = engine(backend, load: () async => animePaths.take(2).toList());
    enhancer.videoChanged(width: 1280, height: 720);
    await enhancer.apply(const ImageEnhancementSettings(mode: UpscaleMode.anime4kFast));
    expect(enhancer.settings.isDefault, isTrue);
    expect(enhancer.error, isNotNull);
    expect(backend.values['glsl-shaders'], '');
    final saved = jsonDecode((await SharedPreferences.getInstance()).getString('mpv.image-enhancement.v1')!);
    expect(saved['mode'], 'off');
    enhancer.dispose();
  });
  test('Anime4K evidence requires both restoration and upscaling output passes with timings', () {
    Map<String, Object> pass(String name, int last) => {'desc': name, 'last': last, 'count': 5};
    final restore = pass('Anime4K-v4.0-Restore-CNN-(M)-Conv-3x1x1x56', 100);
    final upscale = pass('Anime4K-v3.2-Upscale-CNN-x2-(M)-Depth-to-Space', 80);
    expect(summarizeAnime4kPasses(null)['anime4kEvidence'], 'unavailable');
    expect(summarizeAnime4kPasses({'fresh': []})['anime4kEvidence'], 'not_observed');
    expect(summarizeAnime4kPasses({'fresh': [restore]})['anime4kEvidence'], 'partial_or_untimed');
    expect(summarizeAnime4kPasses({'fresh': [restore, upscale]})['anime4kEvidence'], 'restore_upscale_timed');
    expect(summarizeFsrPasses({'fresh': [restore, upscale]})['passEvidence'], 'not_observed');
  });
}
