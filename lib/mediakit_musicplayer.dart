import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart'
    hide AudioMetadata;
import 'package:media_kit/media_kit.dart';
import 'settings.dart';
import 'mediakit_audio_service.dart';
import 'package:flutter_lyric/lyrics_reader.dart';
import 'package:share_plus/share_plus.dart';
import 'lyrics_page.dart';
import 'package:path/path.dart' as path;
import 'audio_metadata.dart';

class BlurredIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final double iconSize;
  final Color iconColor;
  final double blurSigma;
  final double opacity;
  final double padding;

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
      borderRadius: BorderRadius.circular(50),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(opacity),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: Icon(icon, size: iconSize, color: iconColor),
            onPressed: onPressed,
            style: ButtonStyle(
              backgroundColor: MaterialStateProperty.all(Colors.transparent),
              shape: MaterialStateProperty.all(const CircleBorder()),
              overlayColor: MaterialStateProperty.all(Colors.transparent),
              iconColor: MaterialStateProperty.all(iconColor),
            ),
          ),
        ),
      ),
    );
  }
}

class MediaKitMusicPlayerPage extends StatefulWidget {
  String filePath;
  Player? player;
  MediaKitMusicPlayerPage({super.key, required this.filePath, this.player});

  @override
  State<MediaKitMusicPlayerPage> createState() =>
      _MediaKitMusicPlayerPageState();
}

