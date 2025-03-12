import 'dart:collection';
import 'dart:ui';

import 'package:aloeplayer/settings.dart';
import 'package:aloeplayer/webdav.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker_ohos/file_picker_ohos.dart';
import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart';
import 'package:media_info/media_info.dart';
import 'package:video_player/video_player.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart'
    hide AudioMetadata;
import 'dart:typed_data';
import 'package:aloeplayer/chewie-1.8.5/lib/src/ffmpegview.dart';
import 'package:flutter/services.dart';
import 'package:aloeplayer/musicplayer.dart';
import 'package:lpinyin/lpinyin.dart'; // Add this package for Chinese pinyin conversion
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'mini_player.dart';
import 'audio_player_service.dart';

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

class AudioInfoEditor extends StatefulWidget {
  final String filePath;

  const AudioInfoEditor({Key? key, required this.filePath}) : super(key: key);

  @override
  _AudioInfoEditorState createState() => _AudioInfoEditorState();
}

class _AudioInfoEditorState extends State<AudioInfoEditor> {
  late TextEditingController _titleController;
  late TextEditingController _artistController;
  late TextEditingController _albumController;
  late TextEditingController _yearController;
  late TextEditingController _trackController;
  late TextEditingController _discController;
  late TextEditingController _genreController;
  late TextEditingController _albumArtistController;
  late TextEditingController _composerController;
  late TextEditingController _lyricistController;
  late TextEditingController _commentController;
  late TextEditingController _lyricsController;
  final SettingsService _settingsService = SettingsService();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _artistController = TextEditingController();
    _albumController = TextEditingController();
    _yearController = TextEditingController();
    _trackController = TextEditingController();
    _discController = TextEditingController();
    _genreController = TextEditingController();
    _albumArtistController = TextEditingController();
    _composerController = TextEditingController();
    _lyricistController = TextEditingController();
    _commentController = TextEditingController();
    _lyricsController = TextEditingController();

    _loadMetadata();
  }

  Future<void> _loadMetadata() async {
    final filename = widget.filePath;

    setState(() async {
      _titleController.text = await AudioMetadata.getTitle(filename);
      _artistController.text = await AudioMetadata.getArtist(filename);
      _albumController.text = await AudioMetadata.getAlbum(filename);
      _yearController.text = (await AudioMetadata.getYear(filename)).toString();
      _trackController.text =
          (await AudioMetadata.getTrack(filename)).toString();
      _discController.text = (await AudioMetadata.getDisc(filename)).toString();
      _genreController.text = await AudioMetadata.getGenre(filename);
      _albumArtistController.text =
          await AudioMetadata.getAlbumArtist(filename);
      _composerController.text = await AudioMetadata.getComposer(filename);
      _lyricistController.text = await AudioMetadata.getLyricist(filename);
      _commentController.text = await AudioMetadata.getComment(filename);
      _lyricsController.text = await AudioMetadata.getLyrics(filename);
    });
  }

  Future<void> _saveMetadata() async {
    final filename = widget.filePath;

    await AudioMetadata.setTitle(filename, _titleController.text);
    await AudioMetadata.setArtist(filename, _artistController.text);
    await AudioMetadata.setAlbum(filename, _albumController.text);
    await AudioMetadata.setYear(filename, int.parse(_yearController.text));
    await AudioMetadata.setTrack(filename, int.parse(_trackController.text));
    await AudioMetadata.setDisc(filename, int.parse(_discController.text));
    await AudioMetadata.setGenre(filename, _genreController.text);
    await AudioMetadata.setAlbumArtist(filename, _albumArtistController.text);
    await AudioMetadata.setComposer(filename, _composerController.text);
    await AudioMetadata.setLyricist(filename, _lyricistController.text);
    await AudioMetadata.setComment(filename, _commentController.text);
    await AudioMetadata.setLyrics(filename, _lyricsController.text);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('元信息保存成功')),
    );
  }

// 获取音频缩略图
  Future<Uint8List?> _getAudioThumbnail(File file) async {
    final filePath = file.path;
    final metadata = readMetadata(file, getImage: true);
    if (metadata.pictures.isNotEmpty) {
      return metadata.pictures[0].bytes;
    }
    final coverNative =
        await _settingsService.fetchCoverNative(pathToUri(file.path));
    return coverNative;
  }

  @override
  Widget build(BuildContext context) {
    File file = File(widget.filePath);
    return FutureBuilder<Uint8List?>(
      future: _getAudioThumbnail(file),
      builder: (context, snapshot) {
        final coverArt = snapshot.data;

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            elevation: 0,
            backgroundColor: Colors.transparent,
            title: Text('编辑元信息',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.white)),
            actions: [
              TextButton.icon(
                icon: Icon(Icons.save_rounded, color: Colors.white),
                label: Text('保存', style: TextStyle(color: Colors.white)),
                onPressed: _saveMetadata,
              ),
            ],
          ),
          body: Stack(
            children: [
              // 背景层 - 专辑封面和模糊效果
              if (coverArt != null)
                Container(
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: MemoryImage(coverArt),
                      fit: BoxFit.cover,
                    ),
                  ),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      color: Colors.black.withOpacity(0.3),
                    ),
                  ),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.indigo.shade800,
                        Colors.purple.shade900,
                      ],
                    ),
                  ),
                ),

              // 内容层
              SafeArea(
                child: SingleChildScrollView(
                  physics: BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 封面显示区域
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Container(
                            width: 200,
                            height: 200,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 15,
                                  offset: Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: coverArt != null
                                  ? Image.memory(
                                      coverArt,
                                      fit: BoxFit.cover,
                                    )
                                  : Container(
                                      color: Colors.grey.shade800,
                                      child: Icon(
                                        Icons.music_note,
                                        size: 80,
                                        color: Colors.white54,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),

                      // 表单区域
                      Container(
                        margin: EdgeInsets.symmetric(horizontal: 16),
                        padding: EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.2),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '基本信息',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            SizedBox(height: 16),
                            _buildTextField(
                                _titleController, '标题', Icons.title),
                            _buildTextField(
                                _artistController, '艺术家', Icons.person),
                            _buildTextField(
                                _albumController, '专辑', Icons.album),
                            _buildTextField(
                                _yearController, '年份', Icons.calendar_today,
                                keyboardType: TextInputType.number),
                            SizedBox(height: 24),
                            Text(
                              '详细信息',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildTextField(
                                    _trackController,
                                    '音轨号',
                                    Icons.format_list_numbered,
                                    keyboardType: TextInputType.number,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: _buildTextField(
                                    _discController,
                                    '碟号',
                                    Icons.album,
                                    keyboardType: TextInputType.number,
                                  ),
                                ),
                              ],
                            ),
                            _buildTextField(
                                _genreController, '风格', Icons.category),
                            _buildTextField(
                                _albumArtistController, '专辑艺术家', Icons.group),
                            _buildTextField(
                                _composerController, '作曲', Icons.music_note),
                            _buildTextField(
                                _lyricistController, '作词', Icons.edit),
                            _buildTextField(
                                _commentController, '注释', Icons.comment),
                            SizedBox(height: 16),
                            Text(
                              '歌词',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            SizedBox(height: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white30,
                                ),
                              ),
                              child: TextField(
                                controller: _lyricsController,
                                maxLines: 8,
                                style: TextStyle(
                                    color: Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.white
                                        : Colors.black),
                                decoration: InputDecoration(
                                  contentPadding: EdgeInsets.all(16),
                                  border: InputBorder.none,
                                  hintText: '输入歌词...',
                                  hintStyle: TextStyle(color: Colors.white54),
                                ),
                              ),
                            ),
                            SizedBox(height: 24),
                            Container(
                              padding: EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.orange.withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded,
                                      color: Colors.orange.shade300, size: 24),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      '修改元信息可能会导致文件损坏，请谨慎操作。支持UTF-8和ID3v2标签。',
                                      style: TextStyle(
                                        color: Colors.orange.shade100,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Builder(builder: (context) {
      final ThemeData theme = Theme.of(context);
      final bool isDarkMode = theme.brightness == Brightness.dark;

      // 根据主题亮暗模式选择颜色
      final Color containerColor = isDarkMode
          ? Colors.white.withOpacity(0.1)
          : Colors.black.withOpacity(0.05);
      final Color borderColor = isDarkMode ? Colors.white30 : Colors.black12;
      final Color textColor = isDarkMode ? Colors.white : Colors.black;
      final Color iconColor = isDarkMode ? Colors.white70 : Colors.black54;
      final Color hintColor = isDarkMode ? Colors.white54 : Colors.black38;

      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Container(
          decoration: BoxDecoration(
            color: containerColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: borderColor,
            ),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            style: TextStyle(color: textColor),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
              border: InputBorder.none,
              prefixIcon: Icon(icon, color: iconColor),
              hintText: label,
              hintStyle: TextStyle(color: hintColor),
            ),
          ),
        ),
      );
    });
  }
}

