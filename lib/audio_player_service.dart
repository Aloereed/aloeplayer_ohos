/*
 * @Author: 
 * @Date: 2025-03-08 16:38:50
 * @LastEditors: Please set LastEditors
 * @LastEditTime: 2025-03-16 18:58:39
 * @Description: file content
 */
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:path/path.dart' as path;
import 'settings.dart';

// 循环模式枚举：关闭、全部循环、单曲循环
enum LoopMode { off, all, one, random }

class AudioPlayerService {
  static final AudioPlayerService _instance = AudioPlayerService._internal();
  factory AudioPlayerService() => _instance;
  final _settingsService = SettingsService();
  AudioPlayerService._internal();
  final _controllerChangeController = StreamController<String>.broadcast();
  Stream<String> get controllerChangeStream => _controllerChangeController.stream;

  VideoPlayerController? controller;
  String? currentFilePath;
  String title = '';
  String artist = '';
  String album = '';
  LoopMode loopMode = LoopMode.off;
  Uint8List? coverBytes;
  List<Map<String, String>> playlist = [];
  int currentIndex = 0;
  bool firstPlay = true;

  // 标志位，用于跟踪是否正在处理歌曲结束时的过渡操作
  bool _isHandlingCompletion = false;

  // 用于广播播放器状态变化的流
  final _playerStateController = StreamController<PlayerState>.broadcast();
  Stream<PlayerState> get playerStateStream => _playerStateController.stream;

  // 循环模式切换方法
  void toggleLoopMode() {
    switch (loopMode) {
      case LoopMode.off:
        loopMode = LoopMode.all;
        break;
      case LoopMode.all:
        loopMode = LoopMode.one;
        break;
      case LoopMode.one:
        loopMode = LoopMode.random;
        break;
      case LoopMode.random:
        loopMode = LoopMode.off;
        break;
    }
  }

  // 更新播放器状态并通过流广播
  void updatePlayerState() {
    if (controller != null) {
      _playerStateController.add(
        PlayerState(
          isPlaying: controller!.value.isPlaying,
          position: controller!.value.position,
          duration: controller!.value.duration,
        ),
      );
    }
  }

  // 释放资源
  void dispose() {
    _playerStateController.close();
    _controllerChangeController.close(); // 添加这一行
    controller?.dispose();
  }

  // 开始播放新的音频文件
  Future<void> startNewPlay(String path) async {
    print("AudioPlayerService startNewPlay $path");
    currentFilePath = path;
    controller?.dispose();
    await _initPlayer();
    // 通知控制器已更改
    _controllerChangeController.add(path);
  }

  // 初始化播放器
  Future<void> _initPlayer() async {
    firstPlay = true;
    _isHandlingCompletion = false; // 重置标志位

    if (currentFilePath == null) {
      return;
    }

    // 获取后台播放设置
    final isBgPlay = await _settingsService.getBackgroundPlay();

    // 创建并初始化播放器
    controller = VideoPlayerController.file(File(currentFilePath!),
        videoPlayerOptions: VideoPlayerOptions(
            allowBackgroundPlayback: isBgPlay, mixWithOthers: true))
      ..initialize().then((_) {
        controller!.play();
        updatePlayerState();
      });

    // 读取音频文件元数据
    List<String> includeExts = ['mp3', 'm4a', 'flac', 'ogg'];
    if (includeExts.contains(currentFilePath?.split('.').last)) {
      final metadata =
          await readMetadata(File(currentFilePath!), getImage: true);
      String titleTmp = await AudioMetadata.getTitle(currentFilePath!);
      String artistTmp = await AudioMetadata.getArtist(currentFilePath!);
      String albumTmp = await AudioMetadata.getAlbum(currentFilePath!);
      title =
          titleTmp.isNotEmpty ? titleTmp : path.basenameWithoutExtension(currentFilePath!);
      artist = artistTmp.isNotEmpty ? artistTmp : 'Unknown Artist';
      album = albumTmp.isNotEmpty ? albumTmp : 'Unknown Album';
      coverBytes =
          metadata.pictures.isNotEmpty ? metadata.pictures[0].bytes : null;
    } else {
      title = currentFilePath!.split('/').last;
      artist = 'Unknown Artist';
      album = 'Unknown Album';
      coverBytes = null;
    }

    // 监听播放位置
    controller?.addListener(() {
      updatePlayerState();

      // 仅在接近歌曲结尾且未处于过渡状态时处理
      if (!_isHandlingCompletion &&
          (controller!.value.position >= controller!.value.duration ||
              (controller!.value.position == Duration.zero &&
                  !controller!.value.isPlaying))) {
        _isHandlingCompletion = true;

        switch (loopMode) {
          case LoopMode.off:
            // 不循环，停止播放
            break;
          case LoopMode.all:
          case LoopMode.random:
            // 循环整个列表
            if (!firstPlay) {
              // 使用延迟避免立即调用playNext
              Future.delayed(Duration(milliseconds: 100), () {
                if (controller!.value.position == Duration.zero &&
                    !controller!.value.isPlaying)
                  playNext().then((_) {
                    // 过渡完成后重置标志位
                    Future.delayed(Duration(seconds: 1), () {
                      _isHandlingCompletion = false;
                    });
                  });
              });
            }
            break;
          case LoopMode.one:
            // 单曲循环
            controller!.seekTo(Duration.zero);
            controller!.play();
            _isHandlingCompletion = false; // 单曲循环立即重置标志位
            break;
        }
      } else if (controller!.value.position <
          controller!.value.duration - Duration(seconds: 1)) {
        // 不在歌曲结尾附近，重置标志位
        _isHandlingCompletion = false;
      }
    });

    controller?.play();
    firstPlay = false;
  }

