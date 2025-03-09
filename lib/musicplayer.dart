import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:rxdart/rxdart.dart';
import 'settings.dart';
import 'audio_player_service.dart';
// enum LoopMode { off, all, one }

class BlurredIconButton extends StatelessWidget {
  final IconData icon; // 图标
  final VoidCallback onPressed; // 点击回调
  final double iconSize; // 图标大小
  final Color iconColor; // 图标颜色
  final double blurSigma; // 高斯模糊强度
  final double opacity; // 背景透明度
  final double padding; // 内边距

  const BlurredIconButton({
    Key? key,
    required this.icon,
    required this.onPressed,
    this.iconSize = 36,
    this.iconColor = Colors.white,
    this.blurSigma = 5,
    this.opacity = 0.3,
    this.padding = 8,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(50), // 使背景为圆形
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma), // 高斯模糊
        child: Container(
          padding: EdgeInsets.all(padding), // 内边距
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(opacity), // 半透明背景
            shape: BoxShape.circle, // 圆形背景
          ),
          child: IconButton(
            icon: Icon(icon, size: iconSize, color: iconColor),
            onPressed: onPressed,
            style: ButtonStyle(
              backgroundColor:
                  MaterialStateProperty.all(Colors.transparent), // 覆盖背景色为透明
              shape: MaterialStateProperty.all(const CircleBorder()), // 保持圆形
              overlayColor:
                  MaterialStateProperty.all(Colors.transparent), // 覆盖点击时的水波纹效果
              iconColor: MaterialStateProperty.all(iconColor), // 覆盖图标颜色
            ),
          ),
        ),
      ),
    );
  }
}

class MusicPlayerPage extends StatefulWidget {
  String filePath;
  VideoPlayerController? controller;
  MusicPlayerPage({super.key, required this.filePath, this.controller});

  @override
  State<MusicPlayerPage> createState() => _MusicPlayerPageState();
}

