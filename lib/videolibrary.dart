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

// import 'mpvplayer.dart';
// import 'package:path/path.dart';
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
  Map<String, Uint8List?> _thumbnailCache = {};
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
    await initPreferences();
    bool useinnerthumb = await _settingsService.getUseInnerThumbnail();
    if (useinnerthumb) {
      // path join
      _thumbnailPath =
          path.join((await getTemporaryDirectory()).path, 'Thumbnails');
    }
    _ensureVideoDirectoryExists();
    setState(() async {
      _isGridView = !(await _settingsService.getDefaultListmode());
    });
    // _loadVideoFiles();
    _loadItems();
  }

  // 加载所有项目的收藏状态
  Future<void> _loadFavoriteStatus() async {
    for (var item in _allItems) {
      if (item is File) {
        bool isFav = await _favoritesDb.isFavorite(item.path);

        _favoriteStatus[item.path] = isFav;
      }
    }
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
          DateTime dateA = a.statSync().modified;
          DateTime dateB = b.statSync().modified;
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
    final directory = Directory(_currentPath);
    List<File> files = [];
    List<Directory> directories = [];

    disableThumbnail = await _settingsService.getDisableThumbnail();

    if (await directory.exists()) {
      final items = directory.listSync();
      for (var item in items) {
        if (item is File) {
          String extension = path.extension(item.path).toLowerCase();
          // 排除 .srt 和 .ass 文件
          if (extension != '.srt' &&
              extension != '.ass' &&
              extension != '.jpg' &&
              extension != '.png' &&
              extension != '.jpeg' &&
              extension != '.gif' &&
              extension != '.bmp' &&
              extension != '.aac' &&
              extension != '.pdf' &&
              !item.path.contains('.ux_store')) {
            if (extension == '.lnk') {
              // 作为string读取lnk文件为uri
              String uri = await item.readAsString();
              if (!uri.contains(':')) {
                uri = "file://docs" + uri;
                uri = Uri.parse(uri).toString();
              }
              _settingsService.activatePersistPermission(uri);
            }
            files.add(item);
          }
        } else if (item is Directory) {
          directories.add(item);
        }
      }
    }
    _videoFiles = files;
    _directories = directories;
    // _filteredItems = [...directories, ...files]; // 初始化时显示所有文件和文件夹
    _allItems = [...directories, ...files]; // 保存所有项目
    setState(() {
      // 根据筛选条件设置显示的项目
      _applyFavoritesFilter();
    });
    _sortItems(needRefresh: false);
    await _loadFavoriteStatus();
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

  Future<bool> _showImportInfoDialog(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
              child: Dialog(
                backgroundColor: Colors.white.withOpacity(0.9),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20.0),
                ),
                child: Container(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Colors.blue,
                        size: 48.0,
                      ),
                      const SizedBox(height: 16.0),
                      const Text(
                        "文件导入说明",
                        style: TextStyle(
                          fontSize: 22.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16.0),
                      const Text(
                        "使用文件管理器进行复制导入是最快捷和方便的方式：\n\n"
                        "• 在 /下载/AloePlayer/Videos 下可以复制导入视频\n"
                        "• 在 /下载/AloePlayer/Audios 下可以复制导入音频\n\n"
                        "由于开发者使用平板开发，平板端和手机端系统文件管理器的差别越来越大，使用应用内导入可能不稳定（例如不能导入\"最近\"里的视频会崩溃无法复现），尽情谅解。\n\n"
                        "导入后请下拉刷新。",
                        style: TextStyle(fontSize: 16.0),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24.0),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop(false);
                            },
                            child: const Text(
                              "取消",
                              style: TextStyle(fontSize: 16.0),
                            ),
                          ),
                          const SizedBox(width: 16.0),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).pop(true);
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24.0, vertical: 12.0),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30.0),
                              ),
                            ),
                            child: const Text(
                              "确定",
                              style: TextStyle(fontSize: 16.0),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ) ??
        false; // 如果对话框被异常关闭，默认返回false
  }

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
      print("文件创建完成: $destinationPath");
    } catch (e) {
      print("链接文件文件创建失败: $e");
      // 关闭对话框
      Navigator.of(context).pop();

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
    bool deleteIfError = true;
    // 显示加载对话框
    showDialog(
      context: context,
      barrierDismissible: false, // 用户不能通过点击外部关闭对话框
      builder: (BuildContext context) {
        return AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(
                color: Colors.lightBlue,
              ),
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
      print("文件复制完成: $destinationPath 从 ${file.path}");

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

  Future<void> _copyVideoFileWithProgress(XFile file) async {
    final fileName = path.basename(file.path);
    final destinationPath = path.join(_videoDirPath, fileName);
    final destinationFile = File(destinationPath);

    // 显示带有进度条的对话框
    showDialog(
      context: context,
      barrierDismissible: false, // 用户不能通过点击外部关闭对话框
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('复制文件中...'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(),
              SizedBox(height: 16),
              Text('正在复制: $fileName'),
            ],
          ),
        );
      },
    );

    try {
      final inputStream = File(file.path).openRead();
      final outputStream = destinationFile.openWrite();

      // 获取文件大小
      final fileSize = await File(file.path).length();
      int copiedBytes = 0;

      // 监听输入流，逐块写入输出流
      await inputStream.listen(
        (List<int> data) {
          outputStream.add(data);
          copiedBytes += data.length;
          // 更新进度
          double progress = copiedBytes / fileSize;
          // 更新对话框中的进度条
          Navigator.of(context).pop(); // 关闭之前的对话框
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext context) {
              return AlertDialog(
                title: Text('复制文件中...'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(value: progress),
                    SizedBox(height: 16),
                    Text(
                        '正在复制: $fileName (${(progress * 100).toStringAsFixed(1)}%)'),
                  ],
                ),
              );
            },
          );
        },
        onDone: () async {
          await outputStream.close();
          print("文件复制完成: $destinationPath");
          Navigator.of(context).pop(); // 关闭对话框
          _loadItems(); // 刷新视频列表
        },
        onError: (e) {
          print("文件复制失败: $e");
          if (destinationFile.existsSync()) {
            destinationFile.deleteSync();
          }
          Navigator.of(context).pop(); // 关闭对话框
          throw e;
        },
      ).asFuture();
    } catch (e) {
      print("文件复制失败: $e");
      if (await destinationFile.exists()) {
        await destinationFile.delete();
      }
      Navigator.of(context).pop(); // 关闭对话框
      // rethrow;
    }
  }

  // 在删除视频方法中也应用筛选刷新
  Future<void> _deleteVideoFile(File file) async {
    try {
      await file.delete();

      // 如果文件已收藏，从收藏中移除
      if (_favoriteStatus[file.path] ?? false) {
        await _favoritesDb.removeFavorite(file.path);
        setState(() {
          _favoriteStatus.remove(file.path);
        });
      }

      // 从所有项目和已筛选项目中移除
      setState(() {
        _allItems.removeWhere((item) => item is File && item.path == file.path);
        _filteredItems
            .removeWhere((item) => item is File && item.path == file.path);
      });
    } catch (e) {
      print("Error deleting file: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('删除文件失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // 获取视频缩略图
  Future<Uint8List?> _getVideoThumbnail(File file) async {
    if (disableThumbnail) {
      return null;
    }
    // 从file.path提取文件名
    String fileName = path.basename(file.path);
    String filePath = file.path;
    String realFilePath = file.path;
    if (_thumbnailCache.containsKey(filePath)) {
      return _thumbnailCache[filePath];
    }
    // 检查file是否是".lnk"文件
    if (file.path.endsWith('.lnk')) {
      // 读取文件内容
      realFilePath = await file.readAsString();
    }
    // 尝试读取$_thumbnailPath/$fileName.nothumbnail
    String thumbnailPath = '$_thumbnailPath/$fileName.nothumbnail';
    // 检查文件是否存在
    if (await File(thumbnailPath).exists()) {
      // 如果文件存在，则读取文件内容
      _thumbnailCache[filePath] = null;
      return null;
    }

    // 尝试读取$_thumbnailPath/$fileName.jpg
    thumbnailPath = '$_thumbnailPath/$fileName.jpg';
    // 检查文件是否存在
    if (await File(thumbnailPath).exists()) {
      // 如果文件存在，则读取文件内容为Uint8List
      final result = await File(thumbnailPath).readAsBytes();
      _thumbnailCache[filePath] = result;
      return result;
    }

    Uint8List? thumbnail;
    try {
      thumbnail = await VideoThumbnailOhos.thumbnailData(
        video: realFilePath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 128, // 缩略图的最大宽度
        quality: 25, // 缩略图的质量 (0-100)
      );
    } catch (e) {
      thumbnail = null;
      print("获取缩略图失败: $e");
    }
    _thumbnailCache[filePath] = thumbnail;

    try {
      // 保存缩略图到$_thumbnailPath/
      String thumbnailPath = '$_thumbnailPath/$fileName.jpg';
      // 将缩略图保存到文件
      File thumbnailFile = File(thumbnailPath);
      await thumbnailFile.writeAsBytes(thumbnail!);
    } catch (e) {
      // 写入一个空文件$_thumbnailPath/$fileName.nothumbnail
      String thumbnailPath = '$_thumbnailPath/$fileName.nothumbnail';
      // 将缩略图保存到文件
      File thumbnailFile = File(thumbnailPath);
      await thumbnailFile.writeAsBytes([]);
    }
    return thumbnail;
  }

  /// 检查视频文件是否为HDR格式
  Future<bool> _getHdr(File file) async {
    if (disableThumbnail) {
      return false;
    }
    try {
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
      final String hdrJson = await _ffmpegplatform
              .invokeMethod<String>('getVideoHDRInfo', {'path': filePath}) ??
          '';

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
      _settingsService.activatePersistPermission(pathToUri(realFilePath));
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
    String filePath = file.path;
    // 检查file是否是".lnk"文件
    if (file.path.endsWith('.lnk')) {
      // 读取文件内容
      filePath = file.readAsStringSync();
      _settingsService.activatePersistPermission(pathToUri(filePath));
    }
    final sizeInBytes = File(filePath).lengthSync();
    if (sizeInBytes < 1024) {
      return '$sizeInBytes B';
    } else if (sizeInBytes < 1024 * 1024) {
      return '${(sizeInBytes / 1024).toStringAsFixed(2)} KB';
    } else {
      return '${(sizeInBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
  }

  String _getFileDate(File file) {
    final fileDate = file.lastModifiedSync();
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
    return WillPopScope(
        onWillPop: () async {
          if (_videoDirPath != _currentPath) {
            _navigateUp();
            return true;
          } else {
            return true;
          }
        },
        child: Scaffold(
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? Color(0xFF121212)
              : Color(0xFFF5F5F5),
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
                    hintText: '搜索视频...',
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
            bottom: PreferredSize(
              preferredSize: Size.fromHeight(1),
              child: Divider(height: 1, color: Colors.transparent),
            ),
            actions: [
              if (_isMultiSelectMode) ...[
                IconButton(
                  icon: Icon(Icons.delete),
                  tooltip: '删除选中项目',
                  onPressed: _selectedItems.isEmpty
                      ? null
                      : () {
                          _showDeleteConfirmationDialog();
                        },
                ),
                IconButton(
                  icon: Icon(Icons.close,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black),
                  tooltip: '退出多选',
                  onPressed: () {
                    setState(() {
                      _isMultiSelectMode = false;
                      _selectedItems.clear();
                    });
                  },
                ),
              ] else ...[
                if (_searchQuery.isEmpty)
                  AnimatedSwitcher(
                    duration: Duration(milliseconds: 300),
                    child: IconButton(
                      key: ValueKey<bool>(_isGridView),
                      icon: Icon(
                        _isGridView
                            ? Icons.list_rounded
                            : Icons.grid_view_rounded,
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
                AnimatedSwitcher(
                  duration: Duration(milliseconds: 300),
                  child: IconButton(
                    key: ValueKey<bool>(_showOnlyFavorites),
                    icon: Icon(
                      _showOnlyFavorites
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: _showOnlyFavorites
                          ? Colors.red
                          : Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : Colors.black,
                    ),
                    tooltip: _showOnlyFavorites ? "显示全部" : "只看收藏",
                    onPressed: () {
                      setState(() {
                        _showOnlyFavorites = !_showOnlyFavorites;
                        _applyFavoritesFilter();
                      });

                      // 显示切换状态提示
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content:
                              Text(_showOnlyFavorites ? '只显示收藏视频' : '显示全部视频'),
                          behavior: SnackBarBehavior.floating,
                          width: 160,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                ),
                Visibility(
                  visible: _currentPath != _videoDirPath,
                  child: IconButton(
                    icon: Icon(Icons.arrow_upward_rounded,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : Colors.black),
                    tooltip: "返回上级",
                    onPressed: _navigateUp,
                  ),
                ),
                if (_searchQuery.isEmpty)
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.add_rounded,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black,
                    ),
                    tooltip: "添加视频",
                    elevation: 0,
                    offset: const Offset(0, 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    color: Colors.transparent,
                    onSelected: (value) {
                      if (value == 'pick') {
                        _pickVideoWithFilePicker();
                      } else if (value == 'folder') {
                        _createNewFolder(context);
                      } else if (value == 'gallery') {
                        _pickVideoWithImagePicker();
                      } else if (value == 'webdav') {
                        _openWebDavFileManager(context);
                      } else if (value == 'softlink') {
                        _pickVideoWithPersist();
                      } else if (value == 'filemanager') {
                        _pickVideoWithFileManager(context);
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
                            filter:
                                ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.black.withOpacity(0.6)
                                    : Colors.white.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.white.withOpacity(0.2)
                                      : Colors.white.withOpacity(0.5),
                                  width: 1.5,
                                ),
                              ),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Add files from file manager
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16.0,
                                        vertical: 8.0,
                                      ),
                                      child: Text(
                                        '添加视频',
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
                                    // Add files from File Manager
                                    _buildActionMenuItem(
                                      context: context,
                                      title: '从文件管理器添加',
                                      icon: Icons.folder_open_rounded,
                                      iconColor: Colors.lightBlue,
                                      onTap: () {
                                        Navigator.pop(context);
                                        _pickVideoWithFileManager(context);
                                      },
                                    ),

                                    // Add local video
                                    _buildActionMenuItem(
                                      context: context,
                                      title: '添加本地视频文件',
                                      icon: Icons.file_upload,
                                      iconColor: Colors.lightBlue,
                                      onTap: () {
                                        Navigator.pop(context);
                                        _pickVideoWithFilePicker();
                                      },
                                    ),

                                    // Add local video link
                                    _buildActionMenuItem(
                                      context: context,
                                      title: '添加本地视频文件链接',
                                      icon: Icons.dataset_linked_rounded,
                                      iconColor: Colors.lightBlue,
                                      onTap: () {
                                        Navigator.pop(context);
                                        _pickVideoWithPersist();
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

                                    // Pick from gallery
                                    _buildActionMenuItem(
                                      context: context,
                                      title: '从相册选择',
                                      icon: Icons.video_library_rounded,
                                      iconColor: Colors.lightBlue,
                                      onTap: () {
                                        Navigator.pop(context);
                                        _pickVideoWithImagePicker();
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
                //   icon: Icon(Icons.refresh_rounded,
                //       color: Theme.of(context).brightness == Brightness.dark
                //           ? Colors.white
                //           : Colors.black),
                //   tooltip: "刷新",
                //   onPressed: () {
                //     // Add loading indicator
                //     _loadItems();
                //   },
                // ),
                PopupMenuButton<Map<String, dynamic>>(
                  tooltip: '排序方式',
                  icon: Icon(
                    Icons.sort,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black,
                  ),
                  elevation: 0, // Remove default shadow
                  offset:
                      const Offset(0, 10), // Give it some space from the icon
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  color:
                      Colors.transparent, // Make default background transparent
                  onSelected: (Map<String, dynamic> option) {
                    setState(() {
                      _currentSortType = option['type'];
                      _currentSortOrder = option['order'];
                      _sortItems();
                    });
                  },
                  itemBuilder: (context) => [
                    // Custom popup menu with glassmorphism effect
                    PopupMenuItem(
                      padding: EdgeInsets.zero,
                      value: null, // This won't be selectable
                      enabled: false,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.black.withOpacity(0.6)
                                  : Colors.white.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.white.withOpacity(0.2)
                                    : Colors.white.withOpacity(0.5),
                                width: 1.5,
                              ),
                            ),
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8.0),
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
                                      '选择排序方式',
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

                                  // Menu Items
                                  _buildSortMenuItem(
                                    context,
                                    '原始顺序',
                                    SortType.none,
                                    SortOrder.ascending,
                                  ),
                                  _buildSortMenuItem(
                                    context,
                                    '文件名 (A-Z)',
                                    SortType.name,
                                    SortOrder.ascending,
                                  ),
                                  _buildSortMenuItem(
                                    context,
                                    '文件名 (Z-A)',
                                    SortType.name,
                                    SortOrder.descending,
                                  ),
                                  _buildSortMenuItem(
                                    context,
                                    '最早修改日期在前',
                                    SortType.modifiedDate,
                                    SortOrder.ascending,
                                  ),
                                  _buildSortMenuItem(
                                    context,
                                    '最近修改日期在前',
                                    SortType.modifiedDate,
                                    SortOrder.descending,
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

                IconButton(
                  icon: Icon(Icons.checklist,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black),
                  tooltip: '进入多选模式',
                  onPressed: () {
                    setState(() {
                      _isMultiSelectMode = true;
                      _selectedItems.clear();
                    });
                  },
                ),
              ],
            ],
          ),
          body: Column(
            children: [
              // 筛选模式提示条
              if (_showOnlyFavorites)
                Container(
                  padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  color: Colors.red.withOpacity(0.1),
                  child: Row(
                    children: [
                      Icon(Icons.favorite, size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text(
                        '已筛选：仅显示收藏视频',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.red,
                        ),
                      ),
                      Spacer(),
                      TextButton(
                        child: Text('取消筛选'),
                        onPressed: () {
                          setState(() {
                            _showOnlyFavorites = false;
                            _applyFavoritesFilter();
                          });
                        },
                        style: TextButton.styleFrom(
                          padding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          foregroundColor: Colors.red,
                          minimumSize: Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ),

              // 原有主体内容
              Expanded(
                child: _isLoading
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text("加载中...",
                                style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          await _loadItems();
                        },
                        child: _filteredItems.isEmpty
                            ? ListView(
                                // 包装在ListView中使RefreshIndicator在空状态下也能工作
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [_buildEmptyStateView()])
                            : _isGridView
                                ? _buildGridView()
                                : _buildListView(),
                      ),
              ),
            ],
          ),
          floatingActionButton: _buildSpeedDial(),
        ));
  }

  Widget _buildEmptyStateView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _showOnlyFavorites
                ? Icons.favorite_border
                : Icons.videocam_off_rounded,
            size: 80,
            color: Colors.grey.withOpacity(0.5),
          ),
          SizedBox(height: 16),
          Text(
            _showOnlyFavorites ? '暂无收藏视频' : '暂无视频',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 8),
          if (_showOnlyFavorites)
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _showOnlyFavorites = false;
                  _applyFavoritesFilter();
                });
              },
              icon: Icon(
                Icons.visibility,
                color: Colors.lightBlue,
              ),
              label: Text(
                '显示全部视频',
                style: TextStyle(color: Colors.lightBlue),
              ),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).primaryColor,
              ),
            )
          else
            TextButton.icon(
              onPressed: _pickVideoWithFilePicker,
              icon: Icon(
                Icons.add,
                color: Colors.lightBlue,
              ),
              label: Text('添加视频'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.lightBlue,
              ),
            ),
        ],
      ),
    );
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



  Widget _buildGridView() {
    DeviceInfo di = getDeviceInfo(context);
    final isTablet = di.isTablet;
    final isLandscape = di.isLandscape;
    int ncols = 5;
    if(isTablet){
      if(isLandscape){
        ncols=5;
      }else{
        ncols=4;
      }
    }else{
      if(isLandscape){
        ncols=3;
      }else{
        ncols=2;
      }
    }
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
            child: GridView.builder(
              cacheExtent: 500,
              key: ValueKey<String>('grid'),
              padding: EdgeInsets.all(12),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: ncols,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.85,
              ),
              itemCount: _filteredItems.length,
              itemBuilder: (context, index) {
                final file = _filteredItems[index];
                Widget card;
                if (file is Directory) {
                  card = _buildFolderCard(file);
                } else {
                  card = _buildVideoCard(file);
                }

                if (_isMultiSelectMode) {
                  return _wrapWithCheckbox(card, file);
                } else {
                  return card;
                }
              },
            ),
          ),
        ],
      ),
    );
  }

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
          child: child,
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
          child: child,
        ),
      ],
    );
  }

