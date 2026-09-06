import 'package:aloeplayer/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('HDR mode changes notify library listeners after persisting the setting', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    final modes = <Future<int>>[];
    void changed() => modes.add(settings.getHdrDetect());
    SettingsService.hdrDetectionChanges.addListener(changed);
    addTearDown(() => SettingsService.hdrDetectionChanges.removeListener(changed));

    for (final mode in [1, 2, 0]) {
      await settings.saveHdrDetect(mode);
      expect(await modes.last, mode);
    }
    expect(modes, hasLength(3));
  });
}