class _MusicPlayerPageState extends State<MusicPlayerPage>
    with SingleTickerProviderStateMixin {
  late VideoPlayerController _controller;
  bool _isPlaying = false;
  late Duration _position = Duration.zero;
  late Duration _duration = Duration.zero;
  late String _title = '';
  late String _artist = '';
  late String _album = '';
  late Uint8List? _coverBytes;
  final SettingsService _settingsService = SettingsService();
  bool isBgPlay = true;
  bool _usePlaylist = true;
  bool _showLyrics = false;
  String _lrcContent = ''; // 歌词内容
  List<LyricsLine> _lyrics = [];
  ScrollController _lyricsScrollController = ScrollController();
  List<Map<String, String>> _playlist = [];
  final AudioPlayerService _audioService = AudioPlayerService();
  late StreamSubscription<String> _controllerChangeSubscription;
  // 定义循环模式

  // LoopMode _loopMode get {}
  // 设置get方法 loopMode 返回_audioService.loopMode
  void set _loopMode(LoopMode value) {
    _audioService.loopMode = value;
  }

  LoopMode get _loopMode {
    return _audioService.loopMode;
  }

  // 播放速度
  double _playbackSpeed = 1.0;

  @override
  void initState() async {
    super.initState();
    _usePlaylist = await _settingsService.getUsePlaylist();
    _getPlaylist(widget.filePath);
    _initPlayer();
    // 订阅控制器变更通知
    _controllerChangeSubscription =
        _audioService.controllerChangeStream.listen((path) {
      if (mounted) {
        // 当接收到控制器变化通知时更新UI
        setState(() {
          widget.controller = _audioService.controller;
          startNewPlay(_audioService.currentFilePath!);
        });
      }
    });
  }

  void _getPlaylist(String path) async {
    //提取文件夹路径
    _playlist.clear();
    if (!_usePlaylist) {
      return;
    }
    print("music path: $path");
    if (path.contains(':')) {
      _playlist.add({
        'name': path,
        'path': path,
      });
      return;
    }
    String folderPath = path.substring(0, path.lastIndexOf('/'));
    List<String> excludeExts = ['lrc', 'srt', 'ux_store', 'jpg'];
    List<String> includeExts = ['mp3', 'm4a', 'flac', 'ogg'];
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
          if (includeExts.contains(file.path.split('.').last)) {
            final metadata =
                await readMetadata(File(file.path), getImage: true);
            // setState(() {
            //   _title = metadata.title ?? 'Unknown Title';
            //   _artist = metadata.artist ?? 'Unknown Artist';
            //   _album = metadata.album ?? 'Unknown Album';
            //   _coverBytes =
            //       metadata.pictures.isNotEmpty ? metadata.pictures[0].bytes : null;
            // });
            _playlist.add({
              'name': file.path.split('/').last,
              'path': file.path,
              'title': metadata.title ?? file.path.split('/').last,
              'artist': metadata.artist ?? 'Unknown Artist',
              'album': metadata.album ?? 'Unknown Album',
              'coverBytes': metadata.pictures.isNotEmpty
                  ? String.fromCharCodes(metadata.pictures[0].bytes)
                  : '',
            });
          } else {
            _playlist.add({
              'name': file.path.split('/').last,
              'path': file.path,
              'title': file.path.split('/').last,
              'artist': 'Unknown Artist',
              'album': 'Unknown Album',
              'coverBytes': '',
            });
          }
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

  void _playNextItem() {
    if (_playlist.isEmpty || _playlist.length == 1) {
      return;
    }
    // 获取当前播放项的索引
    int currentIndex =
        _playlist.indexWhere((item) => item['path'] == widget.filePath);
    // 如果当前播放项是最后一项，播放第一项
    if (currentIndex == _playlist.length - 1) {
      startNewPlay(_playlist[0]['path']!);
    } else {
      startNewPlay(_playlist[currentIndex + 1]['path']!);
    }
  }

  void startNewPlay(String path) {
    widget.filePath = path;
    _controller.dispose();
    _lyricsScrollController.dispose();
    _initPlayer();
  }

  void _playPreviousItem() {
    if (_playlist.isEmpty || _playlist.length == 1) {
      return;
    }
    // 获取当前播放项的索引
    int currentIndex =
        _playlist.indexWhere((item) => item['path'] == widget.filePath);
    // 如果当前播放项是第一项，播放最后一项
    if (currentIndex == 0) {
      startNewPlay(_playlist[_playlist.length - 1]['path']!);
    } else {
      startNewPlay(_playlist[currentIndex - 1]['path']!);
    }
  }

  Future<void> _initPlayer() async {
    // 初始化视频播放器
    isBgPlay = await _settingsService.getBackgroundPlay();
    try {
      if (widget.controller != null) {
        _controller = widget.controller!;
        widget.controller = null;
      } else {
        _audioService.controller?.dispose();
        _controller = VideoPlayerController.file(File(widget.filePath),
            videoPlayerOptions: VideoPlayerOptions(
                allowBackgroundPlayback: isBgPlay, mixWithOthers: true));
        await _controller.initialize();
        // Store in the global service
        _audioService.controller = _controller;
      }

      _audioService.currentFilePath = widget.filePath;
      _audioService.playlist = _playlist;
      setState(() {
        _duration = _controller.value.duration;
      });

      // 读取音频元数据
      List<String> includeExts = ['mp3', 'm4a', 'flac', 'ogg'];
      if (includeExts.contains(widget.filePath.split('.').last)) {
        final metadata =
            await readMetadata(File(widget.filePath), getImage: true);
        setState(() {
          _title = metadata.title ?? widget.filePath.split('/').last;
          _artist = metadata.artist ?? 'Unknown Artist';
          _album = metadata.album ?? 'Unknown Album';
          _coverBytes =
              metadata.pictures.isNotEmpty ? metadata.pictures[0].bytes : null;
        });
        _audioService.album = _album;
        _audioService.artist = _artist;
        _audioService.title = _title;
        _audioService.coverBytes = _coverBytes;
      } else {
        setState(() {
          _title = widget.filePath.split('/').last;
          _artist = 'Unknown Artist';
          _album = 'Unknown Album';
          _coverBytes = null;
        });
        _audioService.album = _album;
        _audioService.artist = _artist;
        _audioService.title = _title;
        _audioService.coverBytes = _coverBytes;
        // _audioService.loopMode = _loopMode;
      }

      // 监听播放位置
      _controller.addListener(() {
        if (mounted) {
          setState(() {
            _position = _controller.value.position;
            _isPlaying = _controller.value.isPlaying;
            _duration = _controller.value.duration;
          });
          _audioService.updatePlayerState();

          // 检查是否到达结尾
          // if (_controller.value.position >= _controller.value.duration ||
          //     (_controller.value.position == Duration.zero &&
          //         !_controller.value.isPlaying)) {
          //   switch (_loopMode) {
          //     case LoopMode.off:
          //       // 不循环，停止播放
          //       break;
          //     case LoopMode.all:
          //       // 循环整个列表（在此示例中只有一首歌）
          //       // _controller.seekTo(Duration.zero);
          //       // _controller.play();
          //       _playNextItem();
          //       _controller.play();
          //       break;
          //     case LoopMode.one:
          //       // 单曲循环
          //       _controller.seekTo(Duration.zero);
          //       _controller.play();
          //       break;
          //   }
          // }

          // 更新歌词位置
          _updateLyricPosition(_controller.value.position);
        }
      });
      _audioService.externalAddListener();

      // 加载歌词
      _loadLyrics();

      _play();
      _audioService.firstPlay = false;
      _audioService.updatePlayerState();
    } catch (e) {
      _playNextItem();
    }
  }

  Future<void> _loadLyrics() async {
    // 假设歌词文件和音频文件同名，只是扩展名不同
    final lrcPath = widget.filePath.replaceAll(RegExp(r'\.[^.]+$'), '.lrc');
    try {
      final lrcFile = File(lrcPath);
      if (await lrcFile.exists()) {
        final content = await lrcFile.readAsString();
        setState(() {
          _lrcContent = content;
          _parseLyrics(content);
        });
      } else {
        setState(() {
          _lrcContent = '暂无歌词';
          _lyrics = [LyricsLine(timeMs: 0, text: '暂无歌词')];
        });
      }
    } catch (e) {
      print('加载歌词失败: $e');
      setState(() {
        _lrcContent = '加载歌词失败';
        _lyrics = [LyricsLine(timeMs: 0, text: '加载歌词失败')];
      });
    }
  }

  void _showPlaylist() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true, // 允许更大的高度
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.7, // 占屏幕高度的70%
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: Colors.grey.shade900,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '播放列表',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${_playlist.length} 首歌曲',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(color: Colors.white.withOpacity(0.1)),
              Expanded(
                child: ListView.builder(
                  physics: BouncingScrollPhysics(),
                  itemCount: _playlist.length,
                  itemBuilder: (context, index) {
                    final song = _playlist[index];
                    // 检查是否是当前播放的歌曲
                    bool isCurrentSong = widget.filePath == song['path'];

                    return ListTile(
                      title: Text(
                        song['title'] ?? 'Unknown Title',
                        style: TextStyle(
                          color: isCurrentSong ? Colors.blue : Colors.white,
                          fontWeight: isCurrentSong
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        song['artist'] ?? 'Unknown Artist',
                        style: TextStyle(
                          color: isCurrentSong
                              ? Colors.blue.withOpacity(0.7)
                              : Colors.white.withOpacity(0.7),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: song['coverBytes'] != null
                            ? Image.memory(
                                Uint8List.fromList(
                                    song['coverBytes']!.codeUnits),
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                width: 50,
                                height: 50,
                                color: Colors.grey.shade800,
                                child: Icon(
                                  Icons.music_note,
                                  color: Colors.white.withOpacity(0.7),
                                ),
                              ),
                      ),
                      trailing: isCurrentSong
                          ? Icon(Icons.volume_up, color: Colors.blue, size: 20)
                          : null,
                      onTap: () {
                        // 如果点击的不是当前播放的歌曲，切换到该歌曲
                        if (!isCurrentSong) {
                          _playSongFromList(song);
                        }
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

// 根据传入的歌曲信息播放
  void _playSongFromList(Map<String, String> song) {
    // 根据情况可能需要在上层Widget中处理切换歌曲
    // 这里假设我们使用回调或Navigator将控制权返回给父组件

    startNewPlay(song['path']!);
  }

  void _parseLyrics(String lrcContent) {
    Map<int, String> lyricsMap = {};

    // 支持灵活的时间格式，包括小时、分钟、秒、毫秒
    final RegExp timeTagRegex = RegExp(r'\[(\d+):(\d+)(?::(\d+))?\.(\d+)\]');

    final lines = lrcContent.split('\n');

    for (var line in lines) {
      if (line.trim().isEmpty) continue;

      final matches = timeTagRegex.allMatches(line);
      if (matches.isEmpty) continue;

      String text = line.replaceAll(timeTagRegex, '').trim();
      if (text.isEmpty) continue;

      for (var match in matches) {
        String group1 = match.group(1)!;
        String group2 = match.group(2)!;
        String? group3 = match.group(3);
        String fraction = match.group(4)!;

        int hours = 0;
        int minutes = 0;
        int seconds = 0;
        int milliseconds = 0;

        // 解析小时、分钟、秒
        if (group3 != null) {
          hours = int.parse(group1);
          minutes = int.parse(group2);
          seconds = int.parse(group3);
        } else {
          minutes = int.parse(group1);
          seconds = int.parse(group2);
        }

        // 处理不同精度的毫秒
        switch (fraction.length) {
          case 1:
            milliseconds = int.parse(fraction) * 100; // 0.1秒 -> 100毫秒
            break;
          case 2:
            milliseconds = int.parse(fraction) * 10; // 0.01秒 -> 10毫秒
            break;
          default:
            milliseconds = int.parse(fraction.substring(0, 3)); // 截取前三位
        }

        // 计算总毫秒数
        int totalMs =
            hours * 3600000 + minutes * 60000 + seconds * 1000 + milliseconds;

        // 合并相同时间点的歌词
        lyricsMap.update(
          totalMs,
          (existing) => '$existing\n$text',
          ifAbsent: () => text,
        );
      }
    }

    // 转换为有序列表
    List<LyricsLine> lyrics = lyricsMap.entries
        .map((e) => LyricsLine(timeMs: e.key, text: e.value))
        .toList()
      ..sort((a, b) => a.timeMs.compareTo(b.timeMs));

    setState(() => _lyrics = lyrics);
  }

  void _updateLyricPosition(Duration position) {
    if (_lyrics.isEmpty || !_showLyrics) return;

    // 找到当前时间对应的歌词
    int currentIndex = 0;
    for (int i = 0; i < _lyrics.length; i++) {
      if (i == _lyrics.length - 1 ||
          _lyrics[i + 1].timeMs > position.inMilliseconds) {
        currentIndex = i;
        break;
      }
    }

    // 仅当显示歌词页面且控制器已初始化时滚动
    if (_lyricsScrollController.hasClients) {
      // 获取可视区域高度
      final containerHeight = MediaQuery.of(context).size.height * 0.4;
      final itemHeight = 60.0;

      // 计算中心位置
      final centerPosition = max(0,
          currentIndex * itemHeight - (containerHeight / 2) + (itemHeight / 2));

      // 使用带动画的滚动，但只有当位置变化较大或是关键歌词时才滚动
      if ((currentIndex % 3 == 0) ||
          (_lyricsScrollController.offset - centerPosition).abs() >
              itemHeight) {
        _lyricsScrollController.animateTo(
          centerPosition * 1.0,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  @override
  void dispose() {
    // _controller.dispose();
    _lyricsScrollController.dispose();
    _controllerChangeSubscription.cancel();
    super.dispose();
  }

  void _playPause() {
    setState(() {
      if (_isPlaying) {
        _controller.pause();
      } else {
        _controller.play();
      }
      _isPlaying = !_isPlaying;
    });
  }

  void _play() {
    setState(() {
      _controller.play();
      _isPlaying = true;
    });
  }

  void _pause() {
    setState(() {
      _controller.pause();
      _isPlaying = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity! < 0) {
            // 向左滑动，显示歌词
            setState(() {
              _showLyrics = true;
            });
          } else if (details.primaryVelocity! > 0) {
            // 向右滑动，显示封面
            setState(() {
              _showLyrics = false;
            });
          }
        },
        onTap: () {
          setState(() {
            _showLyrics = !_showLyrics;
          });
        },
        child: Stack(
          children: [
            // 背景 - 模糊的专辑封面
            _buildBlurredBackground(),

            // 主内容
            _showLyrics ? _buildLyricsPage() : _buildPlayerPage(),
          ],
        ),
      ),
    );
  }

  Widget _buildBlurredBackground() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black,
      ),
      child: _coverBytes != null
          ? Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(
                  _coverBytes!,
                  fit: BoxFit.cover,
                ),
                BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Container(
                    color: Colors.black.withOpacity(0.5),
                  ),
                ),
              ],
            )
          : Container(color: Colors.black54),
    );
  }

  Widget _buildPlayerPage() {
    return SafeArea(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 标题和艺术家
          _buildSongInfo(),

          // 专辑封面
          _buildAlbumArt(),

          // 进度条
          _buildProgressBar(),

          // 播放控件
          _buildPlayControls(),

          // 底部选项按钮
          _buildBottomOptions(),
        ],
      ),
    );
  }

  Widget _buildLyricsPage() {
    return SafeArea(
      child: Column(
        children: [
          // 歌曲信息
          _buildSongInfo(),

          // 小封面
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: _coverBytes != null
                  ? Image.memory(
                      _coverBytes!,
                      width: 120,
                      height: 120,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 120,
                      height: 120,
                      color: Colors.grey.shade800,
                      child: const Icon(Icons.music_note,
                          size: 60, color: Colors.white),
                    ),
            ),
          ),

          // 歌词显示部分
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildSimpleLyricWidget(),
            ),
          ),

          // 进度条
          _buildProgressBar(),

          // 播放控件
          _buildPlayControls(),
        ],
      ),
    );
  }

  Widget _buildSimpleLyricWidget() {
    // 找到当前应该高亮显示的歌词索引
    int currentIndex = 0;
    for (int i = 0; i < _lyrics.length; i++) {
      if (i == _lyrics.length - 1 ||
          _lyrics[i + 1].timeMs > _position.inMilliseconds) {
        currentIndex = i;
        break;
      }
    }

    // 计算可视区域高度
    final screenHeight = MediaQuery.of(context).size.height;
    // 预估的歌词容器高度 (考虑其他UI元素后的剩余空间)
    final containerHeight = screenHeight * 0.4; // 假设歌词区域占屏幕高度的40%
    final itemHeight = 60.0; // 每行歌词高度

    // 如果需要滚动到当前播放的歌词
    if (_lyricsScrollController.hasClients) {
      // 计算中心位置
      final centerPosition = max(0,
          currentIndex * itemHeight - (containerHeight / 2) + (itemHeight / 2));

      // 使用带动画的滚动
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _lyricsScrollController.hasClients) {
          _lyricsScrollController.animateTo(
            centerPosition * 1.0,
            duration: Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }

    return LayoutBuilder(builder: (context, constraints) {
      final availableHeight = constraints.maxHeight;

      return ListView.builder(
        controller: _lyricsScrollController,
        itemCount: _lyrics.length,
        itemBuilder: (context, index) {
          // 当前播放的歌词使用不同样式
          final isCurrentLyric = index == currentIndex;

          return Container(
            height: itemHeight,
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            child: Text(
              _lyrics[index].text,
              style: TextStyle(
                color: isCurrentLyric
                    ? Colors.white
                    : Colors.white.withOpacity(0.5),
                fontSize: isCurrentLyric ? 18 : 16,
                fontWeight:
                    isCurrentLyric ? FontWeight.bold : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          );
        },
      );
    });
  }

  Widget _buildSongInfo() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(
            _title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Text(
            _artist,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 16,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumArt() {
    return Container(
      width: 250,
      height: 250,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            spreadRadius: 2,
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: _coverBytes != null
            ? Image.memory(
                _coverBytes!,
                fit: BoxFit.cover,
              )
            : Container(
                color: Colors.grey.shade800,
                child: const Icon(Icons.music_note,
                    size: 100, color: Colors.white),
              ),
      ),
    );
  }

  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white.withOpacity(0.3),
              thumbColor: Colors.white,
              overlayColor: Colors.white.withOpacity(0.2),
            ),
            child: Slider(
              min: 0.0,
              max: _duration.inMilliseconds.toDouble(),
              value: _position.inMilliseconds
                  .toDouble()
                  .clamp(0, _duration.inMilliseconds.toDouble()),
              onChanged: (value) {
                _controller.seekTo(Duration(milliseconds: value.toInt()));
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(_position),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
                Text(
                  _formatDuration(_duration),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          BlurredIconButton(
            icon: Icons.skip_previous,
            onPressed: () {
              // 由于没有上一首功能，这里跳转到开始
              // _controller.seekTo(Duration.zero);
              _playPreviousItem();
            },
          ),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: BlurredIconButton(
              icon: _isPlaying ? Icons.pause : Icons.play_arrow,
              onPressed: _playPause,
              iconSize: 32,
            ),
          ),
          BlurredIconButton(
            icon: Icons.skip_next,
            onPressed: () {
              // 由于没有下一首功能，这里跳转到结束
              // _controller.seekTo(_duration);
              _playNextItem();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBottomOptions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildOptionButton(
            icon: _loopMode == LoopMode.one
                ? Icons.repeat_one
                : (_loopMode == LoopMode.all ? Icons.repeat : Icons.stop),
            color: _loopMode == LoopMode.off ? Colors.white : Colors.blue,
            onPressed: () {
              setState(() {
                switch (_loopMode) {
                  case LoopMode.off:
                    _loopMode = LoopMode.all;
                    // _audioService.loopMode = LoopMode.all;
                    break;
                  case LoopMode.all:
                    _loopMode = LoopMode.one;
                    // _audioService.loopMode = LoopMode.one;
                    break;
                  case LoopMode.one:
                    _loopMode = LoopMode.off;
                    // _audioService.loopMode = LoopMode.off;
                    break;
                }
              });
            },
          ),
          _buildOptionButton(
            icon: Icons.playlist_play,
            onPressed: () {
              // 显示播放列表逻辑
              _showPlaylist();
              // ScaffoldMessenger.of(context).showSnackBar(
              //   SnackBar(content: Text('播放列表功能待实现')),
              // );
            },
          ),
          _buildOptionButton(
            icon: Icons.more_horiz,
            onPressed: () {
              // 显示更多选项
              _showMoreOptions();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildOptionButton({
    required IconData icon,
    required VoidCallback onPressed,
    Color color = Colors.white,
  }) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: BlurredIconButton(
        icon: icon,
        onPressed: onPressed,
        iconSize: 20,
      ),
    );
  }

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.grey.shade900,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.speed, color: Colors.white70),
                title:
                    const Text('播放速度', style: TextStyle(color: Colors.white)),
                trailing: Text(
                  '${_playbackSpeed}x',
                  style: const TextStyle(color: Colors.white70),
                ),
                onTap: () {
                  _showSpeedOptions();
                },
              ),
              // 可以添加更多选项...
            ],
          ),
        );
      },
    );
  }

  void _showSpeedOptions() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.grey.shade900,
          title: const Text('选择播放速度', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                .map((speed) => ListTile(
                      title: Text('${speed}x',
                          style: const TextStyle(color: Colors.white)),
                      onTap: () {
                        setState(() {
                          _playbackSpeed = speed;
                          // VideoPlayerController 设置播放速度
                          _controller.setPlaybackSpeed(speed);
                        });
                        Navigator.pop(context);
                      },
                    ))
                .toList(),
          ),
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}

class PositionData {
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;

  PositionData(this.position, this.bufferedPosition, this.duration);
}

class LyricsLine {
  final int timeMs;
  String text;

  LyricsLine({required this.timeMs, required this.text});
}
