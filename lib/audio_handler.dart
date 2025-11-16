import 'dart:io';
import 'dart:typed_data';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

/// 通用的视频播放器 AudioHandler 基类
/// 支持不同类型的播放器通过回调函数来实现控制
class VideoPlayerAudioHandler extends BaseAudioHandler {
  // 播放控制回调
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onStop;
  final VoidCallback? onPlayNext;
  final VoidCallback? onPlayPrevious;
  final Function(Duration) onSeek;
  final Function(double) onSetSpeed;
  final Function(Duration) onFastForward;
  final Function(Duration) onRewind;

  // 状态获取回调
  final bool Function() isPlaying;
  final Duration Function() getCurrentPosition;
  final Duration Function() getDuration;
  final double Function() getPlaybackSpeed;

  VideoPlayerAudioHandler({
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
    this.onPlayNext,
    this.onPlayPrevious,
  });

  @override
  Future<void> play() async {
    onPlay();
    playbackState.add(playbackState.value.copyWith(
      playing: true,
      controls: _getControls(true),
    ));
  }

  @override
  Future<void> pause() async {
    onPause();
    playbackState.add(playbackState.value.copyWith(
      playing: false,
      controls: _getControls(false),
    ));
  }

  @override
  Future<void> stop() async {
    onStop();
    playbackState.add(playbackState.value.copyWith(
      playing: false,
      processingState: AudioProcessingState.idle,
    ));
  }

  @override
  Future<void> skipToNext() async {
    if (onPlayNext != null) {
      onPlayNext!();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (onPlayPrevious != null) {
      onPlayPrevious!();
    }
  }

  @override
  Future<void> fastForward() async {
    onFastForward(const Duration(seconds: 10));
  }

  @override
  Future<void> rewind() async {
    onRewind(const Duration(seconds: 10));
  }

  @override
  Future<void> seek(Duration position) async {
    onSeek(position);
    playbackState.add(playbackState.value.copyWith(
      updatePosition: position,
    ));
  }

  @override
  Future<void> setSpeed(double speed) async {
    onSetSpeed(speed);
    playbackState.add(playbackState.value.copyWith(
      speed: speed,
    ));
  }

  /// 获取控制按钮列表
  List<MediaControl> _getControls(bool playing) {
    final controls = <MediaControl>[];

    if (onPlayPrevious != null) {
      controls.add(MediaControl.skipToPrevious);
    }
    controls.add(MediaControl.rewind);
    controls.add(playing ? MediaControl.pause : MediaControl.play);
    controls.add(MediaControl.fastForward);
    if (onPlayNext != null) {
      controls.add(MediaControl.skipToNext);
    }

    return controls;
  }

  /// 更新播放状态
  void updatePlaybackState() {
    final position = getCurrentPosition();
    final duration = getDuration();
    final playing = isPlaying();
    final speed = getPlaybackSpeed();

    playbackState.add(PlaybackState(
      controls: _getControls(playing),
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      playing: playing,
      updatePosition: position,
      bufferedPosition: position,
      speed: speed,
      processingState: duration > Duration.zero && position < duration
          ? AudioProcessingState.ready
          : AudioProcessingState.idle,
      repeatMode: AudioServiceRepeatMode.none,
      shuffleMode: AudioServiceShuffleMode.none,
    ));
  }

  /// 设置当前媒体项目
  Future<void> setCurrentMediaItem(String filePath, Duration duration) async {
    // 先查看缩略图目录下是否有对应的缩略图文件
    final thumbnailPath = path.join(
        '/storage/Users/currentUser/Download/com.aloereed.aloeplayer',
        'Thumbnails',
        '${path.basename(filePath)}.jpg');
    var iconFile = File(thumbnailPath);

    // 如果缩略图不存在，使用默认图标
    if (!await iconFile.exists()) {
      final iconBytes = await rootBundle.load('Assets/icon.png');
      iconFile = File(path.join(
          Directory.systemTemp.path, 'com.aloereed.aloeplayer', 'icon.png'));
      await iconFile.create(recursive: true);
      await iconFile.writeAsBytes(iconBytes.buffer.asUint8List());
    }

    mediaItem.add(MediaItem(
      id: filePath,
      album: "AloePlayer",
      title: path.basenameWithoutExtension(filePath),
      artist: "AloePlayer",
      duration: duration,
      artUri: Uri.file(iconFile.path),
    ));
  }
}
