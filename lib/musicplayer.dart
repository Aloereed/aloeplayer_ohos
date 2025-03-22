import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart'
    hide AudioMetadata;
import 'package:rxdart/rxdart.dart';
import 'settings.dart';
import 'audio_player_service.dart';
import 'package:flutter_lyric/lyrics_reader.dart';
import 'package:share_plus/share_plus.dart';
import 'lyrics_page.dart';
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
  Uint8List? _coverBytes = null;
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
  late dynamic _lyricModel;
  final UINetease _lyricUI = UINetease();
  late LyricUISettings _lyricSettings;
  bool _isLoadingSettings = true;
  bool _isTapProgressBar = false;
  bool _hasInitializedLyrics = false;
  // 定义循环模式
  // 初始化歌词UI样式
  void _setLyricUI() {
    _lyricUI.defaultSize = _lyricSettings.defaultSize; // 主歌词字体大小
    _lyricUI.defaultExtSize = _lyricSettings.defaultExtSize; // 副歌词字体大小
    _lyricUI.lineGap = _lyricSettings.lineGap; // 行间距
    _lyricUI.inlineGap = _lyricSettings.inlineGap; // 主副歌词间距
    _lyricUI.lyricAlign = _lyricSettings.lyricAlign; // 歌词对齐方式
    _lyricUI.highlightDirection = _lyricSettings.highlightDirection; // 高亮方向
    _lyricUI.highlight = _lyricSettings.highlight; // 启用高亮
    _lyricUI.bias = _lyricSettings.bias; // 选中行偏移比例
    _lyricUI.lyricBaseLine = _lyricSettings.lyricBaseLine; // 偏移基准线
  }

  Future<void> _loadSettings() async {
    _lyricSettings = await LyricUISettings.loadFromPrefs();
    setState(() {
      _isLoadingSettings = false;
      _setLyricUI();
    });
  }

  void _showLyricSettings() async {
    if (_isLoadingSettings) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: LyricSettingsDialog(
            initialSettings: _lyricSettings,
            onApplySettings: (settings) {
              setState(() {
                _lyricSettings = settings;
                _setLyricUI();
              });
            },
          ),
        );
      },
    );
  }

  Map<String, String> parseDualLanguageLyrics(String lrcContent) {
    // Output maps for original and translated lyrics
    Map<int, String> originalLyricsMap = {};
    Map<int, String> translationLyricsMap = {};
    bool hasDualLanguage = false;

    // Support flexible time formats, including hours, minutes, seconds, milliseconds
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

        // Parse hours, minutes, seconds
        int hours = 0;
        int minutes = 0;
        int seconds = 0;
        int milliseconds = 0;

        if (group3 != null) {
          hours = int.parse(group1);
          minutes = int.parse(group2);
          seconds = int.parse(group3);
        } else {
          minutes = int.parse(group1);
          seconds = int.parse(group2);
        }

        // Process milliseconds with different precisions
        switch (fraction.length) {
          case 1:
            milliseconds =
                int.parse(fraction) * 100; // 0.1 second -> 100 milliseconds
            break;
          case 2:
            milliseconds =
                int.parse(fraction) * 10; // 0.01 second -> 10 milliseconds
            break;
          default:
            milliseconds = int.parse(
                fraction.substring(0, 3)); // Take the first three digits
        }

        // Calculate total milliseconds
        int totalMs =
            hours * 3600000 + minutes * 60000 + seconds * 1000 + milliseconds;

        // Check if the timestamp already has lyrics (dual language check)
        if (originalLyricsMap.containsKey(totalMs)) {
          // If this timestamp already has original lyrics, we consider this as translation
          translationLyricsMap.update(
            totalMs,
            (existing) => '$existing\n$text',
            ifAbsent: () => text,
          );
          hasDualLanguage = true;
        } else {
          // First occurrence is considered original language
          originalLyricsMap[totalMs] = text;
        }
      }
    }

    // Rebuild LRC content for both languages
    String originalLrcContent = '';
    String translationLrcContent = '';

    // Sort timestamps to maintain correct order
    List<int> sortedTimestamps = originalLyricsMap.keys.toList()..sort();

    for (var timestamp in sortedTimestamps) {
      String timeTag = _formatTimeTag(timestamp);
      originalLrcContent += '$timeTag${originalLyricsMap[timestamp]}\n';

      if (hasDualLanguage && translationLyricsMap.containsKey(timestamp)) {
        translationLrcContent += '$timeTag${translationLyricsMap[timestamp]}\n';
      }
    }

    return {
      'original': originalLrcContent.trim(),
      'translation': hasDualLanguage ? translationLrcContent.trim() : '',
    };
  }

