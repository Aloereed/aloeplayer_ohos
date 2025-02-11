/*
 * @Author: 
 * @Date: 2025-01-07 22:27:23
 * @LastEditors: Please set LastEditors
 * @LastEditTime: 2025-02-11 17:18:30
 * @Description: file content
 */
/*
 * @Author: 
 * @Date: 2025-01-07 17:00:15
 * @LastEditors: Please set LastEditors
 * @LastEditTime: 2025-01-07 22:37:09
 * @Description: file content
 * 
 */
import 'dart:ui';

import 'package:aloeplayer/privacy_policy.dart';
import 'package:xml/xml.dart' as xml;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock/wakelock.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:just_audio/just_audio.dart';
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
import 'package:just_audio/just_audio.dart';
import 'package:file_picker_ohos/file_picker_ohos.dart';
import 'settings.dart';
import 'theme_provider.dart';
import 'dart:typed_data';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'volumeview.dart';
import 'package:aloeplayer/chewie-1.8.5/lib/src/ffmpegview.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';

late MyAudioHandler audioHandler;
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  audioHandler = await AudioService.init(
    builder: () => MyAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.aloereed.aloeplayer',
      androidNotificationChannelName: '后台音频播放',
    ),
  );
  // 初始化音频会话
  final session = await AudioSession.instance;
  await session.configure(AudioSessionConfiguration.music());
  runApp(
    ChangeNotifierProvider(
      create: (context) => ThemeProvider(),
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    Wakelock.enable();

    // 自定义浅蓝色主题
    // final lightTheme = ThemeData(
    //   primarySwatch: Colors.blue, // 主色调为蓝色
    //   primaryColor: Colors.lightBlue[200], // 浅蓝色
    //   colorScheme: ColorScheme.light(
    //     primary: Colors.lightBlue[200]!, // 主色调
    //     secondary: Colors.blueAccent[100]!, // 次要色调
    //     surface: Colors.white, // 背景色
    //     background: Colors.lightBlue[50]!, // 背景色
    //   ),
    //   scaffoldBackgroundColor: Colors.lightBlue[50], // 页面背景色
    //   appBarTheme: AppBarTheme(
    //     color: Colors.lightBlue[200], // AppBar 背景色
    //     elevation: 0, // 去掉阴影
    //     iconTheme: IconThemeData(color: Colors.white), // AppBar 图标颜色
    //     titleTextStyle: TextStyle(
    //       color: Colors.white,
    //       fontSize: 20,
    //       fontWeight: FontWeight.bold,
    //     ), // AppBar 文字样式
    //   ),
    //   textTheme: TextTheme(
    //     bodyLarge: TextStyle(color: Colors.black87), // 正文文字颜色
    //     bodyMedium: TextStyle(color: Colors.black87),
    //     titleLarge:
    //         TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
    //   ),
    //   buttonTheme: ButtonThemeData(
    //     buttonColor: Colors.lightBlue[200], // 按钮背景色
    //     textTheme: ButtonTextTheme.primary, // 按钮文字颜色
    //   ),
    //   floatingActionButtonTheme: FloatingActionButtonThemeData(
    //     backgroundColor: Colors.lightBlue[200], // FloatingActionButton 背景色
    //   ),
    // );
    final lightTheme = ThemeData(
      primarySwatch: Colors.grey, // 主色调为灰色
      primaryColor: const Color(0xFFF5F5F5), // 浅灰色，与背景保持一致
      colorScheme: ColorScheme.light(
        primary: const Color(0xFFF5F5F5), // 主色调
        secondary: const Color(0xFFCCCCCC), // 次要色调为浅灰色
        surface: Colors.white, // 卡片和控件的背景色
        background: const Color(0xFFF2F3F5), // 页面背景色
      ),
      scaffoldBackgroundColor: const Color(0xFFF2F3F5), // 整体背景色
      appBarTheme: AppBarTheme(
        color: const Color(0xFFF2F3F5), // AppBar 背景色
        elevation: 0, // 去掉阴影
        iconTheme: const IconThemeData(color: Colors.black54), // AppBar 图标颜色
        titleTextStyle: const TextStyle(
          color: Colors.black87,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ), // AppBar 标题样式
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Colors.black87), // 正文文字颜色
        bodyMedium: TextStyle(color: Colors.black54), // 辅助文字颜色
        titleLarge: TextStyle(
            color: Colors.black87, fontWeight: FontWeight.bold), // 标题文字颜色
      ),
      buttonTheme: ButtonThemeData(
        buttonColor: const Color(0xFFCCCCCC), // 按钮背景色为浅灰色
        textTheme: ButtonTextTheme.primary, // 按钮文字颜色
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Color(0xFFCCCCCC), // FloatingActionButton 背景色为浅灰色
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFFF2F3F5), // 底部导航栏背景色
        selectedItemColor: Colors.lightBlue, // 选中项的颜色
        unselectedItemColor: Color(0xFF919294), // 未选中项的颜色
        elevation: 0, // 去掉分割线
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          backgroundColor: MaterialStateProperty.all(Color(0xFFE7E8EA)), // 背景色
          shape: MaterialStateProperty.all(
            CircleBorder(), // 圆形
          ),
          iconColor: MaterialStateProperty.all(Colors.black), // 图标颜色
        ),
      ),
      iconTheme: IconThemeData(color: Colors.black), // 默认图标颜色
    );

    // 自定义深色主题（可选）
    final darkTheme = ThemeData.dark().copyWith(
      scaffoldBackgroundColor: Colors.black, // 背景颜色设置为纯黑
      primaryColor: Colors.lightBlue, // 主要颜色设置为红色，用于高亮
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Colors.white), // 文本颜色为白色或浅灰色
        bodyMedium: TextStyle(color: Colors.grey), // 辅助文本颜色为灰色
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.black, // 底部导航栏背景颜色为纯黑
        selectedItemColor: Colors.lightBlue, // 选中项的颜色为红色
        unselectedItemColor: Color(0xFF818181), // 未选中项的颜色为灰色
        elevation: 0, // 去掉分割线
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.black, // AppBar 背景颜色为纯黑
        iconTheme: IconThemeData(color: Colors.grey), // 图标为灰色
        elevation: 0, // 去掉阴影
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ), // 标题为白色
      ),
      iconTheme: const IconThemeData(
        color: Colors.white, // 默认图标颜色为白色
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          backgroundColor: MaterialStateProperty.all(Color(0xFF222222)), // 背景色
          shape: MaterialStateProperty.all(
            CircleBorder(), // 圆形
          ),
          iconColor: MaterialStateProperty.all(Colors.white), // 图标颜色
        ),
      ),
    );

    return MaterialApp(
      theme: lightTheme, // 使用自定义的浅蓝色主题
      darkTheme: darkTheme,
      themeMode: themeProvider.themeMode,
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  final PageController _pageController = PageController();
  int videoHeight = 0;
  int videoWidth = 0;
  bool _isFullScreen = false;
  String _openfile = '';
  bool _isPolicyAccepted = false;
  @override
  void initState() {
    super.initState();
    _checkPrivacyPolicyStatus();
  }

  void setHomeWH(int width, int height) {
    setState(() {
      videoHeight = height;
      videoWidth = width;
    });
  }

  void _toggleFullScreen() {
    setState(() {
      _isFullScreen = !_isFullScreen;
    });

    if (_isFullScreen) {
      // 进入全屏时隐藏状态栏
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      final _videoWidth = videoWidth;
      final _videoHeight = videoHeight;

      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);

      // if (widget.controller.systemOverlaysOnEnterFullScreen != null) {
      //   /// Optional user preferred settings
      //   SystemChrome.setEnabledSystemUIMode(
      //     SystemUiMode.manual,
      //     overlays: widget.controller.systemOverlaysOnEnterFullScreen,
      //   );
      // } else {
      //   /// Default behavior
      //   SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
      // }

      final isLandscapeVideo = videoWidth > videoHeight;
      final isPortraitVideo = videoWidth < videoHeight;

      /// Default behavior
      /// Video w > h means we force landscape
      if (isLandscapeVideo) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }

      /// Video h > w means we force portrait
      else if (isPortraitVideo) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      }

      /// Otherwise if h == w (square video)
      else {
        SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      }
    } else {
      // 退出全屏时显示状态栏
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
  }

  Future<bool> _onWillPop() async {
    if (_isFullScreen) {
      _toggleFullScreen();
      return false; // 阻止退出程序
    }
    return true; // 允许退出程序
  }

  void _getopenfile(String openfile) {
    setState(() {
      _openfile = openfile;
    });
  }

  Future<void> _checkPrivacyPolicyStatus() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool? isAccepted = prefs.getBool('privacy_policy_accepted');

    // 如果尚未接受隐私政策，显示对话框
    if (isAccepted == null || !isAccepted) {
      Future.delayed(Duration.zero, () {
        _showPrivacyPolicyDialog();
      });
    } else {
      setState(() {
        _isPolicyAccepted = true;
      });
      // 创建实例
      final _platform =
          const MethodChannel('samples.flutter.dev/downloadplugin');
// 调用方法 getBatteryLevel
      final result =
          await _platform.invokeMethod<String>('getDownloadPermission');
      final result2 = await _platform.invokeMethod<String>('startBgTask');
    }
  }

  void _showPrivacyPolicyDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // 禁止点击外部关闭对话框
      builder: (BuildContext context) {
        return PrivacyPolicyDialog(
          onAccept: () async {
            SharedPreferences prefs = await SharedPreferences.getInstance();
            await prefs.setBool('privacy_policy_accepted', true);
            setState(() {
              _isPolicyAccepted = true;
            });
            Navigator.of(context).pop(); // 关闭对话框
            // 创建实例
            final _platform =
                const MethodChannel('samples.flutter.dev/downloadplugin');
// 调用方法 getBatteryLevel
            final result =
                await _platform.invokeMethod<String>('getDownloadPermission');
          },
          onDecline: () {
            // 用户拒绝，退出应用
            Navigator.of(context).pop(); // 关闭对话框
            Future.delayed(Duration(milliseconds: 200), () {
              // 退出应用
              // SystemNavigator.pop();
              exit(0);
            });
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
        onWillPop: _onWillPop,
        child: Scaffold(
          body: PageView(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            children: [
              PlayerTab(
                key: ValueKey(_openfile),
                toggleFullScreen: _toggleFullScreen,
                isFullScreen: _isFullScreen,
                getopenfile: _getopenfile,
                openfile: _openfile,
                setHomeWH: setHomeWH,
              ),
              VideoLibraryTab(
                getopenfile: _getopenfile,
                changeTab: (index) {
                  setState(() {
                    _selectedIndex = index;
                  });
                  _pageController.animateToPage(
                    index,
                    duration: Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
                toggleFullScreen: () {},
              ),
              AudioLibraryTab(
                getopenfile: _getopenfile,
                changeTab: (index) {
                  setState(() {
                    _selectedIndex = index;
                  });
                  _pageController.animateToPage(
                    index,
                    duration: Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
                toggleFullScreen: () {},
              ),
              SettingsTab(),
            ],
          ),
          bottomNavigationBar: _isFullScreen
              ? null
              : BottomNavigationBar(
                  currentIndex: _selectedIndex,
                  onTap: (index) {
                    setState(() {
                      _selectedIndex = index;
                    });
                    _pageController.animateToPage(
                      index,
                      duration: Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                  items: [
                    BottomNavigationBarItem(
                      icon: Icon(Icons.play_arrow),
                      label: '播放器',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.video_library),
                      label: '视频库',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.library_music),
                      label: '音频库',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.settings),
                      label: '设置',
                    ),
                  ],
                  type: BottomNavigationBarType.fixed,
                ),
        ));
  }
}

class MyAudioHandler extends BaseAudioHandler {
  final _player = AudioPlayer();

  MyAudioHandler() {
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.pause,
        MediaControl.play,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.seek,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _player.currentIndex,
    );
  }

  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();
  Future<void> stop() => _player.stop();

  Future<void> setAudioSource(String url) async {
    await _player.setUrl(url);
  }

  Future<void> setLoopingSilence() async {
    // 加载 assets 中的静音音频文件
    await _player.setAudioSource(AudioSource.asset('Assets/10s_silence.wav'));
    // 设置循环模式为循环播放
    _player.setLoopMode(LoopMode.one);
  }
}

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
  final bool isFullScreen;
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
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
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
  bool _isLooping = false;
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
  bool _useFfmpegForPlay = false;
  bool _initVpWhenFfmpeg = false;
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
      _openUri(event); // 打开URI
      setState(() {
        widget.openfile = event;
      });
    }
  }

  void _onErrorOpenuri(Object error) {
    print('Error receiving event: $error');
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
    if(_videoController == null)
      return;
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
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('选择音轨'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                  const Text(
                    '选择非音频轨道可能会导致错误。0一般为视频轨。然后是音频轨。其他轨道可能是字幕轨道。',
                    style: TextStyle(color: Colors.red),
                  ),
                ListBody(
                  children: audioTracks.map((track) {
                    return ListTile(
                      title: Text(track),
                      onTap: () {
                        Navigator.of(context).pop(track); // 返回选中的音轨
                      },
                    );
                  }).toList(),
                ),
              ],
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
          widget.getopenfile(uri);
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

  Future<void> _initializeChewieController() async {
    _volumeController = _volumeExample?.controller;

    _chewieController = ChewieController(
      ffmpeg: _useFfmpegForPlay,
      sendToFfmpegPlayer: _ffmpegExample,
      videoPlayerController: _videoController!,
      allowMuting: !_useFfmpegForPlay,
      autoPlay: true,
      looping: _isLooping,
      showControls: _showControls,
      allowFullScreen: true,
      zoomAndPan: true,
      customToggleFullScreen: widget.toggleFullScreen,
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
          OptionItem(
            onTap: () => _openAudioTrackDialog(),
            iconData: Icons.volume_up_sharp,
            title: '选择音频轨道（非FFMpeg）',
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
                _isLooping = !_isLooping;
                _videoController?.setLooping(_isLooping);
              });
            },
            iconData: _isLooping ? Icons.repeat_one : Icons.repeat,
            title: _isLooping ? '取消单曲循环' : '单曲循环',
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
      toggleFullScreen: this.widget.toggleFullScreen,
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
          if (_currentSubtitleIndex == -1 && _subtitles.isNotEmpty) {
            _currentSubtitleIndex = 0;
            _chewieController!.setSubtitle(_subtitles[0].subtitles!);
          }

          // 更新 UI
          setState(() {});

          // 文件加载成功，退出循环
          return;
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

  Future<void> _openUri(String uri, {bool wantFirst = false}) async {
    // 如果uri以"/Photos"开头，则在uri前面加上"file://media"
    _subtitles.clear();
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
        })
        ..setLooping(_isLooping);
      _useFfmpegForPlay = await _settingsService.getUseFfmpegForPlay();
      if (_useFfmpegForPlay) {
        if (_ffmpegExample == null) {
          _ffmpegExample = FfmpegExample(
              initUri: convertUriToPath(widget.openfile),
              toggleFullScreen: this.widget.toggleFullScreen);
        }
        _ffmpegExample?.controller?.sendMessageToOhosView(
            "newPlay", convertUriToPath(widget.openfile));
      }

      widget.getopenfile(uri);
    } else {
      _videoController?.dispose();
      if (uri == "AloePlayer播放器") {
        // await audioHandler.setLoopingSilence();
        // await audioHandler.play();
        Wakelock.enable();
        return;
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
        })
        ..setLooping(_isLooping);
      _useFfmpegForPlay = await _settingsService.getUseFfmpegForPlay();
      if (_useFfmpegForPlay) {
        if (_ffmpegExample == null) {
          _ffmpegExample = FfmpegExample(
              initUri: convertUriToPath(widget.openfile),
              toggleFullScreen: this.widget.toggleFullScreen);
        }
        _ffmpegExample?.controller?.sendMessageToOhosView(
            "newPlay", convertUriToPath(widget.openfile));
      }
      String fileName = uri.split('/').last;
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
  //     widget.getopenfile(file.path);
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
      widget.getopenfile(file.path!);
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
        subtitleData.subtitles = await ass2srt(fileContent);
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
      if (_currentSubtitleIndex == -1) {
        _currentSubtitleIndex = _subtitles.length - 1;
        _chewieController!.setSubtitle(subtitleData.subtitles!);
      }

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
      builder: (context) {
        return AlertDialog(
          title: Text('选择字幕轨道'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: _subtitles
                .asMap()
                .entries
                .map(
                  (entry) => ListTile(
                    title: Text(entry.value.name),
                    onTap: () => Navigator.pop(context, entry.key),
                  ),
                )
                .toList(),
          ),
        );
      },
    );

    // 如果用户选择了字幕
    if (selectedIndex != null) {
      _currentSubtitleIndex = selectedIndex;
      _chewieController!.setSubtitle(_subtitles[selectedIndex].subtitles!);
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
        appBar: widget.isFullScreen
            ? null
            : AppBar(
                title: widget.openfile == ''
                    ? Text('AloePlayer播放器')
                    : Text('当前文件：' + widget.openfile),
                actions: [
                  IconButton(
                    icon: Icon(Icons.open_in_browser),
                    onPressed: _openFile,
                  ),
                  IconButton(
                    icon: Icon(Icons.link),
                    onPressed: () => _showUrlDialog(context),
                  ),
                  IconButton(
                      onPressed: () => _shareFileOrText(context),
                      icon: Icon(Icons.share)),
                  // 主题切换按钮
                  PopupMenuButton<ThemeMode>(
                    icon: Icon(Icons.brightness_medium), // 主题切换图标
                    onSelected: (ThemeMode mode) {
                      // 切换主题
                      Provider.of<ThemeProvider>(context, listen: false)
                          .setThemeMode(mode);
                    },
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<ThemeMode>>[
                      // 亮色主题
                      PopupMenuItem<ThemeMode>(
                        value: ThemeMode.light,
                        child: Row(
                          children: [
                            Icon(Icons.brightness_high, color: Colors.orange),
                            SizedBox(width: 8),
                            Text('亮色主题'),
                          ],
                        ),
                      ),
                      // 暗色主题
                      PopupMenuItem<ThemeMode>(
                        value: ThemeMode.dark,
                        child: Row(
                          children: [
                            Icon(Icons.brightness_2, color: Colors.blue),
                            SizedBox(width: 8),
                            Text('暗色主题'),
                          ],
                        ),
                      ),
                      // 跟随系统
                      PopupMenuItem<ThemeMode>(
                        value: ThemeMode.system,
                        child: Row(
                          children: [
                            Icon(Icons.settings, color: Colors.grey),
                            SizedBox(width: 8),
                            Text('跟随系统'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
        body: GestureDetector(
          // onTap: () {
          //   setState(() {
          //     _showControls = !_showControls;
          //     _resetHideTimer();
          //   });
          // },
          // onScaleStart: (details) {
          //   // 开始缩放手势时，记录当前缩放比例
          //   _previousScale = _scale;
          // },
          // onScaleUpdate: (details) {
          //   setState(() {
          //     // 更新缩放比例
          //     _scale = _previousScale * details.scale;

          //     // 如果缩放比例超过一定的阈值，则执行全屏切换
          //     if (_scale > 1.5) {
          //       widget.toggleFullScreen();
          //       _scale = 1.0; // 重置缩放比例
          //       _previousScale = 1.0;
          //     } else if (_scale < 0.5) {
          //       widget.toggleFullScreen();
          //       _scale = 1.0; // 重置缩放比例
          //       _previousScale = 1.0;
          //     }
          //   });
          // },
          // onScaleEnd: (details) {
          //   // 缩放结束，重置缩放比例
          //   _previousScale = 1.0;
          // },
          // onLongPress: () {
          //   if (!_isAudio) {
          //     // 记录当前的播放速率
          //     _previousPlaybackSpeed = _playbackSpeed; // 假设有一个方法可以获取当前的播放速率

          //     // 使用 fluttertoast 显示消息
          //     // 背景半透明
          //     Fluttertoast.showToast(
          //       msg: '长按3倍速播放',
          //       toastLength: Toast.LENGTH_SHORT,
          //       gravity: ToastGravity.CENTER,
          //       timeInSecForIosWeb: 1,
          //       backgroundColor: Colors.grey,
          //       textColor: Colors.white,
          //       fontSize: 16.0,
          //     );

          //     _setPlaybackSpeed(3.0); // 长按三倍速播放
          //   }
          // },
          // onLongPressEnd: (_) {
          //   if (!_isAudio) {
          //     _setPlaybackSpeed(_previousPlaybackSpeed); // 松开恢复到长按之前的播放速率
          //   }
          // },
          // onHorizontalDragUpdate: (details) {
          //   // 计算滑动的距离
          //   _swipeDistance += details.delta.dx;

          //   // 根据滑动距离计算快进或快退的时间
          //   final double sensitivity = 10.0; // 灵敏度，可以根据需要调整
          //   final Duration seekDuration = Duration(
          //       milliseconds: (_swipeDistance / sensitivity).round() * 1000);

          //   if (seekDuration.inMilliseconds != 0) {
          //     _seekVideo(seekDuration);
          //     _swipeDistance = 0.0; // 重置滑动距离
          //   }
          // },
          // onHorizontalDragEnd: (details) {
          //   // 滑动结束时重置滑动距离
          //   _swipeDistance = 0.0;
          // },
          // onDoubleTapDown: (details) {
          //   // Get the width of the screen
          //   final double screenWidth = MediaQuery.of(context).size.width;

          //   // Define a range for the middle part of the screen
          //   final double middleRangeStart = screenWidth * 0.4;
          //   final double middleRangeEnd = screenWidth * 0.6;

          //   // Determine the position of the double tap
          //   if (details.globalPosition.dx < middleRangeStart) {
          //     // Left part of the screen: rewind 10 seconds
          //     Fluttertoast.showToast(
          //       msg: '快退10秒',
          //       toastLength: Toast.LENGTH_SHORT,
          //       gravity: ToastGravity.CENTER,
          //       timeInSecForIosWeb: 1,
          //       backgroundColor: Colors.red,
          //       textColor: Colors.white,
          //       fontSize: 16.0,
          //     );
          //     _rewind10Seconds();
          //   } else if (details.globalPosition.dx > middleRangeEnd) {
          //     // Right part of the screen: fast forward 10 seconds
          //     Fluttertoast.showToast(
          //       msg: '快进10秒',
          //       toastLength: Toast.LENGTH_SHORT,
          //       gravity: ToastGravity.CENTER,
          //       timeInSecForIosWeb: 1,
          //       backgroundColor: Colors.red,
          //       textColor: Colors.white,
          //       fontSize: 16.0,
          //     );
          //     _fastForward10Seconds();
          //   } else {
          //     // Middle part of the screen: toggle fullscreen
          //     Fluttertoast.showToast(
          //       msg: '切换全屏模式',
          //       toastLength: Toast.LENGTH_SHORT,
          //       gravity: ToastGravity.CENTER,
          //       timeInSecForIosWeb: 1,
          //       backgroundColor: Colors.blue,
          //       textColor: Colors.white,
          //       fontSize: 16.0,
          //     );
          //     widget.toggleFullScreen();
          //   }
          // },
          // onVerticalDragUpdate: (details) {
          //   if (true) {
          //     // 计算滑动的距离
          //     double delta = details.primaryDelta ?? 0;

          //     // 根据滑动方向调整音量
          //     setState(() {
          //       if (delta < 0) {
          //         // 上滑增加音量
          //         _volume = (_volume + 0.01).clamp(0.0, 1.0);
          //       } else if (delta > 0) {
          //         // 下滑减少音量
          //         _volume = (_volume - 0.01).clamp(0.0, 1.0);
          //       }
          //       _videoController?.setVolume(_volume);
          //     });
          //     _showVolumeSlider = true;
          //     _startVolumeSliderTimer();
          //     // 显示音量变化提示
          //     Fluttertoast.showToast(
          //       msg: '音量: ${(_volume * 100).toStringAsFixed(0)}%',
          //       toastLength: Toast.LENGTH_SHORT,
          //       gravity: ToastGravity.CENTER,
          //       timeInSecForIosWeb: 1,
          //       backgroundColor: Colors.black.withOpacity(0.7),
          //       textColor: Colors.white,
          //       fontSize: 16.0,
          //     );
          //   }
          // },
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
                    Visibility(
                      visible: (_chewieController == null ||
                              _videoController == null ||
                              !_videoController!.value.isInitialized ||
                              _isAudio) &&
                          coverData != null,
                      child: InkWell(
                        onTap: _openFile, // 点击时执行 _openFile 方法
                        child: AnimatedBuilder(
                          animation: _animeController!,
                          builder: (context, child) {
                            return Transform.rotate(
                              angle: _animeController!.value *
                                  2 *
                                  3.14159, // 360度旋转
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  // 圆形图片
                                  ClipOval(
                                    child: Image.memory(
                                      coverData!,
                                      width: 256,
                                      height: 256,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  // 光碟效果：叠加一个半透明的圆形渐变
                                  Container(
                                    width: 256,
                                    height: 256,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: RadialGradient(
                                        colors: [
                                          Colors.transparent,
                                          Colors.white.withOpacity(0.3),
                                        ],
                                        stops: [0.7, 1.0],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
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
              if (_useFfmpegForPlay && (_ffmpegExample != null))
                Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..scale(_isMirrored ? -1.0 : 1.0, 1.0), // 水平翻转
                    child: this._ffmpegExample!),
              if (_chewieController != null &&
                  _videoController != null &&
                  _videoController!.value.isInitialized)

                // 视频播放器
                Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..scale(_isMirrored ? -1.0 : 1.0, 1.0), // 水平翻转
                    child: Chewie(controller: _chewieController!)),
              if (false && (_showControls || _isAudio))
                Positioned(
                  bottom: 20,
                  left: 20,
                  right: 20,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          // 已播放时长/总时长
                          Text(
                            '${_formatDuration(_currentPosition)}/${_formatDuration(_totalDuration)}',
                            style: TextStyle(
                              color:
                                  Theme.of(context).textTheme.bodyLarge?.color,
                            ),
                          ),
                          Expanded(
                            child: Slider(
                              value: _currentPosition.inSeconds.toDouble(),
                              min: 0,
                              max: _totalDuration.inSeconds.toDouble(),
                              onChanged: (value) {
                                setState(() {
                                  _currentPosition =
                                      Duration(seconds: value.toInt());
                                });
                                _videoController?.seekTo(_currentPosition);
                              },
                            ),
                          ),
                          // 音量按钮和悬浮音量控制条
                          Stack(
                            children: [
                              GestureDetector(
                                onLongPress: () {
                                  // 如果音量不为0设置静音
                                  if (_volume != 0) {
                                    setState(() {
                                      _lastVolume = _volume;
                                      _volume = 0;
                                      _videoController?.setVolume(_volume);
                                    });
                                  } else {
                                    // 如果音量为0恢复上次音量
                                    setState(() {
                                      _volume = _lastVolume;
                                      _videoController?.setVolume(_volume);
                                    });
                                  }
                                },
                                child: IconButton(
                                  icon: Icon(
                                    _volume == 0
                                        ? Icons.volume_off
                                        : Icons.volume_up,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _showVolumeSlider = !_showVolumeSlider;
                                    });
                                    _startVolumeSliderTimer();
                                  },
                                ),
                              )
                            ],
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: Icon(Icons.open_in_browser),
                            onPressed: _openFile,
                          ),
                          IconButton(
                            icon: Icon(Icons.link),
                            onPressed: () => _showUrlDialog(context),
                          ),
                          IconButton(
                            icon: Icon(
                                _isPlaying ? Icons.pause : Icons.play_arrow),
                            onPressed: _togglePlayPause,
                          ),
                          IconButton(
                            icon: Icon(_isMirrored
                                ? Icons.flip
                                : Icons.flip_camera_android),
                            onPressed: () {
                              setState(() {
                                _isMirrored = !_isMirrored; // 切换镜像状态
                              });
                            },
                          ),
                          IconButton(
                            icon: Icon(widget.isFullScreen
                                ? Icons.fullscreen_exit
                                : Icons.fullscreen),
                            onPressed: widget.toggleFullScreen,
                          ),
                          PopupMenuButton<double>(
                            icon: Icon(Icons.speed),
                            itemBuilder: (context) => [
                              PopupMenuItem(value: 0.5, child: Text('0.5x')),
                              PopupMenuItem(value: 0.75, child: Text('0.75x')),
                              PopupMenuItem(value: 1.0, child: Text('1.0x')),
                              PopupMenuItem(value: 1.25, child: Text('1.25x')),
                              PopupMenuItem(value: 1.5, child: Text('1.5x')),
                              PopupMenuItem(value: 1.75, child: Text('1.75x')),
                              PopupMenuItem(value: 2.0, child: Text('2.0x')),
                              PopupMenuItem(value: 3.0, child: Text('3.0x')),
                            ],
                            onSelected: _setPlaybackSpeed,
                          ),
                          IconButton(
                            icon: Icon(
                                _isLooping ? Icons.repeat_one : Icons.repeat),
                            onPressed: () {
                              setState(() {
                                _isLooping = !_isLooping;
                                _videoController?.setLooping(_isLooping);
                              });
                            },
                          ),

                          // 静音切换按钮
                        ],
                      ),
                    ],
                  ),
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
        ));
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

  SubtitleData({
    required this.name,
    required this.content,
    required this.extension,
    this.subtitles,
  });
}
