import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/thumbnail_cache.dart';

void main() {
  test('same basename in different folders and replacements do not collide', () {
    final original = ThumbnailCache.key('/a/movie.mp4', 42, 1);
    expect(original, isNot(ThumbnailCache.key('/b/movie.mp4', 42, 1)));
    expect(original, isNot(ThumbnailCache.key('/a/movie.mp4', 42, 2)));
  });
  test('memory budget evicts least recently used entries', () {
    final cache = ThumbnailCache(maxBytes: 4);
    cache.put('a', Uint8List(2));
    cache.put('b', Uint8List(2));
    cache.get('a');
    cache.put('c', Uint8List(2));
    expect(cache.get('a'), isNotNull);
    expect(cache.get('b'), isNull);
    expect(cache.get('c'), isNotNull);
  });
}
