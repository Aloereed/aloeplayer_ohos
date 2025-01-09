/*
 * @Author: 
 * @Date: 2025-01-07 22:27:23
 * @LastEditors: Please set LastEditors
 * @LastEditTime: 2025-01-09 17:05:20
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
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock/wakelock.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:just_audio/just_audio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:share_plus/share_plus.dart';
import 'package:simple_gesture_detector/simple_gesture_detector.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;
import 'videolibrary.dart';
import 'audiolibrary.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:audio_session/audio_session.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:file_picker_ohos/file_picker_ohos.dart';

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
    final lightTheme = ThemeData(
      primarySwatch: Colors.blue, // 主色调为蓝色
      primaryColor: Colors.lightBlue[200], // 浅蓝色
      colorScheme: ColorScheme.light(
        primary: Colors.lightBlue[200]!, // 主色调
        secondary: Colors.blueAccent[100]!, // 次要色调
        surface: Colors.white, // 背景色
        background: Colors.lightBlue[50]!, // 背景色
      ),
      scaffoldBackgroundColor: Colors.lightBlue[50], // 页面背景色
      appBarTheme: AppBarTheme(
        color: Colors.lightBlue[200], // AppBar 背景色
        elevation: 0, // 去掉阴影
        iconTheme: IconThemeData(color: Colors.white), // AppBar 图标颜色
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ), // AppBar 文字样式
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: Colors.black87), // 正文文字颜色
        bodyMedium: TextStyle(color: Colors.black87),
        titleLarge:
            TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
      ),
      buttonTheme: ButtonThemeData(
        buttonColor: Colors.lightBlue[200], // 按钮背景色
        textTheme: ButtonTextTheme.primary, // 按钮文字颜色
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: Colors.lightBlue[200], // FloatingActionButton 背景色
      ),
    );

    // 自定义深色主题（可选）
    final darkTheme = ThemeData.dark();

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
  bool _isFullScreen = false;
  String _openfile = '';

  void _toggleFullScreen() {
    setState(() {
      _isFullScreen = !_isFullScreen;
    });

    if (_isFullScreen) {
      // 进入全屏时隐藏状态栏
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      // 退出全屏时显示状态栏
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  void _getopenfile(String openfile) {
    setState(() {
      _openfile = openfile;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          PlayerTab(
            key: ValueKey(_openfile), // 使用_openfile作为Key
            toggleFullScreen: _toggleFullScreen,
            isFullScreen: _isFullScreen,
            getopenfile: _getopenfile,
            openfile: _openfile, // 传递_openfile
          ),
          VideoLibraryTab(
            getopenfile: _getopenfile,
            changeTab: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
          ),
          AudioLibraryTab(
            getopenfile: _getopenfile,
            changeTab: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
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
              selectedItemColor: Theme.of(context).colorScheme.primary,
              unselectedItemColor: Theme.of(context).colorScheme.onSurface,
              type: BottomNavigationBarType.fixed,
            ),
    );
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

class PlayerTab extends StatefulWidget {
  final VoidCallback toggleFullScreen;
  final bool isFullScreen;
  final Function(String) getopenfile;
  final String openfile;

  PlayerTab(
      {Key? key, // 定义Key参数,
      required this.toggleFullScreen,
      required this.isFullScreen,
      required this.getopenfile,
      required this.openfile});

  @override
  _PlayerTabState createState() => _PlayerTabState();
}

class _PlayerTabState extends State<PlayerTab> {
  VideoPlayerController? _videoController;
  double _volume = 1.0;
  bool _isPlaying = false;
  bool _showControls = true;
  Timer? _hideTimer;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  double _playbackSpeed = 1.0;
  double _lastVolume = 1.0;
  bool _isMirrored = false;
  bool _isAudio = true;
  bool _showVolumeSlider = false;
  Timer? _volumeSliderTimer;
  Timer? _timer;
  bool _isLooping = false;
  double _previousPlaybackSpeed = 1.0; // 用于存储长按之前的播放速率
  double _swipeDistance = 0.0;
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

  @override
  void initState() {
    super.initState();
    _checkAndOpenUriFile(); // 添加文件检查逻辑
    if (widget.openfile.isNotEmpty) {
      _openUri(widget.openfile);
    }
    // 启动定时器，每秒执行一次
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      _checkAndOpenUriFile();
    });
    _setupAudioSession();
  }

  @override
  void didUpdateWidget(PlayerTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.openfile != oldWidget.openfile && widget.openfile.isNotEmpty) {
      _openUri(widget.openfile);
    }
  }

  Future<void> _checkAndOpenUriFile() async {
    try {
      final file = File('/data/storage/el2/base/openuri.txt'); // 构建文件路径

      if (await file.exists()) {
        final uri = await file.readAsString(); // 读取文件内容
        if (uri.isNotEmpty) {
          _openUri(uri); // 打开URI
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
          title: Text('输入 URL'),
          content: TextField(
            controller: urlController,
            decoration: InputDecoration(hintText: "请输入音视频 URL"),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _openUri(urlController.text); // 调用 _openUri 方法
              },
              child: Text('确认'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('取消'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openUri(String uri) async {
    if (uri.contains(':')) {
      if (_videoController != null) {
        _videoController?.dispose();
      }
      _videoController = VideoPlayerController.network(uri)
        ..initialize().then((_) {
          setState(() {
            _totalDuration = _videoController!.value.duration;
            _isAudio = _videoController == null || _videoController!.value.size.width == 0; // 判断是否为音频文件
          });
          _videoController?.play();
          _videoController?.addListener(_updatePlaybackState);
        })
        ..setLooping(_isLooping);
      widget.getopenfile(uri);
    } else {
      _videoController?.dispose();
      if (uri == "AloePlayer播放器") {
        // await audioHandler.setLoopingSilence();
        // await audioHandler.play();
        Wakelock.enable();
        return;
      }
      _videoController = VideoPlayerController.file(File(uri))
        ..initialize().then((_) {
          setState(() {
            _totalDuration = _videoController!.value.duration;
            _isAudio = _videoController == null || _videoController!.value.size.width == 0; // 判断是否为音频文件
          });
          _videoController?.play();
          _videoController?.addListener(_updatePlaybackState);
        })
        ..setLooping(_isLooping);
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
        '*',
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
        'ogg'
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
    _volumeSliderTimer?.cancel();
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

  void _seekVideo(Duration duration) {
    if (_videoController != null) {
      final currentPosition = _videoController!.value.position;
      final newPosition = currentPosition + duration;
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
    return Scaffold(
        appBar: widget.isFullScreen
            ? null
            : AppBar(
                title: widget.openfile == ''
                    ? Text('AloePlayer播放器')
                    : Text('当前文件：' + widget.openfile),
                actions: [
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
          onTap: () {
            setState(() {
              _showControls = !_showControls;
              _resetHideTimer();
            });
          },
          onLongPress: () {
            if (!_isAudio) {
              // 记录当前的播放速率
              _previousPlaybackSpeed = _playbackSpeed; // 假设有一个方法可以获取当前的播放速率

              // 使用 fluttertoast 显示消息
              // 背景半透明
              Fluttertoast.showToast(
                msg: '长按3倍速播放',
                toastLength: Toast.LENGTH_SHORT,
                gravity: ToastGravity.CENTER,
                timeInSecForIosWeb: 1,
                backgroundColor: Colors.grey,
                textColor: Colors.white,
                fontSize: 16.0,
              );

              _setPlaybackSpeed(3.0); // 长按三倍速播放
            }
          },
          onLongPressEnd: (_) {
            if (!_isAudio) {
              _setPlaybackSpeed(_previousPlaybackSpeed); // 松开恢复到长按之前的播放速率
            }
          },
          onHorizontalDragUpdate: (details) {
            // 计算滑动的距离
            _swipeDistance += details.delta.dx;

            // 根据滑动距离计算快进或快退的时间
            final double sensitivity = 10.0; // 灵敏度，可以根据需要调整
            final Duration seekDuration = Duration(
                milliseconds: (_swipeDistance / sensitivity).round() * 1000);

            if (seekDuration.inMilliseconds != 0) {
              _seekVideo(seekDuration);
              _swipeDistance = 0.0; // 重置滑动距离
            }
          },
          onHorizontalDragEnd: (details) {
            // 滑动结束时重置滑动距离
            _swipeDistance = 0.0;
          },
          onDoubleTapDown: (details) {
            // Get the width of the screen
            final double screenWidth = MediaQuery.of(context).size.width;
            // Determine if the double tap is on the left or right half
            if (details.globalPosition.dx < screenWidth / 2) {
              // Left half of the screen: rewind 10 seconds
              Fluttertoast.showToast(
                  msg: '快退10秒',
                  toastLength: Toast.LENGTH_SHORT,
                  gravity: ToastGravity.CENTER,
                  timeInSecForIosWeb: 1,
                  backgroundColor: Colors.red,
                  textColor: Colors.white,
                  fontSize: 16.0);
              _rewind10Seconds();
            } else {
              // Right half of the screen: fast forward 10 seconds
              Fluttertoast.showToast(
                  msg: '快进10秒',
                  toastLength: Toast.LENGTH_SHORT,
                  gravity: ToastGravity.CENTER,
                  timeInSecForIosWeb: 1,
                  backgroundColor: Colors.red,
                  textColor: Colors.white,
                  fontSize: 16.0);
              _fastForward10Seconds();
            }
          },
          onVerticalDragUpdate: (details) {
            if (!_isAudio) {
              // 计算滑动的距离
              double delta = details.primaryDelta ?? 0;

              // 根据滑动方向调整音量
              setState(() {
                if (delta < 0) {
                  // 上滑增加音量
                  _volume = (_volume + 0.01).clamp(0.0, 1.0);
                } else if (delta > 0) {
                  // 下滑减少音量
                  _volume = (_volume - 0.01).clamp(0.0, 1.0);
                }
                _videoController?.setVolume(_volume);
              });
              _showVolumeSlider = true;
              _startVolumeSliderTimer();
              // 显示音量变化提示
              Fluttertoast.showToast(
                msg: '音量: ${(_volume * 100).toStringAsFixed(0)}%',
                toastLength: Toast.LENGTH_SHORT,
                gravity: ToastGravity.CENTER,
                timeInSecForIosWeb: 1,
                backgroundColor: Colors.black.withOpacity(0.7),
                textColor: Colors.white,
                fontSize: 16.0,
              );
            }
          },
          child: Stack(
            children: [
              if (_videoController != null &&
                  _videoController!.value.isInitialized)
                GestureDetector(
                  // onLongPress: () {
                  //   if (!_isAudio) {
                  //     _setPlaybackSpeed(3.0); // 长按三倍速播放
                  //   }
                  // },
                  // onLongPressEnd: (_) {
                  //   if (!_isAudio) {
                  //     _setPlaybackSpeed(1.0); // 松开恢复原速
                  //   }
                  // },
                  child: Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // 视频播放器
                        Visibility(
                          visible: _videoController != null &&
                              _videoController!.value.isInitialized &&
                              !_isAudio,
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: SizedBox(
                              width: _videoController!.value.size.width,
                              height: _videoController!.value.size.height,
                              child: Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.identity()
                                  ..scale(
                                      _isMirrored ? -1.0 : 1.0, 1.0), // 水平翻转
                                child: VideoPlayer(_videoController!),
                              ),
                            ),
                          ),
                        ),
                        // 当没有播放或 _isAudio 为 true 时显示 logo
                        Visibility(
                          visible: _videoController == null ||
                              !_videoController!.value.isInitialized ||
                              _isAudio,
                          child: Image.asset('Assets/icon.png'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_showControls || _isAudio)
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

class SettingsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('设置'),
      ),
      body: ListView(
        children: [
          // 主题设置部分
          Column(
            children: [
              RadioListTile<ThemeMode>(
                title: const Text('亮色模式'),
                value: ThemeMode.light,
                groupValue: themeProvider.themeMode,
                onChanged: (ThemeMode? value) {
                  if (value != null) {
                    themeProvider.setThemeMode(value);
                  }
                },
              ),
              RadioListTile<ThemeMode>(
                title: const Text('暗色模式'),
                value: ThemeMode.dark,
                groupValue: themeProvider.themeMode,
                onChanged: (ThemeMode? value) {
                  if (value != null) {
                    themeProvider.setThemeMode(value);
                  }
                },
              ),
              RadioListTile<ThemeMode>(
                title: const Text('跟随系统'),
                value: ThemeMode.system,
                groupValue: themeProvider.themeMode,
                onChanged: (ThemeMode? value) {
                  if (value != null) {
                    themeProvider.setThemeMode(value);
                  }
                },
              ),
            ],
          ),
          Divider(), // 分割线

          // 关于此应用程序部分
          ListTile(
            title: Text('关于此应用程序'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 8),
                Text('AloePlayer'),
                SizedBox(height: 4),
                Text('版本号: 0.9.2。 本版本修复大文件打开支持。'),
                SizedBox(height: 4),
                Text('尽享视听盛宴'),
                SizedBox(height: 4),
                GestureDetector(
                  onTap: () async {
                    await launchUrl(
                      Uri.parse('https://ohos.aloereed.com'),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                  child: Text(
                    '官网: https://ohos.aloereed.com',
                    style: TextStyle(
                      color: Colors.blue,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                SizedBox(height: 16),
                Text('手势说明:'),
                SizedBox(height: 8),
                Text('1. 长按: 三倍速播放'),
                SizedBox(height: 4),
                Text('2. 双击播放界面左侧或右侧: 快退、快进10秒，或者使用左右滑动来快退、快进'),
                SizedBox(height: 4),
                Text('3. 上下滑动: 增减音量'),
                SizedBox(height: 4),
                Text('4. 添加媒体进入音频库或视频库需要时间。较大的文件不建议加入媒体库。如果长时间没反应可以再次尝试。'),
                SizedBox(height: 4),
                Text('5. 长按媒体控制的音量按钮可以切换静音。'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;

  ThemeProvider() {
    _loadThemeMode();
  }

  ThemeMode get themeMode => _themeMode;

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeMode', mode.index);
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt('themeMode') ?? ThemeMode.system.index;
    _themeMode = ThemeMode.values[themeIndex];
    notifyListeners();
  }
}