// 添加弹出菜单的方法
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
          onLongPress: () {
            _showFolderOptions(directory);
          },
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

  Widget _buildVideoCard(File file, {bool isListView = false}) {
    final fileName = path.basename(file.path);
    // Modified extension handling for .lnk files
    String videoExtension = path.extension(file.path).toLowerCase();
    bool isShortcut = videoExtension == '.lnk';

    // If it's a shortcut (.lnk), try to get the original extension
    if (isShortcut) {
      // Extract the original extension before .lnk
      final nameWithoutLnk = fileName.substring(0, fileName.length - 4);
      final originalExtension = path.extension(nameWithoutLnk).toLowerCase();
      if (originalExtension.isNotEmpty) {
        videoExtension = originalExtension;
      }
    }

    final heroTag = 'video-${file.path}';
    // Add this function to get the history progress from HistoryService
    Future<double> _getHistoryProgress(String filePath) async {
      Duration duration = await _getVideoDuration(File(filePath));
      final historyItem = await historyService.getHistoryByPath(filePath);
      if (historyItem == null || duration.inMilliseconds <= 0) {
        return 0.0;
      }
      // Calculate progress percentage (capped at 98% to indicate not complete)
      double progress = historyItem.lastPosition / duration.inMilliseconds;
      print('[history] $filePath $progress');
      return progress > 0.98 ? 0.98 : progress;
    }

    if (isListView) {
      return RepaintBoundary(
        child: Hero(
          tag: heroTag,
          child: Card(
            margin: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            child: ListTile(
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 70,
                  height: 70,
                  color: Colors.black,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      FutureBuilder<Uint8List?>(
                        future: _getVideoThumbnail(file),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return Container(
                              color: Colors.grey.withOpacity(0.2),
                              child: Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white70),
                                  ),
                                ),
                              ),
                            );
                          }
                          if (snapshot.hasError || snapshot.data == null) {
                            return Center(
                              child: Icon(Icons.movie_outlined,
                                  size: 30, color: Colors.white54),
                            );
                          }
                          return Image.memory(
                            snapshot.data!,
                            fit: BoxFit.cover,
                          );
                        },
                      ),
                      // History progress bar for list view
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: FutureBuilder<double>(
                          future: _getHistoryProgress(file.path),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData || snapshot.data == 0.0) {
                              return SizedBox.shrink();
                            }
                            return Container(
                              height: 3,
                              child: LinearProgressIndicator(
                                value: snapshot.data,
                                backgroundColor: Colors.grey.withOpacity(0.3),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.redAccent),
                              ),
                            );
                          },
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding:
                              EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(4),
                            ),
                          ),
                          child: Text(
                            videoExtension,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      // Shortcut indicator for .lnk files
                      if (isShortcut)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.7),
                              borderRadius: BorderRadius.only(
                                bottomLeft: Radius.circular(4),
                              ),
                            ),
                            child: Icon(
                              Icons.link,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      // HDR indicator for list view
                      FutureBuilder<bool>(
                        future: _getHdr(file),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                                  ConnectionState.done &&
                              snapshot.data == true) {
                            return Positioned(
                              top: 0,
                              left: 0,
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 2),
                                decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.amber.shade700,
                                        Colors.orange.shade900
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.only(
                                      bottomRight: Radius.circular(4),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black26,
                                        blurRadius: 2,
                                        offset: Offset(0, 1),
                                      )
                                    ]),
                                child: Text(
                                  'HDR',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            );
                          }
                          return SizedBox.shrink();
                        },
                      ),
                    ],
                  ),
                ),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      fileName,
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              subtitle: FutureBuilder<Duration?>(
                future: _getVideoDuration(file),
                builder: (context, snapshot) {
                  final fileSize = _getFileSize(file);
                  final fileDateString = _getFileDate(file);
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    final hours = '';
                    final minutes = '00:';
                    final seconds = '00';
                    return Row(
                      children: [
                        Icon(Icons.access_time,
                            size: 14, color: Colors.lightBlue.withOpacity(0.7)),
                        SizedBox(width: 4),
                        Text(
                          '$hours$minutes$seconds',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        SizedBox(width: 12),
                        Icon(Icons.sd_storage,
                            size: 14, color: Colors.lightBlue.withOpacity(0.7)),
                        SizedBox(width: 4),
                        Text(
                          fileSize,
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        SizedBox(width: 12),
                        Icon(Icons.date_range,
                            size: 14, color: Colors.lightBlue.withOpacity(0.7)),
                        SizedBox(width: 4),
                        Text(
                          fileDateString,
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    );
                  }
                  if (snapshot.hasError || snapshot.data == null) {
                    final hours = '';
                    final minutes = '00:';
                    final seconds = '00';
                    return Row(
                      children: [
                        Icon(Icons.access_time,
                            size: 14, color: Colors.lightBlue.withOpacity(0.7)),
                        SizedBox(width: 4),
                        Text(
                          '$hours$minutes$seconds',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        SizedBox(width: 12),
                        Icon(Icons.sd_storage,
                            size: 14, color: Colors.lightBlue.withOpacity(0.7)),
                        SizedBox(width: 4),
                        Text(
                          fileSize,
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        SizedBox(width: 12),
                        Icon(Icons.date_range,
                            size: 14, color: Colors.lightBlue.withOpacity(0.7)),
                        SizedBox(width: 4),
                        Text(
                          fileDateString,
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    );
                  }
                  final duration = snapshot.data!;
                  final hours =
                      duration.inHours > 0 ? '${duration.inHours}:' : '';
                  final minutes =
                      '${(duration.inMinutes % 60).toString().padLeft(2, '0')}:';
                  final seconds =
                      '${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
                  return Row(
                    children: [
                      Icon(Icons.access_time,
                          size: 14, color: Colors.lightBlue.withOpacity(0.7)),
                      SizedBox(width: 4),
                      Text(
                        '$hours$minutes$seconds',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      SizedBox(width: 12),
                      Icon(Icons.sd_storage,
                          size: 14, color: Colors.lightBlue.withOpacity(0.7)),
                      SizedBox(width: 4),
                      Text(
                        fileSize,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      SizedBox(width: 12),
                      Icon(Icons.date_range,
                          size: 14, color: Colors.lightBlue.withOpacity(0.7)),
                      SizedBox(width: 4),
                      Text(
                        fileDateString,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  );
                },
              ),
              trailing: IconButton(
                icon: Icon(Icons.more_vert, color: Colors.grey[600]),
                onPressed: () => _showVideoOptionsBottomSheet(file),
              ),
              onTap: () {
                widget.getopenfile(file.path);
                widget.startPlayerPage(context);
              },
              onLongPress: () => _showVideoOptionsBottomSheet(file),
            ),
          ),
        ),
      );
    } else {
      // Grid view layout
      return RepaintBoundary(
        child: Hero(
          tag: heroTag,
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: InkWell(
              onTap: () {
                widget.getopenfile(file.path);
                widget.startPlayerPage(context);
              },
              onLongPress: () => _showVideoOptionsBottomSheet(file),
              borderRadius: BorderRadius.circular(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                    child: Stack(
                      children: [
                        AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              FutureBuilder<Uint8List?>(
                                future: _getVideoThumbnail(file),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState ==
                                      ConnectionState.waiting) {
                                    return Container(
                                      color: Colors.grey.withOpacity(0.2),
                                      child: Center(
                                        child: SizedBox(
                                          width: 30,
                                          height: 30,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                    Colors.white70),
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                  if (snapshot.hasError ||
                                      snapshot.data == null) {
                                    return Container(
                                      color: Colors.grey[800],
                                      child: Center(
                                        child: Icon(Icons.movie_outlined,
                                            size: 40, color: Colors.white54),
                                      ),
                                    );
                                  }
                                  return Image.memory(
                                    snapshot.data!,
                                    fit: BoxFit.cover,
                                  );
                                },
                              ),
                              // Extension tag
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.6),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    videoExtension,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              // HDR indicator for grid view (now positioned below shortcut if present)
                              FutureBuilder<bool>(
                                future: _getHdr(file),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState ==
                                          ConnectionState.done &&
                                      snapshot.data == true) {
                                    return Positioned(
                                      top: isShortcut
                                          ? 36
                                          : 8, // Position below the shortcut indicator if present
                                      left: 8,
                                      child: Container(
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 3),
                                        decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.amber.shade600,
                                                Colors.orange.shade900
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black38,
                                                blurRadius: 3,
                                                offset: Offset(0, 1),
                                              )
                                            ]),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.hdr_on_rounded,
                                                size: 12, color: Colors.white),
                                            SizedBox(width: 2),
                                            Text(
                                              'HDR',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }
                                  return SizedBox.shrink();
                                },
                              ),
                              Positioned.fill(
                                child: Center(
                                  child: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.5),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Icon(
                                      Icons.play_arrow_rounded,
                                      color: Colors.white,
                                      size: 30,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: FutureBuilder<Duration?>(
                                  future: _getVideoDuration(file),
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState ==
                                            ConnectionState.waiting ||
                                        snapshot.hasError ||
                                        snapshot.data == null) {
                                      return SizedBox();
                                    }
                                    final duration = snapshot.data!;
                                    final hours = duration.inHours > 0
                                        ? '${duration.inHours}:'
                                        : '';
                                    final minutes =
                                        '${(duration.inMinutes % 60).toString().padLeft(2, '0')}:';
                                    final seconds =
                                        '${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
                                    return Container(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.bottomCenter,
                                          end: Alignment.topCenter,
                                          colors: [
                                            Colors.black.withOpacity(0.7),
                                            Colors.transparent,
                                          ],
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.access_time,
                                              size: 12, color: Colors.white70),
                                          SizedBox(width: 4),
                                          Text(
                                            '$hours$minutes$seconds',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Add history progress bar below the thumbnail
                        Positioned(
                          top: (16 /
                              9 *
                              100), // Position right below the 16/9 aspect ratio thumbnail
                          left: 0,
                          right: 0,
                          child: FutureBuilder<double>(
                            future: _getHistoryProgress(file.path),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData || snapshot.data == 0.0) {
                                return SizedBox(
                                    height:
                                        3); // Keep consistent height even if no progress
                              }
                              return Container(
                                height: 3,
                                child: LinearProgressIndicator(
                                  value: snapshot.data,
                                  backgroundColor: Colors.grey.withOpacity(0.3),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.redAccent),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  fileName,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isShortcut)
                                Container(
                                  margin: EdgeInsets.only(left: 4),
                                  padding: EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                  child: Icon(
                                    Icons.link,
                                    size: 10,
                                    color: Colors.blue,
                                  ),
                                ),
                            ],
                          ),
                          Spacer(),
                          // Show watched percentage if available
                          FutureBuilder<double>(
                            future: _getHistoryProgress(file.path),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData || snapshot.data == 0.0) {
                                return Text(
                                  _getFileSize(file) + " " + _getFileDate(file),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey[600],
                                  ),
                                );
                              }
                              // Display percentage watched
                              final percentage = (snapshot.data! * 100).toInt();
                              return Row(
                                children: [
                                  Icon(Icons.play_circle_outline,
                                      size: 10, color: Colors.redAccent),
                                  SizedBox(width: 2),
                                  Text(
                                    '$percentage% 已观看',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.redAccent,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Spacer(),
                                  Text(
                                    _getFileSize(file),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              );
                            },
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
      );
    }
  }

  void _handleVideoAction(String value, File file) {
    switch (value) {
      case 'play':
        widget.getopenfile(file.path);
        widget.startPlayerPage(context);
        break;
      case 'convert':
        _showConvertToMp4Dialog(file);
        break;
      case 'extract':
        _showExtractSubtitleDialog(file);
        break;
      case 'share':
        String filePath = file.path;
        if (file.path.endsWith('.lnk')) {
          filePath = file.readAsStringSync();
          _settingsService.activatePersistPermission(pathToUri(filePath));
        }
        Share.shareXFiles([XFile(filePath)]);
        break;
      case 'favorite':
        _toggleFavorite(file);
        break;
      case 'delete':
        _showDeleteConfirmDialog(file);
        break;
    }
  }

  void _showVideoOptionsBottomSheet(File file) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      backgroundColor: Colors.transparent, // Keep this transparent
      builder: (BuildContext context) {
        final fileName = path.basename(file.path);
        final orientation = MediaQuery.of(context).orientation;
        final isLandscape = orientation == Orientation.landscape;
        final screenWidth = MediaQuery.of(context).size.width;
        final isLargeScreen = screenWidth > 600;

        final gridColumns = isLandscape ? 6 : (isLargeScreen ? 4 : 3);
        final aspectRatio = isLandscape ? 1.1 : (isLargeScreen ? 1.5 : 1.0);

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                // Apply blur directly to the container with frosted glass effect
                color: Colors.transparent,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    // Add the colored container inside the backdropFilter
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.black.withOpacity(0.85)
                          : Colors.white.withOpacity(0.85),
                    ),
                    child: isLandscape
                        // Landscape layout
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildDragHandle(),
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 1,
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _buildThumbnail(file),
                                          SizedBox(width: 16),
                                          Expanded(
                                              child: _buildFileInfo(
                                                  fileName, file)),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: _buildOptionsGrid(
                                          file, gridColumns, aspectRatio),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        // Portrait layout
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildDragHandle(),
                              Padding(
                                padding: EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    _buildThumbnail(file),
                                    SizedBox(width: 16),
                                    Expanded(
                                        child: _buildFileInfo(fileName, file)),
                                  ],
                                ),
                              ),
                              Divider(height: 1, thickness: 0.5),
                              _buildOptionsGrid(file, gridColumns, aspectRatio),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

// 添加拖动把手
  Widget _buildDragHandle() {
    return Container(
      margin: EdgeInsets.only(top: 12, bottom: 4),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.5),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

// 提取缩略图组件
  Widget _buildThumbnail(File file) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 4,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: FutureBuilder<Uint8List?>(
        future: _getVideoThumbnail(file),
        builder: (context, snapshot) {
          return Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: BorderRadius.circular(12),
            ),
            child: snapshot.connectionState == ConnectionState.done &&
                    snapshot.data != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(snapshot.data!, fit: BoxFit.cover),
                  )
                : Icon(Icons.movie_outlined, size: 30, color: Colors.white70),
          );
        },
      ),
    );
  }

// 提取文件信息组件
  Widget _buildFileInfo(String fileName, File file) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          fileName,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: 4),
        FutureBuilder<Duration?>(
          future: _getVideoDuration(file),
          builder: (context, snapshot) {
            final fileSize = _getFileSize(file);
            final fileDateString = _getFileDate(file);

            if (snapshot.connectionState == ConnectionState.waiting ||
                snapshot.hasError ||
                snapshot.data == null) {
              return Text(
                '大小: $fileSize, 日期: $fileDateString',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              );
            }

            final duration = snapshot.data!;
            final hours = duration.inHours > 0 ? '${duration.inHours}:' : '';
            final minutes =
                '${(duration.inMinutes % 60).toString().padLeft(2, '0')}:';
            final seconds =
                '${(duration.inSeconds % 60).toString().padLeft(2, '0')}';

            return Text(
              '时长: $hours$minutes$seconds • 大小: $fileSize • 日期: $fileDateString',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            );
          },
        ),
      ],
    );
  }

