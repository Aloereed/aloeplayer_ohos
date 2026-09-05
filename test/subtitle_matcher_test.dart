import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/subtitle_matcher.dart';
void main() {
  test('exact episode boundary and preferred language beat directory order', () {
    final matched = matchSubtitles('episode1.mkv', ['episode10.srt', 'episode1.en.srt', 'episode1.srt', 'episode1.zh.ass'], preferredLanguage: 'zh,zho');
    expect(matched, ['episode1.zh.ass', 'episode1.srt', 'episode1.en.srt']);
  });
}
