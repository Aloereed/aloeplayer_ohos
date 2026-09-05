import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aloeplayer/services/mpv_image_enhancement.dart';

class FakeImageBackend implements MpvImageBackend {
  final values = <String, String>{'scale': 'bilinear', 'cscale': 'bilinear', 'glsl-shaders': '',
    'deband': 'no', 'brightness': '0', 'contrast': '0', 'saturation': '0', 'gamma': '0'};
  String? reject;
  ({int? width, int? height}) size = (width: null, height: null);
  int writes = 0;
  @override Future<String> read(String key) async => values[key] ?? '';
  @override Future<void> write(String key, String value) async {
    writes++;
    // The bundled mpv binding silently ignores setProperty failures. Readback
    // must catch this instead of showing a successful but inactive switch.
    if (key != reject) values[key] = value;
  }
  @override Future<void> resize(int? width, int? height) async { size = (width: width, height: height); }
}
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('output respects 2x, 1080p/4K budgets, portrait aspect and no downscale', () {
    expect(enhancedOutputSize(UpscaleMode.fsr1080, 1280, 720), (width: 1920, height: 1080));
    expect(enhancedOutputSize(UpscaleMode.fsr4k, 1920, 1080), (width: 3840, height: 2160));
    expect(enhancedOutputSize(UpscaleMode.fsr1080, 720, 1280), (width: 1080, height: 1920));
    expect(enhancedOutputSize(UpscaleMode.fsr4k, 640, 360), (width: 1280, height: 720));
    expect(enhancedOutputSize(UpscaleMode.fsr1080, 3840, 2160), isNull);
    expect(enhancedOutputSize(UpscaleMode.fsr4k, 0, 0), isNull);
  });
  test('default settings leave decoder rendering untouched', () async {
    final backend = FakeImageBackend();
    final engine = MpvImageEnhancer(backend: backend);
    await engine.initialize();
    expect(backend.writes, 0);
    engine.dispose();
  });
  test('FSR changes actual output and disabling restores all original properties', () async {
    final backend = FakeImageBackend();
    final original = Map<String, String>.from(backend.values);
    final engine = MpvImageEnhancer(backend: backend, shaderPath: () async => '/app/FSR.glsl');
    engine.videoChanged(width: 1280, height: 720, gamma: 'bt.1886', format: 'yuv420p');
    await engine.apply(const ImageEnhancementSettings(mode: UpscaleMode.fsr1080, deband: true, contrast: 10));
    expect(backend.values['glsl-shaders'], '/app/FSR.glsl');
    expect(backend.size, (width: 1920, height: 1080));
    expect(backend.values['contrast'], '10');
    await engine.apply(const ImageEnhancementSettings());
    expect(backend.values, original);
    expect(backend.size, (width: null, height: null));
    engine.dispose();
  });
  test('HDR skips SDR shader and unsupported options roll back instead of pretending success', () async {
    final backend = FakeImageBackend();
    var shaderLoads = 0;
    final engine = MpvImageEnhancer(backend: backend, shaderPath: () async { shaderLoads++; return '/app/FSR.glsl'; });
    engine.videoChanged(width: 1280, height: 720, gamma: 'pq', format: 'yuv420p10');
    await engine.apply(const ImageEnhancementSettings(mode: UpscaleMode.fsr1080));
    expect(shaderLoads, 0);
    expect(engine.status, contains('HDR'));
    backend.reject = 'deband';
    await engine.apply(const ImageEnhancementSettings(mode: UpscaleMode.fsr1080, deband: true));
    expect(engine.settings.isDefault, isTrue);
    expect(engine.error, isNotNull);
    expect(backend.values['scale'], 'bilinear');
    expect(backend.size, (width: null, height: null));
    engine.dispose();
  });
  test('invalid saved values are bounded and unknown presets stay off', () {
    final value = ImageEnhancementSettings.fromJson({'mode': 'future', 'brightness': 900, 'gamma': double.nan, 'contrast': 'oops'});
    expect(value.mode, UpscaleMode.off);
    expect(value.brightness, 50);
    expect(value.gamma, 0);
    expect(value.contrast, 0);
  });
}