  // 外部添加监听器
  void externalAddListener() {
    firstPlay = true;
    _isHandlingCompletion = false;

    controller?.addListener(() {
      updatePlayerState();

      // 检测歌曲是否结束
      if (!_isHandlingCompletion &&
          (controller!.value.position >= controller!.value.duration ||
              (controller!.value.position == Duration.zero &&
                  !controller!.value.isPlaying))) {
        _isHandlingCompletion = true;

        switch (loopMode) {
          case LoopMode.off:
            // 不循环，停止播放
            break;
          case LoopMode.all:
          case LoopMode.random:
            // 循环整个列表
            if (!firstPlay) {
              Future.delayed(Duration(milliseconds: 100), () {
                if (controller!.value.position == Duration.zero &&
                    !controller!.value.isPlaying)
                playNext().then((_) {
                  Future.delayed(Duration(seconds: 1), () {
                    _isHandlingCompletion = false;
                  });
                });
              });
            }
            break;
          case LoopMode.one:
            // 单曲循环
            controller!.seekTo(Duration.zero);
            controller!.play();
            _isHandlingCompletion = false;
            break;
        }
      } else if (controller!.value.position <
          controller!.value.duration - Duration(seconds: 1)) {
        _isHandlingCompletion = false;
      }
    });
  }

  // 播放下一首歌
  Future<void> playNext() async {
    if (playlist.isEmpty || playlist.length == 1) {
      return;
    }

    if(loopMode==LoopMode.random){
      // 随机播放
      Random random = Random();
      int randomIndex = random.nextInt(playlist.length);
      await startNewPlay(playlist[randomIndex]['path']!);
      return;
    }

    // 获取当前播放项的索引
    int currentIndex =
        playlist.indexWhere((item) => item['path'] == currentFilePath);
    if (currentIndex == -1) {
      currentIndex = 0; // 如果未找到，默认为第一项
    }

    // 计算下一首的索引
    int nextIndex =
        (currentIndex == playlist.length - 1) ? 0 : currentIndex + 1;

    // 这是手动切换，无论_isHandlingCompletion状态如何都执行
    await startNewPlay(playlist[nextIndex]['path']!);
  }

  // 播放上一首歌
  Future<void> playPrevious() async {
    if (playlist.isEmpty || playlist.length == 1) {
      return;
    }

    // 获取当前播放项的索引
    int currentIndex =
        playlist.indexWhere((item) => item['path'] == currentFilePath);
    if (currentIndex == -1) {
      currentIndex = 0; // 如果未找到，默认为第一项
    }

    // 计算上一首的索引
    int prevIndex =
        (currentIndex == 0) ? playlist.length - 1 : currentIndex - 1;

    // 这是手动切换，无论_isHandlingCompletion状态如何都执行
    await startNewPlay(playlist[prevIndex]['path']!);
  }
}

// 播放器状态模型类
class PlayerState {
  final bool isPlaying;
  final Duration position;
  final Duration duration;

  PlayerState({
    required this.isPlaying,
    required this.position,
    required this.duration,
  });
}

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
    }
  }
}