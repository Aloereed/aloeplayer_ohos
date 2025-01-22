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

class VideoLibraryTab extends StatefulWidget {
  final Function(String) getopenfile;
  final Function(int) changeTab;

  VideoLibraryTab({required this.getopenfile, required this.changeTab});

  @override
  _VideoLibraryTabState createState() => _VideoLibraryTabState();
}

class _VideoLibraryTabState extends State<VideoLibraryTab> {
  final String _videoDirPath =
      '/storage/Users/currentUser/Download/com.aloereed.aloeplayer/Videos';
  final String _videoDirPathOld = '/data/storage/el2/base/Videos';
  List<File> _videoFiles = [];
  List<File> _filteredVideoFiles = []; // 用于存储过滤后的视频文件
  String _searchQuery = ''; // 搜索框的内容
  bool _isGridView = true; // 默认显示Grid视图

  @override
  void initState() {
    super.initState();
    _ensureVideoDirectoryExists();
    _loadVideoFiles();
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
  }

// 加载视频文件
  Future<void> _loadVideoFiles() async {
    final directory = Directory(_videoDirPath);
    List<File> files = [];
    if (await directory.exists()) {
      files = directory.listSync().whereType<File>().where((file) {
        // 获取文件扩展名
        String extension = path.extension(file.path).toLowerCase();
        // 排除 .srt 和 .ass 文件
        return extension != '.srt' && extension != '.ass';
      }).toList();
    }

    final directoryOld = Directory(_videoDirPathOld);
    List<File> filesOld = [];
    if (await directoryOld.exists()) {
      filesOld = directoryOld.listSync().whereType<File>().where((file) {
        // 获取文件扩展名
        String extension = path.extension(file.path).toLowerCase();
        // 排除 .srt 和 .ass 文件
        return extension != '.srt' && extension != '.ass';
      }).toList();
    }

    // 拼接新旧视频文件
    final filesCap = [...files, ...filesOld];
    setState(() {
      _videoFiles = filesCap;
      _filteredVideoFiles = filesCap; // 初始化时显示所有文件
    });
  }

