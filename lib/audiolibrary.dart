import 'package:aloeplayer/webdav.dart';
import 'package:flutter/material.dart';
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
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'dart:typed_data';

class AudioLibraryTab extends StatefulWidget {
  final Function(String) getopenfile;
  final Function(int) changeTab;

  AudioLibraryTab({required this.getopenfile, required this.changeTab});

  @override
  _AudioLibraryTabState createState() => _AudioLibraryTabState();
}

class _AudioLibraryTabState extends State<AudioLibraryTab> {
  final String _audioDirPath =
      '/storage/Users/currentUser/Download/com.aloereed.aloeplayer/Audios';
  final String _audioDirPathOld = '/data/storage/el2/base/Audios';
  List<File> _audioFiles = [];
  List<File> _filteredAudioFiles = []; // 用于存储过滤后的音频文件
  String _searchQuery = ''; // 搜索框的内容
  bool _isGridView = true; // 是否以网格视图显示  

  @override
  void initState() {
    super.initState();
    _ensureAudioDirectoryExists();
    _loadAudioFiles();
  }

  // 确保音频目录存在
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

  // 加载音频文件
  Future<void> _loadAudioFiles() async {
    final directory = Directory(_audioDirPath);
    List<File> files = [];
    if (await directory.exists()) {
      files = directory.listSync().whereType<File>().toList();
    }
    final directoryOld = Directory(_audioDirPathOld);
    List<File> filesOld = [];
    if (await directoryOld.exists()) {
      filesOld = directoryOld.listSync().whereType<File>().toList();
    }
    // 拼接新旧音频文件
    final filesCap = [...files, ...filesOld];
    setState(() {
      _audioFiles = filesCap;
      _filteredAudioFiles = filesCap; // 初始化时显示所有文件
    });
  }

  void _openWebDavFileManager(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return WebDAVDialog(
            onLoadFiles: _loadAudioFiles,
            fileExts: ['mp3', 'flac', 'wav', 'm4a', 'aac', 'ogg']);
      },
    );
  }

  // 根据搜索内容过滤音频文件
  void _filterAudioFiles(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredAudioFiles = _audioFiles; // 无搜索内容时显示全部
      } else {
        _filteredAudioFiles = _audioFiles
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
        'mp3',
        'wav',
        'flac',
        'aac',
        'm4a',
        'ogg'
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
    final destinationPath = path.join(_audioDirPath, fileName);
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
      _loadAudioFiles();
    }
  }

  // 删除音频文件
  Future<void> _deleteAudioFile(File file) async {
    await file.delete();
    _loadAudioFiles(); // 刷新音频列表
  }

  // 获取音频缩略图
  Future<Uint8List?> _getAudioThumbnail(File file) async {
    final metadata = readMetadata(file, getImage: true);
    return metadata.pictures[0].bytes;
  }

  // 获取音频时长
  Future<Duration> _getAudioDuration(File file) async {
    final metadata = readMetadata(file, getImage: false);
    return metadata.duration??Duration.zero;
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
                hintText: '搜索音频...',
                border: InputBorder.none,
                prefixIcon: Icon(Icons.search),
                contentPadding: EdgeInsets.symmetric(horizontal: 16),
              ),
              onChanged: _filterAudioFiles, // 监听搜索框内容变化
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
            onPressed: _pickAudioWithFilePicker,
          ),
          IconButton(
            icon: Icon(Icons.webhook),
            onPressed: () => _openWebDavFileManager(context),
          ),
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadAudioFiles,
          ),
        ],
      ),
      body: _filteredAudioFiles.isEmpty
          ? Center(child: Text('暂无音频'))
          : _isGridView
              ? GridView.builder(
                  padding: EdgeInsets.all(8),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: _filteredAudioFiles.length,
                  itemBuilder: (context, index) {
                    final file = _filteredAudioFiles[index];
                    return _buildAudioCard(file);
                  },
                )
              : ListView.builder(
                  padding: EdgeInsets.all(8),
                  itemCount: _filteredAudioFiles.length,
                  itemBuilder: (context, index) {
                    final file = _filteredAudioFiles[index];
                    return _buildAudioCard(file, isListView: true);
                  },
                ),
    );
  }

  Widget _buildAudioCard(File file, {bool isListView = false}) {
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
                          title: Text('删除音频'),
                          content: Text('确定要删除该音频吗？'),
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
                                _deleteAudioFile(file); // 调用删除方法
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
          _getAudioThumbnail(file),
          _getAudioDuration(file),
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
