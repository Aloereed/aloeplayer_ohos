import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as path;
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:media_info/media_info.dart';

class VideoLibraryTab extends StatefulWidget {
  final Function(String) getopenfile;
  final Function(int) changeTab;

  VideoLibraryTab({required this.getopenfile, required this.changeTab});

  @override
  _VideoLibraryTabState createState() => _VideoLibraryTabState();
}

class _VideoLibraryTabState extends State<VideoLibraryTab> {
  final String _videoDirPath = '/data/storage/el2/base/Videos';
  List<File> _videoFiles = [];
  List<File> _filteredVideoFiles = []; // 用于存储过滤后的视频文件
  String _searchQuery = ''; // 搜索框的内容

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
  }

  // 加载视频文件
  Future<void> _loadVideoFiles() async {
    final directory = Directory(_videoDirPath);
    if (await directory.exists()) {
      final files = directory.listSync().whereType<File>().toList();
      setState(() {
        _videoFiles = files;
        _filteredVideoFiles = files; // 初始化时显示所有文件
      });
    }
  }

  // 根据搜索内容过滤视频文件
  void _filterVideoFiles(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredVideoFiles = _videoFiles; // 无搜索内容时显示全部
      } else {
        _filteredVideoFiles = _videoFiles
            .where((file) =>
                path.basename(file.path).toLowerCase().contains(query.toLowerCase()))
            .toList(); // 过滤文件名包含搜索字符串的文件
      }
    });
  }

  // 使用file_selector选择视频文件
  Future<void> _pickVideoWithFileSelector() async {
    final typeGroup =
        XTypeGroup(label: 'videos', extensions: ['mp4', 'mkv', 'avi']);
    final XFile? file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file != null) {
      await _copyVideoFile(file);
    }
  }

  // 使用image_picker选择视频文件
  Future<void> _pickVideoWithImagePicker() async {
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

    try {
      // 打开源文件的输入流
      final inputStream = File(file.path).openRead();
      // 打开目标文件的输出流
      final outputStream = destinationFile.openWrite();

      // 监听输入流，逐块写入输出流
      await inputStream.pipe(outputStream);

      print("文件复制完成: $destinationPath");
    } catch (e) {
      print("文件复制失败: $e");
      // 如果复制失败，删除可能已创建的目标文件
      if (await destinationFile.exists()) {
        await destinationFile.delete();
      }
      rethrow; // 重新抛出异常
    } finally {
      _loadVideoFiles(); // 刷新视频列表
    }
  }

  // 删除视频文件
  Future<void> _deleteVideoFile(File file) async {
    await file.delete();
    _loadVideoFiles(); // 刷新视频列表
  }

  // 获取视频缩略图
  Future<Uint8List?> _getVideoThumbnail(File file) async {
    final thumbnail = await VideoThumbnail.thumbnailData(
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
    int durationInMilliseconds = metadata['duration'];

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
            icon: Icon(Icons.add),
            onPressed: _pickVideoWithFileSelector,
          ),
          IconButton(
            icon: Icon(Icons.video_library),
            onPressed: _pickVideoWithImagePicker,
          ),
        ],
      ),
      body: _filteredVideoFiles.isEmpty
          ? Center(child: Text('暂无视频'))
          : GridView.builder(
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
                return GestureDetector(
                  onTap: () {
                    widget.getopenfile(file.path); // 更新_openfile状态
                    widget.changeTab(0); // 切换到PlayerTab
                  },
                  onLongPress: () {
                    showDialog(
                      context: context,
                      builder: (context) {
                        return AlertDialog(
                          title: Text('删除视频'),
                          content: Text('确定要删除该视频吗？'),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                              },
                              child: Text('取消'),
                            ),
                            TextButton(
                              onPressed: () {
                                _deleteVideoFile(file);
                                Navigator.pop(context);
                              },
                              child: Text('删除'),
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
                        return Center(child: CircularProgressIndicator());
                      }
                      final thumbnail = snapshot.data?[0] as Uint8List?;
                      final duration = snapshot.data?[1] as Duration?;
                      return Card(
                        child: Column(
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
              },
            ),
    );
  }
}
