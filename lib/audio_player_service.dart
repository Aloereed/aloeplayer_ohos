/*
 * @Author: 
 * @Date: 2025-03-08 16:38:50
 * @LastEditors: Please set LastEditors
 * @LastEditTime: 2025-03-09 18:00:57
 * @Description: file content
 */
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'settings.dart';

// 循环模式枚举：关闭、全部循环、单曲循环
enum LoopMode { off, all, one }

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
      title = metadata.title ?? currentFilePath!.split('/').last;
      artist = metadata.artist ?? 'Unknown Artist';
      album = metadata.album ?? 'Unknown Album';
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