class _MediaKitMusicPlayerPageState extends State<MediaKitMusicPlayerPage>
    with TickerProviderStateMixin {
  late Player _player;
  bool _isPlaying = false;
  late Duration _position = Duration.zero;
  late Duration _duration = Duration.zero;
  late String _title = '';
  late String _artist = '';
  late String _album = '';
  Uint8List? _coverBytes = null;
  final SettingsService _settingsService = SettingsService();
  bool _usePlaylist = true;
  bool _showLyrics = false;
  String _lrcContent = '';
  List<Map<String, String>> _playlist = [];
  final MediaKitAudioService _audioService = MediaKitAudioService();
  late StreamSubscription<String> _controllerChangeSubscription;
  late dynamic _lyricModel;
  final UINetease _lyricUI = UINetease();
  late LyricUISettings _lyricSettings;
  bool _isLoadingSettings = true;
  bool _hasInitializedLyrics = false;
  double _playbackSpeed = 1.0;

  // 动画控制器
  late AnimationController _rotationController;
  late AnimationController _scaleController;
  bool _showPlaylist = false;

  // 循环模式
  void set _loopMode(MediaKitLoopMode value) {
    _audioService.loopMode = value;
  }

  MediaKitLoopMode get _loopMode {
    return _audioService.loopMode;
  }

  @override
  void initState() async {
    super.initState();

    // 初始化旋转动画控制器
    _rotationController = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    );

    // 初始化缩放动画控制器
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
      value: 1.0,
    );

    _loadSettings();
    _usePlaylist = await _settingsService.getUsePlaylist();
    _getPlaylist(widget.filePath);
    await _audioService.initAudioHandler();
    _initPlayer();

    _controllerChangeSubscription =
        _audioService.controllerChangeStream.listen((path) {
      if (mounted) {
        setState(() {
          widget.player = _audioService.player;
          startNewPlay(_audioService.currentFilePath!);
        });
      }
    });
  }

  void _setLyricUI() {
    _lyricUI.defaultSize = _lyricSettings.defaultSize;
    _lyricUI.defaultExtSize = _lyricSettings.defaultExtSize;
    _lyricUI.lineGap = _lyricSettings.lineGap;
    _lyricUI.inlineGap = _lyricSettings.inlineGap;
    _lyricUI.lyricAlign = _lyricSettings.lyricAlign;
    _lyricUI.highlightDirection = _lyricSettings.highlightDirection;
    _lyricUI.highlight = _lyricSettings.highlight;
    _lyricUI.bias = _lyricSettings.bias;
    _lyricUI.lyricBaseLine = _lyricSettings.lyricBaseLine;
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
    Map<int, String> originalLyricsMap = {};
    Map<int, String> translationLyricsMap = {};
    bool hasDualLanguage = false;

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

        if (group3 != null) {
          hours = int.parse(group1);
          minutes = int.parse(group2);
          seconds = int.parse(group3);
        } else {
          minutes = int.parse(group1);
          seconds = int.parse(group2);
        }

        switch (fraction.length) {
          case 1:
            milliseconds = int.parse(fraction) * 100;
            break;
          case 2:
            milliseconds = int.parse(fraction) * 10;
            break;
          default:
            milliseconds = int.parse(fraction.substring(0, 3));
        }

        int totalMs =
            hours * 3600000 + minutes * 60000 + seconds * 1000 + milliseconds;

        if (originalLyricsMap.containsKey(totalMs)) {
          translationLyricsMap.update(
            totalMs,
            (existing) => '$existing\n$text',
            ifAbsent: () => text,
          );
          hasDualLanguage = true;
        } else {
          originalLyricsMap[totalMs] = text;
        }
      }
    }

    String originalLrcContent = '';
    String translationLrcContent = '';

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

  String _formatTimeTag(int milliseconds) {
    int totalSeconds = milliseconds ~/ 1000;
    int minutes = totalSeconds ~/ 60;
    int seconds = totalSeconds % 60;
    int remainingMillis = milliseconds % 1000;

    return '[${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${remainingMillis.toString().padLeft(3, '0')}]';
  }

  void _parseLyrics(String lrcContent) {
    if (lrcContent.isEmpty) {
      setState(() {
        _lyricModel = LyricsModelBuilder.create().getModel();
        _hasInitializedLyrics = true;
      });
      return;
    }

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

    if (folderPath.startsWith(
        '/storage/Users/currentUser/Download/com.aloereed.aloeplayer/')) {
      final directory = Directory(folderPath);
      List<FileSystemEntity> files = directory.listSync();

      for (FileSystemEntity file in files) {
        if (file is File) {
          if (excludeExts.contains(file.path.split('.').last)) {
            continue;
          }
          if (includeExts.contains(file.path.split('.').last)) {
            try {
              String title = await AudioMetadata.getTitle(file.path);
              String artist = await AudioMetadata.getArtist(file.path);
              String album = await AudioMetadata.getAlbum(file.path);
              final metadata =
                  await readMetadata(File(file.path), getImage: true);
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
            } catch (e) {
              _playlist.add({
                'name': file.path.split('/').last,
                'path': file.path,
                'title': file.path.split('/').last,
                'artist': 'Unknown Artist',
                'album': 'Unknown Album',
                'coverBytes': String.fromCharCodes(Uint8List.fromList([])),
              });
            }
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
      setState(() {
        _playlist.sort((a, b) => a['name']!.compareTo(b['name']!));
      });
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
    if (_loopMode == MediaKitLoopMode.random) {
      Random random = Random();
      int randomIndex = random.nextInt(_playlist.length);
      startNewPlay(_playlist[randomIndex]['path']!);
      return;
    }

    int currentIndex =
        _playlist.indexWhere((item) => item['path'] == widget.filePath);
    if (currentIndex == _playlist.length - 1) {
      startNewPlay(_playlist[0]['path']!);
    } else {
      startNewPlay(_playlist[currentIndex + 1]['path']!);
    }
  }

  void startNewPlay(String path) {
    widget.filePath = path;
    _initPlayer();
  }

  void _playPreviousItem() {
    if (_playlist.isEmpty || _playlist.length == 1) {
      return;
    }

    int currentIndex =
        _playlist.indexWhere((item) => item['path'] == widget.filePath);
    if (currentIndex == 0) {
      startNewPlay(_playlist[_playlist.length - 1]['path']!);
    } else {
      startNewPlay(_playlist[currentIndex - 1]['path']!);
    }
  }

  Future<void> _initPlayer() async {
    try {
      bool shouldOpenNewFile = true;

      if (widget.player != null) {
        _player = widget.player!;
        widget.player = null;

        // 如果传递的播放器正在播放当前文件，则不需要重新打开
        if (_audioService.currentFilePath == widget.filePath) {
          shouldOpenNewFile = false;

          // 直接从 audioService 获取元数据
          _artist = _audioService.artist;
          _title = _audioService.title;
          _album = _audioService.album;
          _coverBytes = _audioService.coverBytes;

          setState(() {
            _isPlaying = _player.state.playing;
            _position = _player.state.position;
            _duration = _player.state.duration;
          });
        }
      } else {
        _audioService.player?.dispose();
        _player = Player();
        _audioService.player = _player;
      }

      _audioService.currentFilePath = widget.filePath;
      _audioService.playlist = _playlist;

      // 监听播放状态
      _player.stream.playing.listen((playing) {
        if (mounted) {
          setState(() {
            _isPlaying = playing;
          });
          _audioService.updatePlayerState();
        }
      });

      // 监听播放位置
      _player.stream.position.listen((position) {
        if (mounted) {
          setState(() {
            _position = position;
          });
          _audioService.updatePlayerState();
        }
      });

      // 监听播放时长
      _player.stream.duration.listen((duration) {
        if (mounted) {
          setState(() {
            _duration = duration;
          });
        }
      });

      // 只有在需要时才打开新文件
      if (shouldOpenNewFile) {
        // 打开音频文件
        await _player.open(Media(widget.filePath));

        // 读取音频元数据
        List<String> includeExts = ['mp3', 'm4a', 'flac', 'ogg'];
        if (includeExts.contains(widget.filePath.split('.').last)) {
          try {
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
          } catch (e) {
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
          }
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
        }

        // 加载歌词
        try {
          await _loadLyrics();
        } catch (e) {}

        _audioService.updateMediaItem();
        _play();
        _audioService.firstPlay = false;
      } else {
        // 如果不需要打开新文件，仍然需要加载歌词
        try {
          await _loadLyrics();
        } catch (e) {}

        // 根据当前播放状态更新动画
        if (_isPlaying) {
          _rotationController.repeat();
          _scaleController.forward();
        }
      }

      _audioService.updatePlayerState();
    } catch (e) {
      print('Error initializing player: $e');
      _playNextItem();
    }
  }

  Future<void> _loadLyrics() async {
    _lrcContent = '';
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
          _lrcContent = '[00:00.000]暂无歌词';
          _parseLyrics(_lrcContent);
        });
      }
    } catch (e) {
      print('加载歌词失败: $e');
      setState(() {
        _lrcContent = '[00:00.000]暂无歌词';
        _parseLyrics(_lrcContent);
      });
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _scaleController.dispose();
    _controllerChangeSubscription.cancel();
    super.dispose();
  }

  void _playPause() {
    setState(() {
      if (_isPlaying) {
        _player.pause();
        _rotationController.stop();
        _scaleController.reverse();
      } else {
        _player.play();
        _rotationController.repeat();
        _scaleController.forward();
      }
      _isPlaying = !_isPlaying;
    });
  }

  void _play() {
    setState(() {
      _player.play();
      _isPlaying = true;
      _rotationController.repeat();
      _scaleController.forward();
    });
  }

  void _pause() {
    setState(() {
      _player.pause();
      _isPlaying = false;
      _rotationController.stop();
      _scaleController.reverse();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTabletLayout = screenWidth > 600;

    return Scaffold(
      body: isTabletLayout ? _buildTabletLayout() : _buildPhoneLayout(),
    );
  }

  Widget _buildPhoneLayout() {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity! < 0) {
          setState(() {
            _showLyrics = true;
          });
        } else if (details.primaryVelocity! > 0) {
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
          _buildBlurredBackground(),
          _showLyrics ? _buildLyricsPage() : _buildPlayerPage(),
        ],
      ),
    );
  }

  Widget _buildTabletLayout() {
    return Stack(
      children: [
        _buildBlurredBackground(),
        Row(
          children: [
            Expanded(
              flex: 4,
              child: _buildPlayerPage(),
            ),
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
      child: Stack(
        children: [
          Column(
            children: [
              _buildTopBar(),
              const SizedBox(height: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildAnimatedAlbumArt(),
                    const SizedBox(height: 16),
                    _buildSongInfoEnhanced(),
                    const SizedBox(height: 16),
                    _buildEnhancedProgressBar(),
                    const SizedBox(height: 12),
                    _buildEnhancedPlayControls(),
                    const SizedBox(height: 12),
                    _buildBottomOptionsEnhanced(),
                  ],
                ),
              ),
            ],
          ),
          // 播放列表抽屉
          if (_showPlaylist) _buildPlaylistDrawer(),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          BlurredIconButton(
            icon: Icons.keyboard_arrow_down,
            onPressed: () => Navigator.of(context).pop(),
            iconSize: 28,
            padding: 4,
          ),
          Text(
            'PLAYING NOW',
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 2,
            ),
          ),
          BlurredIconButton(
            icon: Icons.queue_music,
            onPressed: () {
              setState(() {
                _showPlaylist = !_showPlaylist;
              });
            },
            iconSize: 24,
            padding: 4,
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedAlbumArt() {
    return AnimatedBuilder(
      animation: Listenable.merge([_rotationController, _scaleController]),
      builder: (context, child) {
        return Transform.scale(
          scale: 0.9 + (_scaleController.value * 0.1),
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  spreadRadius: 5,
                  blurRadius: 30,
                  offset: const Offset(0, 15),
                ),
                BoxShadow(
                  color: Colors.white.withOpacity(0.1),
                  spreadRadius: -2,
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 外圈装饰
                Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withOpacity(0.3),
                        Colors.white.withOpacity(0.1),
                        Colors.black.withOpacity(0.3),
                      ],
                    ),
                  ),
                ),
                // 旋转的专辑封面
                Transform.rotate(
                  angle: _rotationController.value * 2 * pi,
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                        width: 3,
                      ),
                    ),
                    child: ClipOval(
                      child: _coverBytes != null
                          ? Image.memory(
                              _coverBytes!,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Colors.grey.shade800,
                                    Colors.grey.shade900,
                                  ],
                                ),
                              ),
                              child: const Icon(
                                Icons.music_note,
                                size: 60,
                                color: Colors.white54,
                              ),
                            ),
                    ),
                  ),
                ),
                // 中心圆点（唱片中心）
                Container(
                  width: 25,
                  height: 25,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSongInfoEnhanced() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Column(
        children: [
          Text(
            _title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            _artist,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Text(
            _album,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedProgressBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Column(
        children: [
          Container(
            height: 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              color: Colors.white.withOpacity(0.1),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Stack(
                children: [
                  // 进度条背景
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  // 进度条
                  FractionallySizedBox(
                    widthFactor: _duration.inMilliseconds > 0
                        ? (_position.inMilliseconds / _duration.inMilliseconds)
                            .clamp(0.0, 1.0)
                        : 0.0,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withOpacity(0.9),
                            Colors.white.withOpacity(0.7),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 1),
          // 可拖动的滑块
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 0,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
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
                _player.seek(Duration(milliseconds: value.toInt()));
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(_position),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  _formatDuration(_duration),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedPlayControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildControlButton(
            icon: Icons.skip_previous_rounded,
            size: 30,
            onPressed: _playPreviousItem,
          ),
          // 主播放按钮
          GestureDetector(
            onTap: _playPause,
            child: Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withOpacity(0.3),
                    Colors.white.withOpacity(0.1),
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: ClipOval(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        _isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        key: ValueKey<bool>(_isPlaying),
                        size: 40,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          _buildControlButton(
            icon: Icons.skip_next_rounded,
            size: 30,
            onPressed: _playNextItem,
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required double size,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.1),
          border: Border.all(
            color: Colors.white.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Center(
              child: Icon(
                icon,
                size: size,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomOptionsEnhanced() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildOptionButton(
            icon: _loopMode == MediaKitLoopMode.one
                ? Icons.repeat_one_rounded
                : (_loopMode == MediaKitLoopMode.all
                    ? Icons.repeat_rounded
                    : (_loopMode == MediaKitLoopMode.random
                        ? Icons.shuffle_rounded
                        : Icons.trending_flat_rounded)),
            color: _loopMode == MediaKitLoopMode.off
                ? Colors.white.withOpacity(0.7)
                : Colors.greenAccent,
            onPressed: () {
              setState(() {
                switch (_loopMode) {
                  case MediaKitLoopMode.off:
                    _loopMode = MediaKitLoopMode.all;
                    break;
                  case MediaKitLoopMode.all:
                    _loopMode = MediaKitLoopMode.one;
                    break;
                  case MediaKitLoopMode.one:
                    _loopMode = MediaKitLoopMode.random;
                    break;
                  case MediaKitLoopMode.random:
                    _loopMode = MediaKitLoopMode.off;
                    break;
                }
              });
            },
          ),
          // 收藏功能已隐藏
          // _buildOptionButton(
          //   icon: Icons.favorite_border_rounded,
          //   onPressed: () {
          //     // TODO: 添加收藏功能
          //   },
          // ),
          _buildOptionButton(
            icon: Icons.playlist_play_rounded,
            onPressed: () {
              setState(() {
                _showPlaylist = !_showPlaylist;
              });
            },
          ),
          _buildOptionButton(
            icon: Icons.more_horiz_rounded,
            onPressed: _showMoreOptions,
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistDrawer() {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      left: 0,
      right: 0,
      bottom: 0,
      height: MediaQuery.of(context).size.height * 0.6,
      child: GestureDetector(
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity! > 0) {
            setState(() {
              _showPlaylist = false;
            });
          }
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.85),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(30),
              topRight: Radius.circular(30),
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.1),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 20,
                offset: const Offset(0, -10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(30),
              topRight: Radius.circular(30),
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Column(
                children: [
                  // 拖动指示器
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // 标题
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
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
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    color: Colors.white.withOpacity(0.1),
                    height: 1,
                  ),
                  // 播放列表内容
                  Expanded(
                    child: _playlist.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.queue_music_rounded,
                                  size: 60,
                                  color: Colors.white.withOpacity(0.3),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  '播放列表为空',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.5),
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: _playlist.length,
                            itemBuilder: (context, index) {
                              final item = _playlist[index];
                              final isCurrentPlaying =
                                  item['path'] == widget.filePath;
                              return _buildPlaylistItem(
                                item,
                                index,
                                isCurrentPlaying,
                              );
                            },
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

  Widget _buildPlaylistItem(
      Map<String, String> item, int index, bool isCurrentPlaying) {
    final coverBytesString = item['coverBytes'] ?? '';
    final hascover =
        coverBytesString.isNotEmpty && coverBytesString.length > 10;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (!isCurrentPlaying) {
            startNewPlay(item['path']!);
            setState(() {
              _showPlaylist = false;
            });
          }
        },
        splashColor: Colors.white.withOpacity(0.1),
        highlightColor: Colors.white.withOpacity(0.05),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: isCurrentPlaying
                ? Colors.white.withOpacity(0.1)
                : Colors.transparent,
            border: Border(
              left: BorderSide(
                color:
                    isCurrentPlaying ? Colors.greenAccent : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              // 序号或播放指示器
              SizedBox(
                width: 30,
                child: isCurrentPlaying
                    ? Icon(
                        Icons.equalizer_rounded,
                        color: Colors.greenAccent,
                        size: 20,
                      )
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 14,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              // 封面
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey.shade800,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: hascover
                      ? Image.memory(
                          Uint8List.fromList(coverBytesString.codeUnits),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.grey.shade800,
                              child: const Icon(
                                Icons.music_note_rounded,
                                color: Colors.white54,
                                size: 24,
                              ),
                            );
                          },
                        )
                      : Container(
                          color: Colors.grey.shade800,
                          child: const Icon(
                            Icons.music_note_rounded,
                            color: Colors.white54,
                            size: 24,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 16),
              // 歌曲信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['title'] ?? item['name'] ?? '',
                      style: TextStyle(
                        color: isCurrentPlaying
                            ? Colors.greenAccent
                            : Colors.white,
                        fontSize: 16,
                        fontWeight: isCurrentPlaying
                            ? FontWeight.bold
                            : FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item['artist'] ?? 'Unknown Artist',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // 更多选项
              IconButton(
                icon: Icon(
                  Icons.more_vert_rounded,
                  color: Colors.white.withOpacity(0.5),
                  size: 20,
                ),
                onPressed: () {
                  // TODO: 显示更多选项
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLyricsPage({bool isPhone = true}) {
    return SafeArea(
      child: Column(
        children: [
          if (isPhone) _buildSongInfo(),
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
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: 20, vertical: isPhone ? 0 : 100),
              child: _buildLyricWidget(isPhone: isPhone),
            ),
          ),
          if (isPhone) _buildProgressBar(),
          if (isPhone) _buildPlayControls(),
        ],
      ),
    );
  }

  Widget _buildLyricWidget({bool isPhone = true}) {
    if (!_hasInitializedLyrics) {
      return Center(
        child: CircularProgressIndicator(),
      );
    }

    return Stack(
      children: [
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
                    _player.seek(Duration(milliseconds: progress));
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
                _player.seek(Duration(milliseconds: value.toInt()));
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
              _playNextItem();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBottomOptions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildOptionButton(
            icon: _loopMode == MediaKitLoopMode.one
                ? Icons.repeat_one
                : (_loopMode == MediaKitLoopMode.all
                    ? Icons.repeat
                    : (_loopMode == MediaKitLoopMode.random
                        ? Icons.shuffle
                        : Icons.stop)),
            color:
                _loopMode == MediaKitLoopMode.off ? Colors.white : Colors.blue,
            onPressed: () {
              setState(() {
                switch (_loopMode) {
                  case MediaKitLoopMode.off:
                    _loopMode = MediaKitLoopMode.all;
                    break;
                  case MediaKitLoopMode.all:
                    _loopMode = MediaKitLoopMode.one;
                    break;
                  case MediaKitLoopMode.one:
                    _loopMode = MediaKitLoopMode.random;
                    break;
                  case MediaKitLoopMode.random:
                    _loopMode = MediaKitLoopMode.off;
                    break;
                }
              });
            },
          ),
          _buildOptionButton(
            icon: Icons.more_horiz,
            onPressed: () {
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
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 45,
        height: 45,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Center(
              child: Icon(
                icon,
                size: 20,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
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
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                _buildOptionTile(
                  icon: Icons.speed,
                  title: '播放速度MPV',
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
                _buildOptionTile(
                  icon: Icons.format_align_left,
                  title: '滚动歌词效果',
                  onTap: _showLyricSettings,
                ),
                const SizedBox(height: 8),
                _buildOptionTile(
                  icon: Icons.share,
                  title: '分享歌曲',
                  onTap: () {
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
                            _player.setRate(speed);
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
