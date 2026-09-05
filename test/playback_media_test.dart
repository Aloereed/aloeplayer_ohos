import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/models/playback_media.dart';

void main() {
  test('remote identity separates servers and roundtrips special characters', () {
    const file = '/电影/100% #1.mkv';
    final id = PlaybackMedia.remoteId('server-a', file);
    expect(id, isNot(PlaybackMedia.remoteId('server-b', file)));
    expect(Uri.decodeComponent(Uri.parse(id).path), file);
    expect(PlaybackMedia.isRemote(id), isTrue);
    expect(PlaybackMedia.isRemote('https://example.com/movie'), isFalse);
  });
}
