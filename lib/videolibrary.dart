import 'widgets/video_library_tile.dart';
import 'widgets/video_file_actions_sheet.dart';
import 'widgets/local_import_sheet.dart';
import 'services/disk_thumbnail_cache.dart';
import 'services/video_thumbnail_loader.dart';
import 'services/work_queue.dart';
import 'services/thumbnail_cache.dart';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as path;
import 'package:video_thumbnail_ohos/video_thumbnail_ohos.dart';
import 'package:file_picker_ohos/file_picker_ohos.dart';
import 'package:media_info/media_info.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'webdav.dart';
import 'settings.dart';
import 'package:aloeplayer/chewie-1.8.5/lib/src/ffmpegview.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'favorite.dart';
import 'package:path_provider/path_provider.dart';
import 'history_page.dart';
import 'screens/cast_screen_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'history_service.dart';
import 'theme_provider.dart';
import 'widgets/hoverable_builder.dart';

// import 'package:path/path.dart';

// 常量键值
const String sortTypeKey = 'sort_type';
const String sortOrderKey = 'sort_order';

Future<Map<int, String>> _getSubtitleTracks(String filePath) async {
  final _platform = MethodChannel('samples.flutter.dev/ffmpegplugin');
  final subtitleTracksJson = await _platform
          .invokeMethod<String>('getSubtitleTracks', {'path': filePath}) ??
      '';
  print("[ffprobe] subtitleTracksJson: $subtitleTracksJson");
  return parseSubtitleTracks(subtitleTracksJson, useOriginalIndices: false);
}

class _SubtitleTracksSelector extends StatefulWidget {
  final Map<int, String> subtitleTracks;
  final File file;
  final VoidCallback onExtractComplete;
  final Function(String) onError;
  final SettingsService settingsService;

  const _SubtitleTracksSelector({
    Key? key,
    required this.subtitleTracks,
    required this.file,
    required this.onExtractComplete,
    required this.onError,
    required this.settingsService,
  }) : super(key: key);

  @override
  _SubtitleTracksSelectorState createState() => _SubtitleTracksSelectorState();
}

class _SubtitleTracksSelectorState extends State<_SubtitleTracksSelector> {
  int? selectedTrack;
  bool extractAllTracks = false;

