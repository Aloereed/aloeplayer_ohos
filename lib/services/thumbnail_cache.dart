import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Bounded memory cache. Keys include a file revision so replacements invalidate.
class ThumbnailCache {
  final int maxBytes;
  final LinkedHashMap<String, Uint8List> _items = LinkedHashMap();
  int _bytes = 0;
  ThumbnailCache({this.maxBytes = 16 * 1024 * 1024});

  static String key(String source, int size, int modifiedMs) =>
      sha256.convert(utf8.encode('$source\u0000$size\u0000$modifiedMs')).toString();

  static Future<String> fileKey(String source) async {
    final stat = await File(source).stat();
    return key(source, stat.size, stat.modified.millisecondsSinceEpoch);
  }

  Uint8List? get(String key) {
    final value = _items.remove(key);
    if (value != null) _items[key] = value;
    return value;
  }

  void put(String key, Uint8List value) {
    final old = _items.remove(key);
    _bytes -= old?.length ?? 0;
    if (value.length <= maxBytes) {
      _items[key] = value;
      _bytes += value.length;
    }
    while (_bytes > maxBytes && _items.isNotEmpty) {
      _bytes -= _items.remove(_items.keys.first)!.length;
    }
  }
  void remove(String key) {
    _bytes -= _items.remove(key)?.length ?? 0;
  }
}
