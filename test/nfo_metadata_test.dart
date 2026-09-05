import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/models/catalog_item.dart';
void main() {
  test('NFO preserves episode identity and decodes escaped plot', () {
    final nfo = NfoMetadata.parse('<episodedetails><title>回归</title><showtitle>测试剧集</showtitle><season>2</season><episode>3</episode><plot>A &amp; B</plot></episodedetails>');
    expect(nfo.title, '回归');
    expect(nfo.showTitle, '测试剧集');
    expect(nfo.season, 2);
    expect(nfo.episode, 3);
    expect(nfo.plot, 'A & B');
  });
}