  // 根据搜索内容过滤视频文件
  void _filterVideoFiles(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredVideoFiles = _videoFiles; // 无搜索内容时显示全部
      } else {
        _filteredVideoFiles = _videoFiles
            .where((file) => path
                .basename(file.path)
                .toLowerCase()
                .contains(query.toLowerCase()))
            .toList(); // 过滤文件名包含搜索字符串的文件
      }
    });
  }

  // 使用file_picker选择视频文件
  Future<void> _pickVideoWithFilePicker() async {
    await _ensureVideoDirectoryExists();
    // 使用 FilePicker 选择多个视频文件
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'mp4',
        'mkv',
        'avi',
        'mov',
        'flv',
        'wmv',
        'webm'
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
    final XFile? file = await picker.pickVideo(source: ImageSource.gallery);
    if (file != null) {
      await _copyVideoFile(file);
    }
  }

  Future<void> _copyVideoFile(XFile file) async {
    final fileName = path.basename(file.path);
    final destinationPath = path.join(_videoDirPath, fileName);
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
      _loadVideoFiles();
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
          _loadVideoFiles(); // 刷新视频列表
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

  // 删除视频文件
  Future<void> _deleteVideoFile(File file) async {
    await file.delete();
    _loadVideoFiles(); // 刷新视频列表
  }

  // 获取视频缩略图
  Future<Uint8List?> _getVideoThumbnail(File file) async {
    final thumbnail = await VideoThumbnailOhos.thumbnailData(
      video: file.path,
      imageFormat: ImageFormat.JPEG,
      maxWidth: 128, // 缩略图的最大宽度
      quality: 25, // 缩略图的质量 (0-100)
    );
    return thumbnail;
  }

  // 获取视频时长
  Future<Duration> _getVideoDuration(File file) async {
    // 创建 MediaInfo 实例
    MediaInfo mediaInfo = MediaInfo();

    // 获取视频文件的元数据
    Map<String, dynamic> metadata = await mediaInfo.getMediaInfo(file.path);

    // 从元数据中提取视频时长
    int durationInMilliseconds = metadata['durationMs'];

    // 将毫秒转换为 Duration 对象
    Duration duration = Duration(milliseconds: durationInMilliseconds);

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

  void _openWebDavFileManager(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return WebDAVDialog(
            onLoadFiles: _loadVideoFiles,
            fileExts: ['mp4', 'mkv', 'avi', 'mov', 'flv', 'wmv', 'webm']);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Container(
          width: double.infinity,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: TextField(
              decoration: InputDecoration(
                hintText: '搜索视频...',
                border: InputBorder.none,
                prefixIcon: Icon(Icons.search),
                contentPadding: EdgeInsets.symmetric(horizontal: 16),
              ),
              onChanged: _filterVideoFiles, // 监听搜索框内容变化
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(_isGridView ? Icons.list : Icons.grid_view),
            onPressed: () {
              setState(() {
                _isGridView = !_isGridView; // 切换视图模式
              });
            },
          ),
          IconButton(
            icon: Icon(Icons.add),
            onPressed: _pickVideoWithFilePicker,
          ),
          IconButton(
            icon: Icon(Icons.video_library),
            onPressed: _pickVideoWithImagePicker,
          ),
          IconButton(
            icon: Icon(Icons.webhook),
            onPressed: () => _openWebDavFileManager(context),
          ),
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadVideoFiles,
          ),
        ],
      ),
      body: _filteredVideoFiles.isEmpty
          ? Center(child: Text('暂无视频'))
          : _isGridView
              ? GridView.builder(
                  padding: EdgeInsets.all(8),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: _filteredVideoFiles.length,
                  itemBuilder: (context, index) {
                    final file = _filteredVideoFiles[index];
                    return _buildVideoCard(file);
                  },
                )
              : ListView.builder(
                  padding: EdgeInsets.all(8),
                  itemCount: _filteredVideoFiles.length,
                  itemBuilder: (context, index) {
                    final file = _filteredVideoFiles[index];
                    return _buildVideoCard(file, isListView: true);
                  },
                ),
    );
  }

  Widget _buildVideoCard(File file, {bool isListView = false}) {
    return GestureDetector(
      onTap: () {
        widget.getopenfile(file.path); // 更新_openfile状态
        widget.changeTab(0); // 切换到PlayerTab
      },
      onLongPress: () {
        showModalBottomSheet(
          context: context,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(15.0),
            ),
          ),
          builder: (context) {
            return Wrap(
              children: [
                // 抽取内挂字幕到库文件夹
                ListTile(
                  leading: Icon(Icons.subtitles, color: Colors.grey),
                  title: Text('抽取内挂字幕'),
                  onTap: () {
                    Navigator.pop(context); // 关闭弹窗
                    showDialog(
                      context: context,
                      builder: (context) {
                        return AlertDialog(
                          title: Text('抽取内挂字幕'),
                          content: Text('确定要抽取该视频的内挂字幕吗？'),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context); // 关闭对话框
                              },
                              child: Text('取消',
                                  style: TextStyle(color: Colors.red)),
                            ),
                            TextButton(
                              onPressed: () async {
                                Navigator.pop(context); // 关闭对话框
                                final _platform = const MethodChannel(
                                    'samples.flutter.dev/ffmpegplugin');
                                // 调用方法 getBatteryLevel
                                final result = await _platform
                                    .invokeMethod<String>(
                                        'getsrt', {"path": file.path});
                                showDialog(
                                  context: context,
                                  builder: (context) {
                                    return AlertDialog(
                                      title: Text('抽取内挂字幕'),
                                      content: Text('内挂字幕抽取已启动，请自行到库文件夹检查结果。'),
                                      actions: [
                                        TextButton(
                                          onPressed: () {
                                            Navigator.pop(context); // 关闭对话框
                                          },
                                          child: Text('确定',
                                              style: TextStyle(
                                                  color: Colors.blue)),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                              child: Text('确定',
                                  style: TextStyle(color: Colors.blue)),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
                ListTile(
                  leading: Icon(Icons.share, color: Colors.blue), // 分享图标
                  title: Text('分享'),
                  onTap: () {
                    Navigator.pop(context); // 关闭弹窗
                    Share.shareXFiles([XFile(file.path)]); // 使用 SharePlus 分享
                  },
                ),
                ListTile(
                  leading: Icon(Icons.delete, color: Colors.red), // 删除图标
                  title: Text('删除'),
                  onTap: () {
                    Navigator.pop(context); // 关闭弹窗
                    showDialog(
                      context: context,
                      builder: (context) {
                        return AlertDialog(
                          title: Text('删除视频'),
                          content: Text('确定要删除该视频吗？'),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context); // 关闭对话框
                              },
                              child: Text('取消',
                                  style: TextStyle(color: Colors.red)),
                            ),
                            TextButton(
                              onPressed: () {
                                _deleteVideoFile(file); // 调用删除方法
                                Navigator.pop(context); // 关闭对话框
                              },
                              child: Text('删除',
                                  style: TextStyle(color: Colors.blue)),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ],
            );
          },
        );
      },
      child: FutureBuilder(
        future: Future.wait([
          _getVideoThumbnail(file),
          _getVideoDuration(file),
        ]),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Card(
              child: isListView
                  ? ListTile(
                      title: Text(
                        path.basename(file.path),
                        style: TextStyle(fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text('加载中...'),
                      leading: CircularProgressIndicator(),
                    )
                  : Column(
                      children: [
                        Expanded(
                          child: Center(child: CircularProgressIndicator()),
                        ),
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                path.basename(file.path),
                                style: TextStyle(fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '时长: 正在加载...',
                                style: TextStyle(fontSize: 10),
                              ),
                              Text(
                                '大小: ${_getFileSize(file)}',
                                style: TextStyle(fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            );
          }
          final thumbnail = snapshot.data?[0] as Uint8List?;
          final duration = snapshot.data?[1] as Duration?;
          return Card(
            child: isListView
                ? ListTile(
                    leading: thumbnail != null
                        ? Image.memory(thumbnail, fit: BoxFit.cover, width: 64)
                        : Icon(Icons.video_library, size: 50),
                    title: Text(
                      path.basename(file.path),
                      style: TextStyle(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '时长: ${duration?.inMinutes}:${duration?.inSeconds.remainder(60)}',
                          style: TextStyle(fontSize: 10),
                        ),
                        Text(
                          '大小: ${_getFileSize(file)}',
                          style: TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      Expanded(
                        child: thumbnail != null
                            ? Image.memory(thumbnail, fit: BoxFit.cover)
                            : Icon(Icons.video_library, size: 50),
                      ),
                      Padding(
                        padding: EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              path.basename(file.path),
                              style: TextStyle(fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '时长: ${duration?.inMinutes}:${duration?.inSeconds.remainder(60)}',
                              style: TextStyle(fontSize: 10),
                            ),
                            Text(
                              '大小: ${_getFileSize(file)}',
                              style: TextStyle(fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }
}