  @override
  void initState() {
    super.initState();
    // Default to first track
    selectedTrack = widget.subtitleTracks.keys.first;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('请选择要抽取的字幕轨道：'),
        SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey[700]!
                    : Colors.grey[300]!),
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey[800]!.withOpacity(0.7)
                : Colors.white.withOpacity(0.7),
          ),
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: selectedTrack,
              isExpanded: true,
              icon: Icon(Icons.arrow_drop_down,
                  color: Theme.of(context).primaryColor),
              dropdownColor: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[800]
                  : Colors.white,
              items: widget.subtitleTracks.entries.map((entry) {
                return DropdownMenuItem<int>(
                  value: entry.key,
                  child: Text("轨道 ${entry.key}: ${entry.value}"),
                );
              }).toList(),
              onChanged: (int? newValue) {
                if (newValue != null) {
                  setState(() {
                    selectedTrack = newValue;
                  });
                }
              },
            ),
          ),
        ),
        SizedBox(height: 16),
        CheckboxListTile(
          title: Text('抽取所有字幕轨道'),
          value: extractAllTracks,
          onChanged: (value) {
            setState(() {
              extractAllTracks = value ?? false;
            });
          },
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: Theme.of(context).primaryColor,
        ),
        SizedBox(height: 8),
        Text(
          '提示: 抽取SRT字幕时会同时输出所有字幕流',
          style: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[400]
                  : Colors.grey[600]),
        ),
        SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: Text('取消',
                  style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[400]
                          : Colors.grey[700])),
            ),
            ElevatedButton(
              onPressed: () async {
                _showProgressDialog(context);
                try {
                  if (extractAllTracks) {
                    await _extractAllSubtitles(widget.file.path);
                  } else if (selectedTrack != null) {
                    await _extractSingleSubtitle(
                        widget.file.path, selectedTrack!);
                  }
                  widget.onExtractComplete();
                } catch (e) {
                  widget.onError(e.toString());
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              child: Text(
                '开始抽取',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showProgressDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: AlertDialog(
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey[900]!.withOpacity(0.9)
                : Colors.white.withOpacity(0.9),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: 20),
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).primaryColor),
                ),
                SizedBox(height: 24),
                Text(
                  extractAllTracks
                      ? '正在抽取所有字幕轨道...'
                      : '正在抽取字幕轨道 $selectedTrack...',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _extractSingleSubtitle(String filePath, int trackIndex) async {
    String realFilePath = filePath;
    if (filePath.endsWith('.lnk')) {
      realFilePath = File(filePath).readAsStringSync();
    }

    final _platform = MethodChannel('samples.flutter.dev/ffmpegplugin');

    // 使用相对路径
    String directoryPath = path.dirname(filePath);
    String fileName = path.basenameWithoutExtension(filePath);
    String trackName = widget.subtitleTracks[trackIndex] ?? "subtitle";

    if (await widget.settingsService.getExtractAssSubtitle()) {
      await _platform.invokeMethod<String>('getasstrack', {
        "path": realFilePath,
        "type": "ass",
        "output": path.join(directoryPath, "${fileName}_${trackName}"),
        "track": "$trackIndex"
      });
    } else {
      await _platform.invokeMethod<String>('getassold', {
        "path": realFilePath,
        "type": "srt",
        "output": filePath,
      });
    }
  }

  Future<void> _extractAllSubtitles(String filePath) async {
    if (filePath.endsWith('.lnk')) {
      filePath = File(filePath).readAsStringSync();
    }

    String directoryPath = path.dirname(filePath);
    String fileName = path.basenameWithoutExtension(filePath);

    final _platform = MethodChannel('samples.flutter.dev/ffmpegplugin');

    if (await widget.settingsService.getExtractAssSubtitle()) {
      for (var entry in widget.subtitleTracks.entries) {
        int key = entry.key;
        String value = entry.value;

        await _platform.invokeMethod<String>('getasstrack', {
          "path": filePath,
          "type": "ass",
          "output": path.join(directoryPath, "${fileName}_${value}"),
          "track": "$key"
        });
        // 休息1秒，避免过快请求
        await Future.delayed(Duration(seconds: 1));
      }
    } else {
      await _platform.invokeMethod<String>('getsrtold', {
        "path": filePath,
        "type": "srt",
      });
    }
  }
}

class VideoLibraryTab extends StatefulWidget {
  final Function(String) getopenfile;
  final Function(int) changeTab;
  final Function(BuildContext) startPlayerPage;
  final Function toggleFullScreen;

  VideoLibraryTab(
      {required this.getopenfile,
      required this.changeTab,
      required this.toggleFullScreen,
      required this.startPlayerPage});

  @override
  _VideoLibraryTabState createState() => _VideoLibraryTabState();
}

class _VideoLibraryTabState extends State<VideoLibraryTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final String _videoDirPath =
      '/storage/Users/currentUser/Download/com.aloereed.aloeplayer/Videos';
  final String _videoDirPathOld = '/data/storage/el2/base/Videos';
  List<File> _videoFiles = [];
  String _currentPath =
      '/storage/Users/currentUser/Download/com.aloereed.aloeplayer/Videos';
  String _thumbnailPath =
      '/storage/Users/currentUser/Download/com.aloereed.aloeplayer/Thumbnails';
  List<Directory> _directories = [];
  List<File> _filteredVideoFiles = []; // 用于存储过滤后的视频文件
  List _filteredItems = []; // 用于存储过滤后的文件和文件夹
  String _searchQuery = ''; // 搜索框的内容
  bool _isGridView = true; // 默认显示Grid视图
  bool _isLoading = false;
  List _allItems = []; // 存储所有项目，用于筛选
  late SortType _currentSortType = SortType.none;
  late SortOrder _currentSortOrder = SortOrder.ascending;
  // 添加缓存
  final ThumbnailCache _thumbnailCache = ThumbnailCache();
  late DiskThumbnailCache _diskThumbnails;
  VideoThumbnailLoader? _thumbnailLoader;
  final WorkQueue _thumbnailQueue = WorkQueue();
  final Map<String, Future<Uint8List?>> _pendingThumbnails = {};
  final WorkQueue _metadataQueue = WorkQueue();
  final Map<String, Future<VideoTileInfo>> _pendingTileInfo = {};
  final Map<String, DateTime> _modifiedTimes = {};
  Map<String, Duration?> _durationCache = {};
  Map<String, bool?> _hdrCache = {};
  final SettingsService _settingsService = SettingsService();
  final FavoritesDatabase _favoritesDb = FavoritesDatabase.instance;
  Map<String, bool> _favoriteStatus = {};
  bool _showOnlyFavorites = false;
  bool isFFmpeged = false;
  bool disableThumbnail = false;
  final historyService = HistoryService();
  // 是否处于多选模式
  bool _isMultiSelectMode = false;

  // 搜索框焦点控制
  final FocusNode _searchFocusNode = FocusNode();
  final TextEditingController _searchTextController = TextEditingController();
  final Map<String, int> _fileSizes = {};
  final Map<String, Future<void>> _permissionRequests = {};
  final Set<String> _activeShortcutUris = {};
  int _loadGeneration = 0;
  String? _libraryError;
  bool _isSearchFocused = false;

// 存储已选中的文件
  Set<FileSystemEntity> _selectedItems = {};

  // 初始化方法，在类初始化时调用
  Future<void> initPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    // 获取保存的排序类型，如果不存在则使用默认值 SortType.none
    final sortTypeIndex = prefs.getInt(sortTypeKey) ?? SortType.none.index;
    _currentSortType = SortType.values[sortTypeIndex];

    // 获取保存的排序顺序，如果不存在则使用默认值 SortOrder.ascending
    final sortOrderIndex =
        prefs.getInt(sortOrderKey) ?? SortOrder.ascending.index;
    _currentSortOrder = SortOrder.values[sortOrderIndex];
  }

  // 保存排序类型的方法
  Future<void> saveSortType(SortType sortType) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(sortTypeKey, sortType.index);
    _currentSortType = sortType;
  }

  // 保存排序顺序的方法
  Future<void> saveSortOrder(SortOrder sortOrder) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(sortOrderKey, sortOrder.index);
    _currentSortOrder = sortOrder;
  }

  @override
  void initState() async {
    super.initState();

    // 添加搜索框焦点监听器
    _searchFocusNode.addListener(() {
      setState(() {
        _isSearchFocused = _searchFocusNode.hasFocus;
      });
    });

    await initPreferences();
    bool useinnerthumb = await _settingsService.getUseInnerThumbnail();
    if (useinnerthumb) {
      // path join
      _thumbnailPath =
          path.join((await getTemporaryDirectory()).path, 'Thumbnails');
    }
    await _ensureVideoDirectoryExists();
    _diskThumbnails = DiskThumbnailCache(Directory(_thumbnailPath));
    _thumbnailLoader = null;
    final defaultList = await _settingsService.getDefaultListmode();
    if (!mounted) return;
    setState(() => _isGridView = !defaultList);
    // _loadVideoFiles();
    _loadItems();
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchTextController.dispose();
    super.dispose();
  }

  // 加载所有项目的收藏状态
  Future<void> _loadFavoriteStatus() async {
    for (var item in _allItems) {
      if (item is File) {
        bool isFav = await _favoritesDb.isFavorite(item.path);

        _favoriteStatus[item.path] = isFav;
      }
    }
    if (!mounted) return;
    setState(() {});

    // 收藏状态更新后重新应用筛选
    if (_showOnlyFavorites) {
      setState(() {
        _applyFavoritesFilter();
      });
    }
  }

  void _sortItems({bool needRefresh = true}) {
    switch (_currentSortType) {
      case SortType.name:
        _filteredItems.sort((a, b) {
          String nameA =
              a is Directory ? path.basename(a.path) : path.basename(a.path);
          String nameB =
              b is Directory ? path.basename(b.path) : path.basename(b.path);
          return _currentSortOrder == SortOrder.ascending
              ? nameA.compareTo(nameB)
              : nameB.compareTo(nameA);
        });
        break;
      case SortType.modifiedDate:
        _filteredItems.sort((a, b) {
          DateTime dateA = _modifiedTimes[a.path] ?? DateTime(1970);
          DateTime dateB = _modifiedTimes[b.path] ?? DateTime(1970);
          return _currentSortOrder == SortOrder.ascending
              ? dateA.compareTo(dateB)
              : dateB.compareTo(dateA);
        });
        break;
      case SortType.none:
        if (needRefresh) _loadItems();
        break;
    }
    if (needRefresh) {
      setState(() {}); // 更新UI
    }
  }

  Widget _buildSortControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        DropdownButton<SortType>(
          value: _currentSortType,
          onChanged: (SortType? newValue) {
            if (newValue != null) {
              setState(() {
                _currentSortType = newValue;
                _sortItems();
              });
            }
          },
          items: [
            DropdownMenuItem(
              value: SortType.name,
              child: Text('按文件名'),
            ),
            DropdownMenuItem(
              value: SortType.modifiedDate,
              child: Text('按修改时间'),
            ),
          ],
        ),
        const SizedBox(width: 16),
        IconButton(
          icon: Icon(_currentSortOrder == SortOrder.ascending
              ? Icons.arrow_upward
              : Icons.arrow_downward),
          onPressed: () {
            setState(() {
              _currentSortOrder = _currentSortOrder == SortOrder.ascending
                  ? SortOrder.descending
                  : SortOrder.ascending;
              _sortItems();
            });
          },
          tooltip: _currentSortOrder == SortOrder.ascending ? '正序' : '倒序',
        ),
      ],
    );
  }

  Future<void> _toggleFavorite(File file) async {
    final path = file.path;
    final name = path.split('/').last;

    if (_favoriteStatus[path] ?? false) {
      // 如果已收藏，则取消收藏
      await _favoritesDb.removeFavorite(path);
      setState(() {
        _favoriteStatus[path] = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已从收藏中移除'),
          behavior: SnackBarBehavior.floating,
          width: 200,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: Duration(seconds: 1),
        ),
      );
    } else {
      // 如果未收藏，则添加到收藏
      final favorite = FavoriteItem(
        path: path,
        name: name,
        type: 'video',
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      await _favoritesDb.addFavorite(favorite);
      setState(() {
        _favoriteStatus[path] = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已添加到收藏'),
          behavior: SnackBarBehavior.floating,
          width: 200,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: Duration(seconds: 1),
        ),
      );
    }

    // 如果正在筛选收藏，刷新视图
    if (_showOnlyFavorites) {
      setState(() {
        _applyFavoritesFilter();
      });
    }
  }

  // 确保视频目录存在
  Future<void> _ensureVideoDirectoryExists() async {
    final directory = Directory(_videoDirPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final directoryOld = Directory(_videoDirPathOld);
    if (!await directoryOld.exists()) {
      await directoryOld.create(recursive: true);
    }
    final directoryThumbnail = Directory(_thumbnailPath);
    if (!await directoryThumbnail.exists()) {
      await directoryThumbnail.create(recursive: true);
    }
  }

// // 加载视频文件
//   Future<void> _loadVideoFiles() async {
//     final directory = Directory(_videoDirPath);
//     List<File> files = [];
//     if (await directory.exists()) {
//       files = directory.listSync().whereType<File>().where((file) {
//         // 获取文件扩展名
//         String extension = path.extension(file.path).toLowerCase();
//         // 排除 .srt 和 .ass 文件
//         return extension != '.srt' &&
//             extension != '.ass' &&
//             !file.path.contains('.ux_store');
//       }).toList();
//     }

//     final directoryOld = Directory(_videoDirPathOld);
//     List<File> filesOld = [];
//     if (await directoryOld.exists()) {
//       filesOld = directoryOld.listSync().whereType<File>().where((file) {
//         // 获取文件扩展名
//         String extension = path.extension(file.path).toLowerCase();
//         // 排除 .srt 和 .ass 文件
//         return extension != '.srt' &&
//             extension != '.ass' &&
//             extension != '.ux_store';
//       }).toList();
//     }

//     // 拼接新旧视频文件
//     final filesCap = [...files, ...filesOld];
//     setState(() {
//       _videoFiles = filesCap;
//       _filteredVideoFiles = filesCap; // 初始化时显示所有文件
//     });
//   }

//   // 根据搜索内容过滤视频文件
//   void _filterVideoFiles(String query) {
//     setState(() {
//       _searchQuery = query;
//       if (query.isEmpty) {
//         _filteredVideoFiles = _videoFiles; // 无搜索内容时显示全部
//       } else {
//         _filteredVideoFiles = _videoFiles
//             .where((file) => path
//                 .basename(file.path)
//                 .toLowerCase()
//                 .contains(query.toLowerCase()))
//             .toList(); // 过滤文件名包含搜索字符串的文件
//       }
//     });
//   }
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

  Future<void> _loadItems() async {
    final generation = ++_loadGeneration;
    final directory = Directory(_currentPath);
    if (mounted) setState(() { _isLoading = true; _libraryError = null; });
    try {
      final files = <File>[];
      final directories = <Directory>[];
      final sizes = <String, int>{};
      final times = <String, DateTime>{};
      disableThumbnail = await _settingsService.getDisableThumbnail();
      if (await directory.exists()) {
        await for (final item in directory.list(followLinks: false)) {
          if (!mounted || generation != _loadGeneration) return;
          if (item.path.contains('.aloe-part-') || item.path.contains('.ux_store') || item.path.contains('.trashed')) continue;
          final stat = await item.stat();
          sizes[item.path] = stat.size; times[item.path] = stat.modified;
          if (item is Directory) directories.add(item);
          if (item is File && !const {'.srt', '.ass', '.jpg', '.png', '.jpeg', '.gif', '.bmp', '.aac', '.pdf'}.contains(path.extension(item.path).toLowerCase())) files.add(item);
        }
      }
      if (!mounted || generation != _loadGeneration) return;
      _fileSizes..clear()..addAll(sizes);
      _modifiedTimes..clear()..addAll(times);
      _videoFiles = files; _directories = directories; _allItems = [...directories, ...files];
      _applyFavoritesFilter(); _sortItems(needRefresh: false);
      await _loadFavoriteStatus();
    } catch (_) {
      if (mounted && generation == _loadGeneration) {
        _libraryError = '暂时无法读取此文件夹，请检查文件权限后刷新';
        _allItems = []; _filteredItems = [];
      }
    } finally {
      if (mounted && generation == _loadGeneration) setState(() => _isLoading = false);
    }
  }

  Future<void> _activateShortcut(File file) {
    if (!file.path.endsWith('.lnk')) return Future.value();
    return _permissionRequests.putIfAbsent(file.path, () => (() async {
      final source = (await file.readAsString()).trim();
      final uri = pathToUri(source);
      if (!_activeShortcutUris.contains(uri) && await _settingsService.activatePersistPermission(uri)) _activeShortcutUris.add(uri);
    })().whenComplete(() { _permissionRequests.remove(file.path); }));
  }

  // 应用收藏筛选
  void _applyFavoritesFilter() {
    if (_showOnlyFavorites) {
      // 仅显示收藏的视频文件
      _filteredItems = _allItems.where((item) {
        if (item is File) {
          return _favoriteStatus[item.path] ?? false;
        }
        return false; // 筛选模式下不显示文件夹
      }).toList();
    } else {
      // 显示所有内容
      _filteredItems = [..._allItems];
    }

    // 如果已经有搜索词，继续应用搜索筛选
    if (_searchQuery.isNotEmpty) {
      _filteredItems = _filteredItems
          .where((item) => path
              .basename(item.path)
              .toLowerCase()
              .contains(_searchQuery.toLowerCase()))
          .toList();
    }
  }

  void _filterItems(String query) {
    setState(() {
      _searchQuery = query;

      // 重新应用筛选
      _applyFavoritesFilter();
      // // 如果有搜索词，应用搜索筛选
      // if (query.isNotEmpty) {
      //   _filteredItems = _filteredItems
      //       .where((item) => path
      //           .basename(item.path)
      //           .toLowerCase()
      //           .contains(query.toLowerCase()))
      //       .toList();
      // }
    });
  }

  void _navigateToDirectory(Directory directory) {
    setState(() {
      _currentPath = directory.path;
    });
    _loadItems();
  }

  void _navigateUp() {
    final parentDirectory = Directory(path.dirname(_currentPath));
    setState(() {
      _currentPath = parentDirectory.path;
    });
    _loadItems();
  }

  // 使用file_picker选择视频文件
  Future<void> _pickVideoWithFilePicker() async {
    await _ensureVideoDirectoryExists();
    _diskThumbnails = DiskThumbnailCache(Directory(_thumbnailPath));
    _thumbnailLoader = null;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('请不要从"最近"选项卡中选择文件'),
        duration: Duration(seconds: 3),
      ),
    );
    // 使用 FilePicker 选择多个视频文件
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'mp4,.mkv,.avi,.mov,.flv,.wmv,.webm,.rmvb,.wmv,.ts',
        'mp4',
        'mkv',
        'avi',
        'mov',
        'flv',
        'wmv',
        'webm',
        'rmvb',
        'wmv',
        'ts'
      ], // 允许的视频文件扩展名
      allowMultiple: true, // 支持多选
    );

    // 检查是否选择了文件
    if (result != null) {
      List<PlatformFile> files = result.files; // 获取所有选择的文件
      for (PlatformFile platformFile in files) {
        final file = XFile(platformFile.path!);
        await _copyVideoFile(file); // 处理每个文件
      }
    } else {
      // 用户取消了选择
      print('用户取消了文件选择');
    }
  }

  Future<void> _pickVideoWithPersist() async {
    await _ensureVideoDirectoryExists();
    _diskThumbnails = DiskThumbnailCache(Directory(_thumbnailPath));
    _thumbnailLoader = null;
    // 创建实例
    final _platform = const MethodChannel('samples.flutter.dev/downloadplugin');
    // 调用方法 persistPermission
    String uriString = await _platform.invokeMethod<String>(
            'persistPermission', {
          "exts": '视频文件|.mp4,.mkv,.avi,.mov,.flv,.wmv,.webm,.rmvb,.wmv,.ts'
        }) ??
        '';

    // 检查是否选择了文件
    if (uriString.isNotEmpty) {
      // 分割多个URI
      List<String> uris = uriString.split('|||');

      // 处理每个URI
      for (String uri in uris) {
        String processedUri = uri;
        if (processedUri.startsWith('file://docs')) {
          // 删除file://docs并解析unicode码
          processedUri = Uri.decodeFull(processedUri.substring(11));
        }

        // 为每个选中的文件创建链接
        await _createLinkFile(processedUri);
      }
    } else {
      // 用户取消了选择
      print('用户取消了文件选择');
    }
  }

  Future<void> _pickVideoWithFileManager(BuildContext context) async {
    await _ensureVideoDirectoryExists();
    _diskThumbnails = DiskThumbnailCache(Directory(_thumbnailPath));
    _thumbnailLoader = null;

    // 显示美观的对话框
    bool shouldProceed = await _showImportInfoDialog(context);

    if (shouldProceed) {
      // 创建实例
      final _platform =
          const MethodChannel('samples.flutter.dev/downloadplugin');
      // 调用方法
      await _platform.invokeMethod<String>('openFileManager');
    }
  }

  Future<bool> _showImportInfoDialog(BuildContext context) async =>
    await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('在文件管理器中导入'),
      content: const SingleChildScrollView(child: Text(
        '打开文件管理器后，将视频复制到：\nDownloads/com.aloereed.aloeplayer/Videos\n\n'
        '音频请放到：\nDownloads/com.aloereed.aloeplayer/Audios\n\n'
        '完成后返回 AloePlayer，下拉刷新即可看到文件。若不想复制，请返回选择“添加快捷方式”。')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('返回')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('打开文件管理器'))],
    )) ?? false;

  Future<void> _createLinkFile(String uri) async {
    final fileName = path.basename(uri + ".lnk");
    final destinationPath = path.join(_currentPath, fileName);
    final destinationFile = File(destinationPath);
    bool deleteIfError = true;

    try {
      // 检查destinationPath是否已存在
      if (await destinationFile.exists()) {
        deleteIfError = false;
        throw FileSystemException(
          "文件已存在",
          destinationPath,
        );
      }
      // 向destinationFile写入uri
      await destinationFile.writeAsString(uri);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('快捷方式已添加，视频未复制，原文件请保留在当前位置')));
    } catch (e) {
      print("链接文件文件创建失败: $e");

      // 显示复制失败的Toast
      Fluttertoast.showToast(
        msg: "链接文件文件创建失败: $e",
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

  // 使用image_picker选择视频文件
  Future<void> _pickVideoWithImagePicker() async {
    await _ensureVideoDirectoryExists();
    _diskThumbnails = DiskThumbnailCache(Directory(_thumbnailPath));
    _thumbnailLoader = null;
    final picker = ImagePicker();
    final List<XFile> files =
        await picker.pickMultipleVideo(source: ImageSource.gallery);
    for (XFile? file in files) {
      if (file != null) {
        await _copyVideoFile(file);
      }
    }
  }

  Future<void> _copyVideoFile(XFile file) async {
    final fileName = path.basename(file.path);
    final destinationPath = path.join(_currentPath, fileName);
    final destinationFile = File(destinationPath);
    if (await destinationFile.exists()) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('媒体库已存在“$fileName”，已跳过复制')));
      return;
    }
    if (!mounted) return;
    final progress = ValueNotifier<double?>(null);
    final navigator = Navigator.of(context, rootNavigator: true);
    final dialog = DialogRoute<void>(context: context, barrierDismissible: false,
      builder: (_) => PopScope(canPop: false, child: AlertDialog(
        title: const Text('正在复制到媒体库'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(fileName, maxLines: 2, overflow: TextOverflow.ellipsis), const SizedBox(height: 20),
          ValueListenableBuilder<double?>(valueListenable: progress, builder: (_, value, __) => Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [LinearProgressIndicator(value: value),
              const SizedBox(height: 10), Text(value == null ? '准备复制…' : '${(value * 100).toStringAsFixed(0)}%')],
          )),
          const SizedBox(height: 16), const Text('原文件会保留。大文件复制需要一些时间。'),
          const SizedBox(height: 8), Text(destinationPath.replaceFirst('/storage/Users/currentUser/Download/', 'Downloads/'),
            style: Theme.of(context).textTheme.bodySmall),
        ]),
      )));
    unawaited(navigator.push(dialog));
    try {
      final length = await File(file.path).length();
      var copied = 0;
      var updated = DateTime.now();
      final input = File(file.path).openRead().map((bytes) {
        copied += bytes.length;
        if (DateTime.now().difference(updated).inMilliseconds >= 100) {
          progress.value = length == 0 ? null : (copied / length).clamp(0.0, 1.0);
          updated = DateTime.now();
        }
        return bytes;
      });
      await input.pipe(destinationFile.openWrite());
      progress.value = 1;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制到媒体库，原文件保留')));
    } catch (_) {
      if (await destinationFile.exists()) await destinationFile.delete();
      rethrow;
    } finally {
      if (dialog.isActive) navigator.removeRoute(dialog);
      // Let the dialog unmount before disposing its progress notifier.
      WidgetsBinding.instance.addPostFrameCallback((_) => progress.dispose());
      if (mounted) await _loadItems();
    }
  }

  // 在删除视频方法中也应用筛选刷新
  Future<bool> _deleteVideoFile(File file) async {
    try { await file.delete(); }
    catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('删除失败，请检查文件访问权限')));
      return false;
    }
    try { await _favoritesDb.removeFavorite(file.path); } catch (_) {}
    _favoriteStatus.remove(file.path);
    _durationCache.remove(file.path); _hdrCache.remove(file.path);
    _videoFiles.removeWhere((item) => item.path == file.path);
    _allItems.removeWhere((item) => item is File && item.path == file.path);
    _filteredItems.removeWhere((item) => item is File && item.path == file.path);
    if (mounted) setState(() {});
    return true;
  }

  // 获取视频缩略图
  Future<Uint8List?> _getVideoThumbnail(File file) {
    return _pendingThumbnails.putIfAbsent(file.path, () => _thumbnailQueue.run(() => _loadVideoThumbnail(file)).whenComplete(() { _pendingThumbnails.remove(file.path); }));
  }

  Future<Uint8List?> _loadVideoThumbnail(File file) async {
    if (disableThumbnail) return null;
    try {
      await _activateShortcut(file);
      _thumbnailLoader ??= VideoThumbnailLoader(
        disk: _diskThumbnails, memory: _thumbnailCache,
        library: Directory(_videoDirPath),
        decode: (source) => VideoThumbnailOhos.thumbnailData(
          video: source, imageFormat: ImageFormat.JPEG, maxWidth: 256, quality: 60),
        fallbackDecode: (source) async {
          const platform = MethodChannel('samples.flutter.dev/ffmpegplugin');
          final encoded = await platform.invokeMethod<String>('getVideoThumbnailFallback', {'path': source});
          return encoded == null || encoded.isEmpty ? null : base64Decode(encoded);
        },
        validateCached: (bytes) async {
          final codec = await instantiateImageCodec(bytes, targetWidth: 16, targetHeight: 16);
          try { final frame = await codec.getNextFrame(); frame.image.dispose(); return true; }
          finally { codec.dispose(); }
        },
      );
      return await _thumbnailLoader!.load(file);
    } catch (_) { return null; }
  }

  /// 检查视频文件是否为HDR格式
  Future<bool> _getHdr(File file) async {
    if (disableThumbnail) {
      return false;
    }
    try {
      await _activateShortcut(file);
      String filePath = file.path;
      if (_hdrCache.containsKey(filePath)) {
        return _hdrCache[filePath] ?? false;
      }
      // 调用原生方法获取HDR信息的JSON字符串
      if (file.path.endsWith('.lnk')) {
        // 读取文件内容
        filePath = await file.readAsString();
      }
      final _ffmpegplatform =
          const MethodChannel('samples.flutter.dev/ffmpegplugin');
      int getHdrMethod = await _settingsService.getHdrDetect();
      if (getHdrMethod == 0) {
        _hdrCache[file.path] = false;
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
        _hdrCache[file.path] = false;
        return false;
      }

      // 解析JSON字符串
      try {
        final Map<String, dynamic> data = json.decode(hdrJson);

        // 提取isHDR字段
        final bool isHdr = data['isHDR'] ?? false;

        print('视频HDR状态: ${isHdr ? "是HDR" : "非HDR"}');
        _hdrCache[file.path] = isHdr;
        return isHdr;
      } catch (e) {
        print('解析HDR JSON出错: $e');
        print('原始JSON: $hdrJson');
        _hdrCache[file.path] = false;
        return false;
      }
    } catch (e) {
      print('获取HDR信息时发生错误: $e');
      _hdrCache[file.path] = false;
      return false;
    }
  }

  // 获取视频时长
  Future<Duration> _getVideoDuration(File file) async {
    if (disableThumbnail) {
      return Duration.zero;
    }
    // // 创建 MediaInfo 实例
    // MediaInfo mediaInfo = MediaInfo();

    // // 获取视频文件的元数据
    // Map<String, dynamic> metadata = await mediaInfo.getMediaInfo(file.path);

    // // 从元数据中提取视频时长
    // int durationInMilliseconds = metadata['durationMs'];
    String filePath = file.path;
    String realFilePath = file.path;
    if (_durationCache.containsKey(filePath)) {
      return _durationCache[filePath] ?? Duration.zero;
    }
    // 检查file是否是".lnk"文件
    if (file.path.endsWith('.lnk')) {
      // 读取文件内容
      realFilePath = await file.readAsString();
      await _activateShortcut(file);
    }
    final _platform = const MethodChannel('samples.flutter.dev/ffmpegplugin');
    // 调用方法 getBatteryLevel
    final result = await _platform
        .invokeMethod<int>('getVideoDurationMs', {"path": realFilePath});

    // 将毫秒转换为 Duration 对象
    Duration duration = Duration(milliseconds: result ?? 0);
    _durationCache[filePath] = duration;

    return duration;
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

  // 获取文件大小
  String _getFileSize(File file) {
    if (file.path.endsWith('.lnk')) return '快捷方式';
    final sizeInBytes = _fileSizes[file.path];
    if (sizeInBytes == null) return '—';
    if (sizeInBytes < 1024) {
      return '$sizeInBytes B';
    } else if (sizeInBytes < 1024 * 1024) {
      return '${(sizeInBytes / 1024).toStringAsFixed(2)} KB';
    } else {
      return '${(sizeInBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
  }

  String _getFileDate(File file) {
    final fileDate = _modifiedTimes[file.path];
    if (fileDate == null) return '—';
    final now = DateTime.now();
    final difference = now.difference(fileDate);
    if (difference.inDays > 30) {
      return '${fileDate.year}/${fileDate.month}/${fileDate.day}';
    }
    if (difference.inDays > 0) {
      return '${difference.inDays}天前';
    }
    if (difference.inHours > 0) {
      return '${difference.inHours}小时前';
    }
    if (difference.inMinutes > 0) {
      return '${difference.inMinutes}分钟前';
    }
    return '刚刚';
  }

  void _openWebDavFileManager(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return WebDAVDialog(onLoadFiles: _loadItems, fileExts: [
          'mp4',
          'mkv',
          'avi',
          'mov',
          'flv',
          'wmv',
          'webm',
          'rmvb',
          'wmv',
          'ts'
        ]);
      },
    );
  }

  Widget _buildSortMenuItem(
    BuildContext context,
    String title,
    SortType type,
    SortOrder order,
  ) {
    bool isSelected = _currentSortType == type &&
        (type == SortType.none || _currentSortOrder == order);

    return InkWell(
      onTap: () {
        Navigator.pop(context);
        setState(() {
          _currentSortType = type;
          _currentSortOrder = order;
          saveSortOrder(_currentSortOrder);
          saveSortType(_currentSortType);
          _sortItems();
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 20,
              width: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? Theme.of(context).primaryColor
                    : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? Theme.of(context).primaryColor
                      : Theme.of(context).brightness == Brightness.dark
                          ? Colors.white70
                          : Colors.black54,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
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
    final desktop = Provider.of<ThemeProvider>(context).pcMode && MediaQuery.sizeOf(context).width >= 840;
    final theme = Theme.of(context);
    return CallbackShortcuts(bindings: {
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): () => _searchFocusNode.requestFocus(),
    }, child: WillPopScope(onWillPop: () async {
      if (_isMultiSelectMode) { setState(() { _isMultiSelectMode = false; _selectedItems.clear(); }); return false; }
      if (_videoDirPath != _currentPath) { _navigateUp(); return false; }
      return true;
    }, child: Scaffold(
      appBar: AppBar(
        leading: _currentPath != _videoDirPath ? IconButton(tooltip: '返回上一级', onPressed: _navigateUp, icon: const Icon(Icons.arrow_back)) : null,
        title: Text(_currentPath == _videoDirPath ? '视频库' : path.basename(_currentPath), maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [IconButton(tooltip: '刷新视频库', onPressed: _loadItems, icon: const Icon(Icons.refresh_rounded)),
          if (desktop) Padding(padding: const EdgeInsets.only(right: 20), child: FilledButton.icon(
            onPressed: () => _showAddOptionsDialog(context), icon: const Icon(Icons.add), label: const Text('添加视频')))],
      ),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), child: TextField(
          controller: _searchTextController, focusNode: _searchFocusNode, onChanged: _filterItems,
          decoration: InputDecoration(hintText: '搜索当前文件夹', prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _searchQuery.isEmpty ? null : IconButton(tooltip: '清除搜索', onPressed: () {
              _searchTextController.clear(); _filterItems('');
            }, icon: const Icon(Icons.close)),
            filled: true, fillColor: theme.colorScheme.surfaceContainerLow,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)),
        )),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Row(children: [
          if (_isMultiSelectMode) ...[
            Expanded(child: Text('已选择 ${_selectedItems.length} 项')),
            IconButton(tooltip: '删除选中项目', onPressed: _selectedItems.isEmpty ? null : _showDeleteConfirmationDialog, icon: const Icon(Icons.delete_outline)),
            IconButton(tooltip: '退出多选', onPressed: () => setState(() { _isMultiSelectMode = false; _selectedItems.clear(); }), icon: const Icon(Icons.close)),
          ] else ...[
            FilterChip(label: const Text('收藏'), avatar: const Icon(Icons.favorite_border, size: 18), selected: _showOnlyFavorites,
              onSelected: (value) => setState(() { _showOnlyFavorites = value; _applyFavoritesFilter(); })),
            const SizedBox(width: 8), Expanded(child: Text('${_filteredItems.length} 项', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall)),
            IconButton(tooltip: _isGridView ? '切换列表视图' : '切换网格视图', icon: Icon(_isGridView ? Icons.view_list_outlined : Icons.grid_view_rounded),
              onPressed: () => setState(() => _isGridView = !_isGridView)),
            PopupMenuButton<String>(tooltip: '排序方式', icon: const Icon(Icons.sort_rounded),
              onSelected: (value) => setState(() {
                if (value == 'direction') _currentSortOrder = _currentSortOrder == SortOrder.ascending ? SortOrder.descending : SortOrder.ascending;
                else _currentSortType = SortType.values.firstWhere((type) => type.name == value);
                _sortItems();
              }), itemBuilder: (_) => [
                for (final type in SortType.values) CheckedPopupMenuItem(value: type.name, checked: _currentSortType == type, child: Text(_getSortTypeName(type))),
                const PopupMenuDivider(), PopupMenuItem(value: 'direction', child: Text(_currentSortOrder == SortOrder.ascending ? '改为降序' : '改为升序')),
              ]),
            IconButton(tooltip: '多选管理', onPressed: () => setState(() { _isMultiSelectMode = true; _selectedItems.clear(); }), icon: const Icon(Icons.checklist_rounded)),
          ],
        ])),
        if (_libraryError != null) Padding(padding: const EdgeInsets.all(16), child: Text(_libraryError!, style: TextStyle(color: theme.colorScheme.error))),
        Expanded(child: _isLoading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(
          onRefresh: _loadItems, child: _filteredItems.isEmpty
            ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: [Padding(padding: const EdgeInsets.symmetric(vertical: 60), child: _buildEmptyStateView())])
            : _isGridView ? _buildGridView() : _buildListView())),
      ]),
      floatingActionButton: desktop || _isMultiSelectMode ? null : _buildSpeedDial(),
    )));
  }

  String _getSortTypeName(SortType type) {
    switch (type) {
      case SortType.name:
        return '按名称';
      case SortType.modifiedDate:
        return '按时间';
      default:
        return '默认';
    }
  }

  Future<void> _showAddOptionsDialog(BuildContext context) async {
    final destination = _currentPath.replaceFirst('/storage/Users/currentUser/Download/', 'Downloads/');
    final action = await showLocalImportSheet(context, destination: destination);
    if (!mounted || action == null) return;
    try {
      switch (action) {
        case LocalImportAction.copy: await _pickVideoWithFilePicker();
        case LocalImportAction.shortcut: await _pickVideoWithPersist();
        case LocalImportAction.gallery: await _pickVideoWithImagePicker();
        case LocalImportAction.fileManager: await _pickVideoWithFileManager(context);
        case LocalImportAction.folder: await _createNewFolder(context);
        case LocalImportAction.webdav: _openWebDavFileManager(context);
        case LocalImportAction.playFile: await _openFile();
        case LocalImportAction.playUrl: _showUrlDialog(context);
        case LocalImportAction.history:
          await Navigator.push(context, MaterialPageRoute(builder: (_) => HistoryPage(
            getOpenFile: widget.getopenfile, startPlayerPage: widget.startPlayerPage)));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未能完成添加，请检查文件权限和剩余空间后重试')));
    }
  }

  Widget _buildEmptyStateView() {
    final filtered = _searchQuery.isNotEmpty || _showOnlyFavorites;
    return Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(filtered ? Icons.search_off_rounded : Icons.video_library_outlined, size: 64, color: Theme.of(context).colorScheme.primary),
      const SizedBox(height: 20), Text(filtered ? '没有匹配的视频' : '添加你的第一部视频', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12), Text(filtered ? '试试其他关键词，或清除筛选条件。' : '复制到媒体库，或创建不占视频空间的快捷方式。',
        textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 24), FilledButton.icon(onPressed: filtered ? () {
        _searchTextController.clear(); setState(() { _searchQuery = ''; _showOnlyFavorites = false; _applyFavoritesFilter(); });
      } : () => _showAddOptionsDialog(context), icon: Icon(filtered ? Icons.filter_alt_off_outlined : Icons.add),
        label: Text(filtered ? '清除筛选' : '添加视频')),
    ]));
  }

  void _showDeleteConfirmationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('确认删除'),
        content: Text('确定要删除选中的${_selectedItems.length}个项目吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteSelectedItems();
            },
            child: Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _deleteSelectedItems() async {
    // 复制一份，避免在迭代过程中修改集合
    final itemsToDelete = Set<FileSystemEntity>.from(_selectedItems);

    for (var item in itemsToDelete) {
      try {
        await item.delete(recursive: item is Directory);
      } catch (e) {
        // 处理删除错误
        print('删除失败: $e');
      }
    }

    // 更新界面
    setState(() {
      _isMultiSelectMode = false;
      _selectedItems.clear();
      // 刷新文件列表（假设你有一个刷新文件列表的函数）
      _refreshFileList();
    });

    // 显示删除成功提示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已删除${itemsToDelete.length}个项目')),
    );
  }