// Helper function to format timestamp back to LRC time tag
  String _formatTimeTag(int milliseconds) {
    int totalSeconds = milliseconds ~/ 1000;
    int minutes = totalSeconds ~/ 60;
    int seconds = totalSeconds % 60;
    int remainingMillis = milliseconds % 1000;

    return '[${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${remainingMillis.toString().padLeft(3, '0')}]';
  }

  // 替换原来的_parseLyrics方法
  void _parseLyrics(String lrcContent) {
    if (lrcContent.isEmpty) {
      setState(() {
        _lyricModel = LyricsModelBuilder.create().getModel();
        _hasInitializedLyrics = true;
      });
      return;
    }

    // 使用flutter_lyric包解析歌词
    Map<String, String> lyricsMap = parseDualLanguageLyrics(lrcContent);
    String originalLyrics = lyricsMap['original'] ?? '';
    String translationLyrics = lyricsMap['translation'] ?? '';
    if (translationLyrics.isNotEmpty) {
      setState(() {
        _lyricModel = LyricsModelBuilder.create()
            .bindLyricToMain(originalLyrics)
            .bindLyricToExt(translationLyrics)
            .getModel();
        _hasInitializedLyrics = true;
      });
      return;
    }
    setState(() {
      _lyricModel =
          LyricsModelBuilder.create().bindLyricToMain(lrcContent).getModel();
      _hasInitializedLyrics = true;
    });
  }

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
    _loadSettings();
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

  String pathToUri(String path) {
    if (path.contains(':')) {
      return Uri.parse(path).toString();
    } else if (path.startsWith('/Photos')) {
      return Uri.parse("file://media" + path).toString();
    } else {
      return Uri.parse("file://docs" + path).toString();
    }
    return path;
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
    List<String> excludeExts = [
      'lrc',
      'srt',
      'ux_store',
      'jpg',
      'pdf',
      'png',
      'bmp'
    ];
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
            String title = await AudioMetadata.getTitle(file.path);
            String artist = await AudioMetadata.getArtist(file.path);
            String album = await AudioMetadata.getAlbum(file.path);
            _playlist.add({
              'name': file.path.split('/').last,
              'path': file.path,
              'title': title == "" ? "Unknown Title" : title,
              'artist': artist == "" ? 'Unknown Artist' : artist,
              'album': album == "" ? 'Unknown Album' : album,
              'coverBytes': metadata.pictures.isNotEmpty
                  ? String.fromCharCodes(metadata.pictures[0].bytes)
                  : (String.fromCharCodes(await _settingsService
                          .fetchCoverNative(pathToUri(file.path)) ??
                      Uint8List.fromList([]))),
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
    if (_loopMode == LoopMode.random) {
      // 随机播放
      Random random = Random();
      int randomIndex = random.nextInt(_playlist.length);
      startNewPlay(_playlist[randomIndex]['path']!);
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
    // 加载歌词
    try {
      await _loadLyrics();
    } catch (e) {}
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
        _artist = await AudioMetadata.getArtist(widget.filePath);
        _title = await AudioMetadata.getTitle(widget.filePath);
        _album = await AudioMetadata.getAlbum(widget.filePath);
        _coverBytes = metadata.pictures.isEmpty
            ? await _settingsService
                .fetchCoverNative(pathToUri(widget.filePath))
            : metadata.pictures[0].bytes;
        setState(() {
          _title = _title == "" ? widget.filePath.split('/').last : _title;
          _artist = _artist == "" ? 'Unknown Artist' : _artist;
          _album = _album == "" ? 'Unknown Album' : _album;
          _coverBytes = _coverBytes;
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
          // 更新歌词位置
          _updateLyricPosition(_controller.value.position);
        }
      });
      _audioService.externalAddListener();

      _play();
      _audioService.firstPlay = false;
      _audioService.updatePlayerState();
    } catch (e) {
      print('Error initializing player: $e');
      _playNextItem();
    }
  }

  Future<void> _loadLyrics() async {
    _lrcContent = '';
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
        try {
          final filename = widget.filePath;
          await AudioMetadata.getTitle(filename);
          // await AudioMetadata.getArtist(filename);
          // await AudioMetadata.getAlbum(filename);
          // await AudioMetadata.getYear(filename);
          // await AudioMetadata.getTrack(filename);
          // await AudioMetadata.getDisc(filename);
          // await AudioMetadata.getGenre(filename);
          // await AudioMetadata.getAlbumArtist(filename);
          // await AudioMetadata.getComposer(filename);
          // await AudioMetadata.getLyricist(filename);
          // await AudioMetadata.getComment(filename);
          final lyrics = await AudioMetadata.getLyrics(widget.filePath);
          print("lyrics: $lyrics");
          if (lyrics == '') {
            setState(() {
              _lrcContent = '[00:00.000]暂无歌词';
              _parseLyrics(_lrcContent);
            });
          } else {
            setState(() {
              _lrcContent = lyrics;
              _parseLyrics(lyrics);
            });
          }
        } catch (e) {
          setState(() {
            _lrcContent = '[00:00.000]暂无歌词';
            _parseLyrics(_lrcContent);
          });
        }
      }
    } catch (e) {
      print('加载歌词失败: $e');
      setState(() {
        _lrcContent = '[00:00.000]暂无歌词';
        _parseLyrics(_lrcContent);
      });
    }
  }

  void _showPlaylist() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25.0, sigmaY: 25.0),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.75,
            padding: const EdgeInsets.only(top: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.8),
                  Colors.black.withOpacity(0.9),
                ],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(30),
                topRight: Radius.circular(30),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  spreadRadius: 1,
                  blurRadius: 10,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: Column(
              children: [
                // 顶部把手
                Container(
                  width: 40,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                // 标题区域
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.queue_music_rounded,
                            color: Colors.white.withOpacity(0.9),
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '播放列表',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_playlist.length} 首歌曲',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // 分割线
                Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.white.withOpacity(0.15),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // 歌曲列表
                Expanded(
                  child: ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    itemCount: _playlist.length,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    itemBuilder: (context, index) {
                      final song = _playlist[index];
                      bool isCurrentSong = widget.filePath == song['path'];

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: isCurrentSong
                              ? Colors.blue.withOpacity(0.15)
                              : Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              if (!isCurrentSong) {
                                _playSongFromList(song);
                              }
                              Navigator.pop(context);
                            },
                            splashColor: Colors.white.withOpacity(0.1),
                            highlightColor: Colors.white.withOpacity(0.05),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Row(
                                children: [
                                  // 封面图
                                  Hero(
                                    tag: 'song_cover_${song['path']}',
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        width: 60,
                                        height: 60,
                                        decoration: BoxDecoration(
                                          boxShadow: [
                                            BoxShadow(
                                              color:
                                                  Colors.black.withOpacity(0.2),
                                              blurRadius: 10,
                                              spreadRadius: 1,
                                            )
                                          ],
                                        ),
                                        child: song['coverBytes'] != null
                                            ? Image.memory(
                                                Uint8List.fromList(
                                                    song['coverBytes']!
                                                        .codeUnits),
                                                width: 60,
                                                height: 60,
                                                fit: BoxFit.cover,
                                              )
                                            : Container(
                                                color: Colors.grey.shade800,
                                                child: Icon(
                                                  Icons.music_note,
                                                  color: Colors.white
                                                      .withOpacity(0.7),
                                                  size: 30,
                                                ),
                                              ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  // 歌曲信息
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          song['title'] ?? 'Unknown Title',
                                          style: TextStyle(
                                            color: isCurrentSong
                                                ? Colors.blue.shade300
                                                : Colors.white,
                                            fontSize: 16,
                                            fontWeight: isCurrentSong
                                                ? FontWeight.w700
                                                : FontWeight.w600,
                                            letterSpacing: 0.3,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          song['artist'] ?? 'Unknown Artist',
                                          style: TextStyle(
                                            color: isCurrentSong
                                                ? Colors.blue.shade100
                                                    .withOpacity(0.8)
                                                : Colors.white.withOpacity(0.6),
                                            fontSize: 14,
                                            fontWeight: FontWeight.w400,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  // 当前播放指示
                                  if (isCurrentSong)
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withOpacity(0.15),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Center(
                                        child: Icon(
                                          Icons.volume_up_rounded,
                                          color: Colors.blue,
                                          size: 22,
                                        ),
                                      ),
                                    )
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // 底部空间
                const SizedBox(height: 20),
              ],
            ),
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

  // void _parseLyrics(String lrcContent) {
  //   Map<int, String> lyricsMap = {};

  //   // 支持灵活的时间格式，包括小时、分钟、秒、毫秒
  //   final RegExp timeTagRegex = RegExp(r'\[(\d+):(\d+)(?::(\d+))?\.(\d+)\]');

  //   final lines = lrcContent.split('\n');

  //   for (var line in lines) {
  //     if (line.trim().isEmpty) continue;

  //     final matches = timeTagRegex.allMatches(line);
  //     if (matches.isEmpty) continue;

  //     String text = line.replaceAll(timeTagRegex, '').trim();
  //     if (text.isEmpty) continue;

  //     for (var match in matches) {
  //       String group1 = match.group(1)!;
  //       String group2 = match.group(2)!;
  //       String? group3 = match.group(3);
  //       String fraction = match.group(4)!;

  //       int hours = 0;
  //       int minutes = 0;
  //       int seconds = 0;
  //       int milliseconds = 0;

  //       // 解析小时、分钟、秒
  //       if (group3 != null) {
  //         hours = int.parse(group1);
  //         minutes = int.parse(group2);
  //         seconds = int.parse(group3);
  //       } else {
  //         minutes = int.parse(group1);
  //         seconds = int.parse(group2);
  //       }

  //       // 处理不同精度的毫秒
  //       switch (fraction.length) {
  //         case 1:
  //           milliseconds = int.parse(fraction) * 100; // 0.1秒 -> 100毫秒
  //           break;
  //         case 2:
  //           milliseconds = int.parse(fraction) * 10; // 0.01秒 -> 10毫秒
  //           break;
  //         default:
  //           milliseconds = int.parse(fraction.substring(0, 3)); // 截取前三位
  //       }

  //       // 计算总毫秒数
  //       int totalMs =
  //           hours * 3600000 + minutes * 60000 + seconds * 1000 + milliseconds;

  //       // 合并相同时间点的歌词
  //       lyricsMap.update(
  //         totalMs,
  //         (existing) => '$existing\n$text',
  //         ifAbsent: () => text,
  //       );
  //     }
  //   }

  //   // 转换为有序列表
  //   List<LyricsLine> lyrics = lyricsMap.entries
  //       .map((e) => LyricsLine(timeMs: e.key, text: e.value))
  //       .toList()
  //     ..sort((a, b) => a.timeMs.compareTo(b.timeMs));

  //   setState(() => _lyrics = lyrics);
  // }

  // void _updateLyricPosition(Duration position) {
  //   if (_lyrics.isEmpty || !_showLyrics) return;

  //   // 找到当前时间对应的歌词
  //   int currentIndex = 0;
  //   for (int i = 0; i < _lyrics.length; i++) {
  //     if (i == _lyrics.length - 1 ||
  //         _lyrics[i + 1].timeMs > position.inMilliseconds) {
  //       currentIndex = i;
  //       break;
  //     }
  //   }

  //   // 仅当显示歌词页面且控制器已初始化时滚动
  //   if (_lyricsScrollController.hasClients) {
  //     // 获取可视区域高度
  //     final containerHeight = MediaQuery.of(context).size.height * 0.4;
  //     final itemHeight = 60.0;

  //     // 计算中心位置
  //     final centerPosition = max(0,
  //         currentIndex * itemHeight - (containerHeight / 2) + (itemHeight / 2));

  //     // 使用带动画的滚动，但只有当位置变化较大或是关键歌词时才滚动
  //     if ((currentIndex % 3 == 0) ||
  //         (_lyricsScrollController.offset - centerPosition).abs() >
  //             itemHeight) {
  //       _lyricsScrollController.animateTo(
  //         centerPosition * 1.0,
  //         duration: Duration(milliseconds: 300),
  //         curve: Curves.easeOutCubic,
  //       );
  //     }
  //   }
  // }

  // 替换原来的_updateLyricPosition方法
  void _updateLyricPosition(Duration position) {
    // flutter_lyric包会自动处理歌词滚动，所以这个方法可以简化
    if (!_isTapProgressBar) {
      setState(() {
        // 更新当前播放进度，用于歌词显示
      });
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
    // 获取屏幕宽度
    final screenWidth = MediaQuery.of(context).size.width;
    // 定义一个阈值，超过这个宽度就认为是平板布局
    final isTabletLayout = screenWidth > 600; // 600dp是一个常用的平板判断阈值

    return Scaffold(
      body: isTabletLayout
          ? _buildTabletLayout() // 平板布局
          : _buildPhoneLayout(), // 手机布局
    );
  }

// 手机布局 - 保持原来的滑动切换逻辑
  Widget _buildPhoneLayout() {
    return GestureDetector(
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
    );
  }

// 平板布局 - 左边播放器，右边歌词
  Widget _buildTabletLayout() {
    return Stack(
      children: [
        // 背景 - 模糊的专辑封面
        _buildBlurredBackground(),
        // 分屏显示
        Row(
          children: [
            // 左侧播放器，占用40%宽度
            Expanded(
              flex: 4,
              child: _buildPlayerPage(),
            ),
            // 右侧歌词，占用60%宽度
            Expanded(
              flex: 6,
              child: _buildLyricsPage(isPhone: false),
            ),
          ],
        ),
      ],
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

  // Widget _buildLyricsPage() {
  //   return SafeArea(
  //     child: Column(
  //       children: [
  //         // 歌曲信息
  //         _buildSongInfo(),

  //         // 小封面
  //         Padding(
  //           padding: const EdgeInsets.symmetric(vertical: 20),
  //           child: ClipRRect(
  //             borderRadius: BorderRadius.circular(20),
  //             child: _coverBytes != null
  //                 ? Image.memory(
  //                     _coverBytes!,
  //                     width: 120,
  //                     height: 120,
  //                     fit: BoxFit.cover,
  //                   )
  //                 : Container(
  //                     width: 120,
  //                     height: 120,
  //                     color: Colors.grey.shade800,
  //                     child: const Icon(Icons.music_note,
  //                         size: 60, color: Colors.white),
  //                   ),
  //           ),
  //         ),

  //         // 歌词显示部分
  //         Expanded(
  //           child: Padding(
  //             padding: const EdgeInsets.symmetric(horizontal: 20),
  //             child: _buildSimpleLyricWidget(),
  //           ),
  //         ),

  //         // 进度条
  //         _buildProgressBar(),

  //         // 播放控件
  //         _buildPlayControls(),
  //       ],
  //     ),
  //   );
  // }

  // Widget _buildSimpleLyricWidget() {
  //   // 找到当前应该高亮显示的歌词索引
  //   int currentIndex = 0;
  //   for (int i = 0; i < _lyrics.length; i++) {
  //     if (i == _lyrics.length - 1 ||
  //         _lyrics[i + 1].timeMs > _position.inMilliseconds) {
  //       currentIndex = i;
  //       break;
  //     }
  //   }

  //   // 计算可视区域高度
  //   final screenHeight = MediaQuery.of(context).size.height;
  //   // 预估的歌词容器高度 (考虑其他UI元素后的剩余空间)
  //   final containerHeight = screenHeight * 0.4; // 假设歌词区域占屏幕高度的40%
  //   final itemHeight = 60.0; // 每行歌词高度

  //   // 如果需要滚动到当前播放的歌词
  //   if (_lyricsScrollController.hasClients) {
  //     // 计算中心位置
  //     final centerPosition = max(0,
  //         currentIndex * itemHeight - (containerHeight / 2) + (itemHeight / 2));

  //     // 使用带动画的滚动
  //     WidgetsBinding.instance.addPostFrameCallback((_) {
  //       if (mounted && _lyricsScrollController.hasClients) {
  //         _lyricsScrollController.animateTo(
  //           centerPosition * 1.0,
  //           duration: Duration(milliseconds: 300),
  //           curve: Curves.easeOutCubic,
  //         );
  //       }
  //     });
  //   }

  //   return LayoutBuilder(builder: (context, constraints) {
  //     final availableHeight = constraints.maxHeight;

  //     return ListView.builder(
  //       controller: _lyricsScrollController,
  //       itemCount: _lyrics.length,
  //       itemBuilder: (context, index) {
  //         // 当前播放的歌词使用不同样式
  //         final isCurrentLyric = index == currentIndex;

  //         return Container(
  //           height: itemHeight,
  //           alignment: Alignment.center,
  //           padding: EdgeInsets.symmetric(horizontal: 16, vertical: 5),
  //           child: Text(
  //             _lyrics[index].text,
  //             style: TextStyle(
  //               color: isCurrentLyric
  //                   ? Colors.white
  //                   : Colors.white.withOpacity(0.5),
  //               fontSize: isCurrentLyric ? 18 : 16,
  //               fontWeight:
  //                   isCurrentLyric ? FontWeight.bold : FontWeight.normal,
  //             ),
  //             textAlign: TextAlign.center,
  //             maxLines: 2,
  //             overflow: TextOverflow.ellipsis,
  //           ),
  //         );
  //       },
  //     );
  //   });
  // }

  // 替换原来的_buildLyricsPage方法
  Widget _buildLyricsPage({bool isPhone = true}) {
    return SafeArea(
      child: Column(
        children: [
          // 歌曲信息
          if (isPhone) _buildSongInfo(),

          // 小封面
          if (isPhone)
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
              padding: EdgeInsets.symmetric(
                  horizontal: 20, vertical: isPhone ? 0 : 100),
              child: _buildLyricWidget(isPhone: isPhone),
            ),
          ),

          // 进度条
          if (isPhone) _buildProgressBar(),

          // 播放控件
          if (isPhone) _buildPlayControls(),
        ],
      ),
    );
  }

// 替换原来的_buildSimpleLyricWidget方法
  Widget _buildLyricWidget({bool isPhone = true}) {
    // 创建flutter_lyric包的歌词显示组件
    if (!_hasInitializedLyrics) {
      return Center(
        child: CircularProgressIndicator(),
      );
    }

    return Stack(
      children: [
        // 如果需要背景效果，可以在这里添加背景
        // 例如：毛玻璃效果等，参考示例中的buildReaderBackground()

        LyricsReader(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          model: _lyricModel,
          position: _position.inMilliseconds,
          lyricUi: _lyricUI,
          playing: _isPlaying,
          size: Size(
              double.infinity,
              isPhone
                  ? MediaQuery.of(context).size.height / 2
                  : MediaQuery.of(context).size.height / 1.2),
          emptyBuilder: () => Center(
            child: Text(
              "暂无歌词",
              style: _lyricUI.getOtherMainTextStyle(),
            ),
          ),
          selectLineBuilder: (progress, confirm) {
            return Row(
              children: [
                IconButton(
                  onPressed: () {
                    confirm.call();
                    _controller.seekTo(Duration(milliseconds: progress));
                  },
                  icon: Icon(Icons.play_arrow, color: Colors.green),
                ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(color: Colors.green),
                    height: 1,
                    width: double.infinity,
                  ),
                ),
                Text(
                  _formatDuration(Duration(milliseconds: progress)),
                  style: TextStyle(color: Colors.green),
                )
              ],
            );
          },
        ),
      ],
    );
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
                : (_loopMode == LoopMode.all
                    ? Icons.repeat
                    : (_loopMode == LoopMode.random
                        ? Icons.shuffle
                        : Icons.stop)),
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
                    _loopMode = LoopMode.random;
                    // _audioService.loopMode = LoopMode.off;
                    break;
                  case LoopMode.random:
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
      isScrollControlled: true, // Allows more control over sheet height
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.65),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(32),
                topRight: Radius.circular(32),
              ),
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
                width: 0.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Sheet handle indicator
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),

                // Playback speed option
                _buildOptionTile(
                  icon: Icons.speed,
                  title: '播放速度',
                  trailing: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '${_playbackSpeed}x',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  onTap: _showSpeedOptions,
                ),

                const SizedBox(height: 8),

                // Lyrics UI option
                _buildOptionTile(
                  icon: Icons.format_align_left,
                  title: '滚动歌词效果',
                  onTap: _showLyricSettings,
                ),

                const SizedBox(height: 8),

                // Share the file option
                _buildOptionTile(
                  icon: Icons.share,
                  title: '分享歌曲',
                  onTap: () {
                    // share_plus
                    Share.shareFiles([widget.filePath]);
                  },
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: Colors.white.withOpacity(0.05),
        highlightColor: Colors.white.withOpacity(0.05),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      ),
    );
  }

  void _showSpeedOptions() {
    showDialog(
      context: context,
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 20),
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 20,
                    spreadRadius: 5,
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '选择播放速度',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 10,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((speed) {
                      final isSelected = _playbackSpeed == speed;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _playbackSpeed = speed;
                            _controller.setPlaybackSpeed(speed);
                          });
                          Navigator.pop(context);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 75,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white.withOpacity(0.2)
                                : Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.white.withOpacity(0.5)
                                  : Colors.white.withOpacity(0.1),
                              width: 1,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '${speed}x',
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.8),
                                fontSize: 16,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: ButtonStyle(
                      padding: MaterialStateProperty.all(
                        const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 24),
                      ),
                      backgroundColor: MaterialStateProperty.all(
                        Colors.white.withOpacity(0.1),
                      ),
                      shape: MaterialStateProperty.all(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    child: const Text(
                      '取消',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
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
