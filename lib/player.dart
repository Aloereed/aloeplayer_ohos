import 'dart:convert';
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:aloeplayer/privacy_policy.dart';
import 'package:xml/xml.dart' as xml;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock/wakelock.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:aloeplayer/chewie-1.8.5/lib/chewie.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:share_plus/share_plus.dart';
import 'package:simple_gesture_detector/simple_gesture_detector.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_subtitle/flutter_subtitle.dart' hide Subtitle;
import 'package:path/path.dart' as path;
import 'videolibrary.dart';
import 'audiolibrary.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:audio_session/audio_session.dart';
import 'package:vivysub_utils/vivysub_utils.dart';
import 'package:audio_service/audio_service.dart';
import 'package:file_picker_ohos/file_picker_ohos.dart';
import 'settings.dart';
import 'theme_provider.dart';
import 'dart:typed_data';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'volumeview.dart';
import 'package:aloeplayer/chewie-1.8.5/lib/src/ffmpegview.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:dart_libass/dart_libass.dart';
import 'history_service.dart';
import 'package:aloeplayer/ass.dart';

// class MyAudioHandler extends BaseAudioHandler {
//   final _player = AudioPlayer();

//   MyAudioHandler() {
//     _player.playbackEventStream.map(_transformEvent).pipe(playbackState);
//   }

//   PlaybackState _transformEvent(PlaybackEvent event) {
//     return PlaybackState(
//       controls: [
//         MediaControl.pause,
//         MediaControl.play,
//         MediaControl.stop,
//       ],
//       systemActions: const {
//         MediaAction.seek,
//       },
//       androidCompactActionIndices: const [0, 1, 2],
//       processingState: const {
//         ProcessingState.idle: AudioProcessingState.idle,
//         ProcessingState.loading: AudioProcessingState.loading,
//         ProcessingState.buffering: AudioProcessingState.buffering,
//         ProcessingState.ready: AudioProcessingState.ready,
//         ProcessingState.completed: AudioProcessingState.completed,
//       }[_player.processingState]!,
//       playing: _player.playing,
//       updatePosition: _player.position,
//       bufferedPosition: _player.bufferedPosition,
//       speed: _player.speed,
//       queueIndex: _player.currentIndex,
//     );
//   }

//   Future<void> play() => _player.play();
//   Future<void> pause() => _player.pause();
//   Future<void> stop() => _player.stop();

//   Future<void> setAudioSource(String url) async {
//     await _player.setUrl(url);
//   }

//   Future<void> setLoopingSilence() async {
//     // 加载 assets 中的静音音频文件
//     await _player.setAudioSource(AudioSource.asset('Assets/10s_silence.wav'));
//     // 设置循环模式为循环播放
//     _player.setLoopMode(LoopMode.one);
//   }
// }

int rgbToColor(int rgb) {
  // 将 RGB 值转换为 ARGB 值，透明度为 0xFF（完全不透明）
  return 0xFF000000 | rgb;
}

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
          'content': DanmakuContentItem(content,
              // time: double.parse(pValues[0]).toInt(), // 弹幕时间
              type: itemType,
              color: Color(rgbToColor(int.parse(pValues[3])))) // 弹幕内容
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

class PlayerTab extends StatefulWidget {
  final VoidCallback toggleFullScreen;
  bool isFullScreen;
  final Function(String) getopenfile;
  final Function(int, int) setHomeWH;
  String openfile;

  PlayerTab(
      {Key? key, // 定义Key参数,
      required this.toggleFullScreen,
      required this.isFullScreen,
      required this.getopenfile,
      required this.openfile,
      required this.setHomeWH});

  @override
  _PlayerTabState createState() => _PlayerTabState();
}

class _PlayerTabState extends State<PlayerTab>
    with SingleTickerProviderStateMixin {
  @override
  // bool get wantKeepAlive => true;
  VideoPlayerController? _videoController;
  double _volume = 1.0;
  double _systemVolume = 7.5;
  double _systemMaxVolume = 15;
  AnimationController? _animeController;
  bool _isPlaying = false;
  bool _showControls = true;
  Timer? _hideTimer;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  double _playbackSpeed = 1.0;
  double _lastVolume = 1.0;
  bool _isMirrored = false;
  bool _isAudio = true;
  bool wantFirst = false;
  bool _showVolumeSlider = false;
  Timer? _volumeSliderTimer;
  Timer? _timer;
  int _isLooping = 0;
  double _previousPlaybackSpeed = 1.0; // 用于存储长按之前的播放速率
  double _swipeDistance = 0.0;
  ChewieController? _chewieController;
  SubtitleController? _subtitleController;
  bool _isLandscape = false;
  Uint8List? coverData;
  double _scale = 1.0; // 当前缩放比例
  double _previousScale = 1.0; // 上一次缩放比例
  final SettingsService _settingsService = SettingsService();
  String receivedData = '';
  VolumeViewController? _volumeController;
  FfmpegViewController? _ffmpegController;
  VolumeExample? _volumeExample;
  FfmpegExample? _ffmpegExample;
  List<SubtitleData> _subtitles = []; // 存储所有字幕
  int _currentSubtitleIndex = -1; // 当前启用的字幕索引
  List<Map<String, dynamic>> _danmakuContents = []; // 存储所有弹幕
  List<Map<String, String>> _playlist = [];
  bool _useFfmpegForPlay = false;
  bool _initVpWhenFfmpeg = false;
  DartLibass? _assRenderer;
  File? _assFile;
  bool _assInit = false;
  File? _assFontFile;
  bool _showPlaylist = false;
  bool _usePlaylist = true;
  final _historyService = HistoryService();
  Timer? _positionUpdateTimer;
  final EventChannel _eventChannel2 = EventChannel('com.example.app/events');
  final EventChannel _eventChannel =
      EventChannel('samples.flutter.dev/volumepluginevent');
  Future<void> _setupAudioSession() async {
    final session = await AudioSession.instance;

    // 配置音频会话
    await session.configure(AudioSessionConfiguration.music());

    // 开始监听音频焦点变化
    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        // 暂停播放
        _videoController?.pause();
      } else {
        // 恢复播放
        _videoController?.play();
      }
    });

    session.becomingNoisyEventStream.listen((_) {
      // 处理音频外放（例如拔出耳机时）
      _videoController?.pause();
    });
  }

  void toggleFullScreen() {
    setState(() {
      widget.toggleFullScreen();
      widget.isFullScreen = !widget.isFullScreen;
    });
  }

  void getopenfile(String openfile) {
    widget.getopenfile(openfile);
    if (widget.openfile != openfile && openfile.isNotEmpty) {
      _openUri(openfile);
    }
    setState(() {
      widget.openfile = openfile;
    });
  }

  Future<bool> _onWillPop() async {
    if (widget.isFullScreen) {
      widget.toggleFullScreen();
      return true; // 阻止退出程序
    }
    return true; // 允许退出程序
  }

  void _startVolumeSliderTimer() {
    _volumeSliderTimer?.cancel(); // 取消之前的 Timer
    _volumeSliderTimer = Timer(Duration(seconds: 5), () {
      setState(() {
        _showVolumeSlider = false; // 5 秒后隐藏 Slider
      });
    });
  }

  void _onEventOpenuri(dynamic event) {
    if (event is String && event.isNotEmpty) {
      _openUri(event, wantFirst: true); // 打开URI
      setState(() {
        widget.openfile = event;
      });
    }
  }

  void _onErrorOpenuri(Object error) {
    print('Error receiving event: $error');
  }

  // 记录播放开始
  void _recordPlayStart(String filePath, String title,
      {bool isVideo = true}) async {
    final mediaType = isVideo ? 'video' : 'audio';

    // 尝试获取现有历史记录
    HistoryItem? existing = await _historyService.getHistoryByPath(filePath);

    if (existing != null) {
      // 更新现有记录
      await _historyService.updateHistory(existing.copyWith(
        lastPlayed: DateTime.now(),
        title: title,
        mediaType: mediaType,
      ));
    } else {
      // 创建新记录
      await _historyService.updateHistory(HistoryItem(
        filePath: filePath,
        durationMs: _videoController?.value.duration.inMilliseconds ?? 0,
        lastPosition: 0,
        lastPlayed: DateTime.now(),
        mediaType: mediaType,
        title: title,
      ));
    }
  }

// 定期或在播放暂停/停止时更新播放位置
  void _updatePlayPosition(String filePath) async {
    int currentPosition = _videoController?.value.position.inMilliseconds ?? 0;
    await _historyService.updatePosition(filePath, currentPosition);
  }

// 播放结束时更新完整记录
  void _recordPlayEnd(String filePath) async {
    HistoryItem? existing = await _historyService.getHistoryByPath(filePath);
    if (existing != null) {
      await _historyService.updateHistory(existing.copyWith(
        durationMs: _videoController?.value.duration.inMilliseconds ?? 0,
        lastPosition: _videoController?.value.position.inMilliseconds ?? 0,
        lastPlayed: DateTime.now(),
      ));
    }
  }

