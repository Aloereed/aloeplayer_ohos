import 'package:flutter/services.dart';

class AudioMetadata {
  static const MethodChannel _channel =
      MethodChannel('samples.flutter.dev/ffmpegplugin');

  // 读取标题
  static Future<String> getTitle(String filename) async {
    try {
      final String title =
          await _channel.invokeMethod('getTitle', {'filename': filename});
      return title;
    } on PlatformException catch (e) {
      print("Failed to get title: ${e.message}");
      return "";
    }
  }

  // 设置标题
  static Future<void> setTitle(String filename, String title) async {
    try {
      await _channel
          .invokeMethod('setTitle', {'filename': filename, 'value': title});
    } on PlatformException catch (e) {
      print("Failed to set title: ${e.message}");
      rethrow;
    }
  }

  // 读取艺术家
  static Future<String> getArtist(String filename) async {
    try {
      final String artist =
          await _channel.invokeMethod('getArtist', {'filename': filename});
      return artist;
    } on PlatformException catch (e) {
      print("Failed to get artist: ${e.message}");
      return "";
    }
  }

  // 设置艺术家
  static Future<void> setArtist(String filename, String artist) async {
    try {
      await _channel
          .invokeMethod('setArtist', {'filename': filename, 'value': artist});
    } on PlatformException catch (e) {
      print("Failed to set artist: ${e.message}");
      rethrow;
    }
  }

  // 读取专辑
  static Future<String> getAlbum(String filename) async {
    try {
      final String album =
          await _channel.invokeMethod('getAlbum', {'filename': filename});
      return album;
    } on PlatformException catch (e) {
      print("Failed to get album: ${e.message}");
      return "";
    }
  }

  // 设置专辑
  static Future<void> setAlbum(String filename, String album) async {
    try {
      await _channel
          .invokeMethod('setAlbum', {'filename': filename, 'value': album});
    } on PlatformException catch (e) {
      print("Failed to set album: ${e.message}");
      rethrow;
    }
  }

  // 读取年份
  static Future<int> getYear(String filename) async {
    try {
      final int year =
          await _channel.invokeMethod('getYear', {'filename': filename});
      return year;
    } on PlatformException catch (e) {
      print("Failed to get year: ${e.message}");
      return 0;
    }
  }

  // 设置年份
  static Future<void> setYear(String filename, int year) async {
    try {
      await _channel
          .invokeMethod('setYear', {'filename': filename, 'value': year});
    } on PlatformException catch (e) {
      print("Failed to set year: ${e.message}");
      rethrow;
    }
  }

  // 读取音轨号
  static Future<int> getTrack(String filename) async {
    try {
      final int track =
          await _channel.invokeMethod('getTrack', {'filename': filename});
      return track;
    } on PlatformException catch (e) {
      print("Failed to get track: ${e.message}");
      return 0;
    }
  }

  // 设置音轨号
  static Future<void> setTrack(String filename, int track) async {
    try {
      await _channel
          .invokeMethod('setTrack', {'filename': filename, 'value': track});
    } on PlatformException catch (e) {
      print("Failed to set track: ${e.message}");
      rethrow;
    }
  }

  // 读取碟号
  static Future<int> getDisc(String filename) async {
    try {
      final int disc =
          await _channel.invokeMethod('getDisc', {'filename': filename});
      return disc;
    } on PlatformException catch (e) {
      print("Failed to get disc: ${e.message}");
      return 0;
    }
  }

  // 设置碟号
  static Future<void> setDisc(String filename, int disc) async {
    try {
      await _channel
          .invokeMethod('setDisc', {'filename': filename, 'value': disc});
    } on PlatformException catch (e) {
      print("Failed to set disc: ${e.message}");
      rethrow;
    }
  }

  // 读取风格
  static Future<String> getGenre(String filename) async {
    try {
      final String genre =
          await _channel.invokeMethod('getGenre', {'filename': filename});
      return genre;
    } on PlatformException catch (e) {
      print("Failed to get genre: ${e.message}");
      return "";
    }
  }