// 提取选项网格组件
  Widget _buildOptionsGrid(
      File file, int crossAxisCount, double childAspectRatio) {
    return GridView.count(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      crossAxisCount: crossAxisCount,
      childAspectRatio: childAspectRatio,
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      children: [
        _buildOptionTile(
          icon: Icons.play_arrow,
          color: Colors.green,
          title: '播放',
          onTap: () {
            Navigator.pop(context);
            widget.getopenfile(file.path);
            widget.startPlayerPage(context);
          },
        ),
        _buildOptionTile(
          icon: Icons.file_download,
          color: Colors.blue,
          title: '转MP4',
          enabled: !isFFmpeged,
          onTap: () {
            Navigator.pop(context);
            _showConvertToMp4Dialog(file);
          },
        ),
        _buildOptionTile(
          icon: Icons.subtitles,
          color: Colors.purple,
          title: '抽取字幕',
          onTap: () {
            Navigator.pop(context);
            _showExtractSubtitleDialog(file);
          },
        ),
        _buildOptionTile(
          icon: Icons.music_note,
          color: Colors.yellow,
          title: '抽取音轨',
          onTap: () {
            Navigator.pop(context);
            _showExtractAudioTrackDialog(file);
          },
        ),
        _buildOptionTile(
          icon: Icons.cast,
          color: Colors.blue,
          title: '投播(测试)',
          onTap: () {
            Navigator.pop(context);
            // 如果file.path是lnk文件，按String读取成为新的path
            String filePath = file.path;
            if (file.path.endsWith('.lnk')) {
              filePath = file.readAsStringSync();
            }
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CastScreenPage(
                  mediaPath: filePath,
                ),
              ),
            );
          },
        ),
        _buildOptionTile(
          icon: Icons.share,
          color: Colors.orange,
          title: '分享',
          onTap: () {
            Navigator.pop(context);
            String filePath = file.path;
            if (file.path.endsWith('.lnk')) {
              filePath = file.readAsStringSync();
              _settingsService.activatePersistPermission(pathToUri(filePath));
            }
            Share.shareXFiles([XFile(filePath)]);
          },
        ),
        _buildOptionTile(
          icon: _favoriteStatus[file.path] ?? false
              ? Icons.favorite
              : Icons.favorite_border,
          color: _favoriteStatus[file.path] ?? false ? Colors.red : Colors.pink,
          title: _favoriteStatus[file.path] ?? false ? '取消收藏' : '收藏',
          onTap: () {
            Navigator.pop(context);
            _toggleFavorite(file);
          },
        ),
        _buildOptionTile(
          icon: Icons.delete,
          color: Colors.red,
          title: '删除',
          onTap: () {
            Navigator.pop(context);
            _showDeleteConfirmDialog(file);
          },
        ),
      ],
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required Color color,
    required String title,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Opacity(
          opacity: enabled ? 1.0 : 0.5,
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                SizedBox(height: 8),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
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

  void _showDeleteConfirmDialog(File file) {
    final fileName = path.basename(file.path);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.delete, color: Colors.red),
              SizedBox(width: 10),
              Text('删除视频'),
            ],
          ),
          content: RichText(
            text: TextSpan(
              style: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black87,
                fontSize: 16,
              ),
              children: [
                TextSpan(text: '确定要删除 '),
                TextSpan(
                  text: fileName,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(text: ' 吗？\n\n'),
                TextSpan(
                  text: '此操作不可恢复',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: Text('取消', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                _deleteVideoFile(file);
                Navigator.pop(context);

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('已删除: $fileName'),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    action: SnackBarAction(
                      label: '关闭',
                      onPressed: () {},
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text('删除'),
            ),
          ],
        );
      },
    );
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

  Widget _buildSpeedDial() {
    return SpeedDial(
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
          labelBackgroundColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.grey[800]
              : Colors.white,
          onTap: () => _openFile(),
        ),
        SpeedDialChild(
          child: Icon(Icons.link, color: Colors.white),
          backgroundColor: Colors.green[600],
          foregroundColor: Colors.white,
          label: '打开URL',
          labelStyle: TextStyle(fontSize: 14),
          labelBackgroundColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.grey[800]
              : Colors.white,
          onTap: () => _showUrlDialog(context),
        ),
        SpeedDialChild(
          child: Icon(Icons.history, color: Colors.white),
          backgroundColor: Colors.orange[600],
          foregroundColor: Colors.white,
          label: '打开历史记录',
          labelStyle: TextStyle(fontSize: 14),
          labelBackgroundColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.grey[800]
              : Colors.white,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => HistoryPage(
                  getOpenFile: widget.getopenfile,
                  startPlayerPage: widget.startPlayerPage,
                ),
              ),
            );
          },
        ),
        // SpeedDialChild(
        //   child: Icon(Icons.webhook, color: Colors.white),
        //   backgroundColor: Colors.orange[600],
        //   foregroundColor: Colors.white,
        //   label: '从WebDAV下载',
        //   labelStyle: TextStyle(fontSize: 14),
        //   labelBackgroundColor: Theme.of(context).brightness == Brightness.dark
        //       ? Colors.grey[800]
        //       : Colors.white,
        //   onTap: () => _openWebDavFileManager(context),
        // ),
      ],
    );
  }

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