// 恢复播放位置
  Future<Duration> _getLastPosition(String filePath) async {
    HistoryItem? history = await _historyService.getHistoryByPath(filePath);
    if (history != null) {
      return Duration(milliseconds: history.lastPosition);
    }
    return Duration.zero;
  }

  @override
  void initState() async {
    super.initState();
    _checkAndOpenUriFile(); // 添加文件检查逻辑
    // if (widget.openfile.isNotEmpty) {
    //   _openUri(widget.openfile);
    // }
    // // 启动定时器，每秒执行一次
    // _timer = Timer.periodic(Duration(seconds: 1), (timer) {
    //   _checkAndOpenUriFile();
    // });
    _usePlaylist = await _settingsService.getUsePlaylist();
    _eventChannel2
        .receiveBroadcastStream()
        .listen(_onEventOpenuri, onError: _onErrorOpenuri);
    // _setupAudioSession();
    _animeController = AnimationController(
      vsync: this,
      duration: Duration(seconds: 8),
    )..repeat();
    _volumeExample = VolumeExample();
    _eventChannel
        .receiveBroadcastStream()
        .listen(_onVolumeChanged, onError: _onError);
    final _platform = const MethodChannel('samples.flutter.dev/volumeplugin');
// 调用方法 getBatteryLevel
    _systemMaxVolume =
        ((await _platform.invokeMethod<int>('getMaxVolume')) ?? 15).toDouble();
    _openUri(widget.openfile);
    // _useFfmpegForPlay = await _settingsService.getUseFfmpegForPlay();
    // _ffmpegExample = FfmpegExample(initUri: '');
  }

  void _onVolumeChanged(dynamic volume) {
    print('Volume changed: $volume');
    setState(() {
      _systemVolume = (volume as int).toDouble(); // 将接收到的音量值赋值给 _volume
    });
  }

  void _onError(Object error) {
    print('Error: $error');
  }

  @override
  void didUpdateWidget(PlayerTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.openfile != oldWidget.openfile && widget.openfile.isNotEmpty) {
      _openUri(widget.openfile, wantFirst: wantFirst);
      wantFirst = false;
    }
  }

  Future<void> _openAudioTrackDialog() async {
    if (_videoController == null) return;
    print('打开音轨列表');
    Fluttertoast.showToast(msg: '打开音轨列表...');

    print('获取音轨列表...');
    List<String> audioTracks = await _videoController!.getAudioTracks();
    print('音轨列表: $audioTracks');

    // 如果音轨列表为空，则默认显示 0, 1, 2, 3, 4, 5
    // if (audioTracks.isEmpty) {
    audioTracks = ['0', '1', '2', '3', '4', '5'];
    // }

    String? selectedTrack = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (BuildContext context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Dialog(
            backgroundColor: Colors.white.withOpacity(0.85),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20.0),
            ),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '选择音轨',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                    ),
                    child: const Text(
                      '选择非音频轨道可能会导致错误。0一般为视频轨。然后是音频轨。其他轨道可能是字幕轨道。',
                      style: TextStyle(color: Colors.red, fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 15),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.4,
                    ),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        children: audioTracks.map((track) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.blue.withOpacity(0.2),
                              ),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              leading: const Icon(Icons.audio_file,
                                  color: Colors.blue),
                              title: Text(
                                track,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              trailing: const Icon(Icons.chevron_right,
                                  color: Colors.blue),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              onTap: () {
                                Navigator.of(context).pop(track);
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.blue.withOpacity(0.1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 24),
                    ),
                    child: const Text(
                      '取消',
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (selectedTrack != null) {
      // 在这里处理选中的音轨
      print('选中的音轨: $selectedTrack');
      // 你可以在这里调用 _videoController.setAudioTrack(selectedTrack) 来设置音轨
      _videoController?.setAudioTrack(selectedTrack);
    }
  }

  Future<void> _checkAndOpenUriFile() async {
    try {
      final file = File('/data/storage/el2/base/openuri.txt'); // 构建文件路径

      if (await file.exists()) {
        final uri = await file.readAsString(); // 读取文件内容
        if (uri.isNotEmpty) {
          // await _openUri(uri,wantFirst: true); // 打开URI
          // await _openUri(uri,wantFirst: true); // 打开URI
          wantFirst = true;
          getopenfile(uri);
          // setState(() {
          //   widget.openfile = uri;
          // });
        }
        await file.delete(); // 删除文件
      }
    } catch (e) {
      print('Error reading or deleting openuri.txt: $e');
    }
  }

  Future<void> _checkAndOpenUriFileTimer() async {
    try {
      final file = File('/data/storage/el2/base/openuri.txt'); // 构建文件路径

      if (await file.exists()) {
        final uri = await file.readAsString(); // 读取文件内容
        if (uri.isNotEmpty) {
          _openUri(uri); // 打开URI
        }
        await file.delete(); // 删除文件
      }
    } catch (e) {}
  }

// 添加 _showUrlDialog 方法
  void _showUrlDialog(BuildContext context) {
    final TextEditingController urlController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.transparent, // 设置对话框背景为透明
          contentPadding: EdgeInsets.zero, // 去掉默认的内边距
          content: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 2.0, sigmaY: 2.0), // 高斯模糊
              child: Container(
                color: Colors.black.withOpacity(0.8), // 半透明黑色背景
                padding: EdgeInsets.all(16), // 添加内边距
                child: Column(
                  mainAxisSize: MainAxisSize.min, // 让 Column 包裹内容
                  children: [
                    Text(
                      '输入 URL',
                      style: TextStyle(color: Colors.white),
                    ),
                    SizedBox(height: 16), // 添加间距
                    TextField(
                      controller: urlController,
                      decoration: InputDecoration(
                        hintText: "请输入音视频 URL",
                        hintStyle: TextStyle(color: Colors.grey),
                        border: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.lightBlue),
                        ),
                      ),
                      style: TextStyle(color: Colors.white),
                    ),
                    SizedBox(height: 16), // 添加间距
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end, // 按钮右对齐
                      children: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            _openUri(urlController.text);
                          },
                          child: Text(
                            '确认',
                            style: TextStyle(color: Colors.lightBlue),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          child: Text(
                            '取消',
                            style: TextStyle(color: Colors.lightBlue),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _checkIfVideoFinished() {
    if (_videoController == null) return;
    if ((_videoController!.value.position.inMilliseconds >=
            _videoController!.value.duration.inMilliseconds - 100) ||
        (_videoController!.value.position == Duration.zero &&
            !_videoController!.value.isPlaying)) {
      // 视频播放完毕
      _handleVideoFinished();
    }
  }

  void _handleVideoFinished() {
    switch (_isLooping) {
      case 0:
        // 播放完停止
        // setState(() {
        //   _isPlaying = false;
        // });
        break;
      case 1:
        // 列表循环（需要手动切换到下一项）
        _playNextItem();
        break;
      case 2:
        // 单曲循环
        // _videoController!.seekTo(Duration.zero); // 回到视频开头
        // _videoController!.play(); // 重新播放
        break;
    }
  }

  Future<void> _initializeChewieController() async {
    _volumeController = _volumeExample?.controller;
    _videoController!.addListener(_checkIfVideoFinished);

    _chewieController = ChewieController(
      ffmpeg: _useFfmpegForPlay,
      sendToFfmpegPlayer: _ffmpegExample,
      videoPlayerController: _videoController!,
      allowMuting: !_useFfmpegForPlay,
      autoPlay: true,
      looping: _isLooping == 2,
      showControls: _showControls,
      allowFullScreen: true,
      zoomAndPan: true,
      subtitleFontsize: await _settingsService.getSubtitleFontSize(),
      customToggleFullScreen: toggleFullScreen,
      playNextItem: _usePlaylist ? _playNextItem : null,
      playPreviousItem: _usePlaylist ? _playPreviousItem : null,
      closePlaylist: _closePlaylist,
      openPlaylist: _openPlaylist,
      optionsTranslation: OptionsTranslation(
        playbackSpeedButtonText: '播放速率',
        subtitlesButtonText: '字幕',
        cancelButtonText: '取消',
      ),
      setSystemVolume: (p0) {
        double nextVolume = _systemVolume + p0 * _systemMaxVolume;

// 确保音量不超过最大音量
        if (nextVolume > _systemMaxVolume) {
          nextVolume = _systemMaxVolume;
        }

// 确保音量不小于 0
        if (nextVolume < 0) {
          nextVolume = 0;
        }

        _volumeController?.sendMessageToOhosView(
            'getMessageFromFlutterView2', nextVolume.toString());
        _systemVolume = nextVolume;
        return nextVolume;
      },
      subtitleBuilder: (context, subtitle) {
        return SubtitleBuilder(subtitle: subtitle);
      },
      additionalOptions: (context) {
        return <OptionItem>[
          // OptionItem(
          //   onTap: _openFile,
          //   iconData: Icons.open_in_browser,
          //   title: '打开文件',
          // ),
          // OptionItem(
          //   onTap: () => _showUrlDialog(context),
          //   iconData: Icons.link,
          //   title: '打开URL',
          // ),
          OptionItem(
            onTap: () => _openSRT(),
            iconData: Icons.subtitles,
            title: '打开字幕文件',
          ),
          OptionItem(
            onTap: () => _openDanmaku(),
            iconData: Icons.comment,
            title: '打开弹幕文件',
          ),
          OptionItem(
            onTap: () => _selectSubtitle(),
            iconData: Icons.closed_caption,
            title: '选择字幕轨道',
          ),
          if (!_useFfmpegForPlay)
            OptionItem(
              onTap: () => _openAudioTrackDialog(),
              iconData: Icons.volume_up_sharp,
              title: '选择音频轨道',
            ),
          OptionItem(
            onTap: () {
              _chewieController?.toggleFullScreen();
            },
            iconData:
                (_chewieController != null && _chewieController!.isFullScreen)
                    ? Icons.fullscreen_exit
                    : Icons.fullscreen,
            title: '切换全屏',
          ),
//           OptionItem(
//             onTap: () async {
//               double nextVolume = _systemVolume + 0.01;

// // 确保音量不超过最大音量
//               if (nextVolume > _systemMaxVolume) {
//                 nextVolume = _systemMaxVolume;
//               }

// // 确保音量不小于 0
//               if (nextVolume < 0) {
//                 nextVolume = 0;
//               }

//               _volumeController?.sendMessageToOhosView(
//                   'getMessageFromFlutterView2', nextVolume.toString());
//             },
//             iconData: Icons.volume_up,
//             title: '音量调节',
//           ),
          OptionItem(
            onTap: () {
              setState(() {
                _isMirrored = !_isMirrored; // 切换镜像状态
              });
            },
            iconData: _isMirrored ? Icons.flip : Icons.flip_camera_android,
            title: _isMirrored ? '取消镜像' : '镜像',
          ),
          OptionItem(
            onTap: () {
              setState(() {
                // 切换循环模式
                _isLooping = (_isLooping + 1) % 3; // 0 -> 1 -> 2 -> 0
                // 更新视频控制器的循环模式
                _videoController
                    ?.setLooping(_isLooping == 2); // 只有单曲循环时设置为 true
              });
            },
            iconData: _isLooping == 0
                ? Icons.stop
                : _isLooping == 1
                    ? Icons.repeat
                    : Icons.repeat_one,
            title: _isLooping == 0
                ? '播放完当前媒体停止'
                : _isLooping == 1
                    ? '列表循环'
                    : '单曲循环',
          ),

          OptionItem(
            onTap: () {
              setState(() {
                _isLandscape = !_isLandscape; // 切换横竖屏状态
                // 这里可以添加代码来实际改变屏幕方向
                SystemChrome.setPreferredOrientations(_isLandscape
                    ? [
                        DeviceOrientation.landscapeLeft,
                        DeviceOrientation.landscapeRight
                      ]
                    : [
                        DeviceOrientation.portraitUp,
                        DeviceOrientation.portraitDown
                      ]);
              });
            },
            iconData: _isLandscape
                ? Icons.screen_lock_landscape
                : Icons.screen_lock_portrait,
            title: '尝试切换横竖屏（导致旋转锁定）',
          ),
        ];
      },
    );
    _chewieController?.setVolume(_useFfmpegForPlay ? 0.0 : 1.0);
  }

  String convertPathToOhosUri(String path) {
    String prefix;

    // 判断路径是否以 /Photos 开头
    if (path.startsWith('/Photos')) {
      prefix = 'file://media';
    } else if (path.contains(':')) {
      prefix = '';
    } else {
      prefix = 'file://docs';
    }

    // 拼接前缀和路径
    String fullPath = '$prefix$path';

    // 使用 Uri.parse 进行一般的 URI 转换
    Uri uri = Uri.parse(fullPath);

    return uri.toString();
  }

  void _ffmpegPlay() {
    this._ffmpegExample = FfmpegExample(
      initUri: this.widget.openfile,
      toggleFullScreen: this.toggleFullScreen,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => this._ffmpegExample!,
      ),
    );
    // this._ffmpegController = this._ffmpegExample!.controller;
    // print("ffmpegcontroller is null?: ${this._ffmpegController == null}");
    // this._ffmpegController?.sendMessageToOhosView(
    //     "getMessageFromFlutterView", convertPathToOhosUri(this.widget.openfile));
  }

  Future<void> readFileWithRetry(String path) async {
    // 提取文件名
    String fileName = path.split('/').last;

    // 构造文件目录
    String directoryPath = '/data/storage/el2/base/haps/entry/cache/';
    await Future.delayed(Duration(seconds: 2));

    // 尝试读取文件
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        // 查找是否有以 fileName 为前缀的 .ass 或 .srt 文件
        final cacheDir = await getTemporaryDirectory();
        final directoryPath = cacheDir.path; // 缓存目录路径

        print('缓存目录路径: $directoryPath');
        Directory directory = Directory(directoryPath);
        List<FileSystemEntity> files = await directory.list().toList();

        // 过滤出符合条件的文件
        List<File> matchingFiles = files.whereType<File>().where((file) {
          String name = file.path.split('/').last;
          return (name.startsWith(fileName) &&
              (name.endsWith('.ass') || name.endsWith('.srt')));
        }).toList();

        // 遍历并打印匹配文件
        if (matchingFiles.isNotEmpty) {
          print('找到 ${matchingFiles.length} 个匹配的文件：');
          for (var file in matchingFiles) {
            print(file.path);
          }
        } else {
          print('未找到匹配的文件。');
        }

        // 如果找到符合条件的文件，加载所有匹配的字幕
        if (matchingFiles.isNotEmpty) {
          for (var file in matchingFiles) {
            String content = await file.readAsString();

            // 创建字幕数据对象
            SubtitleData subtitleData = SubtitleData(
              name: file.path.split('/').last,
              content: content,
              extension: file.path.split('.').last,
            );

            // 解析字幕内容
            if (subtitleData.extension == 'ass') {
              subtitleData.subtitles = await ass2srt(content);
              final result = AssParserPlus.parseAssContent(content);
              subtitleData.styles = result.$1;
              subtitleData.assSubtitles = result.$2;
            } else if (subtitleData.extension == 'srt') {
              SubtitleController controller = SubtitleController.string(
                content,
                format: SubtitleFormat.srt,
              );
              subtitleData.subtitles = controller.subtitles
                  .map(
                    (e) => Subtitle(
                      index: e.number,
                      start: Duration(milliseconds: e.start),
                      end: Duration(milliseconds: e.end),
                      text: e.text.replaceAll('\\N', '\n'),
                    ),
                  )
                  .toList();
            }

            // 将字幕添加到列表中
            _subtitles.add(subtitleData);
          }

          // 如果当前没有启用的字幕，则默认启用第一个匹配的字幕
          // if (_currentSubtitleIndex == -1 && _subtitles.isNotEmpty) {
          //   _currentSubtitleIndex = 0;
          //   _chewieController!.setSubtitle(_subtitles[0].subtitles!);
          // }

          // // 更新 UI
          // setState(() {});

          // 文件加载成功，退出循环
          break;
        } else {
          // 如果没有找到文件，抛出异常
          throw FileSystemException('文件不存在', directoryPath);
        }
      } catch (e) {
        // 如果文件不存在，等待3秒后重试
        if (e is FileSystemException && e.osError?.errorCode == 2) {
          print('文件不存在，等待3秒后重试...');
          await Future.delayed(Duration(seconds: 3));
        } else {
          // 其他异常，直接抛出
          rethrow;
        }
      }
    }

    // 然后尝试在path的同级文件夹里面找
    try {
      directoryPath = path.substring(0, path.lastIndexOf('/'));
      Directory directory = Directory(directoryPath);
      List<FileSystemEntity> files = await directory.list().toList();
      // 过滤出符合条件的文件
      List<File> matchingFiles = files.whereType<File>().where((file) {
        String name = file.path.split('/').last;
        return (name
                .startsWith(fileName.substring(0, fileName.lastIndexOf('.'))) &&
            (name.endsWith('.ass') || name.endsWith('.srt')));
      }).toList();

      // 遍历并打印匹配文件
      if (matchingFiles.isNotEmpty) {
        print('找到 ${matchingFiles.length} 个匹配的文件：');
        for (var file in matchingFiles) {
          print(file.path);
        }
      }

      // 如果找到符合条件的文件，加载所有匹配的字幕
      if (matchingFiles.isNotEmpty) {
        for (var file in matchingFiles) {
          String content = await file.readAsString();

          // 创建字幕数据对象
          SubtitleData subtitleData = SubtitleData(
            name: file.path.split('/').last,
            content: content,
            extension: file.path.split('.').last,
          );
          // 解析字幕内容
          if (subtitleData.extension == 'ass') {
            subtitleData.subtitles = await ass2srt(content);
            final result = AssParserPlus.parseAssContent(content);
            subtitleData.styles = result.$1;
            subtitleData.assSubtitles = result.$2;
          } else if (subtitleData.extension == 'srt') {
            SubtitleController controller = SubtitleController.string(
              content,
              format: SubtitleFormat.srt,
            );
            subtitleData.subtitles = controller.subtitles
                .map(
                  (e) => Subtitle(
                    index: e.number,
                    start: Duration(milliseconds: e.start),
                    end: Duration(milliseconds: e.end),
                    text: e.text.replaceAll('\\N', '\n'),
                  ),
                )
                .toList();
          }
          // 将字幕添加到列表中
          _subtitles.add(subtitleData);
        }
      }
    } catch (e) {
      print(e);
    }

    // 如果当前没有启用的字幕，则优先启用第一个ASS字幕，若没有则启用第一个普通字幕
    if (_currentSubtitleIndex == -1 && _subtitles.isNotEmpty) {
      // 尝试查找第一个ASS字幕
      int assSubtitleIndex =
          _subtitles.indexWhere((subtitle) => subtitle.assSubtitles != null);

      if (assSubtitleIndex != -1) {
        // 找到了ASS字幕
        _currentSubtitleIndex = assSubtitleIndex;
        final subtitleData = _subtitles[assSubtitleIndex];
        _chewieController!.setSubtitle(subtitleData.subtitles!);
        _chewieController!.assStyles = subtitleData.styles;
        _chewieController!.assSubtitles = subtitleData.assSubtitles;
      } else {
        // 没有找到ASS字幕，使用第一个普通字幕
        _currentSubtitleIndex = 0;
        final subtitleData = _subtitles[0];
        _chewieController!.setSubtitle(subtitleData.subtitles!);
        _chewieController!.assStyles = subtitleData.styles;
        _chewieController!.assSubtitles = subtitleData.assSubtitles;
      }
    }

    // 如果3次尝试都失败，返回null
    print('文件读取失败，放弃尝试。');
    return;
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

  void _getPlaylist(String path) {
    //提取文件夹路径
    _playlist.clear();
    if (!_usePlaylist) {
      return;
    }
    if (path.contains(':')) {
      _playlist.add({
        'name': path,
        'path': path,
      });
      return;
    }
    String folderPath = path.substring(0, path.lastIndexOf('/'));
    List<String> excludeExts = ['ux_store', 'srt', 'ass', 'jpg'];
    // 如果文件夹位于 /storage/Users/currentUser/Download/com.aloereed.aloeplayer/下，打开该文件夹
    if (folderPath.startsWith(
        '/storage/Users/currentUser/Download/com.aloereed.aloeplayer/')) {
      final directory = Directory(folderPath);
      // 提取文件夹下所有文件（不包括子文件夹）
      List<FileSystemEntity> files = directory.listSync();
      // 把<文件名, 文件路径>添加到_playlist中
      for (FileSystemEntity file in files) {
        if (file is File) {
          if (excludeExts.contains(file.path.split('.').last)) {
            continue;
          }
          _playlist.add({
            'name': file.path.split('/').last,
            'path': file.path,
          });
        }
      }
      // 按照文件名排序
      setState(() {
        _playlist.sort((a, b) => a['name']!.compareTo(b['name']!));
      });
      // 打印playlist
      print("Playlist: ${_playlist}");
    } else {
      _playlist.add({
        'name': path.split('/').last,
        'path': path,
      });
    }
  }

  void _closePlaylist() {
    setState(() {
      _showPlaylist = false;
    });
  }

  void _openPlaylist() {
    setState(() {
      _showPlaylist = true;
    });
  }

  void _playNextItem() {
    if (_playlist.isEmpty || _playlist.length == 1) {
      return;
    }
    // 获取当前播放项的索引
    int currentIndex =
        _playlist.indexWhere((item) => item['path'] == widget.openfile);
    // 如果当前播放项是最后一项，播放第一项
    if (currentIndex == _playlist.length - 1) {
      getopenfile(_playlist[0]['path']!);
    } else {
      getopenfile(_playlist[currentIndex + 1]['path']!);
    }
  }

  void _playPreviousItem() {
    if (_playlist.isEmpty || _playlist.length == 1) {
      return;
    }
    // 获取当前播放项的索引
    int currentIndex =
        _playlist.indexWhere((item) => item['path'] == widget.openfile);
    // 如果当前播放项是第一项，播放最后一项
    if (currentIndex == 0) {
      getopenfile(_playlist[_playlist.length - 1]['path']!);
    } else {
      getopenfile(_playlist[currentIndex - 1]['path']!);
    }
  }

  void _setupPositionUpdateTimer() {
    // 取消现有计时器（如果存在）
    _positionUpdateTimer?.cancel();

    // 创建新的计时器，每5秒执行一次
    _positionUpdateTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      _updatePlayPosition(widget.openfile);
    });
  }

  Future<void> _openUri(String uri, {bool wantFirst = false}) async {
    // 如果uri以"/Photos"开头，则在uri前面加上"file://media"
    _subtitles.clear();
    _playlist.clear();
    _currentSubtitleIndex = -1;
    coverData = null;
    if (uri.startsWith('/Photo')) {
      uri = 'file://media' + uri;
    }
    if (uri.startsWith('file://docs') && !wantFirst) {
      // 删除file://docs并解析unicode码
      uri = Uri.decodeFull(uri.substring(11));
    }
    bool isBgPlay = await _settingsService.getBackgroundPlay();
    setState(() {
      _initVpWhenFfmpeg = false;
    });

    if (uri.contains(':')) {
      if (_videoController != null) {
        _videoController?.dispose();
      }
      _videoController = VideoPlayerController.network(uri,
          videoPlayerOptions: VideoPlayerOptions(
              allowBackgroundPlayback: isBgPlay, mixWithOthers: true))
        ..initialize().then((_) async {
          setState(() {
            _totalDuration = _videoController!.value.duration;
            _isAudio = _videoController == null ||
                _videoController!.value.size.width == 0; // 判断是否为音频文件
            widget.setHomeWH(_videoController!.value.size.width.toInt(),
                _videoController!.value.size.height.toInt());
            _initVpWhenFfmpeg = true;
          });
          await _initializeChewieController();
          _videoController?.play();
          _videoController?.addListener(_updatePlaybackState);
          final needToFullscreen =
              await _settingsService.getAutoFullscreenBeginPlay();
          if (needToFullscreen) {
            if (!widget.isFullScreen) toggleFullScreen();
          }
        })
        ..setLooping(_isLooping == 2);
      _useFfmpegForPlay = await _settingsService.getUseFfmpegForPlay();
      if (_useFfmpegForPlay) {
        if (_ffmpegExample == null) {
          _ffmpegExample = FfmpegExample(
              initUri: convertUriToPath(widget.openfile),
              toggleFullScreen: this.toggleFullScreen);
        }
        _ffmpegExample?.controller?.sendMessageToOhosView(
            "newPlay", convertUriToPath(widget.openfile));
      }

      getopenfile(uri);
    } else {
      _videoController?.dispose();
      if (uri == "AloePlayer播放器") {
        // await audioHandler.setLoopingSilence();
        // await audioHandler.play();
        Wakelock.enable();
        return;
      }
      String originalUri = uri;
      // 检查file是否是".lnk"文件
      if (uri.endsWith('.lnk')) {
        // 读取文件内容
        File lnkFile = File(uri);
        uri = await lnkFile.readAsString();
        // widget.openfile = uri;
        String uri2 = uri;
        if (!uri.contains(':')) {
          uri2 = "file://docs" + uri;
          uri2 = Uri.parse(uri2).toString();
        }
        await _settingsService.activatePersistPermission(uri2);
      }
      _videoController = VideoPlayerController.file(File(uri),
          videoPlayerOptions:
              VideoPlayerOptions(allowBackgroundPlayback: isBgPlay))
        ..initialize().then((_) async {
          setState(() {
            _totalDuration = _videoController!.value.duration;
            _isAudio = _videoController == null ||
                _videoController!.value.size.width == 0; // 判断是否为音频文件
            widget.setHomeWH(_videoController!.value.size.width.toInt(),
                _videoController!.value.size.height.toInt());
            _initVpWhenFfmpeg = true;
          });
          await _initializeChewieController();
          _videoController?.play();
          _videoController?.addListener(_updatePlaybackState);
          final needToFullscreen =
              await _settingsService.getAutoFullscreenBeginPlay();
          if (needToFullscreen) {
            if (!widget.isFullScreen) toggleFullScreen();
          }
          bool isContinued = await _settingsService.getUseSeekToLatest();
          if (isContinued) {
            final latestDuration = await _getLastPosition(uri);
            if (_videoController != null &&
                latestDuration.inMilliseconds /
                        _videoController!.value.duration.inMilliseconds <
                    0.99 &&
                latestDuration.inMilliseconds != 0) {
              _videoController?.seekTo(latestDuration);
              Fluttertoast.showToast(
                msg: "已跳转到上次播放位置：${latestDuration.toString()}",
                toastLength: Toast.LENGTH_SHORT,
                gravity: ToastGravity.CENTER,
              );
            }
          }
        })
        ..setLooping(_isLooping == 2);
      _useFfmpegForPlay = await _settingsService.getUseFfmpegForPlay();
      if (_useFfmpegForPlay) {
        if (_ffmpegExample == null) {
          _ffmpegExample = FfmpegExample(
              initUri: convertUriToPath(widget.openfile),
              toggleFullScreen: this.toggleFullScreen);
        }
        _ffmpegExample?.controller?.sendMessageToOhosView(
            "newPlay", convertUriToPath(widget.openfile));
      }
      _getPlaylist(originalUri);
      _recordPlayStart(originalUri, originalUri);
      _setupPositionUpdateTimer();
      String fileName = originalUri.split('/').last;
      final _platform = const MethodChannel('samples.flutter.dev/ffmpegplugin');
      final cacheDir = await getTemporaryDirectory();
      final directoryPath = cacheDir.path; // 缓存目录路径
      // 调用方法 getBatteryLevel
      final result2 = await _platform.invokeMethod<String>('getassold', {
        "path": uri,
        "type": "srt",
        "output": path.join(directoryPath, fileName)
      });
      if (await _settingsService.getAutoLoadSubtitle() == true) {
        readFileWithRetry(uri);
      }
      final metadata = readMetadata(File(uri), getImage: true);
      coverData = metadata.pictures[0].bytes;
    }
    // await audioHandler.setLoopingSilence();
    // await audioHandler.play();
    Wakelock.enable();
  }

  // Future<void> _openFile() async {
  //   final typeGroup = XTypeGroup(
  //     label: 'media',
  //     extensions: ['*'],
  //   );
  //   final typeVideoGroup = XTypeGroup(
  //     label: 'media',
  //     extensions: ['mp4', 'mkv', 'avi', 'mov', 'flv', 'wmv', 'webm'],
  //   );
  //   final typeAudioGroup = XTypeGroup(
  //     label: 'media',
  //     extensions: ['mp3', 'wav', 'flac', 'aac', 'm4a', 'ogg'],
  //   );
  //   final XFile? file = await openFile(
  //       acceptedTypeGroups: [typeGroup, typeVideoGroup, typeAudioGroup]);
  //   if (file != null) {
  //     getopenfile(file.path);
  //   }
  // }

  Future<void> _openFile() async {
    // 使用 FilePicker 选择文件
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'mp4,.mkv,.avi,.mov,.flv,.wmv,.webm,mp3,.flac,.wav,.m4a,.aac,.ogg,.rmvb,.wmv,.ts,.m3u8,.m3u,.wma,.ape,.aiff,.dsf,.tak',
        'mp4',
        'mkv',
        'avi',
        'mov',
        'flv',
        'wmv',
        'webm',
        'mp3',
        'wav',
        'flac',
        'aac',
        'm4a',
        'ogg',
        'rmvb',
        'wmv',
        'ts',
        'm3u8',
        'm3u',
        'wma',
        'ape',
        'aiff',
        'dsf',
        'tak',
        '*'
      ],
    );

    // 检查是否选择了文件
    if (result != null) {
      PlatformFile file = result.files.first;
      getopenfile(file.path!);
    } else {
      // 用户取消了选择
      print('用户取消了文件选择');
    }
  }

  static Future<List<Subtitle>> ass2srt(String content) async {
    final assParser = AssParser(content: content); // 解析 ass

    // 字幕
    List<Subtitle> subtitles = [];
    List<Section> sections = assParser.getSections();

    int index = 0; // 用于生成字幕的索引

    // 循环处理字幕数据
    for (var section in sections) {
      if (section.name != '[Events]') continue;

      for (var entity in section.body.sublist(1)) {
        final value = entity.value['value'];
        if (value['Start'] == null || value['End'] == null) continue;

        // 正则表达式 匹配时间
        final regExp =
            RegExp(r'(\d{1,2}):(\d{2}):(\d{2})\.(\d+)', caseSensitive: false);

        // 开始时间
        final startTimeMatch = regExp.allMatches(value['Start']).toList().first;
        final startTimeHours = int.parse(startTimeMatch.group(1)!);
        final startTimeMinutes = int.parse(startTimeMatch.group(2)!);
        final startTimeSeconds = int.parse(startTimeMatch.group(3)!);
        final startTimeMilliseconds =
            int.parse(startTimeMatch.group(4)!.padRight(3, '0'));

        // 结束时间
        final endTimeMatch = regExp.allMatches(value['End']).toList().first;
        final endTimeHours = int.parse(endTimeMatch.group(1)!);
        final endTimeMinutes = int.parse(endTimeMatch.group(2)!);
        final endTimeSeconds = int.parse(endTimeMatch.group(3)!);
        final endTimeMilliseconds =
            int.parse(endTimeMatch.group(4)!.padRight(3, '0'));

        final startTime = Duration(
          hours: startTimeHours,
          minutes: startTimeMinutes,
          seconds: startTimeSeconds,
          milliseconds: startTimeMilliseconds,
        );

        final endTime = Duration(
          hours: endTimeHours,
          minutes: endTimeMinutes,
          seconds: endTimeSeconds,
          milliseconds: endTimeMilliseconds,
        );

        subtitles.add(
          Subtitle(
            index: index++, // 设置字幕的索引
            start: startTime, // 设置开始时间
            end: endTime, // 设置结束时间
            text: value['Text']
                .toString()
                .replaceAll(RegExp(r'({.+?})'), '')
                .replaceAll('\\N', '\n')
                .trim(), // 设置字幕文本
          ),
        );
      }
    }
    // 假设 subtitles 是一个 List<Subtitle> 类型的列表
    List<Subtitle> processedSubtitles = [];

// 创建一个 Map 来存储相同 start 时间的字幕
    Map<Duration, Subtitle> subtitleMap = {};

    for (var subtitle in subtitles) {
      if (subtitleMap.containsKey(subtitle.start)) {
        // 如果已经存在相同 start 时间的字幕，则合并文本并更新 end 时间
        var existingSubtitle = subtitleMap[subtitle.start]!;
        existingSubtitle.text = '${existingSubtitle.text}\n${subtitle.text}';
        if (subtitle.end > existingSubtitle.end) {
          existingSubtitle.end = subtitle.end;
        }
      } else {
        // 如果不存在相同 start 时间的字幕，则直接添加到 Map 中
        subtitleMap[subtitle.start] = Subtitle(
          index: subtitle.index, // 暂时保留原始 index
          start: subtitle.start,
          end: subtitle.end,
          text: subtitle.text,
        );
      }
    }

// 将 Map 中的值转换为列表
    processedSubtitles = subtitleMap.values.toList();

// 按 start 时间排序（如果需要）
    processedSubtitles.sort((a, b) => a.start.compareTo(b.start));

// 重新分配 index
    for (int i = 0; i < processedSubtitles.length; i++) {
      processedSubtitles[i] = Subtitle(
        index: i, // 重新分配 index
        start: processedSubtitles[i].start,
        end: processedSubtitles[i].end,
        text: processedSubtitles[i].text,
      );
    }

// 现在 processedSubtitles 就是处理后的字幕列表

    return processedSubtitles;
  }

  List<Subtitle> parseLrcToSubtitles(String data) {
    final result = <String, String>{};
    final times = <String>[];
    int count = 0;
    const K = 1; // 伪K轴，即是否进行奇偶定位
    final positions = [" ", " "]; // 奇偶位置
    const translate = 0; // 是否保留中文翻译

    final lines = data.split('\n');
    for (var line in lines) {
      final matchList = RegExp(r'\[\d*?:\d*?\.\d*?]').allMatches(line);
      if (matchList.isNotEmpty) {
        for (var match in matchList) {
          final m = match.group(0)!;
          final tmp = result[m];
          if (tmp != null) {
            if (tmp.isEmpty ||
                line.substring(line.lastIndexOf(']') + 1) == "//") {
              continue;
            } else {
              if (translate == 1) {
                result[m] =
                    "$tmp\n${line.substring(line.lastIndexOf(']') + 1)}";
              }
            }
          } else {
            final offset = K == 1 ? positions[count] : '';
            count = count == 0 ? 1 : 0;
            result[m] = "$offset${line.substring(line.indexOf(']') + 1)}";
            times.add(m);
          }
        }
      }
    }

    times.sort();

    final subtitles = <Subtitle>[];
    for (var i = 0; i < times.length; i++) {
      final startTime = _parseTime(times[i]);
      final endTime =
          i < times.length - 1 ? _parseTime(times[i + 1]) : startTime;
      final text = result[times[i]]!;

      subtitles.add(Subtitle(
        index: i + 1,
        start: startTime,
        end: endTime,
        text: text,
      ));
    }

    return subtitles;
  }

  Duration _parseTime(String time) {
    final timeStr = time.substring(1, time.length - 1);
    final parts = timeStr.split(':');
    final minutes = int.parse(parts[0]);
    final seconds = double.parse(parts[1]);
    return Duration(
        minutes: minutes,
        seconds: seconds.toInt(),
        milliseconds: ((seconds - seconds.toInt()) * 1000).toInt());
  }

  Future<File> getAssetAsFile(String assetPath) async {
    // 读取 assets 文件内容
    final byteData = await rootBundle.load(assetPath);

    // 获取临时目录
    final tempDir = await getTemporaryDirectory();

    // 创建临时文件
    final tempFile = File('${tempDir.path}/${assetPath.split('/').last}');

    // 将 assets 文件内容写入临时文件
    await tempFile.writeAsBytes(byteData.buffer.asUint8List());

    return tempFile;
  }

  Future<ui.Image> getEmptyImage() async {
    // 返回一个 1x1 的透明图像
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = Colors.transparent;
    canvas.drawRect(Rect.fromLTWH(0, 0, 1, 1), paint);
    final picture = recorder.endRecording();
    return picture.toImage(1, 1);
  }

  Future<ui.Image> getAssFrame(int time) async {
    print("getAssFrame start");
    if (_assFile == null ||
        _videoController == null ||
        !_videoController!.value.isInitialized) return await getEmptyImage();
    final _platform = const MethodChannel('samples.flutter.dev/ffmpegplugin');
    // final initAssRenderSuccess =
    //     await _platform.invokeMethod<bool>('initLibass', {
    //   "assFilename": _assFile!.path,
    //   "width": _videoController!.value.size.width.toInt(),
    //   "height": _videoController!.value.size.height.toInt()
    // });
    if (_assInit) {
      String img = await _platform.invokeMethod<String>('getPngDataAtTime', {
            "time": time,
            "width": _videoController!.value.size.width.toInt(),
            "height": _videoController!.value.size.height.toInt()
          }) ??
          "";
      print("AssImage:" + img);
      // 1. 将 String 转换为 Uint8List
      Uint8List bytes = base64Decode(img);

      // 2. 使用 MemoryImage 加载字节数据
      final Completer<ui.Image> completer = Completer();
      ImageProvider imageProvider = MemoryImage(bytes);

      // 3. 将 ImageProvider 转换为 ui.Image
      imageProvider.resolve(ImageConfiguration()).addListener(
        ImageStreamListener((ImageInfo info, bool _) {
          completer.complete(info.image);
        }),
      );

      return completer.future;
    }
    return await getEmptyImage();
  }