class AudioCategory {
  final String name;
  final List<dynamic> items;

  AudioCategory({required this.name, required this.items});
}

class AudioMetadataLite {
  final String title;
  final String artist;
  final String album;
  final int trackNumber;
  final String filePath;
  final Uint8List? albumArt;

  AudioMetadataLite({
    required this.title,
    required this.artist,
    required this.album,
    required this.trackNumber,
    required this.filePath,
    this.albumArt,
  });
}

class AudioLibraryTab extends StatefulWidget {
  final Function(String) getopenfile;
  final Function(int) changeTab;
  final Function toggleFullScreen;
  final Function(BuildContext) startPlayerPage;

  AudioLibraryTab({
    required this.getopenfile,
    required this.changeTab,
    required this.toggleFullScreen,
    required this.startPlayerPage,
  });

  @override
  _AudioLibraryTabState createState() => _AudioLibraryTabState();
}

class _AudioLibraryTabState extends State<AudioLibraryTab>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  @override
  bool get wantKeepAlive => true;

  final String _audioDirPath =
      '/storage/Users/currentUser/Download/com.aloereed.aloeplayer/Audios';
  final String _audioDirPathOld = '/data/storage/el2/base/Audios';
  List<File> _audioFiles = [];
  String _currentPath =
      '/storage/Users/currentUser/Download/com.aloereed.aloeplayer/Audios';
  List<Directory> _directories = [];
  List _filteredItems = [];
  String _searchQuery = '';
  bool _isGridView = true;
  final SettingsService _settingsService = SettingsService();
  // 添加缓存
  Map<String, Uint8List?> _thumbnailCache = {};
  Map<String, Duration?> _durationCache = {};
  // For metadata sorted view
  late TabController _tabController;
  final List<String> _tabTitles = ["文件", "艺术家", "专辑", "歌曲"];
  Map<String, List<AudioMetadataLite>> _artistMap = {};
  Map<String, List<AudioMetadataLite>> _albumMap = {};
  List<AudioMetadataLite> _songsList = [];
  List<AudioCategory> _artistCategories = [];
  List<AudioCategory> _albumCategories = [];
  List<AudioCategory> _songCategories = [];
  bool _isLoading = false;
  String? _selectedArtist;
  String? _selectedAlbum;

  @override
  void initState() async {
    super.initState();
    _tabController = TabController(length: _tabTitles.length, vsync: this);
    _tabController.addListener(_handleTabChange);
    _ensureAudioDirectoryExists();
    _isGridView = !(await _settingsService.getDefaultListmode());
    _loadItems();
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) {
      setState(() {});
    }
  }

  // Ensure audio directory exists
  Future<void> _ensureAudioDirectoryExists() async {
    final directory = Directory(_audioDirPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final directoryOld = Directory(_audioDirPathOld);
    if (!await directoryOld.exists()) {
      await directoryOld.create(recursive: true);
    }
  }

  // Load items and process metadata
  Future<void> _loadItems() async {
    setState(() {
      _isLoading = false;
    });

    // Load directories and files
    await _loadDirectoriesAndFiles();

    // Process metadata for categorized views
    await _processMetadata();

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _loadDirectoriesAndFiles() async {
    final directory = Directory(_currentPath);
    List<File> files = [];
    List<Directory> directories = [];

    if (await directory.exists()) {
      final items = directory.listSync();
      for (var item in items) {
        if (item is File) {
          String extension = path.extension(item.path).toLowerCase();
          // Filter out non-audio files
          if (extension != '.srt' &&
              extension != '.ass' &&
              extension != '.lrc' &&
              !item.path.contains('.ux_store') &&
              [
                '.mp3',
                '.flac',
                '.wav',
                '.m4a',
                '.aac',
                '.ogg',
                '.aiff',
                '.tak',
                '.dsf',
                '.wma'
              ].contains(extension)) {
            files.add(item);
          }
        } else if (item is Directory) {
          directories.add(item);
        }
      }
    }

    setState(() {
      _audioFiles = files;
      _directories = directories;
      _filteredItems = [...directories, ...files];
    });
  }

  // Process metadata for all audio files
  Future<void> _processMetadata() async {
    _artistMap = {};
    _albumMap = {};
    _songsList = [];

    for (File file in _audioFiles) {
      try {
        final metadata = await _extractAudioMetadataLite(file);

        // Add to Artists map
        if (metadata.artist.isNotEmpty) {
          _artistMap.putIfAbsent(metadata.artist, () => []).add(metadata);
        } else {
          _artistMap.putIfAbsent('Unknown Artist', () => []).add(metadata);
        }

        // Add to Albums map
        if (metadata.album.isNotEmpty) {
          _albumMap.putIfAbsent(metadata.album, () => []).add(metadata);
        } else {
          _albumMap.putIfAbsent('Unknown Album', () => []).add(metadata);
        }

        // Add to Songs list
        _songsList.add(metadata);
      } catch (e) {
        print('Error processing metadata for ${file.path}: $e');
      }
    }

    // Sort songs by name
    _songsList.sort((a, b) {
      String nameA = a.title;
      String nameB = b.title;
      return nameA.compareTo(nameB);
    });

    // Create categorized lists
    _createCategorizedLists();
  }

  // Create alphabetical categories for artists, albums and songs
  void _createCategorizedLists() {
    // Process Artists
    _artistCategories = _createCategoriesFromMap(_artistMap);

    // Process Albums
    _albumCategories = _createCategoriesFromMap(_albumMap);

    // Process Songs
    Map<String, List<AudioMetadataLite>> songsMap = {};
    for (var song in _songsList) {
      String title = path.basenameWithoutExtension(song.title);
      String firstChar = _getFirstChar(title);
      songsMap.putIfAbsent(firstChar.toUpperCase(), () => []).add(song);
    }
    _songCategories = _createCategoriesFromMap(songsMap);
  }

  // Create categories from a map of items
  List<AudioCategory> _createCategoriesFromMap(
      Map<String, List<AudioMetadataLite>> itemsMap) {
    Map<String, List<dynamic>> categories =
        SplayTreeMap<String, List<dynamic>>();

    // Group by first character
    itemsMap.forEach((name, items) {
      String firstChar = _getFirstChar(name);
      categories.putIfAbsent(firstChar.toUpperCase(), () => []).add({
        'name': name,
        'items': items,
      });
    });

    // Convert to list of AudioCategory
    List<AudioCategory> result = [];
    categories.forEach((char, items) {
      // Sort items alphabetically within each category
      items.sort((a, b) => a['name'].compareTo(b['name']));
      result.add(AudioCategory(name: char, items: items));
    });

    return result;
  }

  // Get first character, handling Chinese characters by converting to pinyin
  String _getFirstChar(String text) {
    if (text.isEmpty) return '#';

    String firstChar;
    // If it's a Chinese character, convert to pinyin
    if (RegExp(r'[\u4e00-\u9fa5]').hasMatch(text[0])) {
      String pinyin = PinyinHelper.getShortPinyin(text[0]);
      firstChar = pinyin.isNotEmpty ? pinyin[0].toUpperCase() : '#';
    } else {
      firstChar = text[0].toUpperCase();
    }

    // Check if it's a letter
    if (RegExp(r'[A-Z]').hasMatch(firstChar)) {
      return firstChar;
    }
    return '#';
  }

  // Extract metadata from audio file
  Future<AudioMetadataLite> _extractAudioMetadataLite(File file) async {
    try {
      final metadata = readMetadata(file, getImage: true);
      String title = await AudioMetadata.getTitle(file.path);
      String artist = await AudioMetadata.getArtist(file.path);
      String album = await AudioMetadata.getAlbum(file.path);
      title =
          title.isNotEmpty ? title : path.basenameWithoutExtension(file.path);
      artist = artist.isNotEmpty ? artist : 'Unknown Artist';
      album = album.isNotEmpty ? album : 'Unknown Album';
      int trackNumber = metadata.trackNumber ?? 0;
      Uint8List? albumArt = metadata.pictures.isEmpty
          ? await _settingsService.fetchCoverNative(pathToUri(file.path))
          : metadata.pictures[0].bytes;

      return AudioMetadataLite(
        title: title,
        artist: artist,
        album: album,
        trackNumber: trackNumber,
        filePath: file.path,
        albumArt: albumArt,
      );
    } catch (e) {
      // If metadata extraction fails, use filename
      return AudioMetadataLite(
        title: path.basenameWithoutExtension(file.path),
        artist: 'Unknown Artist',
        album: 'Unknown Album',
        trackNumber: 0,
        filePath: file.path,
      );
    }
  }

  void _filterItems(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredItems = [..._directories, ..._audioFiles];
      } else {
        _filteredItems = [..._directories, ..._audioFiles]
            .where((item) => path
                .basename(item.path)
                .toLowerCase()
                .contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  void _navigateToDirectory(Directory directory) {
    setState(() {
      _currentPath = directory.path;
      _selectedArtist = null;
      _selectedAlbum = null;
    });
    _loadItems();
  }

  void _navigateUp() {
    final parentDirectory = Directory(path.dirname(_currentPath));
    setState(() {
      _currentPath = parentDirectory.path;
      _selectedArtist = null;
      _selectedAlbum = null;
    });
    _loadItems();
  }

  void _viewArtistSongs(String artist) {
    setState(() {
      _selectedArtist = artist;
      _selectedAlbum = null;
    });
  }

  void _viewAlbumSongs(String album) {
    setState(() {
      _selectedAlbum = album;
      _selectedArtist = null;
    });
  }

  void _resetCategoryView() {
    setState(() {
      _selectedArtist = null;
      _selectedAlbum = null;
    });
  }

  // Create a folder, pick files, etc. (existing functionality)
  // ...
  void _openWebDavFileManager(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return WebDAVDialog(onLoadFiles: _loadItems, fileExts: [
          'mp3',
          'flac',
          'wav',
          'm4a',
          'aac',
          'ogg',
          'aiff',
          'tak',
          'dsf',
          'wma'
        ]);
      },
    );
  }

  // 根据搜索内容过滤音频文件
  void _filterAudioFiles(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredItems = _audioFiles; // 无搜索内容时显示全部
      } else {
        _filteredItems = _audioFiles
            .where((file) => path
                .basename(file.path)
                .toLowerCase()
                .contains(query.toLowerCase()))
            .toList(); // 过滤文件名包含搜索字符串的文件
      }
    });
  }

  // 使用file_picker选择音频文件
  Future<void> _pickAudioWithFilePicker() async {
    await _ensureAudioDirectoryExists();
    // 使用 FilePicker 选择多个视频文件
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'mp3,.flac,.wav,.m4a,.aac,.ogg,.aiff,.tak,.dsf,.wma',
        'mp3',
        'wav',
        'flac',
        'aac',
        'm4a',
        'ogg',
        'aiff',
        'tak',
        'dsf',
        'wma'
      ], // 允许的视频文件扩展名
      allowMultiple: true, // 支持多选
    );

    // 检查是否选择了文件
    if (result != null) {
      List<PlatformFile> files = result.files; // 获取所有选择的文件
      for (PlatformFile platformFile in files) {
        final XFile file = XFile(platformFile.path!);
        await _copyAudioFile(file); // 处理每个文件
      }
    } else {
      // 用户取消了选择
      print('用户取消了文件选择');
    }
  }

  // 使用image_picker选择音频文件

  Future<void> _copyAudioFile(XFile file) async {
    final fileName = path.basename(file.path);
    final destinationPath = path.join(_currentPath, fileName);
    final destinationFile = File(destinationPath);
    bool deleteIfError = true;
    // 显示加载对话框
    showDialog(
      context: context,
      barrierDismissible: false, // 用户不能通过点击外部关闭对话框
      builder: (BuildContext context) {
        return AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text("正在复制..."),
            ],
          ),
        );
      },
    );

    try {
      // 检查destinationPath是否已存在
      if (await destinationFile.exists()) {
        deleteIfError = false;
        throw FileSystemException(
          "文件已存在",
          destinationPath,
        );
      }
      final inputStream = File(file.path).openRead();
      final outputStream = destinationFile.openWrite();

      await inputStream.pipe(outputStream);
      print("文件复制完成: $destinationPath");

      // 关闭对话框
      Navigator.of(context).pop();

      // 显示复制成功的Toast
      Fluttertoast.showToast(
        msg: "文件复制成功",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        timeInSecForIosWeb: 1,
        backgroundColor: Colors.green,
        textColor: Colors.white,
        fontSize: 16.0,
      );
    } catch (e) {
      print("文件复制失败: $e");

      // 关闭对话框
      Navigator.of(context).pop();

      // 显示复制失败的Toast
      Fluttertoast.showToast(
        msg: "文件复制失败: $e",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        timeInSecForIosWeb: 1,
        backgroundColor: Colors.red,
        textColor: Colors.white,
        fontSize: 16.0,
      );

      // 如果复制失败，删除可能已创建的目标文件
      if (deleteIfError && await destinationFile.exists()) {
        await destinationFile.delete();
      }
      rethrow;
    } finally {
      _loadItems();
    }
  }

  // 删除音频文件
  Future<void> _deleteAudioFile(File file) async {
    await file.delete();
    _loadItems(); // 刷新音频列表
  }

  // 获取音频缩略图
  Future<Uint8List?> _getAudioThumbnail(File file) async {
    final filePath = file.path;
    if (_thumbnailCache.containsKey(filePath)) {
      return _thumbnailCache[filePath];
    }
    final metadata = readMetadata(file, getImage: true);
    if (metadata.pictures.isNotEmpty) {
      _thumbnailCache[filePath] = metadata.pictures[0].bytes;
      return metadata.pictures[0].bytes;
    }
    final coverNative =
        await _settingsService.fetchCoverNative(pathToUri(file.path));
    _thumbnailCache[filePath] = coverNative;
    return coverNative;
  }

  // 获取音频时长
  Future<Duration> _getAudioDuration(File file) async {
    // final metadata = readMetadata(file, getImage: false);
    // return metadata.duration ?? Duration.zero;
    final filePath = file.path;
    if (_durationCache.containsKey(filePath)) {
      return _durationCache[filePath] ?? Duration.zero;
    }
    final _platform = const MethodChannel('samples.flutter.dev/ffmpegplugin');
    // 调用方法 getBatteryLevel
    final result = await _platform
        .invokeMethod<int>('getVideoDurationMs', {"path": file.path});

    // 将毫秒转换为 Duration 对象
    Duration duration = Duration(milliseconds: result ?? 0);
    // 缓存结果
    _durationCache[filePath] = duration;
    return duration;
  }

  // 获取文件大小
  String _getFileSize(File file) {
    final sizeInBytes = file.lengthSync();
    if (sizeInBytes < 1024) {
      return '$sizeInBytes B';
    } else if (sizeInBytes < 1024 * 1024) {
      return '${(sizeInBytes / 1024).toStringAsFixed(2)} KB';
    } else {
      return '${(sizeInBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
  }

  Future<void> _createNewFolder(BuildContext context) async {
    String? folderName = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        String newFolderName = '';
        return AlertDialog(
          title: Text('新建文件夹'),
          content: TextField(
            decoration: InputDecoration(hintText: '输入文件夹名称'),
            onChanged: (value) {
              newFolderName = value;
            },
          ),
          actions: <Widget>[
            TextButton(
              child: Text('取消', style: TextStyle(color: Colors.lightBlue)),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('创建', style: TextStyle(color: Colors.lightBlue)),
              onPressed: () {
                Navigator.of(context).pop(newFolderName);
              },
            ),
          ],
        );
      },
    );

    if (folderName != null && folderName.isNotEmpty) {
      // 创建新文件夹
      String newFolderPath = '$_currentPath/$folderName';
      try {
        await Directory(newFolderPath).create(recursive: true);
        setState(() {
          _loadItems(); // 刷新音频列表
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('文件夹创建成功: $newFolderPath')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('文件夹创建失败: $e')),
        );
      }
    }
  }

  Widget _buildSpeedDial() {
    return Padding(
        padding: EdgeInsets.only(bottom: 70),
        child: SpeedDial(
          icon: Icons.add,
          activeIcon: Icons.close,
          backgroundColor: Colors.lightBlue,
          foregroundColor: Colors.white,
          overlayColor: Colors.black,
          overlayOpacity: 0.5,
          spacing: 15,
          spaceBetweenChildren: 10,
          animatedIcon: AnimatedIcons.menu_close,
          animatedIconTheme: IconThemeData(size: 22),
          curve: Curves.bounceIn,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
          children: [
            SpeedDialChild(
              child: Icon(Icons.folder_open, color: Colors.white),
              backgroundColor: Colors.blue[600],
              foregroundColor: Colors.white,
              label: '打开文件',
              labelStyle: TextStyle(fontSize: 14),
              labelBackgroundColor:
                  Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[800]
                      : Colors.white,
              onTap: () => _openFile(),
            ),
            // SpeedDialChild(
            //   child: Icon(Icons.webhook, color: Colors.white),
            //   backgroundColor: Colors.orange[600],
            //   foregroundColor: Colors.white,
            //   label: '从WebDAV下载',
            //   labelStyle: TextStyle(fontSize: 14),
            //   labelBackgroundColor:
            //       Theme.of(context).brightness == Brightness.dark
            //           ? Colors.grey[800]
            //           : Colors.white,
            //   onTap: () => _openWebDavFileManager(context),
            // ),
          ],
        ));
  }

  Future<void> _openFile() async {
    // 使用 FilePicker 选择文件
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'mp3,.flac,.wav,.m4a,.aac,.ogg',
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
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MusicPlayerPage(filePath: file.path!),
        ),
      );
    } else {
      // 用户取消了选择
      print('用户取消了文件选择');
    }
  }

  Widget _buildActionMenuItem({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          children: [
            Container(
              height: 36,
              width: 36,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? Color(0xFF121212)
            : Color(0xFFF5F5F5),
        // floatingActionButton: _buildSpeedDial(),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? Color(0xFF121212)
              : Color(0xFFF5F5F5),
          titleSpacing: 0,
          title: AnimatedContainer(
            duration: Duration(milliseconds: 300),
            width: double.infinity,
            height: 40,
            margin: EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[800]
                  : Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 5,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: TextField(
                decoration: InputDecoration(
                  hintText: '搜索音频...',
                  border: InputBorder.none,
                  prefixIcon: Icon(
                    Icons.search,
                    color: Theme.of(context).brightness != Brightness.dark
                        ? Colors.grey[800]!.withOpacity(0.7)
                        : Colors.white.withOpacity(0.7),
                  ),
                  contentPadding: EdgeInsets.symmetric(horizontal: 16),
                  hintStyle: TextStyle(color: Colors.grey),
                ),
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black87,
                ),
                onChanged: _filterItems,
              ),
            ),
          ),
          bottom: TabBar(
            controller: _tabController,
            isScrollable: false,
            tabs: _tabTitles.map((title) => Tab(text: title)).toList(),
            labelColor: Colors.lightBlue,
            indicatorColor: Colors.lightBlue,
            unselectedLabelColor: Colors.grey,
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.folder_open,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black),
              onPressed: () => _openFile(),
            ),
            AnimatedSwitcher(
              duration: Duration(milliseconds: 300),
              child: IconButton(
                key: ValueKey<bool>(_isGridView),
                icon: Icon(
                  _isGridView ? Icons.list_rounded : Icons.grid_view_rounded,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black,
                ),
                tooltip: _isGridView ? "列表视图" : "网格视图",
                onPressed: () {
                  setState(() {
                    _isGridView = !_isGridView;
                  });
                },
              ),
            ),
            Visibility(
              visible:
                  _currentPath != _audioDirPath && _tabController.index == 0,
              child: IconButton(
                icon: Icon(Icons.arrow_upward,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black),
                onPressed: _navigateUp,
              ),
            ),
            Visibility(
              visible: (_selectedArtist != null || _selectedAlbum != null) &&
                  (_tabController.index == 1 || _tabController.index == 2),
              child: IconButton(
                icon: Icon(Icons.arrow_back,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black),
                onPressed: _resetCategoryView,
              ),
            ),
            PopupMenuButton<String>(
              icon: Icon(
                Icons.add_rounded,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black,
              ),
              tooltip: "添加音频",
              elevation: 0,
              offset: const Offset(0, 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              color: Colors.transparent,
              onSelected: (value) {
                if (value == 'pick') {
                  _pickAudioWithFilePicker();
                } else if (value == 'folder') {
                  _createNewFolder(context);
                } else if (value == 'webdav') {
                  _openWebDavFileManager(context);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  padding: EdgeInsets.zero,
                  value: null,
                  enabled: false,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.black.withOpacity(0.6)
                              : Colors.white.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white.withOpacity(0.2)
                                    : Colors.white.withOpacity(0.5),
                            width: 1.5,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Title
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0,
                                  vertical: 8.0,
                                ),
                                child: Text(
                                  '添加音频',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                              const Divider(height: 1, thickness: 1),

                              // Add local video
                              _buildActionMenuItem(
                                context: context,
                                title: '添加本地音频文件',
                                icon: Icons.file_upload,
                                iconColor: Colors.lightBlue,
                                onTap: () {
                                  Navigator.pop(context);
                                  _pickAudioWithFilePicker();
                                },
                              ),

                              // Create new folder
                              _buildActionMenuItem(
                                context: context,
                                title: '新建文件夹',
                                icon: Icons.create_new_folder,
                                iconColor: Colors.lightBlue,
                                onTap: () {
                                  Navigator.pop(context);
                                  _createNewFolder(context);
                                },
                              ),

                              // WebDAV download
                              _buildActionMenuItem(
                                context: context,
                                title: '从WebDAV下载',
                                icon: Icons.cloud_upload_rounded,
                                iconColor: Colors.lightBlue,
                                onTap: () {
                                  Navigator.pop(context);
                                  _openWebDavFileManager(context);
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // IconButton(
            //   icon: Icon(Icons.webhook),
            //   onPressed: () => _openWebDavFileManager(context),
            // ),
            // IconButton(
            //   icon: Icon(Icons.refresh,
            //       color: Theme.of(context).brightness == Brightness.dark
            //           ? Colors.white
            //           : Colors.black),
            //   onPressed: _loadItems,
            // ),
          ],
        ),
        body: _isLoading
            ? Center(child: CircularProgressIndicator())
            : Column(children: [
                Expanded(
                    child: Container(
                        decoration: BoxDecoration(
                          border: null, // 移除 TabBar 和 TabBarView 之间的分割线
                        ),
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            // Tab 1: Files view (existing functionality)
                            _buildFilesView(),

                            // Tab 2: Artists view
                            _buildArtistsView(),

                            // Tab 3: Albums view
                            _buildAlbumsView(),

                            // Tab 4: Songs view
                            _buildSongsView(),
                          ],
                        ))),
                MiniPlayer(
                  onTap: () {
                    final audioService = AudioPlayerService();
                    if (audioService.currentFilePath != null) {
                      Navigator.push(
                        context,
                        PageRouteBuilder(
                          pageBuilder:
                              (context, animation, secondaryAnimation) =>
                                  MusicPlayerPage(
                            filePath: audioService.currentFilePath!,
                            controller: audioService.controller,
                          ),
                          transitionsBuilder:
                              (context, animation, secondaryAnimation, child) {
                            const begin = Offset(0.0, 1.0); // 从底部开始
                            const end = Offset.zero;
                            const curve = Curves.easeOut;

                            var tween = Tween(begin: begin, end: end)
                                .chain(CurveTween(curve: curve));
                            var offsetAnimation = animation.drive(tween);

                            return SlideTransition(
                              position: offsetAnimation,
                              child: child,
                            );
                          },
                          transitionDuration: const Duration(milliseconds: 300),
                        ),
                      );
                    }
                  },
                ),
              ]));
  }

  Widget _buildFilesView() {
    if (_filteredItems.isEmpty) {
      return Center(child: Text('暂无音频'));
    }

    return RefreshIndicator(
        onRefresh: () async {
          await _loadItems();
        },
        child: _isGridView
            ? GridView.builder(
                padding: EdgeInsets.all(8),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 0.8,
                ),
                itemCount: _filteredItems.length,
                itemBuilder: (context, index) {
                  final file = _filteredItems[index];
                  if (file is Directory) {
                    return _buildFolderCard(file);
                  }
                  return _buildAudioCard(file);
                },
              )
            : ListView.builder(
                padding: EdgeInsets.all(8),
                itemCount: _filteredItems.length,
                itemBuilder: (context, index) {
                  final file = _filteredItems[index];
                  if (file is Directory) {
                    return _buildFolderListItem(file);
                  }
                  return _buildAudioCard(file, isListView: true);
                },
              ));
  }

  Widget _buildArtistsView() {
    if (_selectedArtist != null) {
      // Show selected artist's songs
      final songs = _artistMap[_selectedArtist] ?? [];
      songs.sort((a, b) => a.album.compareTo(b.album));

      return Column(
        children: [
          Container(
            margin: EdgeInsets.symmetric(vertical: 8),
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.light
                  ? Colors.grey[200]
                  : Colors.grey[800],
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).shadowColor.withOpacity(0.12),
                  blurRadius: 6,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.person,
                    size: 40,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedArtist!,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).textTheme.titleLarge?.color,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '${songs.length} 首歌曲',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.color
                              ?.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.play_circle_filled,
                    color: Theme.of(context).primaryColor,
                    size: 36,
                  ),
                  onPressed: () {
                    // 播放该艺术家所有歌曲
                    if (songs.isNotEmpty) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              MusicPlayerPage(filePath: songs[0].filePath),
                        ),
                      );
                    }
                  },
                  tooltip: '播放全部',
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
                onRefresh: () async {
                  await _loadItems();
                },
                child: ListView.builder(
                  itemCount: songs.length,
                  itemBuilder: (context, index) {
                    final song = songs[index];
                    return ListTile(
                      leading: song.albumArt != null
                          ? Image.memory(song.albumArt!, width: 50, height: 50)
                          : Icon(Icons.music_note, size: 40),
                      title: Text(song.title),
                      subtitle: Text(song.album),
                      onTap: () {
                        // widget.getopenfile(song.filePath);
                        // widget.changeTab(0);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                MusicPlayerPage(filePath: song.filePath),
                          ),
                        );
                      },
                      trailing: _buildSongPopupMenu(song),
                    );
                  },
                )),
          ),
        ],
      );
    }

    // Show all artists
    return RefreshIndicator(
        onRefresh: () async {
          await _loadItems();
        },
        child: ListView.builder(
          itemCount: _artistCategories.length,
          itemBuilder: (context, categoryIndex) {
            final category = _artistCategories[categoryIndex];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.light
                        ? Colors.grey[200]
                        : Colors.grey[800],
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).shadowColor.withOpacity(0.1),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  width: double.infinity,
                  child: Text(
                    category.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Theme.of(context).textTheme.titleLarge?.color,
                    ),
                  ),
                ),
                ...category.items.map((item) {
                  final artistName = item['name'];
                  final artistSongs = item['items'];

                  return ListTile(
                    leading: Icon(Icons.person),
                    title: Text(artistName),
                    subtitle: Text('${artistSongs.length} 首歌曲'),
                    onTap: () => _viewArtistSongs(artistName),
                  );
                }).toList(),
              ],
            );
          },
        ));
  }

  Widget _buildAlbumsView() {
    if (_selectedAlbum != null) {
      // Show selected album's songs
      final songs = _albumMap[_selectedAlbum] ?? [];
      songs.sort((a, b) => a.trackNumber.compareTo(b.trackNumber));

      Uint8List? albumArt;
      if (songs.isNotEmpty && songs[0].albumArt != null) {
        albumArt = songs[0].albumArt;
      }

      return Column(
        children: [
          Container(
            margin: EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.light
                  ? Colors.grey[200]
                  : Colors.grey[800],
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).shadowColor.withOpacity(0.12),
                  blurRadius: 6,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Row(
                children: [
                  // 专辑封面区域
                  Container(
                    width: 100,
                    height: 100,
                    child: albumArt != null
                        ? Image.memory(
                            albumArt,
                            fit: BoxFit.cover,
                            width: 100,
                            height: 100,
                          )
                        : Container(
                            color:
                                Theme.of(context).primaryColor.withOpacity(0.2),
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.album,
                              size: 60,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                  ),
                  // 专辑信息区域
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedAlbum!,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color:
                                  Theme.of(context).textTheme.titleLarge?.color,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 6),
                          Text(
                            '${songs.length} 首歌曲',
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.color
                                  ?.withOpacity(0.7),
                            ),
                          ),
                          if (songs.isNotEmpty)
                            Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Text(
                                songs[0].artist,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.color,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // 播放按钮
                  Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: IconButton(
                      icon: Icon(
                        Icons.play_circle_filled,
                        color: Theme.of(context).primaryColor,
                        size: 36,
                      ),
                      onPressed: () {
                        // 播放该专辑所有歌曲
                        if (songs.isNotEmpty) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  MusicPlayerPage(filePath: songs[0].filePath),
                            ),
                          );
                        }
                      },
                      tooltip: '播放全部',
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
                onRefresh: () async {
                  await _loadItems();
                },
                child: ListView.builder(
                  itemCount: songs.length,
                  itemBuilder: (context, index) {
                    final song = songs[index];
                    return ListTile(
                      leading: Text(
                        song.trackNumber > 0
                            ? song.trackNumber.toString()
                            : '-',
                        style: TextStyle(fontSize: 18),
                      ),
                      title: Text(song.title),
                      subtitle: Text(song.artist),
                      onTap: () {
                        // widget.getopenfile(song.filePath);
                        // widget.changeTab(0);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                MusicPlayerPage(filePath: song.filePath),
                          ),
                        );
                      },
                      trailing: _buildSongPopupMenu(song),
                    );
                  },
                )),
          ),
        ],
      );
    }

    // Show all albums
    return RefreshIndicator(
        onRefresh: () async {
          await _loadItems();
        },
        child: _isGridView
            ? GridView.builder(
                padding: EdgeInsets.all(8),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.8,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: _albumCategories.length,
                itemBuilder: (context, categoryIndex) {
                  final category = _albumCategories[categoryIndex];

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color:
                              Theme.of(context).brightness == Brightness.light
                                  ? Colors.grey[200]
                                  : Colors.grey[800],
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(context)
                                  .shadowColor
                                  .withOpacity(0.1),
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        padding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        width: double.infinity,
                        child: Text(
                          category.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color:
                                Theme.of(context).textTheme.titleLarge?.color,
                          ),
                        ),
                      ),
                      Expanded(
                        child: GridView.builder(
                          physics: NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.8,
                          ),
                          itemCount: category.items.length,
                          itemBuilder: (context, index) {
                            final album = category.items[index];
                            final albumName = album['name'];
                            final albumSongs = album['items'];

                            Uint8List? albumArt;
                            if (albumSongs.isNotEmpty &&
                                albumSongs[0].albumArt != null) {
                              albumArt = albumSongs[0].albumArt;
                            }

                            return GestureDetector(
                              onTap: () => _viewAlbumSongs(albumName),
                              child: Card(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: albumArt != null
                                          ? Image.memory(albumArt,
                                              fit: BoxFit.cover,
                                              width: double.infinity)
                                          : Container(
                                              color: Colors.grey[300],
                                              child: Center(
                                                  child: Icon(Icons.album,
                                                      size: 50)),
                                            ),
                                    ),
                                    Padding(
                                      padding: EdgeInsets.all(8),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            albumName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold),
                                          ),
                                          if (albumSongs.isNotEmpty)
                                            Text(
                                              albumSongs[0].artist,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(fontSize: 12),
                                            ),
                                          Text(
                                            '${albumSongs.length} 首歌曲',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              )
            : ListView.builder(
                itemCount: _albumCategories.length,
                itemBuilder: (context, categoryIndex) {
                  final category = _albumCategories[categoryIndex];

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color:
                              Theme.of(context).brightness == Brightness.light
                                  ? Colors.grey[200]
                                  : Colors.grey[800],
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(context)
                                  .shadowColor
                                  .withOpacity(0.1),
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        padding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        width: double.infinity,
                        child: Text(
                          category.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color:
                                Theme.of(context).textTheme.titleLarge?.color,
                          ),
                        ),
                      ),
                      ...category.items.map((item) {
                        final albumName = item['name'];
                        final albumSongs = item['items'];

                        Uint8List? albumArt;
                        if (albumSongs.isNotEmpty &&
                            albumSongs[0].albumArt != null) {
                          albumArt = albumSongs[0].albumArt;
                        }

                        return ListTile(
                          leading: albumArt != null
                              ? Image.memory(albumArt,
                                  width: 50, height: 50, fit: BoxFit.cover)
                              : Icon(Icons.album, size: 40),
                          title: Text(albumName),
                          subtitle: Text('${albumSongs.length} 首歌曲'),
                          onTap: () => _viewAlbumSongs(albumName),
                        );
                      }).toList(),
                    ],
                  );
                },
              ));
  }

  Widget _buildSongsView() {
    return RefreshIndicator(
        onRefresh: () async {
          await _loadItems();
        },
        child: ListView.builder(
          itemCount: _songCategories.length,
          itemBuilder: (context, categoryIndex) {
            final category = _songCategories[categoryIndex];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.light
                        ? Colors.grey[200]
                        : Colors.grey[800],
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).shadowColor.withOpacity(0.1),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  width: double.infinity,
                  child: Text(
                    category.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Theme.of(context).textTheme.titleLarge?.color,
                    ),
                  ),
                ),
                ...category.items.map((item) {
                  final songs = item['items'];

                  return Column(
                    children: songs.map<Widget>((song) {
                      return ListTile(
                        leading: song.albumArt != null
                            ? Image.memory(song.albumArt!,
                                width: 50, height: 50)
                            : Icon(Icons.music_note, size: 40),
                        title: Text(song.title),
                        subtitle: Text('${song.artist} • ${song.album}'),
                        onTap: () {
                          // widget.getopenfile(song.filePath);
                          // widget.changeTab(0);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  MusicPlayerPage(filePath: song.filePath),
                            ),
                          );
                        },
                        trailing: _buildSongPopupMenu(song),
                      );
                    }).toList(),
                  );
                }).toList(),
              ],
            );
          },
        ));
  }

  // 添加弹出菜单的方法
  void _showFolderOptions(Directory directory) {
    final folderName = path.basename(directory.path);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 20),
          margin: EdgeInsets.fromLTRB(10, 0, 10, 10),
          decoration: BoxDecoration(
            color: isDarkMode
                ? Colors.grey[900]!.withOpacity(0.8)
                : Colors.white.withOpacity(0.8),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDarkMode
                  ? Colors.white.withOpacity(0.1)
                  : Colors.black.withOpacity(0.1),
              width: 0.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Color(0xFFFFCA28).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.folder_rounded,
                        size: 36,
                        color: Color(0xFFFFCA28),
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        folderName,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? Colors.white : Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 30,
                color: isDarkMode
                    ? Colors.white.withOpacity(0.2)
                    : Colors.black.withOpacity(0.1),
              ),
              _buildFolderOptionTile(
                icon: Icons.drive_file_rename_outline,
                title: "重命名",
                color: Colors.blue,
                onTap: () {
                  Navigator.pop(context);
                  _renameFolder(directory);
                },
                isDarkMode: isDarkMode,
              ),
              _buildFolderOptionTile(
                icon: Icons.delete_outline,
                title: "删除",
                color: Colors.red,
                onTap: () {
                  Navigator.pop(context);
                  _confirmDeleteFolder(directory);
                },
                isDarkMode: isDarkMode,
              ),
              _buildFolderOptionTile(
                icon: Icons.info_outline,
                title: "详细信息",
                color: Colors.green,
                onTap: () {
                  Navigator.pop(context);
                  _showFolderDetails(directory);
                },
                isDarkMode: isDarkMode,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFolderOptionTile({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
    required bool isDarkMode,
  }) {
    return ListTile(
      leading: Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(isDarkMode ? 0.2 : 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: isDarkMode ? Colors.white : Colors.black87,
        ),
      ),
      onTap: onTap,
      contentPadding: EdgeInsets.symmetric(horizontal: 20),
    );
  }

