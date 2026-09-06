import 'services/media_display_name.dart';
import 'services/mpv_image_enhancement.dart';
import 'services/player_image_backend.dart';
import 'widgets/image_enhancement_sheet.dart';
import 'pages/native_pip_page.dart';
import 'services/subtitle_matcher.dart';
import 'services/playback_tools_store.dart';
import 'services/sleep_timer.dart';
import 'widgets/sleep_timer_button.dart';
import 'widgets/playback_tools_sheet.dart';
import 'models/playback_media.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:ui';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as path;
import 'package:file_picker_ohos/file_picker_ohos.dart';
import 'package:intl/intl.dart';
import 'package:screen/screen.dart';
import 'package:xml/xml.dart' as xml;
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:audio_service/audio_service.dart';
import 'package:galactic_hotkeys/galactic_hotkeys.dart';
import 'history_service.dart';
import 'volumeview.dart';
import 'settings.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'audio_handler.dart';

// 键盘快捷键枚举
enum PlayerHotkey {
  playPause, // 播放/暂停
  seekForward, // 快进5秒
  seekBackward, // 快退5秒
  seekForwardLong, // 快进30秒
  seekBackwardLong, // 快退30秒
  volumeUp, // 音量增加
  volumeDown, // 音量减少
  toggleMute, // 静音切换
  toggleFullscreen, // 全屏切换
  speedUp, // 加速
  speedDown, // 减速
  speedReset, // 恢复正常速度
  nextVideo, // 下一个视频
  previousVideo, // 上一个视频
  screenshot, // 截图
  toggleSubtitle, // 字幕切换
  toggleDanmaku, // 弹幕切换
  quit, // 退出
}

// 播放列表排序类型枚举
enum PlaylistSortType {
  original, // 原始顺序
  name, // 按名称排序
  modified, // 按修改时间排序
}

// 播放列表排序顺序枚举
enum PlaylistSortOrder {
  ascending, // 升序
  descending, // 降序
}

// Custom class for the brightness slider timer
class BrightnessSliderTimer {
  Timer? _timer;
  final VoidCallback onTimeout;

  BrightnessSliderTimer({required this.onTimeout});

  void start() {
    cancel();
    _timer = Timer(Duration(seconds: 3), onTimeout);
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}

// Helper function to resolve .lnk files
Future<String> resolveLnkFile(String filePath) async {
  try {
    final file = File(filePath);

    // Check if file has .lnk extension (case insensitive)
    if (file.path.toLowerCase().endsWith('.lnk')) {
      // Read .lnk file as text
      final content = await file.readAsString(encoding: utf8);

      // Trim whitespace and return the real path
      final realPath = content.trim();

      // If the content is empty or just whitespace, return original path
      if (realPath.isEmpty) {
        print('Warning: .lnk file is empty: $filePath');
        return filePath;
      }

      print('Resolved .lnk file: $filePath -> $realPath');
      return realPath;
    }

    // Not a .lnk file, return original path
    return filePath;
  } catch (e) {
    print('Error resolving .lnk file $filePath: $e');
    // Return original path if there's an error
    return filePath;
  }
}

// 解析弹幕XML文件的函数
List<Map<String, dynamic>> parseDanmakuXml(String xmlString) {
  // 解析 XML 文档
  final document = xml.XmlDocument.parse(xmlString);

  // 获取所有 <d> 标签
  final dElements = document.findAllElements('d');

  // 解析每个 <d> 标签并生成 danmakuContents
  List<Map<String, dynamic>> danmakuContents = [];
  try {
    for (var dElement in dElements) {
      // 获取 p 属性
      final pAttribute = dElement.getAttribute('p');
      if (pAttribute == null) continue;

      // 解析 p 属性
      final pValues = pAttribute.split(',');

      // 获取弹幕内容
      final content = dElement.text;
      final type = int.parse(pValues[1]);
      DanmakuItemType itemType = DanmakuItemType.scroll;
      if (type == 4)
        itemType = DanmakuItemType.bottom;
      else if (type == 5) itemType = DanmakuItemType.top;

      try {
        // 将数据添加到 danmakuContents
        danmakuContents.add({
          'time': double.parse(pValues[0]), // 弹幕时间
          'content': DanmakuContentItem(content, // 弹幕内容
              type: itemType,
              color: Color(_rgbToColor(int.parse(pValues[3]))))
          // 其他属性可以根据需要添加
        });
      } catch (e) {
        print("parse single danmaku xml error");
      }
    }

    print("parse danmaku xml done");
  } catch (e) {
    print("parse danmaku xml error");
  }

  return danmakuContents;
}

// RGB转颜色的辅助函数
int _rgbToColor(int rgb) {
  // 将 RGB 值转换为 ARGB 值，透明度为 0xFF（完全不透明）
  return 0xFF000000 | rgb;
}

class BrightnessSlider extends StatefulWidget {
  final ValueChanged<double>? onBrightnessChanged;

  const BrightnessSlider({Key? key, this.onBrightnessChanged})
      : super(key: key);

  @override
  _BrightnessSliderState createState() => _BrightnessSliderState();
}

class _BrightnessSliderState extends State<BrightnessSlider> {
  double _brightness = 0.5;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _initBrightness();
    // 创建定时器来定期检查亮度变化
    _pollingTimer = Timer.periodic(Duration(milliseconds: 50), (_) {
      _updateBrightness();
    });
  }

  void _initBrightness() async {
    try {
      final brightness = await Screen.brightness ?? 0.5;
      if (mounted) {
        setState(() {
          _brightness = brightness.clamp(0.0, 0.99);
        });
      }
    } catch (e) {
      print('初始化亮度时发生错误: $e');
    }
  }

  void _updateBrightness() async {
    try {
      final brightness = await Screen.brightness ?? 0.5;
      if (mounted && (brightness != _brightness)) {
        setState(() {
          _brightness = brightness.clamp(0.0, 0.99);
        });
      }
    } catch (e) {
      print('更新亮度时发生错误: $e');
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Slider(
      value: _brightness,
      min: 0.0,
      max: 0.99, // 设为0.99以避免潜在的边界问题
      onChanged: (value) async {
        if (value != _brightness) {
          setState(() {
            _brightness = value;
          });

          try {
            await Screen.setBrightness(value);
            if (widget.onBrightnessChanged != null) {
              widget.onBrightnessChanged!(value);
            }
          } catch (e) {
            print('设置亮度时发生错误: $e');
          }
        }
      },
    );
  }
}

class MPVPlayer extends StatefulWidget {
  final String filePath;
  final bool nativeHdr;
  final List<PlaybackMedia>? mediaQueue;
  final int? initialPositionMs;
  final Future<void> Function(PlaybackMedia media, int positionMs, bool stopped, bool playing)? onPlayback;

  const MPVPlayer({Key? key, required this.filePath, this.mediaQueue, this.onPlayback, this.initialPositionMs, this.nativeHdr = false}) : super(key: key);

  @override
  _MPVPlayerState createState() => _MPVPlayerState();
}

class _MPVPlayerState extends State<MPVPlayer>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final Player player;
  late final VideoController controller;
  late final MpvImageEnhancer _imageEnhancer;
  late AnimationController _controlsAnimationController;
  late AnimationController _fadeAnimationController;

  final List<StreamSubscription> _subscriptions = [];
  bool _openingMedia = false;
  bool _disposing = false;
  bool _switchingHdr = false;
  String _historyId = '';
  List<String> _openedPaths = [];
  bool _readyForRestore = false;
  Duration _lastPosition = Duration.zero;
  DateTime _lastCheckpoint = DateTime(1970);
  DateTime _lastUiUpdate = DateTime(1970);
  int? _resumePosition;
  PlaybackMedia? _mediaFor(String url) => widget.mediaQueue?.where((m) => m.url == url).firstOrNull;
  String _mediaTitle(String url) => _mediaFor(url)?.title ?? mediaDisplayName(url);

