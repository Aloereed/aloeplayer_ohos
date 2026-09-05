import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aloeplayer/services/playback_tools_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('preferences persist separately for each media', () async {
    await PlaybackToolsStore.savePreferences('server-a/movie', const PlaybackPreferences(subtitleDelay: 1.2, audioDelay: -0.3, subtitleTrack: 'no'));
    final saved = await PlaybackToolsStore.preferences('server-a/movie');
    expect(saved.subtitleDelay, 1.2);
    expect(saved.audioDelay, -0.3);
    expect(saved.subtitleTrack, 'no');
    expect((await PlaybackToolsStore.preferences('server-b/movie')).subtitleDelay, 0);
  });
  test('named loop bookmarks preserve both boundaries', () async {
    await PlaybackToolsStore.saveBookmarks('movie', [const MediaBookmark('练习', 12000, endMs: 34000)]);
    final saved = (await PlaybackToolsStore.bookmarks('movie')).single;
    expect(saved.name, '练习');
    expect(saved.positionMs, 12000);
    expect(saved.endMs, 34000);
    await PlaybackToolsStore.saveBookmarks('movie', []);
    expect(await PlaybackToolsStore.bookmarks('movie'), isEmpty);
  });
}
