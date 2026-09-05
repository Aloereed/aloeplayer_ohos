import 'services/sleep_timer.dart';
/*
 * @Author:
 * @Date: 2025-11-16
 * @LastEditors: Please set LastEditors
 * @LastEditTime: 2025-11-16 20:32:07
 * @Description: MediaKit音乐播放器服务
 */
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:audio_metadata_reader/audio_metadata_reader.dart' hide AudioMetadata;
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as path;
import 'settings.dart';
import 'audio_handler.dart';
import 'audio_metadata.dart';

// 循环模式枚举：关闭、全部循环、单曲循环、随机
enum MediaKitLoopMode { off, all, one, random }

class MediaKitAudioService {
  static final MediaKitAudioService _instance = MediaKitAudioService._internal();
  factory MediaKitAudioService() => _instance;
  final _settingsService = SettingsService();
  MediaKitAudioService._internal();

  final _controllerChangeController = StreamController<String>.broadcast();
  Stream<String> get controllerChangeStream => _controllerChangeController.stream;

  // MediaKit 播放器
  Player? player;
  VideoController? videoController;

  String? currentFilePath;
  String title = '';
  String artist = '';
  String album = '';
  MediaKitLoopMode loopMode = MediaKitLoopMode.off;
  Uint8List? coverBytes;
  List<Map<String, String>> playlist = [];
  int currentIndex = 0;
  bool firstPlay = true;

  // AudioHandler 实例
  MediaKitAudioHandler? _audioHandler;

  // 标志位，用于跟踪是否正在处理歌曲结束时的过渡操作
  bool _isHandlingCompletion = false;

  // 用于广播播放器状态变化的流
  final _playerStateController = StreamController<MediaKitPlayerState>.broadcast();
  Stream<MediaKitPlayerState> get playerStateStream => _playerStateController.stream;

  // 初始化 AudioHandler
  Future<void> initAudioHandler() async {
    if (_audioHandler != null) return;

    _audioHandler = await AudioService.init(
      builder: () => MediaKitAudioHandler(
        onPlay: () {
          player?.play();
          updatePlayerState();
        },
        onPause: () {
          player?.pause();
          updatePlayerState();
        },
        onStop: () {
          player?.pause();
          updatePlayerState();
        },
        onSeek: (position) {
          player?.seek(position);
          updatePlayerState();
        },
        onSetSpeed: (speed) {
          player?.setRate(speed);
          updatePlayerState();
        },
        onFastForward: (duration) {
          final currentPos = player?.state.position ?? Duration.zero;
          player?.seek(currentPos + duration);
          updatePlayerState();
        },
        onRewind: (duration) {
          final currentPos = player?.state.position ?? Duration.zero;
          player?.seek(currentPos - duration);
          updatePlayerState();
        },
        isPlaying: () => player?.state.playing ?? false,
        getCurrentPosition: () => player?.state.position ?? Duration.zero,
        getDuration: () => player?.state.duration ?? Duration.zero,
        getPlaybackSpeed: () => player?.state.rate ?? 1.0,
        onPlayNext: () => playNext(),
        onPlayPrevious: () => playPrevious(),
      ),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.aloereed.aloeplayer.channel.audio',
        androidNotificationChannelName: 'AloePlayer',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
  }

  // 循环模式切换方法
  void toggleLoopMode() {
    switch (loopMode) {
      case MediaKitLoopMode.off:
        loopMode = MediaKitLoopMode.all;
        break;
      case MediaKitLoopMode.all:
        loopMode = MediaKitLoopMode.one;
        break;
      case MediaKitLoopMode.one:
        loopMode = MediaKitLoopMode.random;
        break;
      case MediaKitLoopMode.random:
        loopMode = MediaKitLoopMode.off;
        break;
    }
  }

  // 更新播放器状态并通过流广播
  void updatePlayerState() {
    if (player != null) {
      _playerStateController.add(
        MediaKitPlayerState(
          isPlaying: player!.state.playing,
          position: player!.state.position,
          duration: player!.state.duration,
          title: title,
          artist: artist,
          album: album,
          coverBytes: coverBytes,
        ),
      );

      // 更新 AudioHandler 的播放状态
      _audioHandler?.updatePlaybackState();
    }
  }

  // 释放资源
  void dispose() {
    PlaybackSleepTimer.instance.detach(this);
    _playerStateController.close();
    _controllerChangeController.close();
    player?.dispose();
  }

  // 开始播放新的音频文件
  Future<void> startNewPlay(String filePath) async {
    print("MediaKitAudioService startNewPlay $filePath");
    currentFilePath = filePath;
    await _initPlayer();
    // 通知控制器已更改
    _controllerChangeController.add(filePath);
  }

  // 初始化播放器
  Future<void> _initPlayer() async {
    PlaybackSleepTimer.instance.attach(this, () async { await player?.pause(); });
    firstPlay = true;
    _isHandlingCompletion = false;

    if (currentFilePath == null) {
      return;
    }

    // 创建 MediaKit 播放器
    if (player == null) {
      player = Player();
      videoController = VideoController(player!);

      // 监听播放完成事件
      player!.stream.completed.listen((completed) {
        if (completed && PlaybackSleepTimer.instance.consumeEnd(this)) return;
        if (completed && !_isHandlingCompletion) {
          _isHandlingCompletion = true;
          _handleCompletion();
        }
      });

      // 监听播放位置变化
      player!.stream.position.listen((position) {
        updatePlayerState();
      });

      // 监听播放状态变化
      player!.stream.playing.listen((playing) {
        updatePlayerState();
      });
    }

    // 打开音频文件
    await player!.open(Media(currentFilePath!));

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

    // 更新 AudioHandler 的媒体信息
    await _updateMediaItem();

    player!.play();
    firstPlay = false;

    // 更新播放器状态以触发 UI 更新
    updatePlayerState();
  }

  // 处理播放完成
  void _handleCompletion() {
    switch (loopMode) {
      case MediaKitLoopMode.off:
        // 不循环，停止播放
        _isHandlingCompletion = false;
        break;
      case MediaKitLoopMode.all:
      case MediaKitLoopMode.random:
        // 循环整个列表
        if (!firstPlay) {
          Future.delayed(Duration(milliseconds: 100), () {
            playNext().then((_) {
              Future.delayed(Duration(seconds: 1), () {
                _isHandlingCompletion = false;
              });
            });
          });
        }
        break;
      case MediaKitLoopMode.one:
        // 单曲循环
        player!.seek(Duration.zero);
        player!.play();
        _isHandlingCompletion = false;
        break;
    }
  }

  // 播放下一首歌
  Future<void> playNext() async {
    if (playlist.isEmpty || playlist.length == 1) {
      return;
    }

    if (loopMode == MediaKitLoopMode.random) {
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
      currentIndex = 0;
    }

    // 计算下一首的索引
    int nextIndex =
        (currentIndex == playlist.length - 1) ? 0 : currentIndex + 1;

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
      currentIndex = 0;
    }

    // 计算上一首的索引
    int prevIndex =
        (currentIndex == 0) ? playlist.length - 1 : currentIndex - 1;

    await startNewPlay(playlist[prevIndex]['path']!);
  }

