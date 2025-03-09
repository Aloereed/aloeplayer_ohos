import 'dart:ui';

import 'package:flutter/material.dart';
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
  final SettingsService _settingsService = SettingsService();
  final FavoritesDatabase _favoritesDb = FavoritesDatabase.instance;
  Map<String, bool> _favoriteStatus = {};
  bool _showOnlyFavorites = false;
  bool isFFmpeged = false;
  @override
  void initState() async {
    super.initState();
    bool useinnerthumb = await _settingsService.getUseInnerThumbnail();
    if(useinnerthumb){
      // path join
      _thumbnailPath = path.join((await getTemporaryDirectory()).path, 'Thumbnails');
    }
    _ensureVideoDirectoryExists();
    setState(() async {
      _isGridView = !(await _settingsService.getDefaultListmode());
    });
    // _loadVideoFiles();
    _loadItems();
    _loadFavoriteStatus();
  }

  // 加载所有项目的收藏状态
  Future<void> _loadFavoriteStatus() async {
    for (var item in _allItems) {
      if (item is File) {
        bool isFav = await _favoritesDb.isFavorite(item.path);
        setState(() {
          _favoriteStatus[item.path] = isFav;
        });
      }
    }

    // 收藏状态更新后重新应用筛选
    if (_showOnlyFavorites) {
      setState(() {
        _applyFavoritesFilter();
      });
    }
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

  Future<void> _loadItems() async {
    final directory = Directory(_currentPath);
    List<File> files = [];
    List<Directory> directories = [];

    if (await directory.exists()) {
      final items = directory.listSync();
      for (var item in items) {
        if (item is File) {
          String extension = path.extension(item.path).toLowerCase();
          // 排除 .srt 和 .ass 文件
          if (extension != '.srt' &&
              extension != '.ass' &&
              !item.path.contains('.ux_store')) {
            files.add(item);
          }
        } else if (item is Directory) {
          directories.add(item);
        }
      }
    }

    setState(() {
      _videoFiles = files;
      _directories = directories;
      // _filteredItems = [...directories, ...files]; // 初始化时显示所有文件和文件夹
      _allItems = [...directories, ...files]; // 保存所有项目

      // 根据筛选条件设置显示的项目
      _applyFavoritesFilter();
    });

    await _loadFavoriteStatus();
    setState(() {
      _isLoading = false;
    });
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
      // 如果有搜索词，应用搜索筛选
      if (query.isNotEmpty) {
        _filteredItems = _filteredItems
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

  // 使用image_picker选择视频文件
  Future<void> _pickVideoWithImagePicker() async {
    await _ensureVideoDirectoryExists();
    final picker = ImagePicker();
    final List<XFile> files = await picker.pickMultipleMedia();
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
    // 从file.path提取文件名
    String fileName = path.basename(file.path);
    // 尝试读取$_thumbnailPath/$fileName.nothumbnail
    String thumbnailPath =
        '$_thumbnailPath/$fileName.nothumbnail';
    // 检查文件是否存在
    if (await File(thumbnailPath).exists()) {
      // 如果文件存在，则读取文件内容
      return null;
    }

    // 尝试读取$_thumbnailPath/$fileName.jpg
    thumbnailPath =
        '$_thumbnailPath/$fileName.jpg';
    // 检查文件是否存在
    if (await File(thumbnailPath).exists()) {
      // 如果文件存在，则读取文件内容为Uint8List
      return await File(thumbnailPath).readAsBytes();
    }

    final thumbnail = await VideoThumbnailOhos.thumbnailData(
      video: file.path,
      imageFormat: ImageFormat.JPEG,
      maxWidth: 128, // 缩略图的最大宽度
      quality: 25, // 缩略图的质量 (0-100)
    );

    try {
      // 保存缩略图到$_thumbnailPath/
      String thumbnailPath =
          '$_thumbnailPath/$fileName.jpg';
      // 将缩略图保存到文件
      File thumbnailFile = File(thumbnailPath);
      await thumbnailFile.writeAsBytes(thumbnail!);
    } catch (e) {
      // 写入一个空文件$_thumbnailPath/$fileName.nothumbnail
      String thumbnailPath =
          '$_thumbnailPath/$fileName.nothumbnail';
      // 将缩略图保存到文件
      File thumbnailFile = File(thumbnailPath);
      await thumbnailFile.writeAsBytes([]);
    }
    return thumbnail;
  }

  // 获取视频时长
  Future<Duration> _getVideoDuration(File file) async {
    // // 创建 MediaInfo 实例
    // MediaInfo mediaInfo = MediaInfo();

    // // 获取视频文件的元数据
    // Map<String, dynamic> metadata = await mediaInfo.getMediaInfo(file.path);

    // // 从元数据中提取视频时长
    // int durationInMilliseconds = metadata['durationMs'];
    final _platform = const MethodChannel('samples.flutter.dev/ffmpegplugin');
    // 调用方法 getBatteryLevel
    final result = await _platform
        .invokeMethod<int>('getVideoDurationMs', {"path": file.path});

    // 将毫秒转换为 Duration 对象
    Duration duration = Duration(milliseconds: result ?? 0);

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
    final sizeInBytes = file.lengthSync();
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
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
          AnimatedSwitcher(
            duration: Duration(milliseconds: 300),
            child: IconButton(
              key: ValueKey<bool>(_showOnlyFavorites),
              icon: Icon(
                _showOnlyFavorites ? Icons.favorite : Icons.favorite_border,
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
                    content: Text(_showOnlyFavorites ? '只显示收藏视频' : '显示全部视频'),
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
          PopupMenuButton<String>(
            icon: Icon(Icons.add_rounded,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black),
            tooltip: "添加视频",
            onSelected: (value) {
              if (value == 'pick') {
                _pickVideoWithFilePicker();
              } else if (value == 'folder') {
                _createNewFolder(context);
              } else if (value == 'gallery') {
                _pickVideoWithImagePicker();
              } else if (value == 'webdav') {
                _openWebDavFileManager(context); 
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'pick',
                child: Row(
                  children: [
                    Icon(Icons.file_upload, color: Colors.lightBlue),
                    SizedBox(width: 10),
                    Text('选择视频文件'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'folder',
                child: Row(
                  children: [
                    Icon(Icons.create_new_folder, color: Colors.lightBlue),
                    SizedBox(width: 10),
                    Text('新建文件夹'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'gallery',
                child: Row(
                  children: [
                    Icon(Icons.video_library_rounded, color: Colors.lightBlue),
                    SizedBox(width: 10),
                    Text('从相册选择'),
                  ],
                ),
              ),
              PopupMenuItem(
               value: 'webdav',
                child: Row(
                  children: [
                    Icon(Icons.cloud_upload_rounded, color: Colors.lightBlue),
                    SizedBox(width: 10),
                    Text('从WebDAV下载'),
                  ],
                ), 
              )
            ],
          ),
          IconButton(
            icon: Icon(Icons.refresh_rounded,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black),
            tooltip: "刷新",
            onPressed: () {
              // Add loading indicator
              setState(() {
                _isLoading = false;
              });
              _loadItems().then((_) {
                setState(() {
                  _isLoading = false;
                });
              });
            },
          ),
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
                        Text("加载中...", style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : _filteredItems.isEmpty
                    ? _buildEmptyStateView()
                    : _isGridView
                        ? _buildGridView()
                        : _buildListView(),
          ),
        ],
      ),
      floatingActionButton: _buildSpeedDial(),
    );
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

  Widget _buildGridView() {
    return AnimatedSwitcher(
      duration: Duration(milliseconds: 300),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: GridView.builder(
        key: ValueKey<String>('grid'),
        padding: EdgeInsets.all(12),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.85,
        ),
        itemCount: _filteredItems.length,
        itemBuilder: (context, index) {
          final file = _filteredItems[index];
          if (file is Directory) {
            return _buildFolderCard(file);
          }
          return _buildVideoCard(file);
        },
      ),
    );
  }

  Widget _buildListView() {
    return AnimatedSwitcher(
      duration: Duration(milliseconds: 300),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: ListView.builder(
        key: ValueKey<String>('list'),
        padding: EdgeInsets.symmetric(vertical: 8),
        itemCount: _filteredItems.length,
        itemBuilder: (context, index) {
          final file = _filteredItems[index];
          if (file is Directory) {
            return _buildFolderListItem(file);
          }
          return _buildVideoCard(file, isListView: true);
        },
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoCard(File file, {bool isListView = false}) {
    final fileName = path.basename(file.path);
    final videoExtension = path.extension(file.path).toLowerCase();
    final heroTag = 'video-${file.path}';

    if (isListView) {
      return Hero(
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
                  ],
                ),
              ),
            ),
            title: Text(
              fileName,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: FutureBuilder<Duration?>(
              future: _getVideoDuration(file),
              builder: (context, snapshot) {
                final fileSize = _getFileSize(file);
                final fileDateString = _getFileDate(file);
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Text('大小: $fileSize, 日期: $fileDateString',
                      style: TextStyle(fontSize: 12, color: Colors.grey));
                }

                if (snapshot.hasError || snapshot.data == null) {
                  return Text('大小: $fileSize, 日期: $fileDateString',
                      style: TextStyle(fontSize: 12, color: Colors.grey));
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
            trailing: PopupMenuButton(
              icon: Icon(Icons.more_vert, color: Colors.grey[600]),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onSelected: (value) => _handleVideoAction(value, file),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'play',
                  child: Row(
                    children: [
                      Icon(Icons.play_circle_outline, color: Colors.green),
                      SizedBox(width: 12),
                      Text('播放'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'convert',
                  child: Row(
                    children: [
                      Icon(Icons.file_download_outlined, color: Colors.blue),
                      SizedBox(width: 12),
                      Text('转换为MP4'),
                    ],
                  ),
                  enabled: !isFFmpeged,
                ),
                PopupMenuItem(
                  value: 'extract',
                  child: Row(
                    children: [
                      Icon(Icons.subtitles_outlined, color: Colors.purple),
                      SizedBox(width: 12),
                      Text('抽取内挂字幕'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'share',
                  child: Row(
                    children: [
                      Icon(Icons.share_outlined, color: Colors.orange),
                      SizedBox(width: 12),
                      Text('分享'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'favorite',
                  child: Row(
                    children: [
                      Icon(
                        _favoriteStatus[file.path] ?? false
                            ? Icons.favorite
                            : Icons.favorite_border_outlined,
                        color: _favoriteStatus[file.path] ?? false
                            ? Colors.red
                            : Colors.grey,
                      ),
                      SizedBox(width: 12),
                      Text(_favoriteStatus[file.path] ?? false ? '取消收藏' : '收藏'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, color: Colors.red),
                      SizedBox(width: 12),
                      Text('删除'),
                    ],
                  ),
                ),
              ],
            ),
            onTap: () {
              widget.getopenfile(file.path);
              widget.startPlayerPage(context);
            },
            onLongPress: () => _showVideoOptionsBottomSheet(file),
          ),
        ),
      );
    } else {
      return Hero(
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
                  child: AspectRatio(
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
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white70),
                                    ),
                                  ),
                                ),
                              );
                            }
                            if (snapshot.hasError || snapshot.data == null) {
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
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fileName,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Spacer(),
                        Text(
                          _getFileSize(file)+ " "+_getFileDate(file),
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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
        Share.shareXFiles([XFile(file.path)]);
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
      isScrollControlled: true, // 允许弹出sheet占据更多空间
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? Color(0xFF2C2C2C)
          : Colors.white,
      builder: (BuildContext context) {
        final fileName = path.basename(file.path);
        final orientation = MediaQuery.of(context).orientation;
        final isLandscape = orientation == Orientation.landscape;

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom),
            child: isLandscape
                // 横屏布局
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        margin: EdgeInsets.only(top: 8),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      // 横屏模式下将信息和操作并排放置
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 左侧：文件信息
                            Expanded(
                              flex: 1,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  FutureBuilder<Uint8List?>(
                                    future: _getVideoThumbnail(file),
                                    builder: (context, snapshot) {
                                      return Container(
                                        width: 60,
                                        height: 60,
                                        decoration: BoxDecoration(
                                          color: Colors.grey[800],
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: snapshot.connectionState ==
                                                    ConnectionState.done &&
                                                snapshot.data != null
                                            ? ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                child: Image.memory(
                                                    snapshot.data!,
                                                    fit: BoxFit.cover),
                                              )
                                            : Icon(Icons.movie_outlined,
                                                size: 30,
                                                color: Colors.white70),
                                      );
                                    },
                                  ),
                                  SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          fileName,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w500,
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

                                            if (snapshot.connectionState ==
                                                    ConnectionState.waiting ||
                                                snapshot.hasError ||
                                                snapshot.data == null) {
                                              return Text(
                                                '大小: $fileSize, 日期: $fileDateString',
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey),
                                              );
                                            }

                                            final duration = snapshot.data!;
                                            final hours = duration.inHours > 0
                                                ? '${duration.inHours}:'
                                                : '';
                                            final minutes =
                                                '${(duration.inMinutes % 60).toString().padLeft(2, '0')}:';
                                            final seconds =
                                                '${(duration.inSeconds % 60).toString().padLeft(2, '0')}';

                                            return Text(
                                              '时长: $hours$minutes$seconds • 大小: $fileSize • 日期: $fileDateString',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // 右侧：操作按钮
                            Expanded(
                              flex: 2,
                              child: GridView.count(
                                shrinkWrap: true,
                                physics: NeverScrollableScrollPhysics(),
                                crossAxisCount: 6,
                                childAspectRatio: 1.1,
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
                                    icon: Icons.share,
                                    color: Colors.orange,
                                    title: '分享',
                                    onTap: () {
                                      Navigator.pop(context);
                                      Share.shareXFiles([XFile(file.path)]);
                                    },
                                  ),
                                  _buildOptionTile(
                                    icon: _favoriteStatus[file.path] ?? false
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    color: _favoriteStatus[file.path] ?? false
                                        ? Colors.red
                                        : Colors.pink,
                                    title: _favoriteStatus[file.path] ?? false
                                        ? '取消收藏'
                                        : '收藏',
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
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                // 竖屏布局保持原样
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        margin: EdgeInsets.only(top: 8),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.all(16),
                        child: Row(
                          children: [
                            FutureBuilder<Uint8List?>(
                              future: _getVideoThumbnail(file),
                              builder: (context, snapshot) {
                                return Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[800],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: snapshot.connectionState ==
                                              ConnectionState.done &&
                                          snapshot.data != null
                                      ? ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: Image.memory(snapshot.data!,
                                              fit: BoxFit.cover),
                                        )
                                      : Icon(Icons.movie_outlined,
                                          size: 30, color: Colors.white70),
                                );
                              },
                            ),
                            SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    fileName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 16,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  SizedBox(height: 4),
                                  FutureBuilder<Duration?>(
                                    future: _getVideoDuration(file),
                                    builder: (context, snapshot) {
                                      final fileSize = _getFileSize(file);
                                      final fileDateString = _getFileDate(file);

                                      if (snapshot.connectionState ==
                                              ConnectionState.waiting ||
                                          snapshot.hasError ||
                                          snapshot.data == null) {
                                        return Text(
                                          '大小: $fileSize, 日期: $fileDateString',
                                          style: TextStyle(
                                              fontSize: 12, color: Colors.grey),
                                        );
                                      }

                                      final duration = snapshot.data!;
                                      final hours = duration.inHours > 0
                                          ? '${duration.inHours}:'
                                          : '';
                                      final minutes =
                                          '${(duration.inMinutes % 60).toString().padLeft(2, '0')}:';
                                      final seconds =
                                          '${(duration.inSeconds % 60).toString().padLeft(2, '0')}';

                                      return Text(
                                        '时长: $hours$minutes$seconds • 大小: $fileSize • 日期: $fileDateString',
                                        style: TextStyle(
                                            fontSize: 12, color: Colors.grey),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1),
                      GridView.count(
                        shrinkWrap: true,
                        physics: NeverScrollableScrollPhysics(),
                        crossAxisCount: 3,
                        childAspectRatio: 1.0,
                        children: [
                          _buildOptionTile(
                            icon: Icons.play_arrow,
                            color: Colors.green,
                            title: '播放视频',
                            onTap: () {
                              Navigator.pop(context);
                              widget.getopenfile(file.path);
                              widget.startPlayerPage(context);
                            },
                          ),
                          _buildOptionTile(
                            icon: Icons.file_download,
                            color: Colors.blue,
                            title: '转换为MP4',
                            enabled: !isFFmpeged,
                            onTap: () {
                              Navigator.pop(context);
                              _showConvertToMp4Dialog(file);
                            },
                          ),
                          _buildOptionTile(
                            icon: Icons.subtitles,
                            color: Colors.purple,
                            title: '抽取内挂字幕',
                            onTap: () {
                              Navigator.pop(context);
                              _showExtractSubtitleDialog(file);
                            },
                          ),
                          _buildOptionTile(
                            icon: Icons.share,
                            color: Colors.orange,
                            title: '分享视频',
                            onTap: () {
                              Navigator.pop(context);
                              Share.shareXFiles([XFile(file.path)]);
                            },
                          ),
                          _buildOptionTile(
                            icon: _favoriteStatus[file.path] ?? false
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: _favoriteStatus[file.path] ?? false
                                ? Colors.red
                                : Colors.pink,
                            title: _favoriteStatus[file.path] ?? false
                                ? '取消收藏'
                                : '收藏',
                            onTap: () {
                              Navigator.pop(context);
                              _toggleFavorite(file);
                            },
                          ),
                          _buildOptionTile(
                            icon: Icons.delete,
                            color: Colors.red,
                            title: '删除视频',
                            onTap: () {
                              Navigator.pop(context);
                              _showDeleteConfirmDialog(file);
                            },
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
        child: Opacity(
          opacity: enabled ? 1.0 : 0.5,
          child: Container(
            width: MediaQuery.of(context).size.width / 3,
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 28),
                SizedBox(height: 8),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12),
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
                  final result = await _platform
                      .invokeMethod<String>('tomp4', {"path": file.path});

                  setState(() {
                    isFFmpeged = true;
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
                style: TextStyle(color: Colors.lightBlue),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showExtractSubtitleDialog(File file) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.subtitles, color: Colors.purple),
              SizedBox(width: 10),
              Text('抽取内挂字幕'),
            ],
          ),
          content: Text('确定要抽取该视频的内挂字幕吗？'),
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
                          Text('正在抽取字幕...'),
                        ],
                      ),
                    );
                  },
                );

                try {
                  if (await _settingsService.getExtractAssSubtitle()) {
                    if (isFFmpeged) {
                      Navigator.pop(context); // Close progress dialog

                      showDialog(
                        context: context,
                        builder: (context) {
                          return AlertDialog(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            title: Row(
                              children: [
                                Icon(Icons.warning, color: Colors.orange),
                                SizedBox(width: 10),
                                Text('操作受限'),
                              ],
                            ),
                            content: Text(
                                '由于当前限制，ASS内挂字幕抽取功能每次只能运行一次，请重启应用或关闭ASS抽取。'),
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
                      return;
                    }

                    final _platform =
                        const MethodChannel('samples.flutter.dev/ffmpegplugin');
                    await _platform.invokeMethod<String>(
                        'getsrt', {"path": file.path, "type": "ass"});
                    setState(() {
                      isFFmpeged = true;
                    });
                  } else {
                    final _platform =
                        const MethodChannel('samples.flutter.dev/ffmpegplugin');
                    await _platform.invokeMethod<String>(
                        'getsrtold', {"path": file.path, "type": "ass"});
                  }

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
                            Text('抽取完成'),
                          ],
                        ),
                        content: Text('内挂字幕抽取已启动，请自行到库文件夹检查结果。'),
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
                            Text('抽取失败'),
                          ],
                        ),
                        content: Text('字幕抽取失败: $e'),
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
                '开始抽取',
                style: TextStyle(color: Colors.lightBlue),
              ),
            ),
          ],
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
                          color: Colors.lightBlue,
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