// 初始化ASS渲染器的方法
  void _initAssRenderer() async {
    if (_assFile == null ||
        _videoController == null ||
        !_videoController!.value.isInitialized) return;
    _assFontFile = await getAssetAsFile('Assets/Montserrat-Bold.ttf');

    _assRenderer = DartLibass(
      subtitle: _assFile!,
      defaultFont: _assFontFile!, // 需要准备默认字体
      defaultFamily: 'Montserrat-Bold',
      width: _videoController!.value.size.width.toInt(),
      height: _videoController!.value.size.height.toInt(),
      fonts: [_assFontFile!],
    );
    final _platform = const MethodChannel('samples.flutter.dev/ffmpegplugin');
    print("ASS: start init libass");
    // 调用方法 getBatteryLevel
    final initAssRenderSuccess =
        await _platform.invokeMethod<bool>('initLibass', {
      "assFilename": _assFile!.path,
      "width": _videoController!.value.size.width.toInt(),
      "height": _videoController!.value.size.height.toInt()
    });
    await _assRenderer!.init();
    // bool initAssRenderSuccess = true;
    if (initAssRenderSuccess ?? false) {
      print("Assrendered init done");
      _assInit = true;

      // String img = await _platform.invokeMethod<String>('getPngDataAtTime', {
      //       "time": 1000,
      //       "width": _videoController!.value.size.width.toInt(),
      //       "height": _videoController!.value.size.height.toInt()
      //     }) ??
      //     "NullImage";
      // print("AssImage:" + img);
      final img = await getAssFrame(125000);
      // final img = _assRenderer!.getFrame(125000);
      ByteData? pngBytes = await img.toByteData(format: ui.ImageByteFormat.png);
      print("Byte: " + pngBytes.toString());
      File('/storage/Users/currentUser/Download/com.aloereed.aloeplayer/test.png')
          .writeAsBytesSync(
        pngBytes!.buffer.asUint8List(
          pngBytes.offsetInBytes,
          pngBytes.lengthInBytes,
        ),
      );
    } else {
      _assInit = false;
      print("Assrendered init failed");
    }
  }

  Future<void> _openSRT() async {
    // 使用 FilePicker 选择文件
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['srt', 'ass', 'lrc', 'vtt'],
    );

    // 检查是否选择了文件
    if (result != null) {
      PlatformFile file = result.files.first;

      // 读取文件内容
      String fileContent = await File(file.path!).readAsString();

      // 创建字幕数据对象
      SubtitleData subtitleData = SubtitleData(
        name: file.name,
        content: fileContent,
        extension: file.extension ?? 'srt', // 默认扩展名
      );

      // 解析字幕内容
      if (subtitleData.extension == 'ass') {
        // 保存原始ass文件
        _assFile = File(file.path!);
        // 初始化渲染器
        // _initAssRenderer();
        // 仍然保留转换逻辑用于普通显示
        subtitleData.subtitles = await ass2srt(fileContent);
        final result = AssParserPlus.parseAssContent(fileContent);
        subtitleData.styles = result.$1;
        subtitleData.assSubtitles = result.$2;
      } else if (subtitleData.extension == 'lrc') {
        subtitleData.subtitles = parseLrcToSubtitles(fileContent);
      } else {
        SubtitleFormat format = subtitleData.extension == 'srt'
            ? SubtitleFormat.srt
            : SubtitleFormat.webvtt;
        SubtitleController controller = SubtitleController.string(
          fileContent,
          format: format,
        );
        subtitleData.subtitles = controller.subtitles
            .map(
              (e) => Subtitle(
                index: e.number,
                start: Duration(milliseconds: e.start),
                end: Duration(milliseconds: e.end),
                text: e.text.replaceAll('\\N', '\n'),
              ),
            )
            .toList();
      }

      // 将字幕添加到列表中
      _subtitles.add(subtitleData);

      // 如果当前没有启用的字幕，则默认启用新添加的字幕
      // if (_currentSubtitleIndex == -1) {
      _currentSubtitleIndex = _subtitles.length - 1;
      _chewieController!.setSubtitle(subtitleData.subtitles!);
      _chewieController!.assStyles = subtitleData.styles;
      _chewieController!.assSubtitles = subtitleData.assSubtitles;

      // }

      // 更新 UI
      setState(() {});
    } else {
      // 用户取消了选择
      print('用户取消了文件选择');
    }
  }

  Future<void> _openDanmaku() async {
    // 使用 FilePicker 选择文件
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xml'],
    );

    // 检查是否选择了文件
    if (result != null) {
      PlatformFile file = result.files.first;

      // 读取文件内容
      String fileContent = await File(file.path!).readAsString();

      // 创建弹幕列表数据对象
      _danmakuContents = parseDanmakuXml(fileContent);
      print("danmu:" + _danmakuContents[0]['time'].toString());

      _chewieController?.setDanmakuContents = _danmakuContents;

      // 更新 UI
      setState(() {});
    } else {
      // 用户取消了选择
      print('用户取消了文件选择');
    }
  }

  Future<void> _selectSubtitle() async {
    if (_subtitles.isEmpty) {
      print('没有可用的字幕');
      Fluttertoast.showToast(msg: '没有可用的字幕');
      return;
    }

    // 显示字幕选择对话框
    int? selectedIndex = await showDialog<int>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Dialog(
            backgroundColor: Colors.white.withOpacity(0.85),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20.0),
            ),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(
                    child: Text(
                      '选择字幕轨道',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.4,
                    ),
                    child: _subtitles.isEmpty
                        ? Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.amber.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.amber.withOpacity(0.3)),
                            ),
                            child: const Center(
                              child: Text(
                                '没有可用的字幕轨道',
                                style: TextStyle(
                                    color: Colors.amber, fontSize: 16),
                              ),
                            ),
                          )
                        : SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Column(
                              children: _subtitles
                                  .asMap()
                                  .entries
                                  .map(
                                    (entry) => Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.purple.withOpacity(0.05),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: Colors.purple.withOpacity(0.2),
                                        ),
                                      ),
                                      child: ListTile(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 4,
                                        ),
                                        leading: const Icon(
                                          Icons.subtitles,
                                          color: Colors.purple,
                                        ),
                                        title: Text(
                                          entry.value.name,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        trailing: const Icon(
                                          Icons.chevron_right,
                                          color: Colors.purple,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        onTap: () =>
                                            Navigator.pop(context, entry.key),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                  ),
                  const SizedBox(height: 15),
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.purple.withOpacity(0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 24,
                        ),
                      ),
                      child: const Text(
                        '取消',
                        style: TextStyle(
                          color: Colors.purple,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    // 如果用户选择了字幕
    if (selectedIndex != null) {
      _currentSubtitleIndex = selectedIndex;
      _chewieController!.setSubtitle(_subtitles[selectedIndex].subtitles!);
      _chewieController!.assStyles = _subtitles[selectedIndex].styles;
      _chewieController!.assSubtitles = _subtitles[selectedIndex].assSubtitles;
      setState(() {});
    }
  }

  void _updatePlaybackState() {
    if (_videoController != null) {
      setState(() {
        _isPlaying = _videoController!.value.isPlaying;
        _currentPosition = _videoController!.value.position;
      });
    }
  }

  void _togglePlayPause() {
    setState(() {
      _isPlaying = !_isPlaying;
      _isPlaying ? _videoController?.play() : _videoController?.pause();
      _resetHideTimer();
    });
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    if (_isPlaying &&
        !_isAudio &&
        _videoController?.value.isInitialized == true) {
      _hideTimer = Timer(Duration(seconds: 5), () {
        setState(() {
          _showControls = false;
        });
      });
    }
  }

  void _setPlaybackSpeed(double speed) {
    setState(() {
      _playbackSpeed = speed;
      _videoController?.setPlaybackSpeed(speed);
    });
  }

  @override
  void dispose() {
    _videoController?.removeListener(_updatePlaybackState);
    _videoController?.dispose();
    _chewieController?.dispose();
    _volumeSliderTimer?.cancel();
    _animeController?.dispose();
    _hideTimer?.cancel();
    _timer?.cancel();
    _positionUpdateTimer?.cancel();
    _positionUpdateTimer = null;
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return hours == '00' ? '$minutes:$seconds' : '$hours:$minutes:$seconds';
  }

  void _rewind10Seconds() {
    if (_videoController != null) {
      final currentPosition = _videoController!.value.position;
      final newPosition = currentPosition - Duration(seconds: 10);
      _videoController!
          .seekTo(newPosition < Duration.zero ? Duration.zero : newPosition);
    }
  }

  void _fastForward10Seconds() {
    if (_videoController != null) {
      final currentPosition = _videoController!.value.position;
      final duration = _videoController!.value.duration;
      final newPosition = currentPosition + Duration(seconds: 10);
      _videoController!.seekTo(newPosition > duration ? duration : newPosition);
    }
  }

  void _seekVideo(Duration _duration) {
    if (_videoController != null) {
      final currentPosition = _videoController!.value.position;
      final duration = _videoController!.value.duration;
      final newPosition = currentPosition + _duration;
      _videoController!.seekTo(
          (newPosition > duration ? duration : newPosition) < Duration.zero
              ? Duration.zero
              : newPosition);
    }
  }

  Future<void> _shareFileOrText(BuildContext context) async {
    try {
      // 判断 openfile 是否是文件路径
      if (widget.openfile.startsWith('file://')) {
        // 如果是本地 URI，转换为文件路径
        final filePath = Uri.decodeFull(
            widget.openfile.replaceFirst(RegExp(r"file://(media|docs)"), ""));
        final file = File(filePath);

        if (await file.exists()) {
          // 分享文件
          await Share.shareXFiles([XFile(filePath)]);
        } else {
          // 文件不存在，分享文本 URI
          await Share.share(widget.openfile);
        }
      } else if (await File(widget.openfile).exists()) {
        // 如果是文件路径且文件存在，分享文件
        if (widget.openfile.endsWith('.lnk')) {
          String uri = File(widget.openfile).readAsStringSync();
          await Share.shareXFiles([XFile(uri)]);
          return;
        }
        await Share.shareXFiles([XFile(widget.openfile)]);
      } else {
        // 否则作为文本分享
        await Share.share(widget.openfile);
      }
    } catch (e) {
      // 处理异常
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分享失败: $e')),
      );
    }
  }

  Widget _buildAssOverlay() {
    if (_assInit == false || _videoController == null) return Container();

    return Positioned.fill(
      child: FutureBuilder<Duration>(
        future: _videoController!.position
            .then((duration) => duration ?? Duration.zero),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return Container();

          return FutureBuilder<ui.Image?>(
            future: getAssFrame(snapshot.data!.inMilliseconds)
                .then((image) => image as ui.Image?)
                .catchError((error) {
              print('Error fetching frame: $error');
              return null; // 返回 null 以处理错误
            }),
            builder: (context, imageSnapshot) {
              if (!imageSnapshot.hasData) return Container();

              return RawImage(
                image: imageSnapshot.data,
                fit: BoxFit.contain,
              );
            },
          );
        },
      ),
    );
  }

  // 辅助方法，创建菜单项
  Widget _buildThemeMenuItem(
      BuildContext context, ThemeMode mode, Icon icon, String text) {
    // 获取当前主题模式
    ThemeMode currentMode = Provider.of<ThemeProvider>(context).themeMode;
    bool isSelected = currentMode == mode;

    return InkWell(
      onTap: () {
        Provider.of<ThemeProvider>(context, listen: false).setThemeMode(mode);
        Navigator.of(context).pop(); // 关闭菜单
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: isSelected
              ? Theme.of(context).primaryColor.withOpacity(0.2)
              : Colors.transparent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            SizedBox(width: 12),
            Text(
              text,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            Spacer(),
            if (isSelected)
              Icon(
                Icons.check_circle_outline,
                color: Theme.of(context).primaryColor,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // super.build(context);
    return WillPopScope(
        onWillPop: _onWillPop,
        child: Scaffold(
            appBar: widget.isFullScreen
                ? null
                : AppBar(
                    title: GestureDetector(
                        onLongPress: () {
                          setState(() {
                            _showPlaylist = !_showPlaylist;
                          });
                        },
                        child: widget.openfile == ''
                            ? Text('AloePlayer播放器')
                            : SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Text('当前文件：' + widget.openfile))),
                    actions: [
                      // IconButton(
                      //   icon: Icon(Icons.open_in_browser),
                      //   onPressed: _openFile,
                      // ),
                      // IconButton(
                      //   icon: Icon(Icons.link),
                      //   onPressed: () => _showUrlDialog(context),
                      // ),
                      IconButton(
                          onPressed: () => _shareFileOrText(context),
                          icon: Icon(Icons.share)),
                      // 主题切换按钮
                      PopupMenuButton<ThemeMode>(
                        icon: Icon(Icons.brightness_medium),
                        offset: Offset(0, 10), // 菜单偏移量，让菜单不会太贴近图标
                        elevation: 0, // 移除默认阴影
                        color: Colors.transparent, // 透明背景色
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16), // 圆角边框
                        ),
                        onSelected: (ThemeMode mode) {
                          Provider.of<ThemeProvider>(context, listen: false)
                              .setThemeMode(mode);
                        },
                        itemBuilder: (BuildContext context) {
                          // 获取当前亮暗主题
                          bool isDarkMode =
                              Theme.of(context).brightness == Brightness.dark;

                          // 返回包含BackdropFilter的项目列表
                          return [
                            // 使用一个自定义PopupMenuItem包装真正的选项
                            PopupMenuItem<ThemeMode>(
                              enabled: false, // 禁用此项，因为它只是容器
                              height: 0, // 设为0使其不占用额外空间
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(
                                      sigmaX: 10, sigmaY: 10), // 高斯模糊效果
                                  child: Container(
                                    padding: EdgeInsets.symmetric(vertical: 8),
                                    decoration: BoxDecoration(
                                      color: isDarkMode
                                          ? Colors.grey[900]!.withOpacity(0.7)
                                          : Colors.white.withOpacity(0.7),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: isDarkMode
                                            ? Colors.white.withOpacity(0.1)
                                            : Colors.black.withOpacity(0.1),
                                        width: 1,
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // 亮色主题选项
                                        _buildThemeMenuItem(
                                            context,
                                            ThemeMode.light,
                                            Icon(Icons.brightness_high,
                                                color: Colors.orange),
                                            '亮色主题'),

                                        Divider(
                                            height: 1,
                                            color:
                                                Colors.grey.withOpacity(0.3)),

                                        // 暗色主题选项
                                        _buildThemeMenuItem(
                                            context,
                                            ThemeMode.dark,
                                            Icon(Icons.brightness_2,
                                                color: Colors.blue),
                                            '暗色主题'),

                                        Divider(
                                            height: 1,
                                            color:
                                                Colors.grey.withOpacity(0.3)),

                                        // 跟随系统选项
                                        _buildThemeMenuItem(
                                            context,
                                            ThemeMode.system,
                                            Icon(Icons.settings_suggest,
                                                color: Colors.grey),
                                            '跟随系统'),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ];
                        },
                      ),

// 不要忘记导入
// import 'dart:ui'; // 为 ImageFilter.blur 导入
                    ],
                  ),
            body: GestureDetector(
              child: Stack(
                children: [
                  Positioned.fill(
                      child: widget.isFullScreen
                          ? Container(
                              color: Colors.black, // 完全透明
                            )
                          : Container(
                              color: Colors.transparent, // 完全透明
                            )),
                  Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // 当没有播放或 _isAudio 为 true 时显示 logo
                        // Visibility(
                        //   visible: (_chewieController == null ||
                        //           _videoController == null ||
                        //           !_videoController!.value.isInitialized ||
                        //           _isAudio) &&
                        //       coverData != null,
                        //   child: InkWell(
                        //     onTap: _openFile, // 点击时执行 _openFile 方法
                        //     child: AnimatedBuilder(
                        //       animation: _animeController!,
                        //       builder: (context, child) {
                        //         return Transform.rotate(
                        //           angle: _animeController!.value *
                        //               2 *
                        //               3.14159, // 360度旋转
                        //           child: Stack(
                        //             alignment: Alignment.center,
                        //             children: [
                        //               // 圆形图片
                        //               ClipOval(
                        //                 child: Image.memory(
                        //                   coverData!,
                        //                   width: 256,
                        //                   height: 256,
                        //                   fit: BoxFit.cover,
                        //                 ),
                        //               ),
                        //               // 光碟效果：叠加一个半透明的圆形渐变
                        //               Container(
                        //                 width: 256,
                        //                 height: 256,
                        //                 decoration: BoxDecoration(
                        //                   shape: BoxShape.circle,
                        //                   gradient: RadialGradient(
                        //                     colors: [
                        //                       Colors.transparent,
                        //                       Colors.white.withOpacity(0.3),
                        //                     ],
                        //                     stops: [0.7, 1.0],
                        //                   ),
                        //                 ),
                        //               ),
                        //             ],
                        //           ),
                        //         );
                        //       },
                        //     ),
                        //   ),
                        // ),
                        Visibility(
                          visible: (_chewieController == null ||
                                  _videoController == null ||
                                  !_videoController!.value.isInitialized ||
                                  _isAudio) &&
                              coverData == null,
                          child: InkWell(
                            onTap: _openFile, // 点击时执行 _openFile 方法
                            child: Image.asset('Assets/icon.png'),
                          ),
                        ),
                        Offstage(
                          offstage: _volumeExample == null,
                          child: SizedBox(
                            width: 1,
                            height: 1,
                            child: _volumeExample!,
                          ),
                        )
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      // 播放器部分（ffmpeg 和 Chewie 堆叠在一起）
                      Expanded(
                        child: Stack(
                          children: [
                            // FFMPEG 播放器
                            if (_useFfmpegForPlay && (_ffmpegExample != null))
                              Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.identity()
                                  ..scale(
                                      _isMirrored ? -1.0 : 1.0, 1.0), // 水平翻转
                                child: this._ffmpegExample!,
                              ),

                            // Chewie 播放器
                            if (_chewieController != null &&
                                _videoController != null &&
                                _videoController!.value.isInitialized)
                              Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.identity()
                                  ..scale(
                                      _isMirrored ? -1.0 : 1.0, 1.0), // 水平翻转
                                child: Chewie(controller: _chewieController!),
                              ),

                            // 播放列表部分 - 覆盖在播放器右侧
                            if (_showPlaylist)
                              Positioned(
                                right: 0,
                                top: 0,
                                bottom: 0,
                                child: AnimatedContainer(
                                  duration: Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                  width: 280,
                                  child: GestureDetector(
                                    onTap: () {}, // 防止点击穿透
                                    onHorizontalDragEnd: (details) {
                                      if (details.primaryVelocity! > 0) {
                                        // 只有向右滑动才关闭
                                        setState(() {
                                          _showPlaylist = false;
                                        });
                                      }
                                    },
                                    child: Stack(
                                      children: [
                                        // 背景模糊效果
                                        Positioned.fill(
                                          child: BackdropFilter(
                                            filter: ImageFilter.blur(
                                                sigmaX: 10, sigmaY: 10),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: Colors.black
                                                    .withOpacity(0.5),
                                                border: Border(
                                                  left: BorderSide(
                                                    color: Colors.white
                                                        .withOpacity(0.2),
                                                    width: 1,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),

                                        // 播放列表内容
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            // 播放列表标题栏
                                            Container(
                                              padding: EdgeInsets.symmetric(
                                                  horizontal: 16, vertical: 12),
                                              decoration: BoxDecoration(
                                                border: Border(
                                                  bottom: BorderSide(
                                                    color: Colors.white
                                                        .withOpacity(0.1),
                                                    width: 1,
                                                  ),
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Text(
                                                    '播放列表',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  IconButton(
                                                    icon: Icon(Icons.close,
                                                        color: Colors.white70),
                                                    onPressed: () =>
                                                        setState(() {
                                                      _showPlaylist = false;
                                                    }),
                                                    iconSize: 20,
                                                    padding: EdgeInsets.zero,
                                                    constraints:
                                                        BoxConstraints(),
                                                  ),
                                                ],
                                              ),
                                            ),

                                            // 播放列表内容
                                            if (_playlist.isEmpty ||
                                                _playlist.length == 1)
                                              Expanded(
                                                child: Center(
                                                  child: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        Icons.playlist_play,
                                                        color: Colors.white54,
                                                        size: 48,
                                                      ),
                                                      SizedBox(height: 8),
                                                      Text(
                                                        '播放列表为空或只有一个文件',
                                                        style: TextStyle(
                                                          color: Colors.white70,
                                                          fontSize: 14,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              )
                                            else
                                              Expanded(
                                                child: ListView.builder(
                                                  padding: EdgeInsets.symmetric(
                                                      vertical: 8),
                                                  itemCount: _playlist.length,
                                                  itemBuilder:
                                                      (context, index) {
                                                    final item =
                                                        _playlist[index];
                                                    final isCurrentFile =
                                                        item['path'] ==
                                                            widget.openfile;

                                                    return Container(
                                                      margin:
                                                          EdgeInsets.symmetric(
                                                              horizontal: 8,
                                                              vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: isCurrentFile
                                                            ? Colors.blue
                                                                .withOpacity(
                                                                    0.2)
                                                            : Colors
                                                                .transparent,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(8),
                                                      ),
                                                      child: ListTile(
                                                        contentPadding:
                                                            EdgeInsets
                                                                .symmetric(
                                                          horizontal: 12,
                                                          vertical: 4,
                                                        ),
                                                        leading: isCurrentFile
                                                            ? Icon(
                                                                Icons
                                                                    .play_circle_filled,
                                                                color:
                                                                    Colors.blue,
                                                                size: 24,
                                                              )
                                                            : Icon(
                                                                Icons
                                                                    .movie_outlined,
                                                                color: Colors
                                                                    .white60,
                                                                size: 24,
                                                              ),
                                                        title: Text(
                                                          item['name']!,
                                                          style: TextStyle(
                                                            color: isCurrentFile
                                                                ? Colors.blue
                                                                : Colors.white,
                                                            fontWeight:
                                                                isCurrentFile
                                                                    ? FontWeight
                                                                        .bold
                                                                    : FontWeight
                                                                        .normal,
                                                            fontSize: 14,
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                        onTap: () {
                                                          if (item['path'] !=
                                                              widget.openfile) {
                                                            setState(() {
                                                              getopenfile(item[
                                                                  'path']!);
                                                              _showPlaylist =
                                                                  false;
                                                            });
                                                          }
                                                        },
                                                        hoverColor: Colors.white
                                                            .withOpacity(0.1),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_showVolumeSlider)
                    Positioned(
                      bottom: 100, // 悬浮在音量按钮上方
                      right: 20, // 靠近音量按钮
                      child: Container(
                        height: 200, // 增加高度
                        width: 40,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: RotatedBox(
                          quarterTurns: 3, // 旋转270度，使Slider变为纵向
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 4, // 调整轨道高度
                              thumbShape: RoundSliderThumbShape(
                                  enabledThumbRadius: 8), // 调整滑块大小
                              overlayShape: RoundSliderOverlayShape(
                                  overlayRadius: 12), // 调整滑块点击区域大小
                            ),
                            child: Slider(
                              value: _volume,
                              min: 0.0,
                              max: 1.0,
                              onChanged: (value) {
                                setState(() {
                                  _volume = value;
                                  _videoController?.setVolume(_volume);
                                });
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            )));
  }
}

class SubtitleBuilder extends StatefulWidget {
  final String subtitle;

  SubtitleBuilder({required this.subtitle});

  @override
  _SubtitleBuilderState createState() => _SubtitleBuilderState();
}

class _SubtitleBuilderState extends State<SubtitleBuilder> {
  late Future<double> _fontSizeFuture;
  final SettingsService _settingsService = SettingsService();

  @override
  void initState() {
    super.initState();
    _fontSizeFuture = _settingsService.getSubtitleFontSize();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<double>(
      future: _fontSizeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildSubtitle(18.0); // 默认字体大小
        } else if (snapshot.hasError) {
          return _buildErrorSubtitle();
        } else {
          final fontSize = snapshot.data ?? 18.0; // 如果获取失败，使用默认值
          return _buildSubtitle(fontSize);
        }
      },
    );
  }

  Widget _buildSubtitle(double fontSize) {
    return Container(
      padding: const EdgeInsets.all(10.0),
      alignment: Alignment.center, // 使文本居中
      child: Stack(
        children: [
          // 四周黑边描边效果
          Text(
            widget.subtitle,
            textAlign: TextAlign.center, // 文本居中
            style: TextStyle(
              fontSize: fontSize,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.5 // 描边宽度
                ..color = Colors.black,
            ),
          ),
          // 实际文本
          Text(
            widget.subtitle,
            textAlign: TextAlign.center, // 文本居中
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorSubtitle() {
    return Container(
      padding: const EdgeInsets.all(10.0),
      alignment: Alignment.center, // 使文本居中
      child: Text(
        '加载字体大小失败',
        textAlign: TextAlign.center, // 文本居中
        style: const TextStyle(
          color: Colors.red,
          fontSize: 18,
        ),
      ),
    );
  }
}

class SubtitleData {
  final String name; // 字幕名称（文件名）
  final String content; // 字幕内容
  final String extension; // 文件扩展名
  List<Subtitle>? subtitles; // 解析后的字幕列表
  List<AssStyle>? styles;
  List<AssSubtitle>? assSubtitles;

  SubtitleData({
    required this.name,
    required this.content,
    required this.extension,
    this.subtitles,
    this.styles,
    this.assSubtitles,
  });
}
