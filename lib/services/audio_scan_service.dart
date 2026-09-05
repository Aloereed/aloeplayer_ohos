import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'thumbnail_cache.dart';
import 'work_queue.dart';

class AudioScanResult {
  final String title, artist, album;
  final int track;
  const AudioScanResult(this.title, this.artist, this.album, this.track);
}

// Top-level functions keep the worker isolate free of State and platform channels.
Future<AudioScanResult> _readTags(String source) => Isolate.run(() {
  final tags = readMetadata(File(source), getImage: false);
  return AudioScanResult(tags.title ?? '', tags.artist ?? '', tags.album ?? '', tags.trackNumber ?? 0);
});
Future<Uint8List?> readAudioArtwork(String source) => Isolate.run(() {
  final tags = readMetadata(File(source), getImage: true);
  return tags.pictures.isEmpty ? null : tags.pictures.first.bytes;
});

class AudioScanService {
  final _cache = LinkedHashMap<String, AudioScanResult>();
  final Map<String, Future<AudioScanResult>> _pending = {};
  final _queue = WorkQueue();
  Future<AudioScanResult> read(String source) async {
    final key = await ThumbnailCache.fileKey(source);
    final existing = _cache.remove(key);
    if (existing != null) { _cache[key] = existing; return existing; }
    return _pending.putIfAbsent(key, () => _queue.run(() async {
      final result = await _readTags(source);
      _cache[key] = result;
      while (_cache.length > 2000) { _cache.remove(_cache.keys.first); }
      return result;
    }).whenComplete(() { _pending.remove(key); }));
  }
}
