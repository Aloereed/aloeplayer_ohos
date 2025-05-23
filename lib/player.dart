import 'dart:convert';
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:aloeplayer/privacy_policy.dart';
import 'package:intl/intl.dart';
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
import 'package:aloeplayer/chewie-1.8.5/lib/src/hdrview.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:dart_libass/dart_libass.dart';
import 'history_service.dart';
import 'package:aloeplayer/ass.dart';
import 'package:galactic_hotkeys/galactic_hotkeys_widget.dart';

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
  VideoPlayerController? _audioTrackController;
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
  HdrExample? _hdrExample;
  List<SubtitleData> _subtitles = []; // 存储所有字幕
  int _currentSubtitleIndex = -1; // 当前启用的字幕索引
  List<Map<String, dynamic>> _danmakuContents = []; // 存储所有弹幕
  List<Map<String, String>> _playlist = [];
  int _useFfmpegForPlay = 0;
  bool _initVpWhenFfmpeg = false;
  DartLibass? _assRenderer;
  File? _assFile;
  bool _assInit = false;
  File? _assFontFile;
  bool _showPlaylist = false;
  bool _usePlaylist = true;
  String? subtitleFontFamily;
  SortType _sortType = SortType.name; // 默认按名称排序
  SortOrder _sortOrder = SortOrder.ascending; // 默认升序
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
    int duration = _videoController?.value.duration.inMilliseconds ?? 0;
    await _historyService.updatePosition(filePath, currentPosition);
    await _historyService.updateDuration(filePath, duration);
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
// 调用原生方法
    _systemMaxVolume =
        ((await _platform.invokeMethod<int>('getMaxVolume')) ?? 15).toDouble();
    _systemVolume =
        ((await _platform.invokeMethod<int>('getCurrentVolume')) ?? 7.5)
            .toDouble();
    subtitleFontFamily = await _settingsService
        .loadFontFromFile(await _settingsService.getSubtitleFont());
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

  Future<bool> _getHdr(File file) async {
    try {
      // 调用原生方法获取HDR信息的JSON字符串
      String filePath = file.path;
      // 调用原生方法获取HDR信息的JSON字符串
      if (file.path.endsWith('.lnk')) {
        // 读取文件内容
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

        // 提取isHDR字段
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

  Future<void> _openAudioTrackDialog() async {
    if (_videoController == null) return;
    print('打开音轨列表');
    final _ffmpegplatform =
        const MethodChannel('samples.flutter.dev/ffmpegplugin');
    // print("[ffprobe] getaudio" +
    //     (await _ffmpegplatform.invokeMethod<String>(
    //             'getAudioTracks', {'path': widget.openfile}) ??
    //         ''));
    // print("[ffprobe] gethdr");
    final audiotrackjson = await _ffmpegplatform.invokeMethod<String>(
            'getAudioTracks', {'path': widget.openfile}) ??
        '';
    print('[ffprobe] 获取音轨信息: $audiotrackjson');
    final Map<int, String> audioTrackInfo = parseAudioTracks(audiotrackjson);
    List<String> audioTracks = ['0', '1', '2', '3', '4', '5'];
    List<String> externalAudioTracks = [];
    String videoBaseName = '';

    // 获取内置音轨
    print('获取内置音轨列表...');
    try {
      audioTracks = await _videoController!.getAudioTracks();
      print('内置音轨列表: $audioTracks, 长度: ${audioTracks.length}');

      // 如果音轨列表为空，则默认显示 0, 1, 2, 3, 4, 5
      if (audioTracks.isEmpty) {
        audioTracks = ['0', '1', '2', '3', '4', '5'];
      }
      // 去除音轨列表中的空字符串
      audioTracks.removeWhere((element) => element.isEmpty);
    } catch (e) {
      print('获取内置音轨列表失败: $e');
      audioTracks = ['0', '1', '2', '3', '4', '5'];
    }

    // 获取外置音轨
    print('获取外置音轨列表...');
    try {
      videoBaseName = path.basenameWithoutExtension(widget.openfile);
      final cacheDir = await getTemporaryDirectory();
      final directoryPath = cacheDir.path;

      // 扫描目录中的所有文件
      final directory = Directory(directoryPath);
      final files = directory.listSync();

      // 筛选出符合条件的AAC文件
      for (final file in files) {
        if (file is File &&
            (file.path.toLowerCase().endsWith('.aac') ||
                file.path.toLowerCase().endsWith('.mp3') ||
                file.path.toLowerCase().endsWith('.m4a')) &&
            path.basename(file.path).startsWith(videoBaseName)) {
          externalAudioTracks.add(file.path);
          print('找到外置音轨: ${file.path}');
        }
      }

      // 然后尝试在文件同级目录下查找
      final parentDir = Directory(path.dirname(widget.openfile));
      final parentFiles = parentDir.listSync();

      for (final file in parentFiles) {
        if (file is File &&
            (file.path.toLowerCase().endsWith('.aac') ||
                file.path.toLowerCase().endsWith('.mp3') ||
                file.path.toLowerCase().endsWith('.m4a')) &&
            path.basename(file.path).startsWith(videoBaseName)) {
          externalAudioTracks.add(file.path);
          print('找到外置音轨: ${file.path}');
        }
      }
    } catch (e) {
      print('获取外置音轨失败: $e');
    }

    // 显示选择对话框
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
                      '选择非音频轨道可能会导致错误。0一般为视频轨。然后是音频轨。其他轨道可能是字幕轨道。如果没有音频轨道，请尝试使用软解或提取外置音轨。',
                      style: TextStyle(color: Colors.red, fontSize: 14),
                    ),
                  ),
                  if (externalAudioTracks.isNotEmpty) ...[
                    const SizedBox(height: 15),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: Colors.green.withOpacity(0.3)),
                      ),
                      child: const Text(
                        '发现外置音轨文件，选择它们将会替换视频原有声音',
                        style: TextStyle(color: Colors.green, fontSize: 14),
                      ),
                    ),
                  ],
                  const SizedBox(height: 15),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.4,
                    ),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        children: [
                          // 内置音轨
                          ...audioTracks.map((track) {
                            return _buildTrackTile(
                              track,
                              '轨道 $track - ${(int.tryParse(track) != null && audioTrackInfo.containsKey(int.tryParse(track))) ? audioTrackInfo[int.tryParse(track)] : '未知'}',
                              Icons.audio_file,
                              Colors.blue,
                              context,
                            );
                          }).toList(),

                          // 分隔线（如果同时存在内置和外置音轨）
                          if (audioTracks.isNotEmpty &&
                              externalAudioTracks.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Container(
                                height: 1,
                                color: Colors.grey.withOpacity(0.3),
                              ),
                            ),

                          // 外置音轨
                          ...externalAudioTracks.map((trackPath) {
                            final fileName = path.basename(trackPath);
                            return _buildTrackTile(
                              trackPath,
                              '外置音轨: $fileName',
                              Icons.music_note,
                              Colors.green,
                              context,
                            );
                          }).toList(),
                        ],
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

    // 处理选择结果
    if (selectedTrack != null) {
      await _handleTrackSelection(selectedTrack, externalAudioTracks);
    }
  }

  Widget _buildTrackTile(String value, String displayName, IconData icon,
      Color color, BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withOpacity(0.2),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(icon, color: color),
        title: Text(
          displayName,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Icon(Icons.chevron_right, color: color),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        onTap: () {
          Navigator.of(context).pop(value);
        },
      ),
    );
  }

  Future<void> _handleTrackSelection(
      String selectedTrack, List<String> externalAudioTracks) async {
    // 判断是内置音轨还是外置音轨
    if (externalAudioTracks.contains(selectedTrack)) {
      // 选择的是外置音轨
      await _setupExternalAudioTrack(selectedTrack);
    } else {
      // 选择的是内置音轨
      await _setupInternalAudioTrack(int.tryParse(selectedTrack) ?? 0);
    }
  }

  Future<void> _setupExternalAudioTrack(String audioFilePath) async {
    try {
      print('设置外置音轨: $audioFilePath');

      // 如果已有外置音轨控制器，先释放
      if (_audioTrackController != null) {
        await _audioTrackController!.dispose();
        _audioTrackController = null;
      }

      // 创建外置音轨控制器
      _audioTrackController = VideoPlayerController.file(File(audioFilePath));
      await _audioTrackController!.initialize();

      // 记录当前视频位置和播放状态
      final currentPosition = _videoController!.value.position;
      final wasPlaying = _videoController!.value.isPlaying;
      final currentPlaybackSpeed = _videoController!.value.playbackSpeed;

      // 设置视频静音
      await _videoController!.setVolume(0.0);

      // 设置音频轨道到相同位置并应用相同的播放速度
      await _audioTrackController!.setPlaybackSpeed(currentPlaybackSpeed);
      await _audioTrackController!.seekTo(currentPosition);

      // 添加监听器以同步视频和音频播放
      _videoController!.removeListener(_syncAudioTrack);
      _videoController!.addListener(_syncAudioTrack);

      // 如果视频在播放，则启动音频
      if (wasPlaying) {
        await _audioTrackController!.play();
      }

      setState(() {});
    } catch (e) {
      print('设置外置音轨失败: $e');
      // 出错时恢复视频声音
      if (_videoController != null) {
        await _videoController!.setVolume(1.0);
      }
    }
  }

  Future<void> _setupInternalAudioTrack(int trackIndex) async {
    try {
      print('设置内置音轨: $trackIndex');

      // 如果有外置音轨控制器，停止并释放
      if (_audioTrackController != null) {
        await _audioTrackController!.pause();
        await _audioTrackController!.dispose();
        _audioTrackController = null;
      }

      // 恢复视频声音
      await _videoController!.setVolume(1.0);

      // 设置内置音轨
      await _videoController!.setAudioTrack(trackIndex.toString());

      // 移除同步监听器
      _videoController!.removeListener(_syncAudioTrack);

      setState(() {});
    } catch (e) {
      print('设置内置音轨失败: $e');
    }
  }

  void _syncAudioTrack() {
    if (_videoController == null || _audioTrackController == null) return;

    // 同步播放/暂停状态
    if (_videoController!.value.isPlaying &&
        !_audioTrackController!.value.isPlaying) {
      _audioTrackController!.play();
    } else if (!_videoController!.value.isPlaying &&
        _audioTrackController!.value.isPlaying) {
      _audioTrackController!.pause();
    }

    // 同步播放速度
    if (_videoController!.value.playbackSpeed !=
        _audioTrackController!.value.playbackSpeed) {
      _audioTrackController!
          .setPlaybackSpeed(_videoController!.value.playbackSpeed);
    }

    // 检查是否需要同步位置(差距大于1秒)
    final videoDuration = _videoController!.value.position;
    final audioDuration = _audioTrackController!.value.position;

    if ((videoDuration - audioDuration).abs().inMilliseconds > 1000) {
      _audioTrackController!.seekTo(videoDuration);
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

  Future<void> showChewieAdjustmentDialog(BuildContext context) async {
    // 获取当前值
    double currentAspectRatio = _chewieController?.aspectRatio ??
        _chewieController?.videoPlayerController.value.aspectRatio ??
        16 / 9;
    double currentScale = _chewieController?.scale ?? 1.0;
    Offset currentPosition = _chewieController?.position ?? Offset.zero;

    // 默认值
    final double defaultAspectRatio =
        _chewieController?.videoPlayerController.value.aspectRatio ?? 16 / 9;
    final double defaultScale = 1.0;
    final Offset defaultPosition = Offset.zero;

    return showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        // 使用StatefulBuilder允许对话框内部状态更新
        return StatefulBuilder(builder: (context, setState) {
          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AlertDialog(
              backgroundColor: Theme.of(context).brightness == Brightness.dark
                  ? Colors.black.withOpacity(0.7)
                  : Colors.white.withOpacity(0.7),
              title: Text('调整视频显示'),
              content: Container(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 宽高比调整
                      Text('宽高比: ${currentAspectRatio.toStringAsFixed(2)}'),
                      Slider(
                        value: currentAspectRatio,
                        min: 0.5,
                        max: 2.5,
                        divisions: 40,
                        onChanged: (newValue) {
                          setState(() {
                            currentAspectRatio = newValue;
                          });
                        },
                      ),

                      SizedBox(height: 16),

                      // 缩放调整
                      Text('缩放: ${currentScale.toStringAsFixed(2)}'),
                      Slider(
                        value: currentScale,
                        min: 0.5,
                        max: 2.0,
                        divisions: 30,
                        onChanged: (newValue) {
                          setState(() {
                            currentScale = newValue;
                          });
                        },
                      ),

                      SizedBox(height: 16),

                      // 位置调整
                      Text(
                          '位置调整: X: ${currentPosition.dx.toStringAsFixed(2)}, Y: ${currentPosition.dy.toStringAsFixed(2)}'),
                      Container(
                        height: 150,
                        decoration: BoxDecoration(
                          border:
                              Border.all(color: Theme.of(context).dividerColor),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: GestureDetector(
                          onPanUpdate: (details) {
                            setState(() {
                              double newDx =
                                  currentPosition.dx + details.delta.dx;
                              double newDy =
                                  currentPosition.dy + details.delta.dy;
                              // newDx = newDx.clamp(-1.0, 1.0);
                              // newDy = newDy.clamp(-1.0, 1.0);
                              currentPosition = Offset(newDx, newDy);
                            });
                          },
                          child: Center(
                            child: Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: Theme.of(context).primaryColor,
                                shape: BoxShape.circle,
                              ),
                              margin: EdgeInsets.only(
                                left: (currentPosition.dx * 50) + 50,
                                top: (currentPosition.dy * 50) + 50,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                // 重置按钮 - 恢复默认值
                TextButton(
                  child: Text('重置'),
                  onPressed: () {
                    setState(() {
                      currentAspectRatio = defaultAspectRatio;
                      currentScale = defaultScale;
                      currentPosition = defaultPosition;
                    });
                  },
                ),
                TextButton(
                  child: Text('取消'),
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                ),
                ElevatedButton(
                  child: Text('应用'),
                  onPressed: () {
                    // 直接设置控制器的属性
                    if (_chewieController != null) {
                      setState(() {
                        _chewieController!.aspectRatio = currentAspectRatio;
                        _chewieController!.scale = currentScale;
                        _chewieController!.position = currentPosition;
                      });
                      // 通知外部UI更新
                      if (context is StatefulElement) {
                        (context as StatefulElement).state.setState(() {});
                      }
                    }
                    Navigator.of(dialogContext).pop();
                  },
                ),
              ],
            ),
          );
        });
      },
    );
  }

  Future<void> _initializeChewieController() async {
    _volumeController = _volumeExample?.controller;
    _videoController!.addListener(_checkIfVideoFinished);

    _chewieController = ChewieController(
      ffmpeg: _useFfmpegForPlay,
      sendToFfmpegPlayer: _ffmpegExample,
      sendToHdrPlayer: _hdrExample,
      videoPlayerController: _videoController!,
      allowMuting: _useFfmpegForPlay == 0,
      autoPlay: true,
      looping: _isLooping == 2,
      showControls: _showControls,
      allowFullScreen: true,
      zoomAndPan: true,
      subtitleFontFamily: subtitleFontFamily,
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
        return SubtitleBuilder(
          subtitle: subtitle,
          fontFamily: subtitleFontFamily,
        );
      },
      additionalOptions: (context) {
        return <OptionItem>[
          // OptionItem(
          //   onTap: _openFile,
          //   iconData: Icons.open_in_browser,
          //   title: '打开文件',
          // ),
          if (_useFfmpegForPlay == 0 || _useFfmpegForPlay == 3)
            OptionItem(
              onTap: () async => showChewieAdjustmentDialog(context),
              iconData: Icons.aspect_ratio,
              title: '缩放和宽高比',
            ),
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
          if (_useFfmpegForPlay == 0)
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
          OptionItem(
            onTap: () {
              setState(() {
                _isMirrored = !_isMirrored; // 切换镜像状态
                _chewieController?.isMirrored = _isMirrored; // 更新视频控制器的镜像状态
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
                ? '循环模式(不循环)'
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
    _chewieController?.setVolume(_useFfmpegForPlay != 0 ? 0.0 : 1.0);
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

  /// 重新读取字幕文件
  Future<void> reloadSubtitles(String path) async {
    // 清空当前字幕
    _subtitles.clear();

    // 提取文件名和不带扩展名的文件名
    final String fileName = path.split('/').last;
    final String fileNameWithoutExt =
        fileName.substring(0, fileName.lastIndexOf('.'));

    // 从缓存目录读取字幕
    await _readSubtitlesFromCacheDirectly(fileName);

    // 从视频所在目录读取字幕
    final String videoDirectory = path.substring(0, path.lastIndexOf('/'));
    await _readSubtitlesFromVideoDirectory(videoDirectory, fileNameWithoutExt);
  }

  /// 从缓存目录直接读取字幕文件，不包含等待和重试机制
  Future<void> _readSubtitlesFromCacheDirectly(String fileName) async {
    try {
      // 获取缓存目录路径
      final cacheDir = await getTemporaryDirectory();
      final String directoryPath = cacheDir.path;
      print('缓存目录路径: $directoryPath');

      // 列出目录中的所有文件
      Directory directory = Directory(directoryPath);
      List<FileSystemEntity> files = await directory.list().toList();

      // 查找匹配的字幕文件
      List<File> matchingFiles = _findSubtitleFiles(files, fileName);

      // 打印找到的字幕文件
      if (matchingFiles.isNotEmpty) {
        print('在缓存目录中找到 ${matchingFiles.length} 个匹配的字幕文件：');
        for (var file in matchingFiles) {
          print(file.path);
        }
        // 处理所有找到的字幕文件
        await _processSubtitleFiles(matchingFiles);
      } else {
        print('缓存中未找到字幕文件');
      }
    } catch (e) {
      // 只记录错误，不重试
      print('从缓存读取字幕失败: $e');
    }
  }

  /// 尝试读取字幕文件，带有重试机制
  Future<void> readFileWithRetry(String path) async {
    // 提取文件名和不带扩展名的文件名
    final String fileName = path.split('/').last;
    final String fileNameWithoutExt =
        fileName.substring(0, fileName.lastIndexOf('.'));

    // 首先从缓存目录读取字幕
    await _readSubtitlesFromCache(fileName);

    // 然后从视频所在目录读取字幕（注意：这里不受缓存目录结果的影响，始终会执行）
    final String videoDirectory = path.substring(0, path.lastIndexOf('/'));
    await _readSubtitlesFromVideoDirectory(videoDirectory, fileNameWithoutExt);

    // 设置默认字幕
    _setDefaultSubtitle();
  }

  /// 从缓存目录读取字幕文件，会尝试多次（因为字幕可能正在被提取）
  Future<void> _readSubtitlesFromCache(String fileName) async {
    // 先等待一段时间，给字幕提取留出时间
    await Future.delayed(Duration(seconds: 2));

    // 尝试最多3次读取文件
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        // 获取缓存目录路径
        final cacheDir = await getTemporaryDirectory();
        final String directoryPath = cacheDir.path;
        print('缓存目录路径: $directoryPath');

        // 列出目录中的所有文件
        Directory directory = Directory(directoryPath);
        List<FileSystemEntity> files = await directory.list().toList();

        // 查找匹配的字幕文件
        List<File> matchingFiles = _findSubtitleFiles(files, fileName);

        // 打印找到的字幕文件
        if (matchingFiles.isNotEmpty) {
          print('在缓存目录中找到 ${matchingFiles.length} 个匹配的字幕文件：');
          for (var file in matchingFiles) {
            print(file.path);
          }

          // 处理所有找到的字幕文件
          await _processSubtitleFiles(matchingFiles);

          // 找到字幕文件，跳出重试循环
          break;
        } else {
          // 如果没有找到文件，抛出异常以触发重试
          throw FileSystemException('缓存中未找到字幕文件', directoryPath);
        }
      } catch (e) {
        // 打印错误信息
        print('尝试 ${attempt + 1}/3 从缓存读取字幕失败: $e');

        // 如果是文件不存在错误，等待3秒后重试
        if (e is FileSystemException) {
          print('等待3秒后重试...');
          await Future.delayed(Duration(seconds: 3));
        } else {
          // 其他类型的错误，直接抛出
          rethrow;
        }
      }

      // 最后一次尝试后，如果仍未成功
      if (attempt == 2) {
        print('从缓存读取字幕文件失败，已尝试3次');
      }
    }
  }

  /// 从视频所在目录读取字幕文件
  Future<void> _readSubtitlesFromVideoDirectory(
      String directoryPath, String fileNameWithoutExt) async {
    try {
      print('尝试从视频目录读取字幕: $directoryPath');

      // 列出目录中的所有文件
      Directory directory = Directory(directoryPath);
      List<FileSystemEntity> files = await directory.list().toList();

      // 查找匹配的字幕文件
      List<File> matchingFiles = files.whereType<File>().where((file) {
        String name = file.path.split('/').last;
        return (name.startsWith(fileNameWithoutExt) &&
            (name.toLowerCase().endsWith('.ass') ||
                name.toLowerCase().endsWith('.srt')));
      }).toList();

      // 打印找到的字幕文件
      if (matchingFiles.isNotEmpty) {
        print('在视频目录中找到 ${matchingFiles.length} 个匹配的字幕文件：');
        for (var file in matchingFiles) {
          print(file.path);
        }

        // 处理所有找到的字幕文件
        await _processSubtitleFiles(matchingFiles);
      } else {
        print('在视频目录中未找到匹配的字幕文件');
      }
    } catch (e) {
      print('从视频目录读取字幕时出错: $e');
    }
  }

  /// 查找匹配的字幕文件
  List<File> _findSubtitleFiles(List<FileSystemEntity> files, String fileName) {
    return files.whereType<File>().where((file) {
      String name = file.path.split('/').last;
      return (name.startsWith(fileName) &&
          (name.toLowerCase().endsWith('.ass') ||
              name.toLowerCase().endsWith('.srt')));
    }).toList();
  }

  /// 处理找到的字幕文件列表
  Future<void> _processSubtitleFiles(List<File> files) async {
    for (var file in files) {
      await _processSubtitleFile(file);
    }
  }

  /// 处理单个字幕文件，错误不会阻塞其他文件的处理
  Future<void> _processSubtitleFile(File file) async {
    try {
      // 读取文件内容
      String content = await file.readAsString();
      String name = file.path.split('/').last;
      String extension = file.path.split('.').last.toLowerCase();
      if (name.contains('_内置_')) {
        // 将名字改为'[内置] _内置_之后的部分'
        name = '[内置] ' + name.split('_内置_')[1];
        // 如果以“.ass”结尾要去掉
        if (name.endsWith('.ass')) {
          name = name.split('.ass')[0];
        }
      }
      // 创建字幕数据对象
      SubtitleData subtitleData = SubtitleData(
        name: name,
        content: content,
        extension: extension,
      );

      // 根据扩展名解析字幕
      if (extension == 'ass') {
        try {
          subtitleData.subtitles = await ass2srt(content);
          final result = AssParserPlus.parseAssContent(content);
          subtitleData.styles = result.$1;
          subtitleData.assSubtitles = result.$2;
        } catch (e) {
          print('解析 ASS 字幕失败: $e');
          // 继续处理，不阻塞其他字幕
          return;
        }
      } else if (extension == 'srt') {
        try {
          SubtitleController controller = SubtitleController.string(
            content,
            format: SubtitleFormat.srt,
          );
          subtitleData.subtitles = controller.subtitles
              .map((e) => Subtitle(
                    index: e.number,
                    start: Duration(milliseconds: e.start),
                    end: Duration(milliseconds: e.end),
                    text: e.text.replaceAll('\\N', '\n'),
                  ))
              .toList();
        } catch (e) {
          print('解析 SRT 字幕失败: $e');
          // 继续处理，不阻塞其他字幕
          return;
        }
      }

      // 将处理好的字幕添加到列表
      _subtitles.add(subtitleData);
    } catch (e) {
      print('处理字幕文件 ${file.path} 时出错: $e');
      // 继续处理其他字幕文件
    }
  }

  /// 设置默认字幕
  void _setDefaultSubtitle() {
    if (_currentSubtitleIndex == -1 && _subtitles.isNotEmpty) {
      // 定义中文字幕的优先关键词列表，按优先级从高到低排序
      final chineseKeywords = [
        "简",
        "SC",
        "sc",
        "繁体",
        "TC",
        "tc",
        "中",
        "CN",
        "cn",
        "chi"
      ];

      // 首先尝试按优先级查找匹配的ASS字幕
      int preferredAssIndex = -1;

      // 按优先级查找匹配关键词的ASS字幕
      for (String keyword in chineseKeywords) {
        preferredAssIndex = _subtitles.indexWhere((subtitle) =>
            subtitle.assSubtitles != null && subtitle.name.contains(keyword));

        if (preferredAssIndex != -1) {
          break; // 找到了匹配的ASS字幕，停止查找
        }
      }

      if (preferredAssIndex != -1) {
        // 找到了匹配关键词的ASS字幕
        _currentSubtitleIndex = preferredAssIndex;
      } else {
        // 没有匹配关键词的ASS字幕，查找任意ASS字幕
        int anyAssIndex =
            _subtitles.indexWhere((subtitle) => subtitle.assSubtitles != null);

        if (anyAssIndex != -1) {
          // 找到了ASS字幕
          _currentSubtitleIndex = anyAssIndex;
        } else {
          // 查找匹配关键词的普通字幕
          int preferredSubtitleIndex = -1;

          for (String keyword in chineseKeywords) {
            preferredSubtitleIndex = _subtitles.indexWhere((subtitle) =>
                subtitle.subtitles != null && subtitle.name.contains(keyword));

            if (preferredSubtitleIndex != -1) {
              break; // 找到了匹配的普通字幕
            }
          }

          if (preferredSubtitleIndex != -1) {
            // 找到了匹配关键词的普通字幕
            _currentSubtitleIndex = preferredSubtitleIndex;
          } else {
            // 没有任何匹配的字幕，使用第一个普通字幕
            _currentSubtitleIndex = 0;
          }
        }
      }

      // 应用选择的字幕
      final subtitleData = _subtitles[_currentSubtitleIndex];
      _chewieController!.setSubtitle(subtitleData.subtitles!);
      _chewieController!.assStyles = subtitleData.styles;
      _chewieController!.assSubtitles = subtitleData.assSubtitles;
      // 更新 UI
      // setState(() {});
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

  void _sortPlaylist() {
    if (_sortType == SortType.none) {
      return; // 不排序
    }

    setState(() {
      _playlist.sort((a, b) {
        int result;

        if (_sortType == SortType.name) {
          result = a['name']!.compareTo(b['name']!);
        } else if (_sortType == SortType.modifiedDate) {
          // 获取文件修改时间
          File fileA = File(a['path']!);
          File fileB = File(b['path']!);
          result = fileA.lastModifiedSync().compareTo(fileB.lastModifiedSync());
        } else {
          result = 0;
        }

        // 根据排序顺序返回结果
        return _sortOrder == SortOrder.ascending ? result : -result;
      });
    });
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
    List<String> excludeExts = ['ux_store', 'srt', 'ass', 'jpg', 'pdf', 'aac'];
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

      // 应用排序
      _sortPlaylist();

      // 打印playlist
      print("Playlist: $_playlist");
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

  Future<void> _extractRestAss(String uri, String directoryPath,
      String fileName, String subtitleTracksJson) async {
    await Future.delayed(Duration(milliseconds: 1000));
    try {
      print("[ffprobe] subtitleTracksJson: $subtitleTracksJson");

      final subtitles =
          parseSubtitleTracks(subtitleTracksJson, useOriginalIndices: false);
      final copilotSubtitleNum = await _settingsService.getSubtitleMany();

      // Skip the first subtitle and prepare tasks
      bool first = true;
      final tasks = <Map<String, dynamic>>[];
      int i = 0;

      for (var entry in subtitles.entries) {
        if (first) {
          first = false;
          continue;
        }
        if (i >= copilotSubtitleNum && copilotSubtitleNum != -1) {
          break;
        }
        tasks.add({
          'key': entry.key,
          'value': entry.value,
        });
        i++;
      }
      await Future.delayed(Duration(milliseconds: 1000));
      if (tasks.isNotEmpty) {
        // Process tasks one by one, but without blocking the UI
        await _processTasksNonBlocking(uri, directoryPath, fileName, tasks);
      }
    } catch (e) {
      print(e);
    }
  }

  Future<void> _processTasksNonBlocking(String uri, String directoryPath,
      String fileName, List<Map<String, dynamic>> tasks) async {
    final _platform = MethodChannel('samples.flutter.dev/ffmpegplugin');

    // Process each task with a small delay to allow the UI to update
    for (var task in tasks) {
      // Use compute or a microtask to yield to the main thread
      await Future.microtask(() async {
        try {
          // 如果path.join(directoryPath, fileName + "_内置_" + task['value']+".ass")存在那么就不做了
          if (File(path.join(
                  directoryPath, fileName + "_内置_" + task['value'] + ".ass"))
              .existsSync()) {
            return;
          }
          await _platform.invokeMethod<String>('getasstrack', {
            "path": uri,
            "type": "ass",
            "output":
                path.join(directoryPath, fileName + "_内置_" + task['value']),
            "track": "${task['key']}"
          });
        } catch (e) {
          print("Error processing track ${task['key']}: $e");
        }
      });

      // Short delay to avoid UI freezes
      await Future.delayed(Duration(milliseconds: 1000));
    }
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
      if (_useFfmpegForPlay == 1) {
        if (_ffmpegExample == null) {
          _ffmpegExample = FfmpegExample(
              initUri: convertUriToPath(widget.openfile),
              toggleFullScreen: this.toggleFullScreen);
        }
        _ffmpegExample?.controller?.sendMessageToOhosView(
            "newPlay", convertUriToPath(widget.openfile));
      }
      if (_useFfmpegForPlay == 2) {
        if (_hdrExample == null) {
          _hdrExample = HdrExample(
              initUri: pathToUri(widget.openfile),
              toggleFullScreen: this.toggleFullScreen);
        } else {
          _hdrExample?.controller
              ?.sendMessageToOhosView("newPlay", pathToUri(widget.openfile));
        }
      }
      if (_useFfmpegForPlay == 3) {
        if (_ffmpegExample == null) {
          _ffmpegExample = FfmpegExample(
            initUri: convertUriToPath(widget.openfile),
            toggleFullScreen: this.toggleFullScreen,
            videoMode: false,
          );
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
            final latestDuration = await _getLastPosition(originalUri);
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
      if (_useFfmpegForPlay == 1) {
        if (_ffmpegExample == null) {
          _ffmpegExample = FfmpegExample(
              initUri: convertUriToPath(uri),
              toggleFullScreen: this.toggleFullScreen);
        }
        _ffmpegExample?.controller
            ?.sendMessageToOhosView("newPlay", convertUriToPath(uri));
      }
      if (_useFfmpegForPlay == 2) {
        if (_hdrExample == null) {
          _hdrExample = HdrExample(
              initUri: pathToUri(uri), toggleFullScreen: this.toggleFullScreen);
        } else {
          _hdrExample?.controller
              ?.sendMessageToOhosView("newPlay", pathToUri(uri));
        }
      }
      if (_useFfmpegForPlay == 3) {
        if (_ffmpegExample == null) {
          _ffmpegExample = FfmpegExample(
            initUri: convertUriToPath(widget.openfile),
            toggleFullScreen: this.toggleFullScreen,
            videoMode: false,
          );
        }
        _ffmpegExample?.controller?.sendMessageToOhosView(
            "newPlay", convertUriToPath(widget.openfile));
      }
      // 立即启动必要的初始化

      // 使用Future.microtask来安排其他初始化任务
      Future.microtask(() {
        _initializePlayer(originalUri, uri);
      });
    }
    // await audioHandler.setLoopingSilence();
    // await audioHandler.play();
    Wakelock.enable();
  }

// 将耗时操作移到单独的方法中
  Future<void> _initializePlayer(String originalUri, String uri) async {
    _getPlaylist(originalUri);

    final isAudio = (uri.split('.').last.toLowerCase() == 'mp3' ||
        uri.split('.').last.toLowerCase() == 'flac' ||
        uri.split('.').last.toLowerCase() == 'wav' ||
        uri.split('.').last.toLowerCase() == 'm4a' ||
        uri.split('.').last.toLowerCase() == 'aac' ||
        uri.split('.').last.toLowerCase() == 'ogg');

    _recordPlayStart(originalUri, originalUri, isVideo: !isAudio);
    _setupPositionUpdateTimer();
    String fileName = originalUri.split('/').last;
    final _platform = const MethodChannel('samples.flutter.dev/ffmpegplugin');
    final cacheDir = await getTemporaryDirectory();
    final directoryPath = cacheDir.path;

    // 异步加载字幕
    if (await _settingsService.getAutoLoadSubtitle() == true) {
      _loadSubtitles(uri, directoryPath, fileName, _platform);
    }

    final ishdr = await _getHdr(File(uri));
    // ui.SetHdr.enableHdr(enable_hdr:true);
    print("[Player] HDR enabled.");
    // ui.SetHdr.setHdrMode(hdr: 1 ,is_image:true);
    print("[Player] HDR set to 1.");
    // 异步读取元数据

    _loadMetadata(uri);
  }

// 拆分为更小的异步方法
  Future<void> _loadSubtitles(String uri, String directoryPath, String fileName,
      MethodChannel platform) async {
    try {
      // 调用原生方法获取字幕
      await platform.invokeMethod<String>('getassold', {
        "path": uri,
        "type": "srt",
        "output": path.join(directoryPath, fileName)
      });

      final subtitleTracksJson = await platform
              .invokeMethod<String>('getSubtitleTracks', {'path': uri}) ??
          '';
      print("[ffprobe] subtitleTracksJson: $subtitleTracksJson");

      final subtitles =
          parseSubtitleTracks(subtitleTracksJson, useOriginalIndices: false);

      for (var entry in subtitles.entries) {
        var key = entry.key;
        var value = entry.value;
        await platform.invokeMethod<String>('getasstrack', {
          "path": uri,
          "type": "ass",
          "output": path.join(directoryPath, fileName + "_内置_" + value),
          "track": "$key"
        });
        break; // 只处理第一个
      }

      _extractRestAss(uri, directoryPath, fileName, subtitleTracksJson);
    } catch (e) {
      print(e);
    }

    readFileWithRetry(uri);
  }

  Future<void> _loadMetadata(String uri) async {
    final metadata = readMetadata(File(uri), getImage: true);
    setState(() {
      coverData =
          metadata.pictures.isNotEmpty ? metadata.pictures[0].bytes : null;
    });
  }

  Future<void> getAudioTrack(
      String filePath, String outputPrefix, int trackNum) async {
    final _platform = const MethodChannel('samples.flutter.dev/ffmpegplugin');
    // 调用原生方法
    await _platform.invokeMethod<String>('getaudiotrack',
        {"path": filePath, "output": outputPrefix, "track": trackNum});
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
    // final _platform = const MethodChannel('samples.flutter.dev/ffmpegplugin');
    // print("ASS: start init libass");
    // // 调用原生方法
    // final initAssRenderSuccess =
    //     await _platform.invokeMethod<bool>('initLibass', {
    //   "assFilename": _assFile!.path,
    //   "width": _videoController!.value.size.width.toInt(),
    //   "height": _videoController!.value.size.height.toInt()
    // });
    await _assRenderer!.init();
    bool initAssRenderSuccess = true;
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
      // final img = await getAssFrame(125000);
      final img = _assRenderer!.getFrame(125000);
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
        name: '[手动] ${file.name}',
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
    await reloadSubtitles(widget.openfile);
    if (_subtitles.isEmpty) {
      print('没有可用的字幕');
      Fluttertoast.showToast(msg: '没有可用的字幕');
      return;
    }

    // 先对字幕列表进行排序，ASS字幕置顶
    final sortedSubtitles = List<SubtitleData>.from(_subtitles);
    sortedSubtitles.sort((a, b) {
      if (a.assSubtitles != null && b.assSubtitles == null) return -1;
      if (a.assSubtitles == null && b.assSubtitles != null) return 1;
      return 0;
    });

    // 显示字幕选择对话框
    int? selectedIndex = await showDialog<int>(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) {
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        final dialogBackgroundColor = isDarkMode
            ? Colors.grey[900]!.withOpacity(0.85)
            : Colors.white.withOpacity(0.85);
        final textColor = isDarkMode ? Colors.white : Colors.black87;
        final hintColor = isDarkMode ? Colors.grey[400]! : Colors.black54;

        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20.0),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: dialogBackgroundColor,
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
                      Center(
                        child: Text(
                          '选择字幕轨道',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.4,
                        ),
                        child: sortedSubtitles.isEmpty
                            ? Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Colors.amber
                                      .withOpacity(isDarkMode ? 0.2 : 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: Colors.amber.withOpacity(0.3)),
                                ),
                                child: Center(
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
                                  children: sortedSubtitles.asMap().entries.map(
                                    (entry) {
                                      final isAss =
                                          entry.value.assSubtitles != null;
                                      final color =
                                          isAss ? Colors.teal : Colors.purple;

                                      return Container(
                                        margin:
                                            const EdgeInsets.only(bottom: 8),
                                        decoration: BoxDecoration(
                                          color: color.withOpacity(
                                              isDarkMode ? 0.15 : 0.05),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                            color: color.withOpacity(
                                                isDarkMode ? 0.3 : 0.2),
                                          ),
                                        ),
                                        child: ListTile(
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 4,
                                          ),
                                          leading: Icon(
                                            isAss
                                                ? Icons.subtitles_outlined
                                                : Icons.subtitles,
                                            color: color,
                                          ),
                                          title: Text(
                                            entry.value.name,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w500,
                                              color: textColor,
                                            ),
                                          ),
                                          subtitle: isAss
                                              ? Text(
                                                  'ASS 字幕',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: color,
                                                  ),
                                                )
                                              : null,
                                          trailing: Icon(
                                            Icons.chevron_right,
                                            color: color,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                          onTap: () {
                                            // 找到原始列表中的索引
                                            int originalIndex = _subtitles
                                                .indexWhere((subtitle) =>
                                                    subtitle == entry.value);
                                            Navigator.pop(
                                                context, originalIndex);
                                          },
                                        ),
                                      );
                                    },
                                  ).toList(),
                                ),
                              ),
                      ),
                      const SizedBox(height: 15),
                      Center(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.purple
                                .withOpacity(isDarkMode ? 0.2 : 0.1),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 24,
                            ),
                          ),
                          child: Text(
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
    // ui.ImageFilter.setHdr(
    //   hdr: 0,
    //   is_image: true,
    // );
    // ui.SetHdr.enableHdr(enable_hdr:false);
    // ui.SetHdr.setHdrMode(hdr:  0 ,is_image:true);
    // print("[Dispose] HDR disabled.");
    _videoController?.removeListener(_updatePlaybackState);
    _videoController?.removeListener(_syncAudioTrack);
    _audioTrackController?.dispose();
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
    return GalacticHotkeys<String>(
      shortcuts: {
        'Play': [
          [LogicalKeyboardKey.space],
        ],
        'Rewind': [
          [LogicalKeyboardKey.arrowLeft],
        ],
        'FastForward': [
          [LogicalKeyboardKey.arrowRight],
        ],
        'VolumeUp': [
          [LogicalKeyboardKey.arrowUp],
        ],
        'VolumeDown': [
          [LogicalKeyboardKey.arrowDown],
        ],
        'Mute': [
          [LogicalKeyboardKey.keyM],
        ],
        // Add more shortcuts as needed
      },
      onShortcutPressed:
          (String identifier, List<LogicalKeyboardKey> pressedKeys) {
        // Handle the shortcut press
        if (identifier == 'Play') {
          _togglePlayPause();
        } else if (identifier == 'Rewind') {
          _rewind10Seconds();
        } else if (identifier == 'FastForward') {
          _fastForward10Seconds();
        } else if (identifier == 'VolumeUp') {
          // _volumeUp();
        } else if (identifier == 'VolumeDown') {
          // _volumeDown();
        } else if (identifier == 'Mute') {
          // _mute();
          _videoController
              ?.setVolume(_videoController!.value.volume == 0 ? 1 : 0);
        }
      },
      child: buildPlayerPage(context),
    );
  }

  Widget buildPlayerPage(BuildContext context) {
    // super.build(context);
    return WillPopScope(
        onWillPop: _onWillPop,
        child: Scaffold(
            appBar: null,
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
                            // 黑色背景
                            Container(
                              color: Colors.black,
                            ),
                            // BackdropFilter(
                            //     filter: ui.ImageFilter.setHdr(
                            //       hdr: 2,
                            //       is_image: true,
                            //     ),
                            //     child: Stack(children: [
                            // HDR 播放器
                            if (_useFfmpegForPlay == 2 && (_hdrExample != null))
                              Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.identity()
                                  ..scale(
                                      _isMirrored ? -1.0 : 1.0, 1.0), // 水平翻转
                                child: this._hdrExample!,
                              ),
                            // FFMPEG 播放器
                            if ((_useFfmpegForPlay == 1 ||
                                    _useFfmpegForPlay == 3) &&
                                (_ffmpegExample != null))
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
                              Chewie(controller: _chewieController!),
                            // ])),

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
                                    child: ClipRect(
                                      // 添加ClipRect限制模糊效果范围
                                      child: Stack(
                                        children: [
                                          // 背景模糊效果 - 现在只在容器范围内模糊
                                          BackdropFilter(
                                            filter: ImageFilter.blur(
                                                sigmaX: 10, sigmaY: 10),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: Colors.black
                                                    .withOpacity(0.6),
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
                                          // 播放列表内容
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              // 播放列表标题栏
                                              Container(
                                                padding: EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 12),
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    colors: [
                                                      Colors.blue
                                                          .withOpacity(0.4),
                                                      Colors.black
                                                          .withOpacity(0.3),
                                                    ],
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                  ),
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
                                                          color:
                                                              Colors.white70),
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
                                              // 排序工具栏
                                              if (_playlist.length > 1)
                                                Container(
                                                  padding: EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 8),
                                                  decoration: BoxDecoration(
                                                    color: Colors.black45,
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
                                                      // 排序类型下拉菜单
                                                      DropdownButtonHideUnderline(
                                                        child: DropdownButton<
                                                            SortType>(
                                                          value: _sortType,
                                                          dropdownColor:
                                                              Colors.black87,
                                                          iconEnabledColor:
                                                              Colors.white70,
                                                          style: TextStyle(
                                                              color:
                                                                  Colors.white,
                                                              fontSize: 13),
                                                          items: [
                                                            DropdownMenuItem(
                                                              value:
                                                                  SortType.name,
                                                              child:
                                                                  Text('按名称'),
                                                            ),
                                                            DropdownMenuItem(
                                                              value: SortType
                                                                  .modifiedDate,
                                                              child:
                                                                  Text('按修改日期'),
                                                            ),
                                                          ],
                                                          onChanged: (value) {
                                                            setState(() {
                                                              _sortType =
                                                                  value!;
                                                              _sortPlaylist();
                                                            });
                                                          },
                                                        ),
                                                      ),
                                                      // 排序顺序按钮
                                                      IconButton(
                                                        icon: Icon(
                                                          _sortOrder ==
                                                                  SortOrder
                                                                      .ascending
                                                              ? Icons
                                                                  .arrow_upward
                                                              : Icons
                                                                  .arrow_downward,
                                                          color: Colors.white70,
                                                          size: 18,
                                                        ),
                                                        onPressed: () {
                                                          setState(() {
                                                            _sortOrder = _sortOrder ==
                                                                    SortOrder
                                                                        .ascending
                                                                ? SortOrder
                                                                    .descending
                                                                : SortOrder
                                                                    .ascending;
                                                            _sortPlaylist();
                                                          });
                                                        },
                                                        tooltip: _sortOrder ==
                                                                SortOrder
                                                                    .ascending
                                                            ? '升序'
                                                            : '降序',
                                                        padding:
                                                            EdgeInsets.zero,
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
                                                            color:
                                                                Colors.white70,
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
                                                    padding:
                                                        EdgeInsets.symmetric(
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
                                                        margin: EdgeInsets
                                                            .symmetric(
                                                                horizontal: 8,
                                                                vertical: 4),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: isCurrentFile
                                                              ? Colors.blue
                                                                  .withOpacity(
                                                                      0.3)
                                                              : Colors
                                                                  .transparent,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(8),
                                                          boxShadow:
                                                              isCurrentFile
                                                                  ? [
                                                                      BoxShadow(
                                                                        color: Colors
                                                                            .blue
                                                                            .withOpacity(0.3),
                                                                        blurRadius:
                                                                            5,
                                                                        spreadRadius:
                                                                            0,
                                                                      )
                                                                    ]
                                                                  : null,
                                                        ),
                                                        child: ListTile(
                                                          contentPadding:
                                                              EdgeInsets
                                                                  .symmetric(
                                                            horizontal: 12,
                                                            vertical: 4,
                                                          ),
                                                          leading: Container(
                                                            width: 32,
                                                            height: 32,
                                                            decoration:
                                                                BoxDecoration(
                                                              color: isCurrentFile
                                                                  ? Colors.blue
                                                                      .withOpacity(
                                                                          0.2)
                                                                  : Colors.white
                                                                      .withOpacity(
                                                                          0.05),
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          16),
                                                            ),
                                                            child: Center(
                                                              child:
                                                                  isCurrentFile
                                                                      ? Icon(
                                                                          Icons
                                                                              .play_circle_filled,
                                                                          color:
                                                                              Colors.blue,
                                                                          size:
                                                                              24,
                                                                        )
                                                                      : Icon(
                                                                          Icons
                                                                              .movie_outlined,
                                                                          color:
                                                                              Colors.white60,
                                                                          size:
                                                                              20,
                                                                        ),
                                                            ),
                                                          ),
                                                          title:
                                                              SingleChildScrollView(
                                                            // 添加水平滚动
                                                            scrollDirection:
                                                                Axis.horizontal,
                                                            child: Text(
                                                              item['name']!,
                                                              style: TextStyle(
                                                                color: isCurrentFile
                                                                    ? Colors
                                                                        .blue
                                                                    : Colors
                                                                        .white,
                                                                fontWeight: isCurrentFile
                                                                    ? FontWeight
                                                                        .bold
                                                                    : FontWeight
                                                                        .normal,
                                                                fontSize: 14,
                                                              ),
                                                            ),
                                                          ),
                                                          // 添加修改日期小标签（如果按修改日期排序）
                                                          subtitle: _sortType ==
                                                                  SortType
                                                                      .modifiedDate
                                                              ? Padding(
                                                                  padding:
                                                                      EdgeInsets
                                                                          .only(
                                                                              top: 4),
                                                                  child: Text(
                                                                    DateFormat(
                                                                            'yyyy-MM-dd HH:mm')
                                                                        .format(
                                                                            File(item['path']!).lastModifiedSync()),
                                                                    style:
                                                                        TextStyle(
                                                                      color: Colors
                                                                          .white60,
                                                                      fontSize:
                                                                          10,
                                                                    ),
                                                                  ),
                                                                )
                                                              : null,
                                                          onTap: () {
                                                            if (item['path'] !=
                                                                widget
                                                                    .openfile) {
                                                              setState(() {
                                                                getopenfile(item[
                                                                    'path']!);
                                                                _showPlaylist =
                                                                    false;
                                                              });
                                                            }
                                                          },
                                                          hoverColor: Colors
                                                              .white
                                                              .withOpacity(0.1),
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ),
                                              // 底部信息栏
                                              if (_playlist.length > 1)
                                                Container(
                                                  padding: EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 8),
                                                  decoration: BoxDecoration(
                                                    color: Colors.black38,
                                                    border: Border(
                                                      top: BorderSide(
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
                                                        '共 ${_playlist.length} 个文件',
                                                        style: TextStyle(
                                                          color: Colors.white70,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                      TextButton(
                                                        onPressed: () {
                                                          // 切换到下一个文件
                                                          int currentIndex = _playlist
                                                              .indexWhere((item) =>
                                                                  item[
                                                                      'path'] ==
                                                                  widget
                                                                      .openfile);
                                                          if (currentIndex !=
                                                                  -1 &&
                                                              _playlist.length >
                                                                  1) {
                                                            int nextIndex =
                                                                (currentIndex +
                                                                        1) %
                                                                    _playlist
                                                                        .length;
                                                            getopenfile(_playlist[
                                                                    nextIndex]
                                                                ['path']!);
                                                          }
                                                        },
                                                        child: Row(
                                                          children: [
                                                            Text(
                                                              '下一个',
                                                              style: TextStyle(
                                                                color: Colors
                                                                    .blue[300],
                                                                fontSize: 12,
                                                              ),
                                                            ),
                                                            SizedBox(width: 4),
                                                            Icon(
                                                              Icons.skip_next,
                                                              color: Colors
                                                                  .blue[300],
                                                              size: 16,
                                                            ),
                                                          ],
                                                        ),
                                                        style: ButtonStyle(
                                                          padding:
                                                              MaterialStateProperty
                                                                  .all(
                                                            EdgeInsets
                                                                .symmetric(
                                                                    horizontal:
                                                                        8,
                                                                    vertical:
                                                                        4),
                                                          ),
                                                          minimumSize:
                                                              MaterialStateProperty
                                                                  .all(Size(
                                                                      0, 0)),
                                                        ),
                                                      ),
                                                    ],
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
  final String? fontFamily;

  SubtitleBuilder({required this.subtitle, this.fontFamily});

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
          return _buildSubtitle(18.0, widget.fontFamily); // 默认字体大小
        } else if (snapshot.hasError) {
          return _buildErrorSubtitle();
        } else {
          final fontSize = snapshot.data ?? 18.0; // 如果获取失败，使用默认值
          return _buildSubtitle(fontSize, widget.fontFamily);
        }
      },
    );
  }

  Widget _buildSubtitle(double fontSize, String? fontFamily) {
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
              fontFamily: fontFamily,
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
              fontFamily: fontFamily,
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