// 重命名文件夹
  void _renameFolder(Directory directory) {
    final TextEditingController controller = TextEditingController();
    controller.text = path.basename(directory.path);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        backgroundColor: isDarkMode ? Colors.grey[850] : Colors.white,
        title: Text(
          "重命名文件夹",
          style: TextStyle(
            color: isDarkMode ? Colors.white : Colors.black87,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(
            color: isDarkMode ? Colors.white : Colors.black87,
          ),
          decoration: InputDecoration(
            hintText: "输入新的文件夹名称",
            hintStyle: TextStyle(
              color: isDarkMode ? Colors.white70 : Colors.black45,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: isDarkMode ? Colors.white30 : Colors.black26,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: isDarkMode ? Colors.white30 : Colors.black26,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: Color(0xFFFFCA28),
              ),
            ),
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            filled: true,
            fillColor: isDarkMode ? Colors.grey[800] : Colors.grey[50],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "取消",
              style: TextStyle(
                color: isDarkMode ? Colors.white70 : Colors.grey[700],
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty &&
                  controller.text != path.basename(directory.path)) {
                final newPath =
                    path.join(path.dirname(directory.path), controller.text);
                try {
                  directory.renameSync(newPath);
                  // 更新UI状态
                  _loadItems();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('重命名成功'),
                      backgroundColor: Colors.green,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('重命名失败: ${e.toString()}'),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
              Navigator.pop(context);
            },
            child: Text("确认"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFFFFCA28),
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: isDarkMode ? 0 : 2,
            ),
          ),
        ],
      ),
    );
  }