// 刷新文件列表的函数（如果你还没有这个函数）
  void _refreshFileList() {
    // 根据你的应用逻辑重新加载文件列表
    _loadItems();
  }

  Widget _buildGridView() => LayoutBuilder(builder: (context, box) {
    final desktop = Provider.of<ThemeProvider>(context).pcMode;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final gap = desktop ? 16.0 : 12.0;
    final minimum = (desktop ? 220.0 : 132.0) * scale.clamp(1.0, 1.6);
    final columns = ((box.maxWidth - 32 + gap) / (minimum + gap)).floor().clamp(1, 8);
    final tileWidth = (box.maxWidth - 32 - gap * (columns - 1)) / columns;
    return Column(children: [
      if (_isMultiSelectMode) _selectionSummary(),
      Expanded(child: GridView.builder(cacheExtent: 500, key: const PageStorageKey('video-grid'),
        physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, crossAxisSpacing: gap,
          mainAxisSpacing: gap, mainAxisExtent: tileWidth * 9 / 16 + 48 * scale + 44),
        itemCount: _filteredItems.length, itemBuilder: (context, index) {
          final file = _filteredItems[index];
          final card = file is Directory ? _buildFolderCard(file) : _buildVideoCard(file);
          return _isMultiSelectMode ? _wrapWithCheckbox(card, file) : card;
        })),
    ]);
  });
  Widget _selectionSummary() => Row(children: [
    Checkbox(value: _selectedItems.length == _filteredItems.length && _filteredItems.isNotEmpty,
      onChanged: (all) => setState(() { _selectedItems = all == true ? Set.from(_filteredItems) : {}; })),
    const Text('全选'),
  ]);

  Widget _buildListView() {
    return AnimatedSwitcher(
      duration: Duration(milliseconds: 300),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: Column(
        children: [
          if (_isMultiSelectMode)
            Padding(
              padding: EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Checkbox(
                    value: _selectedItems.length == _filteredItems.length &&
                        _filteredItems.isNotEmpty,
                    tristate: _selectedItems.isNotEmpty &&
                        _selectedItems.length < _filteredItems.length,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selectedItems = Set.from(_filteredItems);
                        } else {
                          _selectedItems.clear();
                        }
                      });
                    },
                  ),
                  Text('全选'),
                  Spacer(),
                  Text('已选择 ${_selectedItems.length} 项'),
                ],
              ),
            ),
          Expanded(
            child: ListView.builder(
              cacheExtent: 500,
              key: ValueKey<String>('list'),
              padding: EdgeInsets.symmetric(vertical: 8),
              itemCount: _filteredItems.length,
              itemBuilder: (context, index) {
                final file = _filteredItems[index];
                Widget item;
                if (file is Directory) {
                  item = _buildFolderListItem(file);
                } else {
                  item = _buildVideoCard(file, isListView: true);
                }

                if (_isMultiSelectMode) {
                  return _wrapWithListCheckbox(item, file);
                } else {
                  return item;
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _wrapWithCheckbox(Widget child, FileSystemEntity file) {
    final isSelected = _selectedItems.contains(file);

    return Stack(
      fit: StackFit.expand, // 确保 Stack 填满整个空间
      children: [
        GestureDetector(
          onTap: () {
            // 点击时切换选中状态
            setState(() {
              if (isSelected) {
                _selectedItems.remove(file);
              } else {
                _selectedItems.add(file);
              }
            });
          },
          child: IgnorePointer(child: child),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.8),
              shape: BoxShape.circle,
            ),
            child: Checkbox(
              value: isSelected,
              onChanged: (value) {
                setState(() {
                  if (value == true) {
                    _selectedItems.add(file);
                  } else {
                    _selectedItems.remove(file);
                  }
                });
              },
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
      ],
    );
  }

  Widget _wrapWithListCheckbox(Widget child, FileSystemEntity file) {
    return Row(
      children: [
        // 添加左侧复选框
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 8.0),
          child: Checkbox(
            value: _selectedItems.contains(file),
            onChanged: (value) {
              setState(() {
                if (value == true) {
                  _selectedItems.add(file);
                } else {
                  _selectedItems.remove(file);
                }
              });
            },
          ),
        ),
        // 原始的列表项占据剩余空间
        Expanded(
          child: GestureDetector(onTap: () => setState(() {
            if (!_selectedItems.remove(file)) _selectedItems.add(file);
          }), child: IgnorePointer(child: child)),
        ),
      ],
    );
  }

// 添加弹出菜单的方法
  Widget _buildFolderCard(Directory directory) {
    final folderName = path.basename(directory.path);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isPcMode = themeProvider.pcMode;

    Widget cardContent(bool isHovered) {
      return Card(
        // Match the file tile bounds; grid spacing is provided by the grid.
        margin: EdgeInsets.zero,
        elevation: isHovered ? 8 : 2,
        shadowColor: isHovered ? Colors.black45 : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        child: Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
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
                size: isPcMode ? 60 : 50,
                color: Colors.white,
              ),
              SizedBox(height: 8),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(22),
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
      );
    }

    if (isPcMode) {
      return HoverableBuilder(builder: (context, isHovered) {
        return Hero(
          tag: 'folder-${directory.path}',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                _navigateToDirectory(directory);
              },
              onLongPress: () {
                _showFolderOptions(directory);
              },
              onSecondaryTap: () {
                _showFolderOptions(directory);
              },
              borderRadius: BorderRadius.circular(22),
              child: cardContent(isHovered),
            ),
          ),
        );
      });
    }

    return Hero(
      tag: 'folder-${directory.path}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            _navigateToDirectory(directory);
          },
          onLongPress: () {
            _showFolderOptions(directory);
          },
          borderRadius: BorderRadius.circular(22),
          child: cardContent(false),
        ),
      ),
    );
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
                  // setState(() {});
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

  Widget _buildFolderListItem(Directory directory) {
    final folderName = path.basename(directory.path);

    return Hero(
      tag: 'folder-${directory.path}',
      child: Card(
        margin: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
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

  Future<VideoTileInfo> _tileInfo(File file) => _pendingTileInfo.putIfAbsent(file.path,
    () => _metadataQueue.run(() => _loadTileInfo(file)).whenComplete(() { _pendingTileInfo.remove(file.path); }));

  Future<VideoTileInfo> _loadTileInfo(File file) async {
    if (!mounted) return const VideoTileInfo();
    try {
      final duration = await _getVideoDuration(file);
      final history = await historyService.getHistoryByPath(file.path);
      final hdr = await _getHdr(file);
      final progress = history == null || duration.inMilliseconds <= 0 ? 0.0
        : (history.lastPosition / duration.inMilliseconds).clamp(0.0, 1.0);
      return VideoTileInfo(duration: duration, progress: progress, hdr: hdr);
    } catch (_) { return const VideoTileInfo(); }
  }
  Widget _buildVideoCard(File file, {bool isListView = false}) => RepaintBoundary(child: VideoLibraryTile(
    key: ValueKey(file.path), name: path.basename(file.path).replaceFirst(RegExp(r'\.lnk$'), ''),
    details: _getFileSize(file), list: isListView, shortcut: file.path.endsWith('.lnk'),
    favorite: _favoriteStatus[file.path] ?? false,
    thumbnail: _getVideoThumbnail(file), info: _tileInfo(file),
    onPlay: () { widget.getopenfile(file.path); widget.startPlayerPage(context); },
    onOptions: () => _showVideoOptionsBottomSheet(file), onFavorite: () => _toggleFavorite(file),
  ));

  Future<void> _regenerateThumbnail(File file) async {
    if (disableThumbnail) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先在设置中开启缩略图')));
      return;
    }
    try {
      await _pendingThumbnails[file.path];
      await _thumbnailLoader?.invalidate(file);
      final bytes = await _getVideoThumbnail(file);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
        bytes == null ? '暂时无法提取缩略图，请确认原文件仍可访问' : '缩略图已更新')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('缩略图更新失败，可稍后重试')));
    }
  }

  Future<void> _showVideoOptionsBottomSheet(File file) async {
    final action = await showVideoFileActions(context,
      name: path.basename(file.path).replaceFirst(RegExp(r'\.lnk$'), ''),
      details: '${_getFileSize(file)} · ${_getFileDate(file)}', thumbnail: _getVideoThumbnail(file),
      favorite: _favoriteStatus[file.path] ?? false, shortcut: file.path.endsWith('.lnk'), conversionBusy: isFFmpeged);
    if (!mounted || action == null) return;
    try {
      switch (action) {
        case VideoFileAction.play:
          widget.getopenfile(file.path); widget.startPlayerPage(context);
        case VideoFileAction.favorite: await _toggleFavorite(file);
        case VideoFileAction.refreshThumbnail: await _regenerateThumbnail(file);
        case VideoFileAction.convert: _showConvertToMp4Dialog(file);
        case VideoFileAction.extractSubtitle:
          await _activateShortcut(file);
          if (mounted) _showExtractSubtitleDialog(file);
        case VideoFileAction.extractAudio:
          await _activateShortcut(file);
          if (mounted) _showExtractAudioTrackDialog(file);
        case VideoFileAction.share:
        case VideoFileAction.cast:
          await _activateShortcut(file);
          final source = file.path.endsWith('.lnk') ? (await file.readAsString()).trim() : file.path;
          if (!mounted) return;
          if (action == VideoFileAction.share) { await Share.shareXFiles([XFile(source)]); }
          else { await Navigator.push(context, MaterialPageRoute(builder: (_) => CastScreenPage(mediaPath: source))); }
        case VideoFileAction.delete: _showDeleteConfirmDialog(file);
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法完成操作，请检查文件访问权限后重试')));
    }
  }

  void _showConvertToMp4Dialog(File file) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.file_download, color: Colors.blue),
              SizedBox(width: 10),
              Text('转换为MP4'),
            ],
          ),
          content: Text('确定要转换该视频为MP4格式吗？这可能需要一些时间。'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: Text('取消', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);

                // Show progress dialog
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(height: 16),
                          CircularProgressIndicator(),
                          SizedBox(height: 24),
                          Text('正在启动视频转换...'),
                          SizedBox(height: 8),
                          Text(
                            '请保持应用在前台运行',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    );
                  },
                );

                try {
                  final _platform =
                      const MethodChannel('samples.flutter.dev/ffmpegplugin');
                  if (file.path.endsWith('.lnk')) {
                    Navigator.pop(context);
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16.0),
                          ),
                          title: const Text(
                            '暂不支持链接文件',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          content: const Text(
                            '当前暂不支持处理链接文件 (.lnk)，请选择其他文件。',
                            style: TextStyle(
                              fontSize: 16,
                            ),
                          ),
                          actions: <Widget>[
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                              child: const Text(
                                '确定',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.blue,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                    return;
                  }
                  final result = await _platform
                      .invokeMethod<String>('tomp4', {"path": file.path});

                  setState(() {
                    // isFFmpeged = true;
                  });

                  // Close progress dialog
                  Navigator.pop(context);

                  // Show success dialog
                  showDialog(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        title: Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.green),
                            SizedBox(width: 10),
                            Text('转换已启动'),
                          ],
                        ),
                        content: Text('视频转换为MP4格式已启动，请保持前台运行，并自行到库文件夹检查结果。'),
                        actions: [
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                            },
                            child: Text('确定',
                                style: TextStyle(
                                    color: Theme.of(context).primaryColor)),
                          ),
                        ],
                      );
                    },
                  );
                } catch (e) {
                  // Close progress dialog
                  Navigator.pop(context);

                  // Show error dialog
                  showDialog(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        title: Row(
                          children: [
                            Icon(Icons.error, color: Colors.red),
                            SizedBox(width: 10),
                            Text('转换失败'),
                          ],
                        ),
                        content: Text('视频转换失败: $e'),
                        actions: [
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                            },
                            child: Text('确定',
                                style: TextStyle(
                                    color: Theme.of(context).primaryColor)),
                          ),
                        ],
                      );
                    },
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                '开始转换',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showExtractSubtitleDialog(File file) {
    String filePath = file.path;
    if (filePath.endsWith('.lnk')) {
      filePath = file.readAsStringSync();
    }
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: AlertDialog(
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey[900]!.withOpacity(0.9)
                : Colors.white.withOpacity(0.9),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(Icons.subtitles, color: Theme.of(context).primaryColor),
                SizedBox(width: 12),
                Text('抽取内挂字幕', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: FutureBuilder<Map<int, String>>(
              future: _getSubtitleTracks(filePath),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('正在解析字幕轨道...'),
                      ],
                    ),
                  );
                } else if (snapshot.hasError) {
                  return Text('解析字幕轨道时出错: ${snapshot.error}');
                } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Text('未找到字幕轨道');
                } else {
                  return _SubtitleTracksSelector(
                    subtitleTracks: snapshot.data!,
                    file: file,
                    onExtractComplete: () {
                      Navigator.pop(context);
                      _showSuccessDialog();
                    },
                    onError: (error) {
                      Navigator.pop(context);
                      _showErrorDialog(error);
                    },
                    settingsService: _settingsService,
                  );
                }
              },
            ),
          ),
        );
      },
    );
  }

  void _showExtractAudioTrackDialog(File file) async {
    // 获取音轨信息
    String realFilePath = file.path;
    if (file.path.endsWith('.lnk')) {
      realFilePath = file.readAsStringSync();
    }
    final _ffmpegplatform =
        const MethodChannel('samples.flutter.dev/ffmpegplugin');
    // print("[ffprobe] getaudio" +
    //     (await _ffmpegplatform.invokeMethod<String>(
    //             'getAudioTracks', {'path': widget.openfile}) ??
    //         ''));
    // print("[ffprobe] gethdr");
    final audiotrackjson = await _ffmpegplatform
            .invokeMethod<String>('getAudioTracks', {'path': realFilePath}) ??
        '';
    final Map<int, String> audioTrackInfo = parseAudioTracks(audiotrackjson);
    // 默认选择第一个可用的音轨（如果有）
    int selectedTrack =
        audioTrackInfo.isNotEmpty ? audioTrackInfo.keys.first : -1;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;

        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: AlertDialog(
            backgroundColor: isDarkMode
                ? Colors.grey[850]!.withOpacity(0.9)
                : Colors.white.withOpacity(0.9),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(Icons.music_note, color: Theme.of(context).primaryColor),
                SizedBox(width: 12),
                Text('抽取音轨', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: StatefulBuilder(
                builder: (BuildContext context, StateSetter setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('请选择要抽取的音轨：'),
                  SizedBox(height: 16),
                  if (audioTrackInfo.isEmpty)
                    Text('未检测到音轨',
                        style: TextStyle(
                            color: Colors.red, fontWeight: FontWeight.bold))
                  else
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: isDarkMode
                                ? Colors.grey[700]!
                                : Colors.grey[300]!),
                        color: isDarkMode
                            ? Colors.grey[800]!.withOpacity(0.7)
                            : Colors.white.withOpacity(0.7),
                      ),
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: selectedTrack,
                          isExpanded: true,
                          dropdownColor:
                              isDarkMode ? Colors.grey[800] : Colors.white,
                          icon: Icon(Icons.arrow_drop_down,
                              color: Theme.of(context).primaryColor),
                          items: audioTrackInfo.entries.map((entry) {
                            return DropdownMenuItem<int>(
                              value: entry.key,
                              child: Text(
                                "轨道 ${entry.key}: ${entry.value}",
                                style: TextStyle(
                                  color:
                                      isDarkMode ? Colors.white : Colors.black,
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (int? newValue) {
                            if (newValue != null) {
                              setState(() {
                                selectedTrack = newValue;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                  SizedBox(height: 16),
                  Text('确定要抽取该视频的音轨吗（本功能极其不稳定）？',
                      style: TextStyle(
                          color: isDarkMode
                              ? Colors.grey[400]
                              : Colors.grey[600])),
                ],
              );
            }),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: Text('取消',
                    style: TextStyle(
                        color: isDarkMode ? Colors.grey[400] : Colors.grey)),
              ),
              ElevatedButton(
                onPressed: audioTrackInfo.isEmpty
                    ? null
                    : () async {
                        Navigator.pop(context);
                        // 显示进度对话框
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (BuildContext context) {
                            final innerIsDarkMode =
                                Theme.of(context).brightness == Brightness.dark;
                            return BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: AlertDialog(
                                backgroundColor: innerIsDarkMode
                                    ? Colors.grey[850]!.withOpacity(0.9)
                                    : Colors.white.withOpacity(0.9),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(height: 20),
                                    CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Theme.of(context).primaryColor),
                                    ),
                                    SizedBox(height: 24),
                                    Text(
                                      '正在抽取音频轨道 $selectedTrack: ${audioTrackInfo[selectedTrack] ?? ""}...',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w500),
                                    ),
                                    SizedBox(height: 10),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                        try {
                          final _platform = const MethodChannel(
                              'samples.flutter.dev/ffmpegplugin');
                          String filePath = file.path;
                          String realFilePath = file.path;
                          if (file.path.endsWith('.lnk')) {
                            realFilePath = file.readAsStringSync();
                          }
                          await _platform
                              .invokeMethod<String>('getaudiotrack', {
                            "path": realFilePath,
                            "track": selectedTrack - 1, // 直接传入轨道号，而不是索引
                            "output": filePath
                          });
                          // 关闭进度对话框
                          Navigator.pop(context);
                          // 显示成功对话框
                          _showSuccessDialog();
                        } catch (e) {
                          // 关闭进度对话框
                          Navigator.pop(context);
                          // 显示错误对话框
                          _showErrorDialog(e.toString());
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  disabledBackgroundColor:
                      isDarkMode ? Colors.grey[700] : Colors.grey[300],
                  disabledForegroundColor:
                      isDarkMode ? Colors.grey[500] : Colors.grey[500],
                ),
                child: Text(
                  '开始抽取',
                  style: TextStyle(
                      color: audioTrackInfo.isEmpty
                          ? (isDarkMode ? Colors.grey[500] : Colors.grey[500])
                          : Colors.white,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showLinkFileErrorDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: AlertDialog(
            backgroundColor: Colors.white.withOpacity(0.9),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(Icons.link_off, color: Colors.orange),
                SizedBox(width: 12),
                Text(
                  '暂不支持链接文件',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: Text(
              '当前暂不支持处理链接文件 (.lnk)，请选择其他文件。',
              style: TextStyle(fontSize: 16),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text(
                  '确定',
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).primaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: AlertDialog(
            backgroundColor: Colors.white.withOpacity(0.9),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 12),
                Text('开始抽取', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text('内挂轨道抽取已启动，请自行到库文件夹检查结果。'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: Text(
                  '确定',
                  style: TextStyle(
                    color: Theme.of(context).primaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showErrorDialog(String error) {
    showDialog(
      context: context,
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: AlertDialog(
            backgroundColor: Colors.white.withOpacity(0.9),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red),
                SizedBox(width: 12),
                Text('抽取失败', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('字幕抽取失败:'),
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    error,
                    style: TextStyle(fontFamily: 'monospace', fontSize: 14),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: Text(
                  '确定',
                  style: TextStyle(
                    color: Theme.of(context).primaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showDeleteConfirmDialog(File file) async {
    final shortcut = file.path.endsWith('.lnk');
    final fileName = path.basename(file.path).replaceFirst(RegExp(r'\.lnk$'), '');
    final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text(shortcut ? '移除快捷方式' : '删除视频'),
      content: SingleChildScrollView(child: Text(shortcut
        ? '移除“$fileName”的快捷方式？\n\n只移除链接，原视频文件保留。'
        : '删除“$fileName”？\n\n这个文件将从媒体库删除，无法撤销。')),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error,
          foregroundColor: Theme.of(context).colorScheme.onError),
          onPressed: () => Navigator.pop(dialogContext, true), child: Text(shortcut ? '移除链接' : '删除文件'))],
    ));
    if (confirmed != true || !mounted) return;
    if (await _deleteVideoFile(file) && mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(shortcut ? '快捷方式已移除，原视频保留' : '已删除：$fileName')));
  }

  Future<void> _openFile() async {
    // 使用 FilePicker 选择文件
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('请不要从"最近"选项卡中选择文件'),
        duration: Duration(seconds: 3),
      ),
    );
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
      widget.getopenfile(file.path!); // 更新_openfile状态
      widget.startPlayerPage(context);
    } else {
      // 用户取消了选择
      print('用户取消了文件选择');
    }
  }

  Widget _buildSpeedDial() => FloatingActionButton.extended(
    onPressed: () => _showAddOptionsDialog(context),
    icon: const Icon(Icons.add_rounded), label: const Text('添加视频'),
  );
  void _showUrlDialog(BuildContext context) {
    final TextEditingController urlController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Color(0xFF2C2C2C)
                  : Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.link,
                    size: 30,
                    color: Colors.lightBlue,
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  '打开网络媒体',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 20),
                TextField(
                  controller: urlController,
                  decoration: InputDecoration(
                    hintText: "请输入音视频URL",
                    prefixIcon: Icon(Icons.link),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: Colors.grey,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: Theme.of(context).primaryColor,
                        width: 2,
                      ),
                    ),
                  ),
                  style: TextStyle(
                    fontSize: 16,
                  ),
                  autofocus: true,
                ),
                SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      style: TextButton.styleFrom(
                        padding:
                            EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      ),
                      child: Text(
                        '取消',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        if (urlController.text.isNotEmpty) {
                          Navigator.of(context).pop();
                          widget.getopenfile(urlController.text);
                          widget.startPlayerPage(context);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        padding:
                            EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        '确认',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
