import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aloeplayer/services/mpv_image_enhancement.dart';
import 'package:aloeplayer/widgets/image_enhancement_sheet.dart';
import 'package:aloeplayer/theme/app_theme.dart';

class SheetBackend implements MpvImageBackend {
  final values = <String, String>{'scale': 'bilinear', 'cscale': 'bilinear', 'glsl-shaders': '',
    'deband': 'no', 'brightness': '0', 'contrast': '0', 'saturation': '0', 'gamma': '0'};
  @override Future<String> read(String key) async => values[key] ?? '';
  @override Future<void> write(String key, String value) async { values[key] = value; }
  @override Future<void> resize(int? width, int? height) async {}
}

void main() {
  testWidgets('GPU fallback synchronizes visible color sliders and does not resurrect the failed preset', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final engine = MpvImageEnhancer(backend: SheetBackend());
    await engine.apply(const ImageEnhancementSettings(mode: UpscaleMode.highQuality, brightness: 20));
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: buildAloeTheme(Brightness.dark),
      home: Scaffold(body: ImageEnhancementSheet(enhancer: engine))));
    await tester.pumpAndSettle();
    await engine.shaderFailed();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('亮度'), 200);
    await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(find.byType(Slider).first);
    expect(slider.value, 0);
    slider.onChangeEnd!(8);
    await tester.pumpAndSettle();
    expect(engine.settings.mode, UpscaleMode.off);
    expect(engine.settings.brightness, 8);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    engine.dispose();
  });
}
