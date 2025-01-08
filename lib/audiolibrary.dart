import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as path;
import 'package:media_info/media_info.dart';
import 'package:video_player/video_player.dart';

class AudioLibraryTab extends StatefulWidget {
  final Function(String) getopenfile;
  final Function(int) changeTab;

  AudioLibraryTab({required this.getopenfile, required this.changeTab});

  @override
  _AudioLibraryTabState createState() => _AudioLibraryTabState();
}

class _AudioLibraryTabState extends State<AudioLibraryTab> {
  final String _audioDirPath = '/data/storage/el2/base/Audios';
  List<File> _audioFiles = [];
  List<File> _filteredAudioFiles = []; // 用于存储过滤后的音频文件
  String _searchQuery = ''; // 搜索框的内容

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
  }

  // 加载音频文件
  Future<void> _loadAudioFiles() async {
    final directory = Directory(_audioDirPath);
    if (await directory.exists()) {
      final files = directory.listSync().whereType<File>().toList();
      setState(() {
        _audioFiles = files;
        _filteredAudioFiles = files; // 初始化时显示所有文件
      });
    }
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

  // 使用file_selector选择音频文件
  Future<void> _pickAudioWithFileSelector() async {
    final typeGroup = XTypeGroup(
        label: 'audios',
        extensions: ['mp3', 'flac', 'wav', 'm4a', 'aac', 'ogg']);
    final XFile? file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file != null) {
      await _copyAudioFile(file);
    }
  }

  // 使用image_picker选择音频文件

  Future<void> _copyAudioFile(XFile file) async {
    final fileName = path.basename(file.path);
    final destinationPath = path.join(_audioDirPath, fileName);
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
      _loadAudioFiles(); // 刷新音频列表
    }
  }

  // 删除音频文件
  Future<void> _deleteAudioFile(File file) async {
    await file.delete();
    _loadAudioFiles(); // 刷新音频列表
  }

  // 获取音频缩略图
  Future<Uint8List?> _getAudioThumbnail(File file) async {
    return null;
  }

  // 获取音频时长
  Future<Duration> _getAudioDuration(File file) async {
    // 使用videoplayer获取时长
    final videoPlayerController = VideoPlayerController.file(file);

    // 初始化控制器
    await videoPlayerController.initialize();

    // 获取视频时长
    final duration = videoPlayerController.value.duration;

    // 释放控制器资源
    videoPlayerController.dispose();

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
            icon: Icon(Icons.add),
            onPressed: _pickAudioWithFileSelector,
          ),
        ],
      ),
      body: _filteredAudioFiles.isEmpty
          ? Center(child: Text('暂无音频'))
          : GridView.builder(
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
                          title: Text('删除音频'),
                          content: Text('确定要删除该音频吗？'),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                              },
                              child: Text('取消'),
                            ),
                            TextButton(
                              onPressed: () {
                                _deleteAudioFile(file);
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
                      _getAudioThumbnail(file),
                      _getAudioDuration(file),
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
