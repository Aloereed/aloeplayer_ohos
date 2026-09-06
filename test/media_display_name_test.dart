import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/media_display_name.dart';

void main() {
  test('Chinese filesystem names and encoded URI names render identically', () {
    const name = '旅行 100%+#片段.mp4';
    expect(mediaDisplayName('/storage/Videos/$name'), name);
    expect(mediaDisplayName(Uri(scheme: 'file', host: 'docs', path: '/Videos/$name').toString()), name);
    expect(mediaDisplayName('https://nas.home/${Uri.encodeComponent(name)}?token=secret'), name);
    expect(mediaDisplayName(r'E:\Videos\中文.mp4'), '中文.mp4');
  });
  test('literal percent escapes are preserved and URI escapes decode only once', () {
    expect(mediaDisplayName('/Videos/%E4%B8%AD.mp4'), '%E4%B8%AD.mp4');
    expect(mediaDisplayName('file:///Videos/%2520.mp4'), '%20.mp4');
    expect(mediaDisplayName('/Videos/100%.mp4'), '100%.mp4');
  });
}
