import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/disk_thumbnail_cache.dart';
import 'package:aloeplayer/services/thumbnail_cache.dart';

void main() {
  test('disk budget evicts least-recently-used owned thumbnails only', () async {
    final directory = await Directory.systemTemp.createTemp('aloe-thumbnails-');
    final a = ThumbnailCache.key('a', 1, 1), b = ThumbnailCache.key('b', 1, 1), c = ThumbnailCache.key('c', 1, 1);
    try {
      final unrelated = await File('${directory.path}/poster.jpg').writeAsBytes([9]);
      final cache = DiskThumbnailCache(directory, maxBytes: 6);
      await cache.write(a, Uint8List.fromList([1, 2, 3]));
      await cache.write(b, Uint8List.fromList([4, 5, 6]));
      await cache.read(a);
      await cache.write(c, Uint8List.fromList([7, 8, 9]));
      expect(await cache.read(b), isNull);
      expect(await cache.read(a), [1, 2, 3]);
      expect(await cache.read(c), [7, 8, 9]);
      expect(await unrelated.readAsBytes(), [9]);
      await expectLater(cache.read('../poster'), throwsArgumentError);
      expect(await cache.read(a), [1, 2, 3]);
    } finally { await directory.delete(recursive: true); }
  });
}