  Future<void> updateMediaItem() async {
    await _updateMediaItem();
  }

  // 更新 AudioHandler 的媒体信息
  Future<void> _updateMediaItem() async {
    if (_audioHandler == null || currentFilePath == null) return;

    // 创建临时文件用于封面
    File? artFile;
    if (coverBytes != null) {
      final tempDir = Directory.systemTemp;
      artFile = File('${tempDir.path}/aloeplayer_cover_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await artFile.writeAsBytes(coverBytes!);
    }

    _audioHandler!.mediaItem.add(
      MediaItem(
        id: currentFilePath!,
        album: album,
        title: title,
        artist: artist,
        duration: player?.state.duration ?? Duration.zero,
        artUri: artFile != null ? Uri.file(artFile.path) : null,
      ),
    );

    print("发送给AudioHandler的媒体项: $currentFilePath, 专辑: $album, 标题: $title, 艺术家: $artist, 时长: ${player?.state.duration ?? Duration.zero}, 封面: ${artFile != null ? artFile.path : '无'}");
  }
}

// 播放器状态模型类
class MediaKitPlayerState {
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final String title;
  final String artist;
  final String album;
  final Uint8List? coverBytes;

  MediaKitPlayerState({
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.title,
    required this.artist,
    required this.album,
    this.coverBytes,
  });
}

// MediaKit AudioHandler
class MediaKitAudioHandler extends BaseAudioHandler {
  final Function() onPlay;
  final Function() onPause;
  final Function() onStop;
  final Function(Duration) onSeek;
  final Function(double) onSetSpeed;
  final Function(Duration) onFastForward;
  final Function(Duration) onRewind;
  final bool Function() isPlaying;
  final Duration Function() getCurrentPosition;
  final Duration Function() getDuration;
  final double Function() getPlaybackSpeed;
  final Function() onPlayNext;
  final Function() onPlayPrevious;

  MediaKitAudioHandler({
    required this.onPlay,
    required this.onPause,
    required this.onStop,
    required this.onSeek,
    required this.onSetSpeed,
    required this.onFastForward,
    required this.onRewind,
    required this.isPlaying,
    required this.getCurrentPosition,
    required this.getDuration,
    required this.getPlaybackSpeed,
    required this.onPlayNext,
    required this.onPlayPrevious,
  });

  @override
  Future<void> play() async {
    onPlay();
  }

  @override
  Future<void> pause() async {
    onPause();
  }

  @override
  Future<void> stop() async {
    onStop();
  }

  @override
  Future<void> seek(Duration position) async {
    onSeek(position);
  }

  @override
  Future<void> setSpeed(double speed) async {
    onSetSpeed(speed);
  }

  @override
  Future<void> fastForward() async {
    onFastForward(Duration(seconds: 10));
  }

  @override
  Future<void> rewind() async {
    onRewind(Duration(seconds: 10));
  }

  @override
  Future<void> skipToNext() async {
    onPlayNext();
  }

  @override
  Future<void> skipToPrevious() async {
    onPlayPrevious();
  }

  void updatePlaybackState() {
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (isPlaying())
          MediaControl.pause
        else
          MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: AudioProcessingState.ready,
      playing: isPlaying(),
      updatePosition: getCurrentPosition(),
      bufferedPosition: getCurrentPosition(),
      speed: getPlaybackSpeed(),
    ));
  }
}