  // 设置风格
  static Future<void> setGenre(String filename, String genre) async {
    try {
      await _channel
          .invokeMethod('setGenre', {'filename': filename, 'value': genre});
    } on PlatformException catch (e) {
      print("Failed to set genre: ${e.message}");
      rethrow;
    }
  }

  // 读取专辑艺术家
  static Future<String> getAlbumArtist(String filename) async {
    try {
      final String albumArtist =
          await _channel.invokeMethod('getAlbumArtist', {'filename': filename});
      return albumArtist;
    } on PlatformException catch (e) {
      print("Failed to get album artist: ${e.message}");
      return "";
    }
  }

  // 设置专辑艺术家
  static Future<void> setAlbumArtist(
      String filename, String albumArtist) async {
    try {
      await _channel.invokeMethod(
          'setAlbumArtist', {'filename': filename, 'value': albumArtist});
    } on PlatformException catch (e) {
      print("Failed to set album artist: ${e.message}");
      rethrow;
    }
  }

  // 读取作曲
  static Future<String> getComposer(String filename) async {
    try {
      final String composer =
          await _channel.invokeMethod('getComposer', {'filename': filename});
      return composer;
    } on PlatformException catch (e) {
      print("Failed to get composer: ${e.message}");
      return "";
    }
  }

  // 设置作曲
  static Future<void> setComposer(String filename, String composer) async {
    try {
      await _channel.invokeMethod(
          'setComposer', {'filename': filename, 'value': composer});
    } on PlatformException catch (e) {
      print("Failed to set composer: ${e.message}");
      rethrow;
    }
  }

  // 读取作词
  static Future<String> getLyricist(String filename) async {
    try {
      final String lyricist =
          await _channel.invokeMethod('getLyricist', {'filename': filename});
      return lyricist;
    } on PlatformException catch (e) {
      print("Failed to get lyricist: ${e.message}");
      return "";
    }
  }

  // 设置作词
  static Future<void> setLyricist(String filename, String lyricist) async {
    try {
      await _channel.invokeMethod(
          'setLyricist', {'filename': filename, 'value': lyricist});
    } on PlatformException catch (e) {
      print("Failed to set lyricist: ${e.message}");
      rethrow;
    }
  }

  // 读取注释
  static Future<String> getComment(String filename) async {
    try {
      final String comment =
          await _channel.invokeMethod('getComment', {'filename': filename});
      return comment;
    } on PlatformException catch (e) {
      print("Failed to get comment: ${e.message}");
      return "";
    }
  }

  // 设置注释
  static Future<void> setComment(String filename, String comment) async {
    try {
      await _channel
          .invokeMethod('setComment', {'filename': filename, 'value': comment});
    } on PlatformException catch (e) {
      print("Failed to set comment: ${e.message}");
      rethrow;
    }
  }

  // 读取歌词
// 读取歌词
  static Future<String> getLyrics(String filename) async {
    try {
      final String lyrics =
          await _channel.invokeMethod('getLyrics', {'filename': filename});
      return lyrics;
    } on PlatformException catch (e) {
      print("Failed to get lyrics: ${e.message}");
      return "";
    }
  }

  // 设置歌词
  static Future<void> setLyrics(String filename, String lyrics) async {
    try {
      await _channel
          .invokeMethod('setLyrics', {'filename': filename, 'value': lyrics});
    } on PlatformException catch (e) {
      print("Failed to set lyrics: ${e.message}");
      rethrow;
    }
  }

  // 读取封面（返回 base64 编码的图片数据）
  static Future<String> getCover(String filename) async {
    try {
      final String cover =
          await _channel.invokeMethod('getCover', {'filename': filename});
      return cover;
    } on PlatformException catch (e) {
      print("Failed to get cover: ${e.message}");
      return "";
    }
  }

  // 设置封面（接受 base64 编码的图片数据）
  static Future<void> setCover(String filename, String coverBase64) async {
    try {
      await _channel.invokeMethod(
          'setCover', {'filename': filename, 'value': coverBase64});
    } on PlatformException catch (e) {
      print("Failed to set cover: ${e.message}");
      rethrow;
    }
  }
}