  Future<void> _initializeMedia() async {
    try {
      await _initializeSettings();
      await _loadPlaylist();
      if (mounted) await _openMedia(widget.filePath);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('打开媒体失败: $e')));
    }
  }

  // 历史记录服务
  final HistoryService _historyService = HistoryService();

  bool _showControls = true;
  bool _isFullScreen = false;
  bool _showPlaylist = false;
  bool _showSettings = false;

  // 播放列表
  List<File> _playlist = [];
  int _currentIndex = 0;
  List<File> _originalPlaylist = []; // 保存原始播放列表顺序
  PlaylistSortType _sortType = PlaylistSortType.original; // 当前排序类型
  PlaylistSortOrder _sortOrder = PlaylistSortOrder.ascending; // 当前排序顺序

  // 当前播放文件路径
  String _currentFilePath = '';

  // AB循环
  Duration? _pointA;
  Duration? _pointB;

  // 手势控制
  double _brightness = 0.5;
  double _volume = 1.0;
  bool _seeking = false;
  Duration? _seekPosition;
  Offset? _dragStartOffset; // 记录拖动开始时的屏幕位置

  // 播放器设置
  double _playbackSpeed = 1.0;
  bool _mirror = false;
  double _zoom = 1.0;
  PlaylistMode _loopMode = PlaylistMode.none;
  bool _enableBlur = false; // 控制栏高斯模糊，默认关闭

  // 长按无极调速
  bool _isLongPressing = false;
  double _tempSpeed = 2.0;
  Offset? _longPressStartPosition;
  bool _isAdjustingSpeed = false; // 用户正在调整速度
  double _lastSignificantSpeed = 2.0; // 上次显著速度值
  Timer? _speedAdjustTimer; // 速度调整超时定时器
  Duration? _dragStartPosition;

  // 历史记录相关
  Timer? _positionUpdateTimer;
  bool _hasRestoredPosition = false;

  // 亮度调节
  bool _showBrightnessSlider = false;
  bool _isVerticalDragging = false;
  BrightnessSliderTimer? _brightnessSliderTimer;

  // 双击检测相关
  Timer? _doubleTapTimer;
  Offset? _lastTapPosition;
  bool _isDoubleTap = false;
  Timer? _hideTimer;
  bool _isMouseHovering = false;

  // 音量调节
  double _systemVolume = 7.5;
  double _systemMaxVolume = 15.0;
  double _lastVolume = 1.0; // 保存静音前的音量
  VolumeViewController? _volumeController;
  VolumeExample? _volumeExample;
  final EventChannel _eventChannel =
      EventChannel('samples.flutter.dev/volumepluginevent');

  // 弹幕相关
  bool _danmakuOn = true;
  List<Map<String, dynamic>> _danmakuContents = [];
  Map<int, List<Map<String, dynamic>>> _danmakuByTime = {};
  List<int> _sentDanmakuIndexes = [];
  late DanmakuController _danmakuController;
  final _danmuKey = GlobalKey();
  bool _showDanmakuSettings = false;

  // 弹幕设置
  double _danmakuOpacity = 1.0;
  double _danmakuFontSize = 20.0;
  int _danmakuFontWeight = 4;
  int _danmakuDuration = 8;
  bool _danmakuShowStroke = true;
  bool _danmakuHideScroll = false;
  bool _danmakuHideTop = false;
  bool _danmakuHideBottom = false;

  // 设置相关
  final SettingsService _settingsService = SettingsService();
  bool _backgroundPlayEnabled = true;
  bool _useSeekToLatest = false;
  bool _usePlaylist = true;
  int _mpvHardwareDecoding = 1;
  bool _isInBackground = false;
  AppLifecycleState? _lastLifecycleState;

  // HDR相关
  bool _isHDRVideo = false;
  double? _savedBrightness; // 保存进入播放器前的亮度

  // 缓冲相关
  bool _isBuffering = false;
  // removed _isPcModeEnabled per user request to fetch fresh every time

  // Audio Service 相关
  MediaItem? _currentMediaItem;
  bool _audioServiceInitialized = false;
  VideoPlayerAudioHandler? _audioHandler;

  // methodchannel
  static const MethodChannel _methodChannel1 =
      MethodChannel('samples.flutter.dev/downloadplugin');

  Future<bool> _getIsPcMode() async {
    try {
      final context = this.context;
      if (Platform.isAndroid || Platform.isIOS) return false;
      bool userEnabled = await _settingsService.getUsePcMode(context);
      if (!userEnabled) return false;
      if (!mounted) return false;
      return MediaQuery.of(context).size.width > 800;
    } catch (e) {
      return false;
    }
  }

  Future<void> _pickVideoFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'mp4',
        'mkv',
        'avi',
        'mov',
        'flv',
        'wmv',
        'webm',
        'ts'
      ],
    );

    if (result != null) {
      final file = File(result.files.single.path!);
      _openMedia(file.path);
    }
  }

  @override
  void initState() {
    super.initState();

    _controlsAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _fadeAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    // 创建 Player 并配置 mpv 选项以启用 ASS 字幕渲染
    player = Player(
      configuration: PlayerConfiguration(
        // 启用 libass 渲染 ASS 字幕特效
        // 这些选项会传递给底层的 libmpv
        // vo: 'gpu',  // 使用 GPU 视频输出
        libass: !(widget.nativeHdr && Platform.operatingSystem == 'ohos'),
        protocolWhitelist: const [
          'file',
          'http',
          'https',
          'tcp',
          'tls',
          'rtsp',
          'smb',
          'ftp'
        ],
      ),
    );
    controller = VideoController(player, configuration: VideoControllerConfiguration(
      vo: widget.nativeHdr && Platform.operatingSystem == 'ohos' ? 'ohcodec' : null,
      hwdec: widget.nativeHdr && Platform.operatingSystem == 'ohos' ? 'ohcodec' : null,
    ));
    _imageEnhancer = MpvImageEnhancer(backend: PlayerImageBackend(player, controller));
    _subscriptions.add(player.stream.videoParams.listen((video) {
      final rotated = video.rotate == 90 || video.rotate == 270;
      _imageEnhancer.videoChanged(width: (rotated ? video.dh : video.dw) ?? 0,
        height: (rotated ? video.dw : video.dh) ?? 0, gamma: video.gamma,
        format: video.hwPixelformat ?? video.pixelformat);
    }));
    _subscriptions.add(player.stream.log.listen((log) {
      if ((log.level == 'error' || log.level == 'fatal') && RegExp(r'shader|glsl', caseSensitive: false).hasMatch(log.text)) {
        _imageEnhancer.shaderFailed(detail: log.text);
      }
    }));
    if (!widget.nativeHdr) _imageEnhancer.initialize();
    _initializeMedia();

    // 监听播放状态
    _subscriptions.add(player.stream.playing.listen((playing) {
      if (mounted && !_disposing) setState(() {});
      if (!playing) _flushPosition();
      // 同步到 Audio Service
      _updatePlaybackState();
    }));

    _subscriptions.add(player.stream.position.listen((position) {
      if (mounted && !_disposing && !_seeking && DateTime.now().difference(_lastUiUpdate).inMilliseconds >= 250) {
        _lastUiUpdate = DateTime.now();
        setState(() {});
        _updatePlaybackState();
      }
      if (player.state.duration > Duration.zero && position >= player.state.duration - const Duration(milliseconds: 100)) PlaybackSleepTimer.instance.consumeEnd(this);
      _checkABLoop(position);
      // 更新播放位置到历史记录
      _updatePlaybackPosition(position);
      // 更新弹幕
      _updateDanmaku(position);
    }));

    _subscriptions.add(player.stream.duration.listen((duration) {
      if (mounted) setState(() {});
      // 更新视频时长到历史记录
      _updateVideoDuration(duration);
      // 同步到 Audio Service
      _updatePlaybackState();
      _updateMediaItem();
    }));

    // 监听缓冲状态
    _subscriptions.add(player.stream.buffering.listen((buffering) {
      if (mounted) {
        setState(() {
          _isBuffering = buffering;
        });
      }
    }));

    // 监听播放列表变化，用于同步当前播放索引
    _subscriptions.add(player.stream.playlist.listen((playlist) {
      if (mounted && !_disposing && !_openingMedia && playlist.index >= 0 && playlist.index < _openedPaths.length) {
        final newIndex = playlist.index;
        final newFilePath = _openedPaths[newIndex];

        // 只有当索引真的改变时才更新
        if (newFilePath != _currentFilePath) {
          PlaybackSleepTimer.instance.consumeEnd(this);
          _flushPosition();
          _onQueueItemChanged(newFilePath);
          setState(() {
            _currentIndex = _playlist.indexWhere((f) => f.path == newFilePath);
            if (_currentIndex < 0) _currentIndex = 0;
            _currentFilePath = newFilePath;
          });
        }
      }
    }));

    // 自动隐藏控制栏
    _resetHideTimer();

    // 初始化亮度调节计时器
    _brightnessSliderTimer = BrightnessSliderTimer(
      onTimeout: () {
        setState(() {
          _showBrightnessSlider = false;
        });
      },
    );

    // 初始化音量相关组件
    _volumeExample = VolumeExample();

    // 监听音量变化
    _subscriptions.add(_eventChannel
        .receiveBroadcastStream()
        .listen(_onVolumeChanged, onError: _onError));

    // 获取系统音量信息
    _initializeVolume();

    // 初始化设置
    // Settings are awaited before opening the media.

    // 初始化 Audio Service
    _initializeAudioService();

    // 保存当前亮度
    _saveBrightness();

    // 添加应用生命周期监听器
    WidgetsBinding.instance.addObserver(this);
  }

  // 初始化所有设置
  Future<void> _initializeSettings() async {
    try {
      _backgroundPlayEnabled = await _settingsService.getBackgroundPlay();
      _useSeekToLatest = await _settingsService.getUseSeekToLatest();
      _usePlaylist = await _settingsService.getUsePlaylist();
      _mpvHardwareDecoding =
          await _settingsService.getMpvHardwareDecoding();
      print('后台播放设置: $_backgroundPlayEnabled');
      print('使用上次播放位置: $_useSeekToLatest');
      print('启用库内同级文件夹播放列表导入: $_usePlaylist');
      print('MPV硬件解码模式: $_mpvHardwareDecoding');
    } catch (e) {
      print('初始化设置时发生错误: $e');
      _backgroundPlayEnabled = true; // 默认启用
      _useSeekToLatest = false; // 默认不启用
      _usePlaylist = true; // 默认启用
      _mpvHardwareDecoding = 1; // 默认自动（推荐）
    }
  }

  String _mpvHardwareDecodingOption(int mode) {
    switch (mode) {
      case 1:
        return 'auto-safe';
      case 2:
        return 'auto';
      default:
        return 'no';
    }
  }

  Future<void> _applyMpvHardwareDecoding() async {
    try {
      if (widget.nativeHdr && Platform.operatingSystem == 'ohos') {
        await (player.platform as NativePlayer).setProperty('hwdec', 'ohcodec');
        return;
      }
      _mpvHardwareDecoding =
          await _settingsService.getMpvHardwareDecoding();
      final hwdec = _mpvHardwareDecodingOption(_mpvHardwareDecoding);
      await (player.platform as dynamic).setProperty('hwdec', hwdec);
      print('MPV硬件解码已设置为: $hwdec');
    } catch (e) {
      print('设置MPV硬件解码时发生错误: $e');
    }
  }

  // 处理应用生命周期变化
  void _handleLifecycleChange(AppLifecycleState state) async {
    print('应用生命周期状态变化: $state');

    switch (state) {
      case AppLifecycleState.paused:
        // 应用进入后台
        _isInBackground = true;
        if (_backgroundPlayEnabled && player.state.playing) {
          // 启用后台播放
          await _enableBackgroundPlayback();
        }
        break;
      case AppLifecycleState.resumed:
        // 应用回到前台
        _isInBackground = false;
        if (_backgroundPlayEnabled) {
          // 禁用后台播放
          await _disableBackgroundPlayback();
        }
        break;
      case AppLifecycleState.detached:
        // 应用被完全关闭
        await _cleanupBackgroundPlayback();
        break;
      default:
        break;
    }

    _lastLifecycleState = state;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _flushPosition();
    _handleLifecycleChange(state);
  }

  // 启用后台播放
  Future<void> _enableBackgroundPlayback() async {
    try {
      // 保持屏幕唤醒
      await WakelockPlus.enable();

      // 设置播放器为后台模式
      // 注意：media_kit 在 OpenHarmony 上的后台播放可能需要特殊配置
      print('已启用后台播放模式');

      // 显示通知给用户
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已启用后台播放'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('启用后台播放时发生错误: $e');
    }
  }

  // 禁用后台播放
  Future<void> _disableBackgroundPlayback() async {
    try {
      // 释放屏幕唤醒锁
      await WakelockPlus.disable();

      print('已禁用后台播放模式');

      // 显示通知给用户
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已退出后台播放'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('禁用后台播放时发生错误: $e');
    }
  }

  // 清理后台播放资源
  Future<void> _cleanupBackgroundPlayback() async {
    try {
      await WakelockPlus.disable();
      print('已清理后台播放资源');
    } catch (e) {
      print('清理后台播放资源时发生错误: $e');
    }
  }

  // 切换后台播放设置
  void _toggleBackgroundPlay(bool value) async {
    setState(() {
      _backgroundPlayEnabled = value;
    });

    try {
      await _settingsService.saveBackgroundPlay(value);

      if (value) {
        // 如果当前正在播放且应用在后台，立即启用后台播放
        if (_isInBackground && player.state.playing) {
          await _enableBackgroundPlayback();
        }
      } else {
        // 如果当前在后台播放，立即停止
        if (_isInBackground) {
          await _disableBackgroundPlayback();
        }
      }

      print('后台播放设置已更新: $value');
    } catch (e) {
      print('更新后台播放设置时发生错误: $e');
    }
  }

  // 初始化 Audio Service
  void _initializeAudioService() async {
    if (_audioServiceInitialized) return;

    try {
      // 创建 AudioHandler 实例
      _audioHandler = await AudioService.init(
        builder: () => VideoPlayerAudioHandler(
          onPlay: () => _pipController?.play() ?? player.play(),
          onPause: () => _pipController?.pause() ?? player.pause(),
          onStop: () async {
            if (_pipController != null) { await _pipController!.pause(); await _pipController!.seek(Duration.zero); }
            else { await player.pause(); await player.seek(Duration.zero); }
          },
          onSeek: (position) => _pipController?.seek(position) ?? player.seek(position),
          onSetSpeed: (speed) => player.setRate(speed),
          onFastForward: (duration) => _seekActivePlayback((_pipController != null ? _lastPosition : player.state.position) + duration),
          onRewind: (duration) {
            final position = (_pipController != null ? _lastPosition : player.state.position) - duration;
            _seekActivePlayback(position > Duration.zero ? position : Duration.zero);
          },
          isPlaying: () => _pipController != null ? _pipPlaying : player.state.playing,
          getCurrentPosition: () => _pipController != null ? _lastPosition : player.state.position,
          getDuration: () => player.state.duration,
          getPlaybackSpeed: () => _pipController != null ? 1.0 : player.state.rate,
          onPlayNext: _playNext,
          onPlayPrevious: _playPrevious,
        ),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.aloereed.aloeplayer.channel.audio',
          androidNotificationChannelName: 'AloePlayer',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
        ),
      );

      _audioServiceInitialized = true;
      print('Audio Service 初始化完成');
    } catch (e) {
      print('初始化 Audio Service 时发生错误: $e');
      _audioServiceInitialized = false;
    }
  }

  // 更新播放状态到 Audio Service
  void _updatePlaybackState() async {
    if (!_audioServiceInitialized || _audioHandler == null) return;

    try {
      // 使用 AudioHandler 的 updatePlaybackState 方法更新播放状态
      _audioHandler!.updatePlaybackState();
    } catch (e) {
      print('更新播放状态时发生错误: $e');
    }
  }

  // 更新媒体项目到 Audio Service
  void _updateMediaItem() async {
    if (!_audioServiceInitialized || _audioHandler == null) return;

    try {
      final filePath =
          _currentFilePath.isNotEmpty ? _currentFilePath : widget.filePath;
      final duration = player.state.duration;

      // 使用 AudioHandler 的 setCurrentMediaItem 方法更新媒体信息
      _audioHandler!.setCurrentMediaItem(filePath, duration);
    } catch (e) {
      print('更新媒体项目时发生错误: $e');
    }
  }

  void _initializeVolume() async {
    try {
      final _platform = const MethodChannel('samples.flutter.dev/volumeplugin');
      _systemMaxVolume =
          ((await _platform.invokeMethod<int>('getMaxVolume')) ?? 15)
              .toDouble();
      _systemVolume =
          ((await _platform.invokeMethod<int>('getCurrentVolume')) ?? 7.5)
              .toDouble();
    } catch (e) {
      print('初始化音量时发生错误: $e');
    }
  }

  void _onVolumeChanged(dynamic volume) {
    if (!mounted || _disposing) return;
    setState(() {
      _systemVolume = (volume as int).toDouble();
    });
  }

  void _onError(Object error) {
    print('Volume error: $error');
  }

  double setSystemVolume(double delta) {
    _volumeController = _volumeExample?.controller;
    double nextVolume = _systemVolume + delta * _systemMaxVolume;

    // 确保音量不超过最大音量
    if (nextVolume > _systemMaxVolume) {
      nextVolume = _systemMaxVolume;
    }

    // 确保音量不小于 0
    if (nextVolume < 0) {
      nextVolume = 0;
    }

    try {
      _volumeController?.sendMessageToOhosView(
          'getMessageFromFlutterView2', nextVolume.toString());
      _systemVolume = nextVolume;
    } catch (e) {
      print('设置音量时发生错误: $e');
    }
    return nextVolume;
  }

  // 保存当前亮度
  void _saveBrightness() async {
    try {
      final brightness = await Screen.brightness;
      if (brightness != null) {
        _savedBrightness = brightness;
        print('已保存当前亮度: $_savedBrightness');
      }
    } catch (e) {
      print('保存亮度时发生错误: $e');
    }
  }

  // 检测 HDR 视频（使用 ffmpeg）
  Future<bool> _getHdr(String filePath) async {
    try {
      // 如果是.lnk文件，读取实际路径
      if (filePath.endsWith('.lnk')) {
        final file = File(filePath);
        filePath = await file.readAsString();
      }

      final _ffmpegplatform =
          const MethodChannel('samples.flutter.dev/ffmpegplugin');
      int getHdrMethod = await _settingsService.getHdrDetect();

      if (getHdrMethod == 0) {
        return false;
      }

      String hdrJson = '';
      if (getHdrMethod == 1) {
        hdrJson = await _ffmpegplatform
                .invokeMethod<String>('getVideoHDRInfo', {'path': filePath}) ??
            '';
      } else if (getHdrMethod == 2) {
        hdrJson = await _ffmpegplatform.invokeMethod<String>(
                'getVideoHDRInfoFFmpeg', {'path': filePath}) ??
            '';
      }

      // 如果返回的JSON字符串为空，默认为非HDR
      if (hdrJson.isEmpty) {
        print('获取HDR信息失败：返回空JSON');
        return false;
      }

      // 解析JSON字符串
      try {
        final Map<String, dynamic> data = json.decode(hdrJson);
        final bool isHdr = data['isHDR'] ?? false;
        print('视频HDR状态: ${isHdr ? "是HDR" : "非HDR"}');
        return isHdr;
      } catch (e) {
        print('解析HDR JSON出错: $e');
        print('原始JSON: $hdrJson');
        return false;
      }
    } catch (e) {
      print('获取HDR信息时发生错误: $e');
      return false;
    }
  }

  // 检查并处理 HDR 视频
  Future<void> _checkAndHandleHDR(String filePath) async {
    try {
      final isHDR = await _getHdr(filePath);

      // 如果检测到HDR视频且之前不是HDR状态
      if (isHDR && !_isHDRVideo) {
        setState(() {
          _isHDRVideo = true;
        });
        await _setMaxBrightness();
        print('检测到 HDR 视频,已将亮度调至最大');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('检测到 HDR 视频，已自动调整亮度至最大'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else if (!isHDR && _isHDRVideo) {
        // 如果之前是HDR现在不是了,恢复亮度
        setState(() {
          _isHDRVideo = false;
        });
        await _restoreBrightness();
      }
    } catch (e) {
      print('检测 HDR 视频时发生错误: $e');
    }
  }

  // 设置最大亮度
  Future<void> _setMaxBrightness() async {
    try {
      await Screen.setBrightness(0.99); // 设置为最大亮度
    } catch (e) {
      print('设置最大亮度时发生错误: $e');
    }
  }

  // 恢复保存的亮度
  Future<void> _restoreBrightness() async {
    try {
      if (_savedBrightness != null) {
        await Screen.setBrightness(_savedBrightness!);
        print('已恢复亮度到: $_savedBrightness');
      }
    } catch (e) {
      print('恢复亮度时发生错误: $e');
    }
  }

  String convertUriToPath(String uri) {
    // 如果uri以"/Photos"开头，则在uri前面加上"file://media"
    if (uri.startsWith('file://media')) {
      uri = Uri.decodeFull(uri.substring(12));
    }

    // 删除file://docs并解析unicode码
    if (uri.startsWith('file://docs')) {
      uri = Uri.decodeFull(uri.substring(11));
    }

    return uri;
  }

  Future<void> _loadPlaylist() async {
    if (widget.mediaQueue != null) {
      _playlist = widget.mediaQueue!.map((m) => File(m.url)).toList();
      _originalPlaylist = List.from(_playlist);
      _currentIndex = _playlist.indexWhere((f) => f.path == widget.filePath);
      if (_currentIndex < 0) _currentIndex = 0;
      return;
    }
    // 检查是否为HTTP/HTTPS URL
    final isHttpUrl = widget.filePath.startsWith('http://') ||
        widget.filePath.startsWith('https://');

    // 如果是HTTP URL或未启用播放列表导入，只创建当前文件的播放列表
    if (isHttpUrl || widget.filePath.startsWith('file://') || !_usePlaylist) {
      // 对于HTTP URL，不使用File对象，直接使用路径字符串
      if (isHttpUrl) {
        _playlist = [File(widget.filePath)];
        _originalPlaylist = List.from(_playlist);
      } else {
        _playlist = [File(widget.filePath)];
        _originalPlaylist = [File(widget.filePath)];
      }
      _currentIndex = 0;
      if (mounted) setState(() {});
      return;
    }

    final directory = Directory(path.dirname(widget.filePath));
    final files = await directory.list().toList();

    final mediaExtensions = [
      // Video formats
      '.mp4',
      '.mkv',
      '.avi',
      '.mov',
      '.flv',
      '.wmv',
      '.webm',
      '.m4v',
      '.rmvb',
      '.3gp',
      '.rm',
      '.ts',
      '.vob',
      '.mpg',
      '.mpeg',
      '.f4v',
      '.divx',
      '.m2ts',
      '.mts',
      '.ogv',
      '.asf',
      '.m2v',
      '.qt',
      '.y4m',
      // Audio formats
      '.mp3',
      '.flac',
      '.m4a',
      '.aac',
      '.ogg',
      '.opus',
      '.wav',
      '.wma',
      '.ape',
      '.alac',
      '.wv',
      '.tta',
      '.dts',
      '.ac3',
      '.tak',
      '.mpc',
      '.spx',
      '.caf',
      '.aiff',
      '.dsd',
      '.dsf',
      // Link files
      '.lnk' // Add .lnk extension to include them in playlist
    ];

    _originalPlaylist = files
        .whereType<File>()
        .where((file) =>
            mediaExtensions.any((ext) => file.path.toLowerCase().endsWith(ext)))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    _playlist = List.from(_originalPlaylist);

    _currentIndex =
        _playlist.indexWhere((file) => file.path == widget.filePath);
    if (_currentIndex == -1) _currentIndex = 0;

    if (mounted) setState(() {});
  }

  // 排序播放列表
  void _sortPlaylist(PlaylistSortType sortType, PlaylistSortOrder sortOrder) {
    setState(() {
      _sortType = sortType;
      _sortOrder = sortOrder;

      switch (sortType) {
        case PlaylistSortType.original:
          _playlist = List.from(_originalPlaylist);
          break;
        case PlaylistSortType.name:
          _playlist = List.from(_originalPlaylist);
          _playlist.sort((a, b) {
            final nameA = path.basenameWithoutExtension(a.path).toLowerCase();
            final nameB = path.basenameWithoutExtension(b.path).toLowerCase();
            final comparison = nameA.compareTo(nameB);
            return sortOrder == PlaylistSortOrder.ascending
                ? comparison
                : -comparison;
          });
          break;
        case PlaylistSortType.modified:
          _playlist = List.from(_originalPlaylist);
          _playlist.sort((a, b) {
            final modifiedA = _mediaFor(a.path)?.modified ?? (widget.mediaQueue != null ? DateTime(1970) : a.statSync().modified);
            final modifiedB = _mediaFor(b.path)?.modified ?? (widget.mediaQueue != null ? DateTime(1970) : b.statSync().modified);
            final comparison = modifiedA.compareTo(modifiedB);
            return sortOrder == PlaylistSortOrder.ascending
                ? comparison
                : -comparison;
          });
          break;
      }

      // 重新找到当前播放文件的索引
      _currentIndex = _playlist.indexWhere((file) =>
          file.path ==
          (_currentFilePath.isNotEmpty ? _currentFilePath : widget.filePath));
      if (_currentIndex == -1) _currentIndex = 0;
    });
  }

  // 切换排序顺序
  void _toggleSortOrder() {
    final newOrder = _sortOrder == PlaylistSortOrder.ascending
        ? PlaylistSortOrder.descending
        : PlaylistSortOrder.ascending;
    _sortPlaylist(_sortType, newOrder);
  }

  Future<void> _openMedia(String filePath) async {
    if (_openingMedia || !mounted || _disposing) return;
    _openingMedia = true;
    try {
    await _flushPosition();
    // 检查是否为HTTP/HTTPS URL
    final isHttpUrl =
        filePath.startsWith('http://') || filePath.startsWith('https://');

    final isFileUrl = filePath.startsWith('file://');

    // 根据是否为HTTP URL选择不同的处理方式
    String resolvedPath;
    if (isHttpUrl) {
      // HTTP URL直接使用，不需要解析.lnk
      resolvedPath = filePath;
    } else if (isFileUrl) {
      // 处理file:// URI
      filePath = convertUriToPath(filePath);
      resolvedPath = await resolveLnkFile(filePath);
    } else {
      // 本地文件需要解析.lnk
      resolvedPath = await resolveLnkFile(filePath);
    }

    if (!mounted || _disposing) return;
    // 更新当前播放文件路径
    setState(() {
      _currentFilePath = filePath;
    });

    // 创建播放列表
    final List<Media> mediaList = [];
    if (widget.mediaQueue != null) {
      for (final file in _playlist) { mediaList.add(Media(file.path, httpHeaders: _mediaFor(file.path)?.httpHeaders)); }
      _currentIndex = _playlist.indexWhere((f) => f.path == filePath);
      if (_currentIndex < 0) _currentIndex = 0;
    } else if (isHttpUrl || isFileUrl) {
      // HTTP URL直接创建单个媒体项
      mediaList.add(Media(resolvedPath));
    } else {
      // 本地文件从播放列表创建
      for (final file in _playlist) {
        final path = await resolveLnkFile(file.path);
        mediaList.add(Media(path));
      }
    }

    if (mediaList.isEmpty) mediaList.add(Media(resolvedPath));
    _openedPaths = (widget.mediaQueue != null || (!isHttpUrl && !isFileUrl)) && _playlist.isNotEmpty
        ? _playlist.map((f) => f.path).toList() : [filePath];
    // A file picked outside the current folder must not open the first queue item.
    if (!_openedPaths.contains(filePath)) {
      mediaList.add(Media(resolvedPath, httpHeaders: _mediaFor(filePath)?.httpHeaders));
      _openedPaths.add(filePath);
    }
    final selected = _openedPaths.indexOf(filePath);
    final playlist = Playlist(mediaList, index: selected < 0 ? 0 : selected);
    await _beginHistory(filePath);
    if (!mounted || _disposing) return;

    await _applyMpvHardwareDecoding();

    // 打开播放列表
    PlaybackSleepTimer.instance.attach(this, () => player.pause());
    await player.open(playlist);
    _readyForRestore = true;
    player.setPlaylistMode(_loopMode);
    _tryRestorePosition();
    final remoteSubtitles = _mediaFor(filePath)?.subtitles ?? [];
    if (remoteSubtitles.isNotEmpty) await _loadRemoteSubtitle(filePath, remoteSubtitles);
    await applyPlaybackPreferences(player, _historyId);

    // 更新 Audio Service 的媒体信息
    _updateMediaItem();

    // 自动检测并载入字幕文件（仅对特定目录下的本地文件）
    if (!isHttpUrl && !isFileUrl) {
      await _autoLoadSubtitle(resolvedPath);
    }

    // 检测 HDR 视频并调节亮度（仅对本地文件）
    if (!isHttpUrl && !isFileUrl) {
      _checkAndHandleHDR(resolvedPath);
    }
      } catch (e) {
      if (mounted && !_disposing) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('播放失败: $e')));
    } finally { _openingMedia = false; }
  }

  Future<void> _loadRemoteSubtitle(String url, List<String> candidates) async {
    final id = _historyId;
    final preferences = await PlaybackToolsStore.preferences(id);
    final matches = matchSubtitles(_mediaTitle(url), candidates, preferredLanguage: preferences.subtitleLanguage);
    if (mounted && !_disposing && id == _historyId) await player.setSubtitleTrack(SubtitleTrack.uri(matches.isEmpty ? candidates.first : matches.first));
  }

  Future<void> _autoLoadSubtitle(String filePath) async {
    final id = _historyId;
    try {
      final preferences = await PlaybackToolsStore.preferences(id);
      if (preferences.subtitleTrack != null && preferences.subtitleTrack != 'auto') return;
      final directory = Directory(path.dirname(filePath));
      if (!await directory.exists()) return;
      final files = await directory.list().where((entry) => entry is File).map((entry) => entry.path).toList();
      final matches = matchSubtitles(filePath, files, preferredLanguage: preferences.subtitleLanguage);
      if (matches.isNotEmpty && mounted && !_disposing && id == _historyId) {
        await player.setSubtitleTrack(SubtitleTrack.uri(matches.first, title: path.basename(matches.first)));
      }
    } catch (_) {}
  }

  Future<void> _onQueueItemChanged(String url) async {
    try {
      await _beginHistory(url);
      if (!mounted || _disposing) return;
      _tryRestorePosition();
      final subtitles = _mediaFor(url)?.subtitles ?? [];
      if (subtitles.isNotEmpty) await _loadRemoteSubtitle(url, subtitles);
      await applyPlaybackPreferences(player, _historyId);
      _updateMediaItem();
    } catch (_) {}
  }

  Future<void> _seekActivePlayback(Duration position) => _pipController?.seek(position) ?? player.seek(position);
  NativePipController? _pipController;
  bool _pipPlaying = false;
  bool _openingPip = false;
  Future<void> _openSystemPip() async {
    if (Platform.operatingSystem != 'ohos' || _openingMedia || _openingPip || _pipController != null) return;
    _openingPip = true;
    final wasPlaying = player.state.playing;
    PipPlaybackResult? resumed;
    try {
      if (mounted) setState(() => _showSettings = false);
      final position = player.state.position;
      final media = _mediaFor(_currentFilePath);
      final uri = await resolveLnkFile(_currentFilePath);
      await player.pause();
      await _flushPosition();
      if (!mounted || _disposing) return;
      final pip = NativePipController();
      _pipController = pip;
      _pipPlaying = wasPlaying;
      resumed = await Navigator.push<PipPlaybackResult>(context, MaterialPageRoute(builder: (_) => NativePipPage(uri: uri, positionMs: position.inMilliseconds, playing: wasPlaying, headers: media?.httpHeaders ?? {}, controller: pip,
        onPosition: (state) {
          if (_disposing || !mounted) return;
          _lastPosition = Duration(milliseconds: state.positionMs);
          _pipPlaying = state.playing;
          _flushPosition();
          _updatePlaybackState();
        })));
    } catch (_) {
      if (mounted && !_disposing) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('画中画暂时无法打开，已返回原播放器')));
    } finally {
      _pipController = null;
      _openingPip = false;
      if (mounted && !_disposing) {
        PlaybackSleepTimer.instance.attach(this, () => player.pause());
        if (resumed != null) { _lastPosition = Duration(milliseconds: resumed.positionMs); await player.seek(_lastPosition); }
        if (resumed?.playing ?? wasPlaying) await player.play();
      }
    }
  }

  Future<void> _showPlaybackTools() async {
    if (_historyId.isEmpty) return;
    await showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => PlaybackToolsSheet(
      player: player, mediaId: _historyId, loopStart: _pointA, loopEnd: _pointB,
      onBookmark: (start, end) { setState(() { _pointA = end == null ? null : start; _pointB = end; }); player.seek(start); }));
  }

  bool _initialSeekConsumed = false;
  Future<void> _beginHistory(String url) async {
    _readyForRestore = !_openingMedia;
    final media = _mediaFor(url);
    _historyId = media?.id ?? PlaybackMedia.localId(url);
    final previous = await _historyService.getHistoryByPath(_historyId);
    _resumePosition = !_initialSeekConsumed && widget.initialPositionMs != null ? widget.initialPositionMs
      : _useSeekToLatest ? (previous?.lastPosition ?? media?.startPositionMs) : null;
    _initialSeekConsumed = true;
    _hasRestoredPosition = false;
    _lastPosition = Duration.zero;
    await _historyService.updateHistory(HistoryItem(filePath: _historyId, durationMs: previous?.durationMs ?? 0,
      lastPosition: previous?.lastPosition ?? 0, lastPlayed: DateTime.now(),
      mediaType: {'.mp3', '.flac', '.m4a', '.wav', '.ogg', '.aac', '.opus'}.contains(path.extension(media?.title ?? url).toLowerCase()) ? 'audio' : 'video', title: _mediaTitle(url)));
  }

  void _tryRestorePosition() {
    if (_disposing || !_readyForRestore || _hasRestoredPosition || player.state.duration <= Duration.zero) return;
    _hasRestoredPosition = true;
    final position = _resumePosition;
    _resumePosition = null;
    if (position != null && position > 0 && position < player.state.duration.inMilliseconds * 0.95) {
      player.seek(Duration(milliseconds: position));
    }
  }

  Future<void> _flushPosition() async {
    final id = _historyId;
    final position = _lastPosition;
    final media = _mediaFor(_currentFilePath);
    if (media != null && widget.onPlayback != null) {
      unawaited(widget.onPlayback!(media, position.inMilliseconds, _disposing, !_disposing && (_pipController != null ? _pipPlaying : player.state.playing)).catchError((_) {}));
    }
    if (id.isEmpty || position <= Duration.zero) return;
    _lastCheckpoint = DateTime.now();
    try { await _historyService.updatePosition(id, position.inMilliseconds); } catch (_) {}
  }

  void _updatePlaybackPosition(Duration position) {
    if (_disposing || _openingMedia || _pipController != null || _seeking || position <= Duration.zero) return;
    _lastPosition = position;
    if (DateTime.now().difference(_lastCheckpoint) >= const Duration(seconds: 5)) _flushPosition();
  }

  void _updateVideoDuration(Duration duration) {
    if (_historyId.isNotEmpty && duration > Duration.zero) {
      _historyService.updateDuration(_historyId, duration.inMilliseconds).catchError((_) {});
      _tryRestorePosition();
    }
  }

  void _checkABLoop(Duration position) {
    if (_pointA != null && _pointB != null) {
      if (position >= _pointB!) {
        player.seek(_pointA!);
      }
    }
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    _controlsAnimationController.forward();

    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted &&
          player.state.playing &&
          !_showSettings &&
          !_showPlaylist &&
          !_isMouseHovering) {
        _controlsAnimationController.reverse();
        if (mounted) {
          setState(() {
            _showControls = false;
          });
        }
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (_showControls) {
        _controlsAnimationController.forward();
        _resetHideTimer();
      } else {
        _controlsAnimationController.reverse();
        _hideTimer?.cancel();
      }
    });
  }

  void _toggleFullScreen() {
    setState(() {
      _isFullScreen = !_isFullScreen;
      if (_isFullScreen) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
      }
    });
  }

  void _playNext() {
    if (_pipController != null) return;
    if (_playlist.isEmpty) return;
    _currentIndex = (_currentIndex + 1) % _playlist.length;
    _openMedia(_playlist[_currentIndex].path);
  }

  void _playPrevious() {
    if (_pipController != null) return;
    if (_playlist.isEmpty) return;
    _currentIndex = (_currentIndex - 1 + _playlist.length) % _playlist.length;
    _openMedia(_playlist[_currentIndex].path);
  }

  void _takeScreenshot() async {
    try {
      // 生成时间戳文件名
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final screenshotDir =
          '/storage/Users/currentUser/Download/com.aloereed.aloeplayer/Screenshots';

      // 创建截图目录
      final directory = Directory(screenshotDir);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final filePath = '$screenshotDir/$timestamp.png';

      // 使用 media-kit 的截图功能获取图像数据
      final Uint8List? imageData = await player.screenshot(
          format: 'image/png', includeLibassSubtitles: true);

      if (imageData != null) {
        // 将图像数据写入文件
        final file = File(filePath);
        await file.writeAsBytes(imageData);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('截图已保存至: $filePath')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('截图失败：无法获取图像数据')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('截图失败: $e')),
        );
      }
    }
  }

  void _openSubtitleFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['srt', 'ass', 'ssa', 'vtt'],
    );

    if (result != null) {
      final file = File(result.files.single.path!);

      // 对于 ASS/SSA 字幕，使用 libmpv 内置的 libass 渲染
      // 传递额外的字幕选项以确保正确渲染特效
      if (file.path.toLowerCase().endsWith('.ass') ||
          file.path.toLowerCase().endsWith('.ssa')) {
        // 使用 SubtitleTrack.uri 加载 ASS 字幕
        // libmpv 会自动使用内置的 libass 进行渲染
        player.setSubtitleTrack(
          SubtitleTrack.uri(
            file.path,
            title: path.basenameWithoutExtension(file.path),
            language: 'auto',
          ),
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已加载 ASS 特效字幕: ${_mediaTitle(file.path)}')),
        );
      } else {
        // SRT/VTT 等其他格式字幕
        player.setSubtitleTrack(SubtitleTrack.uri(file.path));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已加载字幕: ${_mediaTitle(file.path)}')),
        );
      }
    }
  }

  void _openDanmakuFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xml'],
    );

    if (result != null) {
      final file = File(result.files.single.path!);
      try {
        final xmlContent = await file.readAsString(encoding: utf8);
        final danmakuData = parseDanmakuXml(xmlContent);

        setState(() {
          _danmakuContents = danmakuData;
          _danmakuByTime.clear();
          _sentDanmakuIndexes.clear();

          // 按时间分组弹幕
          for (int i = 0; i < danmakuData.length; i++) {
            final danmaku = danmakuData[i];
            final timeKey = (danmaku['time'] as double).floor();
            if (!_danmakuByTime.containsKey(timeKey)) {
              _danmakuByTime[timeKey] = [];
            }
            _danmakuByTime[timeKey]!.add(danmaku);
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已加载弹幕: ${_mediaTitle(file.path)}')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('弹幕加载失败: $e')),
        );
      }
    }
  }

  void _updateDanmaku(Duration position) {
    if (!_danmakuOn || _danmakuContents.isEmpty) return;

    final currentTime = position.inSeconds;
    final timeKey = currentTime;

    if (_danmakuByTime.containsKey(timeKey)) {
      final danmakus = _danmakuByTime[timeKey]!;
      for (int i = 0; i < danmakus.length; i++) {
        final danmaku = danmakus[i];
        final danmakuIndex = _danmakuContents.indexOf(danmaku);

        if (!_sentDanmakuIndexes.contains(danmakuIndex)) {
          _sentDanmakuIndexes.add(danmakuIndex);

          // 检查弹幕控制器是否已初始化
          if (_danmakuController != null) {
            final content = danmaku['content'] as DanmakuContentItem;
            _danmakuController.addDanmaku(content);
          }
        }
      }
    }
  }

  void _showAudioTrackDialog() async {
    // 获取当前音轨列表
    final tracks = player.state.tracks.audio;
    final currentTrack = player.state.track.audio;

    if (tracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可用的音轨')),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text(
            '选择音轨',
            style: TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                final track = tracks[index];
                final isSelected = currentTrack.id == track.id;

                // 构建音轨显示标题
                String trackTitle = '音轨 ${index + 1}';
                if (track.title != null && track.title!.isNotEmpty) {
                  trackTitle = track.title!;
                } else if (track.language != null &&
                    track.language!.isNotEmpty) {
                  trackTitle = '音轨 ${index + 1} (${track.language})';
                }

                // 添加音轨信息（如果有）
                List<String> trackInfo = [];
                if (track.language != null && track.language!.isNotEmpty) {
                  trackInfo.add(track.language!);
                }
                if (track.codec != null && track.codec!.isNotEmpty) {
                  trackInfo.add(track.codec!);
                }
                if (track.channels != null) {
                  trackInfo.add('${track.channels}ch');
                }

                final subtitle =
                    trackInfo.isNotEmpty ? trackInfo.join(' • ') : null;

                return ListTile(
                  leading: Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: isSelected
                        ? Theme.of(context).primaryColor
                        : Colors.white70,
                  ),
                  title: Text(
                    trackTitle,
                    style: TextStyle(
                      color: isSelected
                          ? Theme.of(context).primaryColor
                          : Colors.white,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle: subtitle != null
                      ? Text(
                          subtitle,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 12,
                          ),
                        )
                      : null,
                  selected: isSelected,
                  onTap: () {
                    player.setAudioTrack(track);
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已切换到: $trackTitle')),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );
  }

  void _showSubtitleTrackDialog() async {
    // 获取当前字幕轨道列表
    final tracks = player.state.tracks.subtitle;
    final currentTrack = player.state.track.subtitle;

    // 字幕轨道可以为空，因为可能没有内置字幕
    // 但我们仍然显示对话框，允许用户选择"无字幕"或加载外部字幕

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text(
            '选择字幕轨道',
            style: TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                // "无字幕"选项
                ListTile(
                  leading: Icon(
                    currentTrack.id == 'no' || currentTrack.id == 'auto'
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: currentTrack.id == 'no' || currentTrack.id == 'auto'
                        ? Theme.of(context).primaryColor
                        : Colors.white70,
                  ),
                  title: Text(
                    '无字幕',
                    style: TextStyle(
                      color:
                          currentTrack.id == 'no' || currentTrack.id == 'auto'
                              ? Theme.of(context).primaryColor
                              : Colors.white,
                      fontWeight:
                          currentTrack.id == 'no' || currentTrack.id == 'auto'
                              ? FontWeight.bold
                              : FontWeight.normal,
                    ),
                  ),
                  onTap: () {
                    // 禁用字幕
                    player.setSubtitleTrack(SubtitleTrack.no());
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已关闭字幕')),
                    );
                  },
                ),

                if (tracks.isNotEmpty) const Divider(color: Colors.white24),

                // 内置字幕轨道列表
                ...tracks.map((track) {
                  final index = tracks.indexOf(track);
                  final isSelected = currentTrack.id == track.id;

                  // 构建字幕轨道显示标题
                  String trackTitle = '字幕 ${index + 1}';
                  if (track.title != null && track.title!.isNotEmpty) {
                    trackTitle = track.title!;
                  } else if (track.language != null &&
                      track.language!.isNotEmpty) {
                    trackTitle = '字幕 ${index + 1} (${track.language})';
                  }

                  // 添加字幕轨道信息（如果有）
                  List<String> trackInfo = [];
                  if (track.language != null && track.language!.isNotEmpty) {
                    trackInfo.add(track.language!);
                  }
                  if (track.codec != null && track.codec!.isNotEmpty) {
                    trackInfo.add(track.codec!);
                  }

                  // 标记内置字幕
                  trackInfo.add('内置');

                  final subtitle =
                      trackInfo.isNotEmpty ? trackInfo.join(' • ') : null;

                  return ListTile(
                    leading: Icon(
                      isSelected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: isSelected
                          ? Theme.of(context).primaryColor
                          : Colors.white70,
                    ),
                    title: Text(
                      trackTitle,
                      style: TextStyle(
                        color: isSelected
                            ? Theme.of(context).primaryColor
                            : Colors.white,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: subtitle != null
                        ? Text(
                            subtitle,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 12,
                            ),
                          )
                        : null,
                    selected: isSelected,
                    onTap: () {
                      player.setSubtitleTrack(track);
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('已切换到: $trackTitle')),
                      );
                    },
                  );
                }).toList(),

                // 分隔线
                if (tracks.isNotEmpty) const Divider(color: Colors.white24),

                // "加载外部字幕"选项
                ListTile(
                  leading: const Icon(Icons.file_open, color: Colors.white70),
                  title: const Text(
                    '加载外部字幕文件...',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    '支持 SRT, ASS, SSA, VTT',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    _openSubtitleFile();
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );
  }

  // 获取键盘快捷键配置
  Map<PlayerHotkey, List<List<LogicalKeyboardKey>>> _getHotkeyShortcuts() {
    return {
      // 空格键 - 播放/暂停
      PlayerHotkey.playPause: [
        [LogicalKeyboardKey.space],
        [LogicalKeyboardKey.keyK],
      ],
      // 左右箭头 - 快进/快退5秒
      PlayerHotkey.seekForward: [
        [LogicalKeyboardKey.arrowRight],
      ],
      PlayerHotkey.seekBackward: [
        [LogicalKeyboardKey.arrowLeft],
      ],
      // Shift + 左右箭头 - 快进/快退30秒
      PlayerHotkey.seekForwardLong: [
        [LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.arrowRight],
        [LogicalKeyboardKey.shiftRight, LogicalKeyboardKey.arrowRight],
        [LogicalKeyboardKey.keyL],
      ],
      PlayerHotkey.seekBackwardLong: [
        [LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.arrowLeft],
        [LogicalKeyboardKey.shiftRight, LogicalKeyboardKey.arrowLeft],
        [LogicalKeyboardKey.keyJ],
      ],
      // 上下箭头 - 音量调节
      PlayerHotkey.volumeUp: [
        [LogicalKeyboardKey.arrowUp],
      ],
      PlayerHotkey.volumeDown: [
        [LogicalKeyboardKey.arrowDown],
      ],
      // M键 - 静音切换
      PlayerHotkey.toggleMute: [
        [LogicalKeyboardKey.keyM],
      ],
      // F键或F11 - 全屏切换
      PlayerHotkey.toggleFullscreen: [
        [LogicalKeyboardKey.keyF],
        [LogicalKeyboardKey.f11],
      ],
      // 速度调节
      PlayerHotkey.speedUp: [
        [LogicalKeyboardKey.bracketRight], // ]
        [LogicalKeyboardKey.equal], // +
      ],
      PlayerHotkey.speedDown: [
        [LogicalKeyboardKey.bracketLeft], // [
        [LogicalKeyboardKey.minus], // -
      ],
      PlayerHotkey.speedReset: [
        [LogicalKeyboardKey.backspace],
      ],
      // N键 - 下一个视频
      PlayerHotkey.nextVideo: [
        [LogicalKeyboardKey.keyN],
        [LogicalKeyboardKey.pageDown],
      ],
      // P键 - 上一个视频
      PlayerHotkey.previousVideo: [
        [LogicalKeyboardKey.keyP],
        [LogicalKeyboardKey.pageUp],
      ],
      // S键 - 截图
      PlayerHotkey.screenshot: [
        [LogicalKeyboardKey.keyS],
      ],
      // C键 - 字幕切换
      PlayerHotkey.toggleSubtitle: [
        [LogicalKeyboardKey.keyC],
      ],
      // D键 - 弹幕切换
      PlayerHotkey.toggleDanmaku: [
        [LogicalKeyboardKey.keyD],
      ],
      // ESC或Q键 - 退出
      PlayerHotkey.quit: [
        [LogicalKeyboardKey.escape],
        [LogicalKeyboardKey.keyQ],
      ],
    };
  }

  // 处理键盘快捷键
  void _handleHotkey(PlayerHotkey hotkey, List<LogicalKeyboardKey> keys) {
    switch (hotkey) {
      case PlayerHotkey.playPause:
        if (player.state.playing) {
          player.pause();
        } else {
          player.play();
        }
        break;

      case PlayerHotkey.seekForward:
        player.seek(player.state.position + const Duration(seconds: 5));
        break;

      case PlayerHotkey.seekBackward:
        final newPosition = player.state.position - const Duration(seconds: 5);
        player.seek(newPosition > Duration.zero ? newPosition : Duration.zero);
        break;

      case PlayerHotkey.seekForwardLong:
        player.seek(player.state.position + const Duration(seconds: 30));
        break;

      case PlayerHotkey.seekBackwardLong:
        final newPosition = player.state.position - const Duration(seconds: 30);
        player.seek(newPosition > Duration.zero ? newPosition : Duration.zero);
        break;

      case PlayerHotkey.volumeUp:
        setSystemVolume(0.1);
        break;

      case PlayerHotkey.volumeDown:
        setSystemVolume(-0.1);
        break;

      case PlayerHotkey.toggleMute:
        if (player.state.volume > 0) {
          _lastVolume = player.state.volume;
          player.setVolume(0.0);
        } else {
          player.setVolume(_lastVolume > 0 ? _lastVolume : 1.0);
        }
        break;

      case PlayerHotkey.toggleFullscreen:
        _toggleFullScreen();
        break;

      case PlayerHotkey.speedUp:
        setState(() {
          _playbackSpeed = (_playbackSpeed + 0.25).clamp(0.25, 16.0);
        });
        player.setRate(_playbackSpeed);
        _showSpeedToast();
        break;

      case PlayerHotkey.speedDown:
        setState(() {
          _playbackSpeed = (_playbackSpeed - 0.25).clamp(0.25, 16.0);
        });
        player.setRate(_playbackSpeed);
        _showSpeedToast();
        break;

      case PlayerHotkey.speedReset:
        setState(() {
          _playbackSpeed = 1.0;
        });
        player.setRate(1.0);
        _showSpeedToast();
        break;

      case PlayerHotkey.nextVideo:
        _playNext();
        break;

      case PlayerHotkey.previousVideo:
        _playPrevious();
        break;

      case PlayerHotkey.screenshot:
        _takeScreenshot();
        break;

      case PlayerHotkey.toggleSubtitle:
        _showSubtitleTrackDialog();
        break;

      case PlayerHotkey.toggleDanmaku:
        setState(() {
          _danmakuOn = !_danmakuOn;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_danmakuOn ? '弹幕已开启' : '弹幕已关闭'),
            duration: const Duration(seconds: 1),
          ),
        );
        break;

      case PlayerHotkey.quit:
        Navigator.pop(context);
        break;
    }
  }

  // 显示速度调整提示
  void _showSpeedToast() {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('播放速度: ${_playbackSpeed.toStringAsFixed(2)}x'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  void dispose() {
    _disposing = true;
    _imageEnhancer.dispose();
    PlaybackSleepTimer.instance.detach(this);
    _flushPosition();
    for (final subscription in _subscriptions) { subscription.cancel(); }

    _speedAdjustTimer?.cancel(); // 清理定时器
    _brightnessSliderTimer?.cancel(); // 清理亮度调节计时器
    _doubleTapTimer?.cancel(); // 清理双击检测定时器
    _hideTimer?.cancel(); // 清理自动隐藏定时器
    _controlsAnimationController.dispose();
    _fadeAnimationController.dispose();

    // 移除应用生命周期监听器
    WidgetsBinding.instance.removeObserver(this);

    // 清理 Audio Service
    if (_audioHandler != null) {
      _audioHandler!.stop();
    }

    // 清理后台播放资源
    _cleanupBackgroundPlayback();

    // 如果是HDR视频，恢复亮度
    if (_isHDRVideo) {
      _restoreBrightness();
    }

    player.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // 恢复所有方向,允许系统自动旋转
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GalacticHotkeys<PlayerHotkey>(
      shortcuts: _getHotkeyShortcuts(),
      onShortcutPressed: _handleHotkey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: MouseRegion(
          onEnter: (_) async {
            if (await _getIsPcMode()) _isMouseHovering = true;
          },
          onExit: (_) async {
            if (await _getIsPcMode()) _isMouseHovering = false;
          },
          onHover: (_) async {
            if (await _getIsPcMode()) _resetHideTimer();
          },
          child: GestureDetector(
            onTapDown: (details) {
              _toggleControls();
            },
            onDoubleTapDown: (details) {
              final screenWidth = MediaQuery.of(context).size.width;
              final tapPosition = details.globalPosition;

              // 判断双击位置并执行相应操作
              if (tapPosition.dx < screenWidth / 4) {
                // 左侧1/4区域：快退10秒
                player
                    .seek(player.state.position - const Duration(seconds: 10));
              } else if (tapPosition.dx > screenWidth * 3 / 4) {
                // 右侧1/4区域：快进10秒
                player
                    .seek(player.state.position + const Duration(seconds: 10));
              } else {
                // 中间区域：播放/暂停
                if (player.state.playing) {
                  player.pause();
                } else {
                  player.play();
                }
              }
            },
            onLongPressStart: (details) {
              // 长按开始，默认2倍速
              setState(() {
                _isLongPressing = true;
                _isAdjustingSpeed = false; // 初始状态为未调整
                _tempSpeed = 2.0;
                _lastSignificantSpeed = 2.0; // 记录初始速度
                _longPressStartPosition = details.globalPosition;
              });
              player.setRate(_tempSpeed);

              // 取消之前的定时器
              _speedAdjustTimer?.cancel();
            },
            onLongPressMoveUpdate: (details) {
              // 长按移动，根据水平滑动距离调整速度
              if (_longPressStartPosition != null) {
                final delta =
                    details.globalPosition.dx - _longPressStartPosition!.dx;
                // 向左滑减速到1.0x，向右滑加速到3x
                // delta范围：-100到100像素对应1.0x到3x
                final speed = (2.0 + (delta / 100.0) * 0.5).clamp(1.0, 3.0);

                // 检查速度是否有显著变化（变化超过0.1x）
                final hasSignificantChange =
                    (speed - _lastSignificantSpeed).abs() >= 0.1;

                if (hasSignificantChange) {
                  setState(() {
                    _tempSpeed = speed;
                    _isAdjustingSpeed = true; // 有显著变化时才为true
                    _lastSignificantSpeed = speed; // 更新上次显著速度
                  });
                  player.setRate(_tempSpeed);

                  // 取消之前的定时器
                  _speedAdjustTimer?.cancel();

                  // 启动新的定时器，1秒内没有显著变化则设置为false
                  _speedAdjustTimer = Timer(const Duration(seconds: 1), () {
                    if (mounted) {
                      setState(() {
                        _isAdjustingSpeed = false;
                      });
                    }
                  });
                } else {
                  // 没有显著变化，只更新速度但不改变_isAdjustingSpeed
                  setState(() {
                    _tempSpeed = speed;
                  });
                  player.setRate(_tempSpeed);
                }
              }
            },
            onLongPressEnd: (details) {
              // 长按结束，恢复原速度
              _speedAdjustTimer?.cancel(); // 取消定时器
              setState(() {
                _isLongPressing = false;
                _isAdjustingSpeed = false; // 长按结束时设置为false
                _longPressStartPosition = null;
              });
              player.setRate(_playbackSpeed);
            },
            // 修改 onHorizontalDragUpdate 和 onHorizontalDragEnd 方法
            onHorizontalDragStart: (details) {
              if (!_isLongPressing) {
                // 记录拖动开始时的播放位置和屏幕位置
                setState(() {
                  _dragStartPosition = player.state.position;
                  _dragStartOffset = details.globalPosition;
                  _seeking = true;
                });
              }
            },
            onHorizontalDragUpdate: (details) {
              if (!_isLongPressing &&
                  _dragStartPosition != null &&
                  _dragStartOffset != null) {
                // 水平滑动快进/快退
                // 计算相对于起始位置的总距离
                final totalDelta =
                    details.globalPosition.dx - _dragStartOffset!.dx;

                // 使用更合理的系数：每100像素约10秒
                final seekSeconds = (totalDelta * 10 / 100).round();
                final newPosition =
                    _dragStartPosition! + Duration(seconds: seekSeconds);

                // 确保新位置在有效范围内
                final clampedPosition = Duration(
                  milliseconds: newPosition.inMilliseconds
                      .clamp(0, player.state.duration.inMilliseconds),
                );

                setState(() {
                  _seekPosition = clampedPosition;
                });
              }
            },
            onHorizontalDragEnd: (details) {
              if (!_isLongPressing && _seekPosition != null) {
                player.seek(_seekPosition!);
                setState(() {
                  _seeking = false;
                  _seekPosition = null;
                  _dragStartPosition = null;
                  _dragStartOffset = null;
                });
              } else if (_dragStartPosition != null) {
                setState(() {
                  _seeking = false;
                  _dragStartPosition = null;
                  _dragStartOffset = null;
                });
              }
            },

            // 垂直滑动相关
            onVerticalDragStart: (details) {
              if (!_isLongPressing) {
                setState(() => _isVerticalDragging = true);
              }
            },
            onVerticalDragUpdate: (details) async {
              if (!_isLongPressing && _isVerticalDragging) {
                // 获取滑动的起始位置
                double screenWidth = MediaQuery.of(context).size.width;
                double touchX = details.localPosition.dx;
                // 判断滑动区域
                if (touchX < screenWidth / 3) {
                  // 左侧 1/3 区域：调整亮度
                  double delta = details.primaryDelta ?? 0;
                  double currentBrightness = (await Screen.brightness) ?? 0.5;
                  if (delta < 0) {
                    // 上滑增加亮度
                    currentBrightness =
                        (currentBrightness + 0.005).clamp(0.0, 0.99);
                  } else if (delta > 0) {
                    // 下滑减少亮度
                    currentBrightness =
                        (currentBrightness - 0.005).clamp(0.0, 0.99);
                  }
                  // 设置亮度
                  Screen.setBrightness(currentBrightness);
                  // 显示亮度滑块
                  setState(() => _showBrightnessSlider = true);
                  // 重启计时器
                  _brightnessSliderTimer?.start();
                } else if (touchX > screenWidth * 2 / 3) {
                  // 右侧 1/3 区域：调整音量
                  double delta = details.primaryDelta ?? 0;
                  if (delta < 0) {
                    // 上滑增加音量
                    setSystemVolume(0.005);
                  } else if (delta > 0) {
                    // 下滑减少音量
                    setSystemVolume(-0.005);
                  }
                }
              }
            },
            onVerticalDragEnd: (details) {
              if (!_isLongPressing) {
                setState(() => _isVerticalDragging = false);
              }
            },
            child: Stack(
              children: [
                // 视频播放器
                Stack(
                  children: [
                    Positioned.fill(
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..scale(_mirror ? -_zoom : _zoom, _zoom),
                        child: Video(
                          controller: controller,
                          controls: NoVideoControls,
                          pauseUponEnteringBackgroundMode:
                              !_backgroundPlayEnabled,
                        ),
                      ),
                    ),
                    // 弹幕层
                    Positioned.fill(
                      child: DanmakuScreen(
                        key: _danmuKey,
                        createdController: (DanmakuController e) {
                          _danmakuController = e;
                        },
                        option: DanmakuOption(
                          fontSize: _danmakuFontSize,
                          fontWeight: _danmakuFontWeight,
                          opacity: _danmakuOpacity,
                          duration: _danmakuDuration,
                          showStroke: _danmakuShowStroke,
                          hideScroll: _danmakuHideScroll,
                          hideTop: _danmakuHideTop,
                          hideBottom: _danmakuHideBottom,
                        ),
                      ),
                    ),
                  ],
                ),

                // 长按无极调速指示器
                if (_isLongPressing) _buildSpeedIndicator(),

                // 高斯模糊背景控制层
                AnimatedBuilder(
                  animation: _controlsAnimationController,
                  builder: (context, child) {
                    return IgnorePointer(
                      ignoring: _controlsAnimationController.value == 0,
                      child: Opacity(
                        opacity: _controlsAnimationController.value,
                        child: child,
                      ),
                    );
                  },
                  child: Column(
                    children: [
                      FutureBuilder<bool>(
                        future: _getIsPcMode(),
                        initialData: false,
                        builder: (context, snapshot) {
                          return (snapshot.data == true)
                              ? _buildPcMenuBar()
                              : _buildTopBar();
                        },
                      ),
                      const Spacer(),
                      _buildBottomControls(),
                    ],
                  ),
                ),

                // 快进/快退提示
                if (_seeking && _seekPosition != null) _buildSeekIndicator(),

                // 缓冲指示器
                if (_isBuffering) _buildBufferingIndicator(),

                // 设置面板背景遮罩（用于点击关闭）
                if (_showSettings)
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () => setState(() => _showSettings = false),
                      child: Container(color: Colors.transparent),
                    ),
                  ),

                // 播放列表背景遮罩（用于点击关闭）
                if (_showPlaylist)
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () => setState(() => _showPlaylist = false),
                      child: Container(color: Colors.transparent),
                    ),
                  ),

                // 设置面板
                if (_showSettings) _buildSettingsPanel(),

                // 播放列表
                if (_showPlaylist) _buildPlaylistPanel(),

                // 亮度滑块
                if (_showBrightnessSlider) _buildBrightnessSlider(),

                // Offstage包装的VolumeExample组件
                Offstage(
                  offstage: _volumeExample == null,
                  child: SizedBox(
                    width: 1,
                    height: 1,
                    child: _volumeExample!,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuButton(String title, List<PopupMenuEntry<dynamic>> items) {
    return Theme(
      data: Theme.of(context).copyWith(
        popupMenuTheme: PopupMenuThemeData(
          color: Colors.grey[900],
          textStyle: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      child: PopupMenuButton(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
        ),
        itemBuilder: (context) => items,
        offset: const Offset(0, 40),
      ),
    );
  }

  Widget _buildPcMenuBar() {
    return Material(
      color: Colors.transparent,
      child: Container(
        // height: 56, // remove fixed height

        decoration: BoxDecoration(
          gradient: widget.nativeHdr ? null : LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.9), // 更深的背景
              Colors.black.withOpacity(0.5),
            ],
          ),
        ),
        child: SafeArea(
          // Ensure it doesn't overlap status bar
          bottom: false,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
                tooltip: '返回',
              ),
              // FILE
              _buildMenuButton(
                '文件',
                [
                  PopupMenuItem(
                    child: ListTile(
                      leading: const Icon(Icons.file_open, color: Colors.white),
                      title: const Text('打开文件',
                          style: TextStyle(color: Colors.white)),
                      onTap: () {
                        Navigator.pop(context);
                        _pickVideoFile();
                      },
                    ),
                  ),
                  PopupMenuItem(
                    child: ListTile(
                      leading:
                          const Icon(Icons.exit_to_app, color: Colors.white),
                      title: const Text('退出',
                          style: TextStyle(color: Colors.white)),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.pop(context);
                      },
                    ),
                  ),
                ],
              ),
              // PLAYBACK
              _buildMenuButton('播放', [
                PopupMenuItem(
                  child: ListTile(
                    leading: Icon(
                        player.state.playing ? Icons.pause : Icons.play_arrow,
                        color: Colors.white),
                    title: Text(player.state.playing ? '暂停' : '播放',
                        style: const TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(context);
                      if (player.state.playing)
                        player.pause();
                      else
                        player.play();
                    },
                  ),
                ),
                PopupMenuItem(
                  child: ListTile(
                    leading: const Icon(Icons.stop, color: Colors.white),
                    title:
                        const Text('停止', style: TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(context);
                      player.pause();
                      player.seek(Duration.zero);
                    },
                  ),
                ),
                PopupMenuItem(
                  child: ListTile(
                    leading: const Icon(Icons.speed, color: Colors.white),
                    title: Text('播放速度 (${_playbackSpeed}x)',
                        style: const TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(context);
                      // 循环切换速度: 0.5 -> 1.0 -> 1.5 -> 2.0 -> 3.0 -> 0.5
                      double newSpeed;
                      if (_playbackSpeed == 0.5)
                        newSpeed = 1.0;
                      else if (_playbackSpeed == 1.0)
                        newSpeed = 1.25;
                      else if (_playbackSpeed == 1.25)
                        newSpeed = 1.5;
                      else if (_playbackSpeed == 1.5)
                        newSpeed = 2.0;
                      else if (_playbackSpeed == 2.0)
                        newSpeed = 3.0;
                      else
                        newSpeed = 0.5;

                      setState(() => _playbackSpeed = newSpeed);
                      player.setRate(newSpeed);
                      _showSpeedToast();
                    },
                  ),
                ),
                PopupMenuItem(
                  child: ListTile(
                    leading: const Icon(Icons.loop, color: Colors.white),
                    title: Text(
                        _loopMode == PlaylistMode.none
                            ? '循环模式 (关闭)'
                            : _loopMode == PlaylistMode.single
                                ? '循环模式 (单曲)'
                                : '循环模式 (列表)',
                        style: const TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(context);
                      // Toggle mode
                      PlaylistMode newMode;
                      if (_loopMode == PlaylistMode.none)
                        newMode = PlaylistMode.single;
                      else if (_loopMode == PlaylistMode.single)
                        newMode = PlaylistMode.loop;
                      else
                        newMode = PlaylistMode.none;

                      setState(() => _loopMode = newMode);
                      player.setPlaylistMode(newMode);
                    },
                  ),
                ),
              ]),
              // VIDEO
              _buildMenuButton('视频', [
                PopupMenuItem(
                  child: ListTile(
                    leading: Icon(
                        _isFullScreen
                            ? Icons.fullscreen_exit
                            : Icons.fullscreen,
                        color: Colors.white),
                    title: Text(_isFullScreen ? '退出全屏' : '全屏',
                        style: const TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(context);
                      _toggleFullScreen();
                    },
                  ),
                ),
                PopupMenuItem(
                  child: ListTile(
                    // Toggle Mirror
                    leading: const Icon(Icons.flip, color: Colors.white),
                    title: Text('镜像 ${_mirror ? "(开)" : "(关)"}',
                        style: const TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(context);
                      setState(() => _mirror = !_mirror);
                    },
                  ),
                ),
                PopupMenuItem(
                  child: ListTile(
                    leading: const Icon(Icons.camera_alt, color: Colors.white),
                    title:
                        const Text('截图', style: TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(context);
                      _takeScreenshot();
                    },
                  ),
                ),
              ]),
              // AUDIO
              _buildMenuButton('音频', [
                PopupMenuItem(
                  child: ListTile(
                    leading: const Icon(Icons.audiotrack, color: Colors.white),
                    title: const Text('选择音轨',
                        style: TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(context);
                      _showAudioTrackDialog();
                    },
                  ),
                ),
                PopupMenuItem(
                  child: ListTile(
                    leading: Icon(
                        player.state.volume == 0
                            ? Icons.volume_off
                            : Icons.volume_up,
                        color: Colors.white),
                    title:
                        const Text('静音', style: TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(context);
                      if (player.state.volume > 0) {
                        _lastVolume = player.state.volume;
                        player.setVolume(0.0);
                      } else {
                        player.setVolume(_lastVolume > 0 ? _lastVolume : 1.0);
                      }
                    },
                  ),
                ),
              ]),
              // SUBTITLE
              _buildMenuButton('字幕', [
                PopupMenuItem(
                  child: ListTile(
                    leading:
                        const Icon(Icons.closed_caption, color: Colors.white),
                    title: const Text('选择字幕',
                        style: TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(context);
                      _showSubtitleTrackDialog();
                    },
                  ),
                ),
                PopupMenuItem(
                  child: ListTile(
                    leading:
                        const Icon(Icons.file_present, color: Colors.white),
                    title: const Text('加载外部字幕',
                        style: TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(context);
                      _openSubtitleFile();
                    },
                  ),
                ),
                PopupMenuItem(
                  child: ListTile(
                    leading: const Icon(Icons.comment, color: Colors.white),
                    title: Text('弹幕 ${_danmakuOn ? "(开)" : "(关)"}',
                        style: const TextStyle(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(context);
                      setState(() => _danmakuOn = !_danmakuOn);
                    },
                  ),
                ),
              ]),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.playlist_play, color: Colors.white),
                onPressed: () => setState(() => _showPlaylist = !_showPlaylist),
                tooltip: '播放列表',
              ),
              IconButton(
                // Settings (Advanced)
                icon: const Icon(Icons.settings, color: Colors.white),
                onPressed: () => setState(() => _showSettings = !_showSettings),
                tooltip: '设置',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      decoration: BoxDecoration(
        gradient: widget.nativeHdr ? null : LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.7),
            Colors.transparent,
          ],
        ),
      ),
      child: ClipRRect(
        child: BackdropFilter(
          enabled: !widget.nativeHdr,
          filter: ImageFilter.blur(
            sigmaX: _enableBlur ? 10 : 0,
            sigmaY: _enableBlur ? 10 : 0,
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      _currentFilePath.isNotEmpty
                          ? _mediaTitle(_currentFilePath)
                          : _mediaTitle(widget.filePath),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.playlist_play, color: Colors.white),
                    onPressed: () =>
                        setState(() => _showPlaylist = !_showPlaylist),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings, color: Colors.white),
                    onPressed: () =>
                        setState(() => _showSettings = !_showSettings),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    final position = _seekPosition ?? player.state.position;
    final duration = player.state.duration;

    return Container(
      decoration: BoxDecoration(
        gradient: widget.nativeHdr ? null : LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withOpacity(0.8),
            Colors.transparent,
          ],
        ),
      ),
      child: ClipRRect(
        child: BackdropFilter(
          enabled: !widget.nativeHdr,
          filter: ImageFilter.blur(
            sigmaX: _enableBlur ? 10 : 0,
            sigmaY: _enableBlur ? 10 : 0,
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 进度条
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    children: [
                      Text(
                        _formatDuration(position),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 14),
                            activeTrackColor: Theme.of(context).primaryColor,
                            inactiveTrackColor: Colors.white.withOpacity(0.3),
                            thumbColor: Colors.white,
                            overlayColor:
                                Theme.of(context).primaryColor.withOpacity(0.3),
                          ),
                          child: Slider(
                            value: position.inMilliseconds.toDouble(),
                            max: duration.inMilliseconds.toDouble(),
                            onChanged: (value) {
                              setState(() {
                                _seeking = true;
                                _seekPosition =
                                    Duration(milliseconds: value.toInt());
                              });
                            },
                            onChangeEnd: (value) {
                              player
                                  .seek(Duration(milliseconds: value.toInt()));
                              setState(() {
                                _seeking = false;
                                _seekPosition = null;
                              });
                            },
                          ),
                        ),
                      ),
                      Text(
                        _formatDuration(duration),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),

                // 控制按钮
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildControlButton(
                        icon: player.state.volume > 0
                            ? Icons.volume_up
                            : Icons.volume_off,
                        onPressed: () {
                          if (player.state.volume > 0) {
                            _lastVolume = player.state.volume;
                            player.setVolume(0.0);
                          } else {
                            player
                                .setVolume(_lastVolume > 0 ? _lastVolume : 1.0);
                          }
                        },
                      ),
                      _buildControlButton(
                        icon: Icons.skip_previous,
                        onPressed: _playPrevious,
                      ),
                      _buildControlButton(
                        icon: player.state.playing
                            ? Icons.pause
                            : Icons.play_arrow,
                        onPressed: () {
                          if (player.state.playing) {
                            player.pause();
                          } else {
                            player.play();
                          }
                        },
                        size: 48,
                      ),
                      _buildControlButton(
                        icon: Icons.skip_next,
                        onPressed: _playNext,
                      ),
                      _buildControlButton(
                        icon: _isFullScreen
                            ? Icons.fullscreen_exit
                            : Icons.fullscreen,
                        onPressed: _toggleFullScreen,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onPressed,
    double size = 32,
  }) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(0.1),
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: size * 0.6),
        iconSize: size,
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildSeekIndicator() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            enabled: !widget.nativeHdr,
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Text(
              _formatDuration(_seekPosition!),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _switchNativeHdr(bool enabled) async {
    if (_switchingHdr || _disposing) return;
    setState(() => _switchingHdr = true);
    final position = player.state.position.inMilliseconds;
    await player.pause();
    await _flushPosition();
    if (!mounted || _disposing) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => MPVPlayer(
      filePath: _currentFilePath,
      mediaQueue: widget.mediaQueue,
      initialPositionMs: position,
      onPlayback: widget.onPlayback,
      nativeHdr: enabled,
    )));
  }

  Widget _buildSettingsPanel() {
    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      child: Container(
        width: MediaQuery.sizeOf(context).width.clamp(0, 400).toDouble(),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.9),
        ),
        child: ClipRRect(
          child: BackdropFilter(
            enabled: !widget.nativeHdr,
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: SafeArea(
              child: Column(
                children: [
                  // 标题栏
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        const Expanded(child: Text(
                          '播放器设置',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        )),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () =>
                              setState(() => _showSettings = false),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white24),

                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (!widget.nativeHdr)
                        ListenableBuilder(listenable: _imageEnhancer, builder: (_, __) => Card(
                          color: const Color(0xFF183547), elevation: 0,
                          child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            leading: const Icon(Icons.auto_awesome_outlined, color: Color(0xFF8DD2F5)),
                            title: const Text('超分与画质', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                            subtitle: Text(_imageEnhancer.settings.mode.label, style: const TextStyle(color: Colors.white70)),
                            trailing: const Icon(Icons.chevron_right, color: Colors.white70),
                            onTap: () {
                              setState(() => _showSettings = false);
                              showImageEnhancementSheet(context, _imageEnhancer);
                            }))),
                        if (Platform.operatingSystem == 'ohos') ListTile(
                          leading: const Icon(Icons.picture_in_picture_alt, color: Colors.white),
                          title: const Text('系统画中画', style: TextStyle(color: Colors.white)),
                          subtitle: const Text('在悬浮小窗中继续播放', style: TextStyle(color: Colors.white70)),
                          onTap: _openSystemPip),
                        const Divider(color: Colors.white24, height: 24),
                        _buildSettingItem(
                          title: '播放速度',
                          subtitle: '${_playbackSpeed}x',
                          child: Column(
                            children: [
                              Slider(
                                value: _playbackSpeed.clamp(0.25, 3.0),
                                min: 0.25,
                                max: 3.0,
                                divisions: 11,
                                label: '${_playbackSpeed}x',
                                onChanged: (value) {
                                  setState(() => _playbackSpeed = value);
                                  player.setRate(value);
                                },
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _buildSpeedButton(1.0),
                                  _buildSpeedButton(4.0),
                                  _buildSpeedButton(8.0),
                                  _buildSpeedButton(16.0),
                                ],
                              ),
                            ],
                          ),
                        ),
                        _buildSettingItem(
                          title: '缩放',
                          subtitle: '${(_zoom * 100).toInt()}%',
                          child: Slider(
                            value: _zoom,
                            min: 0.5,
                            max: 2.0,
                            divisions: 15,
                            label: '${(_zoom * 100).toInt()}%',
                            onChanged: (value) {
                              setState(() => _zoom = value);
                            },
                          ),
                        ),
                        _buildSettingSwitch(
                          title: '镜像',
                          value: _mirror,
                          onChanged: (value) => setState(() => _mirror = value),
                        ),
                        _buildSettingSwitch(
                          title: '控制栏高斯模糊',
                          value: _enableBlur,
                          onChanged: (value) =>
                              setState(() => _enableBlur = value),
                        ),
                        _buildSettingSwitch(
                          title: '后台播放',
                          value: _backgroundPlayEnabled,
                          onChanged: _toggleBackgroundPlay,
                        ),
                        ListTile(leading: const Icon(Icons.tune, color: Colors.white), title: const Text('字幕同步、书签与章节', style: TextStyle(color: Colors.white)), onTap: _showPlaybackTools),
                        ListTile(leading: const Icon(Icons.bedtime_outlined, color: Colors.white), title: const Text('定时停止', style: TextStyle(color: Colors.white)), onTap: () => showSleepTimer(context)),
                        _buildSettingItem(
                          title: '循环模式',
                          child: SegmentedButton<PlaylistMode>(
                            segments: const [
                              ButtonSegment(
                                value: PlaylistMode.none,
                                label:
                                    Text('关闭', style: TextStyle(fontSize: 12)),
                              ),
                              ButtonSegment(
                                value: PlaylistMode.single,
                                label:
                                    Text('单曲', style: TextStyle(fontSize: 12)),
                              ),
                              ButtonSegment(
                                value: PlaylistMode.loop,
                                label:
                                    Text('列表', style: TextStyle(fontSize: 12)),
                              ),
                            ],
                            selected: {_loopMode},
                            onSelectionChanged:
                                (Set<PlaylistMode> newSelection) {
                              setState(() => _loopMode = newSelection.first);
                              player.setPlaylistMode(newSelection.first);
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'AB循环',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(
                                  Icons.looks_one,
                                ),
                                label: Text(
                                  _pointA != null
                                      ? _formatDuration(_pointA!)
                                      : '设置A点',
                                ),
                                onPressed: () {
                                  setState(
                                      () => _pointA = player.state.position);
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(
                                  Icons.looks_two,
                                ),
                                label: Text(
                                  _pointB != null
                                      ? _formatDuration(_pointB!)
                                      : '设置B点',
                                ),
                                onPressed: () {
                                  setState(
                                      () => _pointB = player.state.position);
                                },
                              ),
                            ),
                          ],
                        ),
                        if (_pointA != null || _pointB != null)
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _pointA = null;
                                _pointB = null;
                              });
                            },
                            child: const Text('清除AB点'),
                          ),
                        const Divider(color: Colors.white24),
                        ListTile(
                          leading:
                              const Icon(Icons.subtitles, color: Colors.white),
                          title: const Text('加载字幕文件',
                              style: TextStyle(color: Colors.white)),
                          onTap: _openSubtitleFile,
                        ),
                        ListTile(
                          leading:
                              const Icon(Icons.comment, color: Colors.white),
                          title: const Text('加载弹幕文件',
                              style: TextStyle(color: Colors.white)),
                          onTap: _openDanmakuFile,
                        ),
                        ListTile(
                          leading:
                              const Icon(Icons.camera_alt, color: Colors.white),
                          title: const Text('截图',
                              style: TextStyle(color: Colors.white)),
                          onTap: _takeScreenshot,
                        ),
                        ListTile(
                          leading:
                              const Icon(Icons.audiotrack, color: Colors.white),
                          title: const Text('音轨切换',
                              style: TextStyle(color: Colors.white)),
                          onTap: _showAudioTrackDialog,
                        ),
                        ListTile(
                          leading: const Icon(Icons.closed_caption,
                              color: Colors.white),
                          title: const Text('字幕轨道切换',
                              style: TextStyle(color: Colors.white)),
                          onTap: _showSubtitleTrackDialog,
                        ),
                        const Divider(color: Colors.white24),
                        _buildSettingItem(
                          title: '弹幕设置',
                          child: Column(
                            children: [
                              _buildSettingSwitch(
                                title: '启用弹幕',
                                value: _danmakuOn,
                                onChanged: (value) =>
                                    setState(() => _danmakuOn = value),
                              ),
                              const SizedBox(height: 8),
                              _buildSettingItem(
                                title: '弹幕透明度',
                                subtitle: '${(_danmakuOpacity * 100).toInt()}%',
                                child: Slider(
                                  value: _danmakuOpacity,
                                  min: 0.1,
                                  max: 1.0,
                                  divisions: 9,
                                  label: '${(_danmakuOpacity * 100).toInt()}%',
                                  onChanged: (value) {
                                    setState(() => _danmakuOpacity = value);
                                  },
                                ),
                              ),
                              _buildSettingItem(
                                title: '弹幕字体大小',
                                subtitle: '${_danmakuFontSize.toInt()}',
                                child: Slider(
                                  value: _danmakuFontSize,
                                  min: 12.0,
                                  max: 36.0,
                                  divisions: 12,
                                  label: '${_danmakuFontSize.toInt()}',
                                  onChanged: (value) {
                                    setState(() => _danmakuFontSize = value);
                                  },
                                ),
                              ),
                              _buildSettingItem(
                                title: '弹幕显示时间',
                                subtitle: '${_danmakuDuration}秒',
                                child: Slider(
                                  value: _danmakuDuration.toDouble(),
                                  min: 3.0,
                                  max: 15.0,
                                  divisions: 12,
                                  label: '${_danmakuDuration}秒',
                                  onChanged: (value) {
                                    setState(
                                        () => _danmakuDuration = value.toInt());
                                  },
                                ),
                              ),
                              _buildSettingSwitch(
                                title: '显示描边',
                                value: _danmakuShowStroke,
                                onChanged: (value) =>
                                    setState(() => _danmakuShowStroke = value),
                              ),
                              _buildSettingSwitch(
                                title: '隐藏滚动弹幕',
                                value: _danmakuHideScroll,
                                onChanged: (value) =>
                                    setState(() => _danmakuHideScroll = value),
                              ),
                              _buildSettingSwitch(
                                title: '隐藏顶部弹幕',
                                value: _danmakuHideTop,
                                onChanged: (value) =>
                                    setState(() => _danmakuHideTop = value),
                              ),
                              _buildSettingSwitch(
                                title: '隐藏底部弹幕',
                                value: _danmakuHideBottom,
                                onChanged: (value) =>
                                    setState(() => _danmakuHideBottom = value),
                              ),
                            ],
                          ),
                        ),
                        if (Platform.operatingSystem == 'ohos') ExpansionTile(
                          title: const Text('实验功能', style: TextStyle(color: Colors.white70, fontSize: 14)),
                          iconColor: Colors.white54,
                          collapsedIconColor: Colors.white54,
                          children: [
                            SwitchListTile(
                              title: const Text('原生 HDR 输出', style: TextStyle(color: Colors.white)),
                              subtitle: const Text('兼容性有限，需要设备硬解支持；不支持 ASS 特效和超分。切换后从当前进度重新打开。', style: TextStyle(color: Colors.white54, fontSize: 12)),
                              value: widget.nativeHdr,
                              onChanged: _switchingHdr ? null : _switchNativeHdr,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaylistPanel() {
    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      child: Container(
        width: 320,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.9),
        ),
        child: ClipRRect(
          child: BackdropFilter(
            enabled: !widget.nativeHdr,
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        const Text(
                          '播放列表',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () =>
                              setState(() => _showPlaylist = false),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white24),

                  // 排序控制区域
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 排序类型选择
                        Row(
                          children: [
                            const Text(
                              '排序方式:',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SegmentedButton<PlaylistSortType>(
                                segments: const [
                                  ButtonSegment(
                                    value: PlaylistSortType.original,
                                    label: Text('原始',
                                        style: TextStyle(fontSize: 10)),
                                  ),
                                  ButtonSegment(
                                    value: PlaylistSortType.name,
                                    label: Text('名称',
                                        style: TextStyle(fontSize: 10)),
                                  ),
                                  ButtonSegment(
                                    value: PlaylistSortType.modified,
                                    label: Text('时间',
                                        style: TextStyle(fontSize: 10)),
                                  ),
                                ],
                                selected: {_sortType},
                                onSelectionChanged:
                                    (Set<PlaylistSortType> newSelection) {
                                  _sortPlaylist(newSelection.first, _sortOrder);
                                },
                                style: SegmentedButton.styleFrom(
                                  backgroundColor: Colors.grey[800],
                                  foregroundColor: Colors.white,
                                  selectedForegroundColor: Colors.black,
                                  selectedBackgroundColor:
                                      Theme.of(context).primaryColor,
                                ),
                              ),
                            ),
                          ],
                        ),

                        // 排序顺序切换按钮
                        if (_sortType != PlaylistSortType.original) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Text(
                                '排序顺序:',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: InkWell(
                                  onTap: _toggleSortOrder,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[800],
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _sortOrder ==
                                                  PlaylistSortOrder.ascending
                                              ? Icons.arrow_upward
                                              : Icons.arrow_downward,
                                          color: Theme.of(context).primaryColor,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          _sortOrder ==
                                                  PlaylistSortOrder.ascending
                                              ? '升序'
                                              : '降序',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  const Divider(color: Colors.white24),

                  // 播放列表内容
                  Expanded(
                    child: _usePlaylist
                        ? ListView.builder(
                            itemCount: _playlist.length,
                            itemBuilder: (context, index) {
                              final file = _playlist[index];
                              final isPlaying = index == _currentIndex;

                              // Check if this is a .lnk file and get display name
                              String displayName = _mediaTitle(file.path);
                              bool isLnkFile =
                                  file.path.toLowerCase().endsWith('.lnk');

                              return ListTile(
                                leading: Icon(
                                  isPlaying
                                      ? Icons.play_circle_filled
                                      : (isLnkFile
                                          ? Icons.link
                                          : Icons.video_file),
                                  color: isPlaying
                                      ? Theme.of(context).primaryColor
                                      : Colors.white70,
                                ),
                                title: Text(
                                  displayName,
                                  style: TextStyle(
                                    color: isPlaying
                                        ? Theme.of(context).primaryColor
                                        : Colors.white,
                                    fontWeight: isPlaying
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: isLnkFile
                                    ? Text(
                                        '快捷方式',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.6),
                                          fontSize: 12,
                                        ),
                                      )
                                    : null,
                                selected: isPlaying,
                                onTap: () {
                                  setState(() => _currentIndex = index);
                                  _openMedia(file.path);
                                },
                              );
                            },
                          )
                        : Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.playlist_play,
                                  color: Colors.white54,
                                  size: 64,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  '播放列表功能已禁用',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '可在设置中启用"库内同级文件夹播放列表导入"',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingItem({
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 14,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _buildSettingSwitch({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      title: Text(
        title,
        style: const TextStyle(color: Colors.white),
      ),
      value: value,
      onChanged: onChanged,
      activeColor: Theme.of(context).primaryColor,
    );
  }

  Widget _buildSpeedButton(double speed) {
    final isSelected = (_playbackSpeed - speed).abs() < 0.01;
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor:
            isSelected ? Theme.of(context).primaryColor : Colors.grey[800],
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: const Size(50, 32),
      ),
      onPressed: () {
        setState(() => _playbackSpeed = speed);
        player.setRate(speed);
      },
      child: Text('${speed}x', style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _buildSpeedIndicator() {
    // 如果正在调整速度，显示大块；否则显示小横条
    if (_isAdjustingSpeed) {
      // 大块显示模式
      return Positioned(
        top: 100,
        left: 0,
        right: 0,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).primaryColor.withOpacity(0.9),
                  Theme.of(context).primaryColor.withOpacity(0.7),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                enabled: !widget.nativeHdr,
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.fast_forward,
                      color: Colors.white,
                      size: 32,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_tempSpeed.toStringAsFixed(1)}x',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 200,
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor:
                            (_tempSpeed - 1.0) / 2.0, // 1.5-3.0 映射到 0-1
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '1.0x',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.arrow_back,
                          color: Colors.white70,
                          size: 16,
                        ),
                        const SizedBox(width: 20),
                        const Icon(
                          Icons.arrow_forward,
                          color: Colors.white70,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          '3.0x',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      // 小横条显示模式
      return Positioned(
        top: 80,
        left: 0,
        right: 0,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.85),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                enabled: !widget.nativeHdr,
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.fast_forward,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_tempSpeed.toStringAsFixed(1)}x',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
  }

  Widget _buildBrightnessSlider() {
    return Positioned(
      bottom: 100,
      left: 20,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: BackdropFilter(
          enabled: !widget.nativeHdr,
          filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
          child: Container(
            height: 200,
            width: 40,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 0.5,
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.brightness_6,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        activeTrackColor: Colors.white,
                        inactiveTrackColor: Colors.white.withOpacity(0.3),
                        thumbColor: Colors.white,
                        thumbShape:
                            const RoundSliderThumbShape(enabledThumbRadius: 8),
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 12),
                      ),
                      child: BrightnessSlider(
                        onBrightnessChanged: (value) {
                          // Restart the timer when brightness changes
                          _brightnessSliderTimer?.start();
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Icon(
                  Icons.brightness_7,
                  color: Colors.white,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));

    if (duration.inHours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  Widget _buildBufferingIndicator() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            enabled: !widget.nativeHdr,
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    strokeWidth: 4,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).primaryColor,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '缓冲中...',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