// 确认删除文件夹
  void _confirmDeleteFolder(Directory directory) {
    final folderName = path.basename(directory.path);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        backgroundColor: isDarkMode ? Colors.grey[850] : Colors.white,
        title: Text(
          "删除文件夹",
          style: TextStyle(
            color: isDarkMode ? Colors.white : Colors.black87,
          ),
        ),
        content: Text(
          "确定要删除文件夹 \"$folderName\" 及其所有内容吗？此操作不可撤销。",
          style: TextStyle(
            color: isDarkMode ? Colors.white70 : Colors.black87,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "取消",
              style: TextStyle(
                color: isDarkMode ? Colors.white70 : Colors.grey[700],
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              try {
                directory.deleteSync(recursive: true);
                // 更新UI状态
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('文件夹已删除'),
                    backgroundColor: Colors.green,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('删除失败: ${e.toString()}'),
                    backgroundColor: Colors.red,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
              Navigator.pop(context);
            },
            child: Text("删除"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: isDarkMode ? 0 : 2,
            ),
          ),
        ],
      ),
    );
  }

// 显示文件夹详情
  void _showFolderDetails(Directory directory) async {
    final folderName = path.basename(directory.path);
    final stats = await directory.stat();
    final modified = DateFormat('yyyy-MM-dd HH:mm:ss').format(stats.modified);
    final accessed = DateFormat('yyyy-MM-dd HH:mm:ss').format(stats.accessed);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // 计算文件夹大小和内容数量
    int totalSize = 0;
    int fileCount = 0;
    int folderCount = 0;

    try {
      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) {
          fileCount++;
          totalSize += await entity.length();
        } else if (entity is Directory) {
          folderCount++;
        }
      }
    } catch (e) {
      print('Error calculating folder size: $e');
    }

    String formattedSize = '';
    if (totalSize < 1024) {
      formattedSize = '$totalSize B';
    } else if (totalSize < 1024 * 1024) {
      formattedSize = '${(totalSize / 1024).toStringAsFixed(2)} KB';
    } else if (totalSize < 1024 * 1024 * 1024) {
      formattedSize = '${(totalSize / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else {
      formattedSize =
          '${(totalSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        backgroundColor: isDarkMode ? Colors.grey[850] : Colors.white,
        title: Row(
          children: [
            Icon(Icons.folder_rounded, color: Color(0xFFFFCA28)),
            SizedBox(width: 8),
            Text(
              "文件夹详情",
              style: TextStyle(
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailItem("名称", folderName, isDarkMode),
              _buildDetailItem("路径", directory.path, isDarkMode),
              _buildDetailItem("大小", formattedSize, isDarkMode),
              _buildDetailItem("文件数量", "$fileCount 个文件", isDarkMode),
              _buildDetailItem("文件夹数量", "$folderCount 个文件夹", isDarkMode),
              _buildDetailItem("修改时间", modified, isDarkMode),
              _buildDetailItem("访问时间", accessed, isDarkMode),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: Text("确定"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFFFFCA28),
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: isDarkMode ? 0 : 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(String label, String value, bool isDarkMode) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: isDarkMode ? Colors.white : Colors.black87,
            ),
          ),
          SizedBox(height: 4),
          Divider(
            height: 1,
            color: isDarkMode
                ? Colors.white.withOpacity(0.1)
                : Colors.black.withOpacity(0.1),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderCard(Directory directory) {
    final folderName = path.basename(directory.path);

    return Hero(
      tag: 'folder-${directory.path}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            _navigateToDirectory(directory);
          },
          onLongPress: () => _showFolderOptions(directory),
          borderRadius: BorderRadius.circular(12),
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFFCA28).withOpacity(0.6),
                    Color(0xFFFFA000).withOpacity(0.8),
                  ],
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.folder_rounded,
                    size: 50,
                    color: Colors.white,
                  ),
                  SizedBox(height: 8),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      folderName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
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

  Widget _buildFolderListItem(Directory directory) {
    final folderName = path.basename(directory.path);

    return Hero(
      tag: 'folder-${directory.path}',
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: ListTile(
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Color(0xFFFFCA28),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.folder_rounded, color: Colors.white, size: 28),
          ),
          title: Text(
            folderName,
            style: TextStyle(fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Icon(Icons.arrow_forward_ios_rounded, size: 16),
          onTap: () {
            _navigateToDirectory(directory);
          },
          onLongPress: () => _showFolderOptions(directory),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  Widget _buildAudioCard(File file, {bool isListView = false}) {
    // Existing audio card building code...
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MusicPlayerPage(filePath: file.path),
          ),
        );
      },
      onLongPress: () {
        _showAudioOptions(file);
      },
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: isListView
            ? ListTile(
                leading: FutureBuilder<Uint8List?>(
                  future: _getAudioThumbnail(file),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return CircularProgressIndicator();
                    }
                    if (snapshot.hasError || snapshot.data == null) {
                      return Icon(Icons.music_note,
                          size: 40, color: Colors.blue);
                    }
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.memory(snapshot.data!,
                          fit: BoxFit.cover, width: 50, height: 50),
                    );
                  },
                ),
                title: Text(
                  path.basename(file.path),
                  style: TextStyle(fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: FutureBuilder<Duration?>(
                  future: _getAudioDuration(file),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Text('加载中...');
                    }
                    if (snapshot.hasError || snapshot.data == null) {
                      return Text('未知时长 • ${_getFileSize(file)}');
                    }
                    final duration = snapshot.data!;
                    return Text(
                      '${duration.inMinutes}:${duration.inSeconds.remainder(60).toString().padLeft(2, '0')} • ${_getFileSize(file)}',
                      style: TextStyle(fontSize: 12),
                    );
                  },
                ),
                trailing: IconButton(
                  icon: Icon(Icons.more_vert),
                  onPressed: () => _showAudioOptions(file),
                ),
              )
            : Column(
                children: [
                  Expanded(
                    child: FutureBuilder<Uint8List?>(
                      future: _getAudioThumbnail(file),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return Center(child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError || snapshot.data == null) {
                          return Center(
                              child: Icon(Icons.music_note,
                                  size: 50, color: Colors.blue));
                        }
                        return ClipRRect(
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(8)),
                          child: Image.memory(snapshot.data!,
                              fit: BoxFit.cover, width: double.infinity),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          path.basename(file.path),
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 4),
                        FutureBuilder<Duration?>(
                          future: _getAudioDuration(file),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return Text('加载中...',
                                  style: TextStyle(fontSize: 10));
                            }
                            if (snapshot.hasError || snapshot.data == null) {
                              return Text(
                                _getFileSize(file),
                                style:
                                    TextStyle(fontSize: 10, color: Colors.grey),
                              );
                            }
                            final duration = snapshot.data!;
                            return Text(
                              '${duration.inMinutes}:${duration.inSeconds.remainder(60).toString().padLeft(2, '0')} • ${_getFileSize(file)}',
                              style:
                                  TextStyle(fontSize: 10, color: Colors.grey),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  void _showAudioOptions(File file) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = Theme.of(context);
        final isDarkMode = theme.brightness == Brightness.dark;

        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
          child: Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            decoration: BoxDecoration(
              color: isDarkMode
                  ? theme.colorScheme.surface.withOpacity(0.9)
                  : Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  spreadRadius: 0,
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 顶部指示器
                Container(
                  margin: EdgeInsets.only(top: 12, bottom: 8),
                  height: 4,
                  width: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // 标题
                Padding(
                  padding: const EdgeInsets.only(top: 8.0, bottom: 16.0),
                  child: Text(
                    '音频选项',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                // 选项列表
                _buildOptionTile(
                  icon: Icons.play_arrow,
                  iconColor: Colors.green,
                  title: '播放',
                  theme: theme,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            MusicPlayerPage(filePath: file.path),
                      ),
                    );
                  },
                ),
                _buildDivider(theme),
                _buildOptionTile(
                  icon: Icons.play_circle_fill_sharp,
                  iconColor: Colors.blue,
                  title: '使用视频播放器播放',
                  theme: theme,
                  onTap: () {
                    widget.getopenfile(file.path); // 更新_openfile状态
                    widget.startPlayerPage(context);
                  },
                ),
                _buildDivider(theme),
                _buildOptionTile(
                  icon: Icons.edit,
                  iconColor: Colors.blue,
                  title: '元信息修改',
                  theme: theme,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            AudioInfoEditor(filePath: file.path),
                      ),
                    ).then((_) => _loadItems());
                  },
                ),
                _buildDivider(theme),
                _buildOptionTile(
                  icon: Icons.share,
                  iconColor: Colors.purple,
                  title: '分享',
                  theme: theme,
                  onTap: () {
                    Navigator.pop(context);
                    Share.shareXFiles([XFile(file.path)]);
                  },
                ),
                _buildDivider(theme),
                _buildOptionTile(
                  icon: Icons.delete,
                  iconColor: Colors.red,
                  title: '删除',
                  theme: theme,
                  onTap: () {
                    Navigator.pop(context);
                    _confirmDeleteDialog(file);
                  },
                ),
                SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required VoidCallback onTap,
    required ThemeData theme,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            SizedBox(width: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider(ThemeData theme) {
    return Divider(
      height: 1,
      thickness: 0.5,
      indent: 64,
      endIndent: 16,
      color: theme.colorScheme.onSurface.withOpacity(0.3),
    );
  }

  Widget _buildSongPopupMenu(AudioMetadataLite song) {
    return IconButton(
      icon: Icon(Icons.more_vert),
      onPressed: () => _showAudioOptions(File(song.filePath)),
    );
  }

  void _confirmDeleteDialog(File file) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('删除音频'),
          content: Text('确定要删除该音频吗？此操作无法撤销。'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: Text('取消', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                _deleteAudioFile(file);
                Navigator.pop(context);
              },
              child: Text('删除', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  // The existing helper methods for file operations
  // _getAudioThumbnail, _getAudioDuration, _getFileSize, etc.
}
