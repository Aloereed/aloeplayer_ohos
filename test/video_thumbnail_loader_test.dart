import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/disk_thumbnail_cache.dart';
import 'package:aloeplayer/services/thumbnail_cache.dart';
import 'package:aloeplayer/services/video_thumbnail_loader.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('aloe-thumb-loader-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  test('unwritable cache does not hide decoded bytes or break memory cache',
      () async {
    final video = await File('${root.path}/movie.mp4').writeAsBytes([0]);
    final blocked = await File('${root.path}/blocked').writeAsBytes([0]);
    var calls = 0;
    final loader = VideoThumbnailLoader(
        disk: DiskThumbnailCache(Directory(blocked.path)),
        memory: ThumbnailCache(),
        library: root,
        decode: (_) async {
          calls++;
          return Uint8List.fromList([1, 2, 3]);
        });
    expect(await loader.load(video), [1, 2, 3]);
    expect(await loader.load(video), [1, 2, 3]);
    expect(calls, 1);
  });
  test(
      'legacy thumbnail recovers decoder failure but rejects basename collisions',
      () async {
    final video = await File('${root.path}/movie.mp4').writeAsBytes([0]);
    await video.setLastModified(DateTime(2020));
    final cache = await Directory('${root.path}/thumbs').create();
    await File('${cache.path}/movie.mp4.jpg').writeAsBytes([9]);
    VideoThumbnailLoader loader() => VideoThumbnailLoader(
        disk: DiskThumbnailCache(cache),
        memory: ThumbnailCache(),
        library: root,
        decode: (_) async => null);
    expect(await loader().load(video), [9]);
    // A new revision misses the migrated hash and must not use an ambiguous name.
    await video.writeAsBytes([0, 1]);
    await video.setLastModified(DateTime(2021));
    final sub = await Directory('${root.path}/sub').create();
    await File('${sub.path}/movie.mp4').writeAsBytes([2]);
    expect(await loader().load(video), isNull);
  });
  test('shortcut target revision invalidates cached thumbnail', () async {
    final target = await File('${root.path}/movie.mp4').writeAsBytes([0]);
    final link = await File('${root.path}/movie.lnk')
        .writeAsString(target.uri.toString());
    var calls = 0;
    final loader = VideoThumbnailLoader(
        disk: DiskThumbnailCache(Directory('${root.path}/cache')),
        memory: ThumbnailCache(),
        library: root,
        decode: (_) async => Uint8List.fromList([++calls]));
    expect(await loader.load(link), [1]);
    await target.writeAsBytes([0, 1]);
    expect(await loader.load(link), [2]);
  });
  test('fallback runs only after system failure and its result is cached', () async {
    final video = await File('${root.path}/movie.mkv').writeAsBytes([0]);
    var primaryCalls = 0, fallbackCalls = 0;
    final loader = VideoThumbnailLoader(
      disk: DiskThumbnailCache(Directory('${root.path}/cache')),
      memory: ThumbnailCache(), library: root,
      decode: (_) async { primaryCalls++; throw StateError('unsupported system codec'); },
      fallbackDecode: (source) async {
        expect(source, video.path);
        fallbackCalls++; return Uint8List.fromList([7, 8]);
      });
    expect(await loader.load(video), [7, 8]);
    expect(await loader.load(video), [7, 8]);
    expect(primaryCalls, 1);
    expect(fallbackCalls, 1);
  });
  test('a working system decoder never starts the expensive fallback', () async {
    final video = await File('${root.path}/movie.mp4').writeAsBytes([0]);
    var fallbackCalls = 0;
    final loader = VideoThumbnailLoader(
      disk: DiskThumbnailCache(Directory('${root.path}/cache')),
      memory: ThumbnailCache(), library: root,
      decode: (_) async => Uint8List.fromList([4]),
      fallbackDecode: (_) async { fallbackCalls++; return null; });
    expect(await loader.load(video), [4]);
    expect(fallbackCalls, 0);
  });
}
