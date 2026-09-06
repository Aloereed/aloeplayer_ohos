import 'package:aloeplayer/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const key = 'use_ffmpeg_for_play_2';

  for (final retired in [1, 3]) {
    test('saved engine $retired migrates to MPV and stays migrated', () async {
      SharedPreferences.setMockInitialValues({key: retired});
      expect(await SettingsService().getUseFfmpegForPlay(), 2);
      expect((await SharedPreferences.getInstance()).getInt(key), 2);
      expect(await SettingsService().getUseFfmpegForPlay(), 2);
    });

    test('saving retired engine $retired selects MPV', () async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService().saveUseFfmpegForPlay(retired);
      expect((await SharedPreferences.getInstance()).getInt(key), 2);
    });
  }

  for (final engine in [0, 2, 4]) {
    test('supported engine $engine is preserved', () async {
      SharedPreferences.setMockInitialValues({key: engine});
      final settings = SettingsService();
      expect(await settings.getUseFfmpegForPlay(), engine);
      await settings.saveUseFfmpegForPlay(engine);
      expect((await SharedPreferences.getInstance()).getInt(key), engine);
    });
  }

  test('new users default to MPV', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await SettingsService().getUseFfmpegForPlay(), 2);
  });
}
