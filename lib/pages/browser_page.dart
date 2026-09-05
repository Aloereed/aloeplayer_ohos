import '../services/download_manager.dart';
import 'downloads_page.dart';
import '../models/playback_media.dart';
import '../services/network_playback.dart';
// lib/pages/browser_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/server_config.dart';
import '../services/file_service.dart';
import '../services/http_service.dart';
import '../services/server_config_service.dart';
import '../services/stream_cache_service.dart';
import '../mpvplayer.dart';
import 'package:path/path.dart' as path;
import 'package:file_picker_ohos/file_picker_ohos.dart';
import 'package:dio/dio.dart';
import 'dart:io';

enum ViewMode { list, grid }

enum SortType { name, size, modified }

enum SortOrder { ascending, descending }

class BrowserPage extends StatefulWidget {
  final ServerConfig serverConfig;

  const BrowserPage({Key? key, required this.serverConfig}) : super(key: key);

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  late final FileService _fileService;
  final HttpService _httpService = HttpService.instance;
  final ServerConfigService _configService = ServerConfigService();
  final StreamCacheService _cacheService = StreamCacheService.instance;

  bool _isLoading = false;
  bool _isConnected = false;

  List<FileItem> _allFiles = [];
  List<FileItem> _displayedFiles = [];
  String _currentPath = '/';
  final List<String> _pathHistory = [];

  // UI设置
  ViewMode _viewMode = ViewMode.list;
  SortType _sortType = SortType.name;
  SortOrder _sortOrder = SortOrder.ascending;

  // 搜索
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  // 媒体文件扩展名
  final List<String> _videoExtensions = [
    // 视频文件扩展名
    '.mp4',
    '.mkv',
    '.avi',
    '.mov',
    '.flv',
    '.wmv',
    '.webm',
    '.m4v',
    '.ts',
    '.mpg',
    '.mpeg',
    // 音频文件扩展名
    '.mp3',
    '.wav',
    '.aac',
    '.flac',
    '.m4a',
    '.ogg',
  ];

  @override
  void initState() {
    super.initState();
    _fileService = FileServiceFactory.createService(widget.serverConfig.type);
    
    _connectAndLoad();
  }

  @override
  void dispose() {
    _fileService.disconnect();
    _searchController.dispose();
    // TODO: 如果启用流式缓存，需要清理
    // _cacheService.clearAllCache();
    super.dispose();
  }

  Future<void> _connectAndLoad() async {
    setState(() => _isLoading = true);

    try {
      if (!await _httpService.startServer()) throw StateError('无法启动本地播放服务');
      final success = await _fileService.connect(widget.serverConfig);

      if (!mounted) { await _fileService.disconnect(); return; }
      if (success) {
        setState(() => _isConnected = true);

        // 将文件服务实例传递给HTTP服务
        if (_fileService is SmbFileService) {
          _httpService.setSmbService((_fileService as SmbFileService).smbService);
        } else if (_fileService is WebDavFileService) {
          _httpService.setWebDavService((_fileService as WebDavFileService).webdavService);
        }

        // 更新最后连接时间
        await _configService.updateLastConnected(widget.serverConfig.id);

        // 加载初始路径
        // 对于 SMB: 如果有 initialPath，连接时已经包含在 host 中，所以从 '/' 开始
        // 对于 WebDAV: initialPath 需要在这里使用
        final startPath = widget.serverConfig.type == ServerType.smb ? '/' : widget.serverConfig.initialPath;
        await _loadFiles(startPath);

        _showSuccess('连接成功');
      } else {
        _showError('连接失败，请检查服务器配置');
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      _showError('连接失败: $e');
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadFiles(String path) async {
    if (!mounted || !_fileService.isConnected) return;

    setState(() => _isLoading = true);

    try {
      final files = await _fileService.listFiles(path);
      if (!mounted) return;
      setState(() {
        _currentPath = path;
        _allFiles = files;
        _applyFilters();
      });
    } catch (e) {
      _showError('加载文件失败: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    List<FileItem> filtered = List.from(_allFiles);

    // 搜索过滤
    if (_searchController.text.isNotEmpty) {
      final query = _searchController.text.toLowerCase();
      filtered = filtered.where((file) {
        return file.name.toLowerCase().contains(query);
      }).toList();
    }

    // 排序
    filtered.sort((a, b) {
      int comparison;
      switch (_sortType) {
        case SortType.name:
          // 文件夹优先
          if (a.isDirectory && !b.isDirectory) return -1;
          if (!a.isDirectory && b.isDirectory) return 1;
          comparison = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          break;
        case SortType.size:
          if (a.isDirectory && !b.isDirectory) return -1;
          if (!a.isDirectory && b.isDirectory) return 1;
          comparison = a.size.compareTo(b.size);
          break;
        case SortType.modified:
          if (a.isDirectory && !b.isDirectory) return -1;
          if (!a.isDirectory && b.isDirectory) return 1;
          comparison = (a.modified ?? DateTime(1970)).compareTo(b.modified ?? DateTime(1970));
          break;
      }
      return _sortOrder == SortOrder.ascending ? comparison : -comparison;
    });

    setState(() => _displayedFiles = filtered);
  }

  void _onFileSelected(FileItem file) async {
    if (file.isDirectory) {
      _pathHistory.add(_currentPath);
      _loadFiles(file.path);
    } else {
      // 检查是否为视频文件
      if (_isVideoFile(file.name)) {
        await _playVideo(file);
      } else {
        _showFileOptions(file);
      }
    }
  }

  bool _isVideoFile(String filename) {
    final ext = path.extension(filename).toLowerCase();
    return _videoExtensions.contains(ext);
  }

  Future<void> _playVideo(FileItem file) async {
    try {
      // 生成HTTP链接
      final queue = networkQueue(widget.serverConfig, _displayedFiles, _httpService);
      final httpUrl = queue.firstWhere((m) => m.id == PlaybackMedia.remoteId(widget.serverConfig.id, file.path)).url;

      // 导航到播放器
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MPVPlayer(filePath: httpUrl, mediaQueue: queue),
          ),
        );
      }

      // TODO: 流式缓存播放（暂时禁用）
      // 如果需要启用直接流式播放，使用以下代码：
      /*
      // 显示加载对话框
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('准备播放...'),
            ],
          ),
        ),
      );

      // 获取文件流
      final stream = await _fileService.getFileStream(file.path);

      // 开始流式缓存
      final cachePath = await _cacheService.startStreamCache(
        stream: stream,
        fileName: file.name,
        fileSize: file.size,
      );

      // 等待最小缓存量（5MB 或 文件大小的 10%，取较小值）
      final minCache = (file.size * 0.1).toInt().clamp(2 * 1024 * 1024, 10 * 1024 * 1024);
      await _cacheService.waitForMinimumCache(cachePath, minBytes: minCache);

      // 关闭加载对话框
      if (mounted) {
        Navigator.of(context).pop();

        // 导航到播放器，传递本地缓存文件路径
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MPVPlayer(filePath: cachePath),
          ),
        ).then((_) {
          // 播放器关闭后，清理缓存
          _cacheService.stopCache(cachePath, deleteFile: true);
        });
      }
      */
    } catch (e) {
      _showError('播放失败: $e');
    }
  }

  Future<void> _downloadFile(FileItem file) async {
    try {
      await DownloadManager.instance.add(widget.serverConfig, file);
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadsPage()));
    } catch (e) { if (mounted) _showError('添加下载失败: $e'); }
  }

  void _showFileOptions(FileItem file) async {
    if (!mounted) return;
    final httpUrl = _httpService.getFileUrl(file.path);
    final accessUrls = _httpService.getAccessUrls();

    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              file.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '大小: ${_formatFileSize(file.size)}',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const Divider(height: 32),
            // 下载按钮
            if (!file.isDirectory)
              ListTile(
                leading: const Icon(Icons.download, color: Colors.blue),
                title: const Text('下载到本地'),
                onTap: () {
                  Navigator.pop(context);
                  _downloadFile(file);
                },
              ),
            ListTile(leading: const Icon(Icons.share), title: const Text('生成局域网共享链接'), onTap: () async {
              try {
                await _httpService.enableLanSharing();
                final url = _httpService.getFileUrl(file.path);
                await Clipboard.setData(ClipboardData(text: url));
                if (mounted) _showSuccess('共享链接已复制，24 小时有效');
              } catch (e) { if (mounted) _showError('$e'); }
            }),
            ListTile(leading: const Icon(Icons.stop_circle_outlined), title: const Text('停止文件共享'), onTap: () async {
              await _httpService.disableLanSharing();
              if (context.mounted) Navigator.pop(context);
            }),
            const Divider(height: 16),
            const Text(
              '本机播放链接:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...accessUrls.map((baseUrl) {
              final cleanPath =
                  file.path.startsWith('/') ? file.path.substring(1) : file.path;
              final fullUrl = '$baseUrl/file/$cleanPath';
              return ListTile(
                leading: const Icon(Icons.link),
                title: Text(
                  fullUrl,
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: fullUrl));
                    Navigator.pop(context);
                    _showSuccess('链接已复制');
                  },
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  void _goBack() {
    if (_pathHistory.isNotEmpty) {
      final previousPath = _pathHistory.removeLast();
      _loadFiles(previousPath);
    } else {
      Navigator.pop(context);
    }
  }

  void _showSortDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('排序方式'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<SortType>(
              title: const Text('按名称'),
              value: SortType.name,
              groupValue: _sortType,
              onChanged: (value) {
                setState(() => _sortType = value!);
                _applyFilters();
                Navigator.pop(context);
              },
            ),
            RadioListTile<SortType>(
              title: const Text('按大小'),
              value: SortType.size,
              groupValue: _sortType,
              onChanged: (value) {
                setState(() => _sortType = value!);
                _applyFilters();
                Navigator.pop(context);
              },
            ),
            RadioListTile<SortType>(
              title: const Text('按修改时间'),
              value: SortType.modified,
              groupValue: _sortType,
              onChanged: (value) {
                setState(() => _sortType = value!);
                _applyFilters();
                Navigator.pop(context);
              },
            ),
            const Divider(),
            SwitchListTile(
              title: const Text('降序'),
              value: _sortOrder == SortOrder.descending,
              onChanged: (value) {
                setState(() {
                  _sortOrder = value ? SortOrder.descending : SortOrder.ascending;
                });
                _applyFilters();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_pathHistory.isNotEmpty) {
          _goBack();
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _goBack,
          ),
          title: _isSearching
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: '搜索文件...',
                    border: InputBorder.none,
                    hintStyle: TextStyle(color: Colors.white70),
                  ),
                  style: const TextStyle(color: Colors.white),
                  onChanged: (value) => _applyFilters(),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.serverConfig.type == ServerType.smb
                              ? Icons.folder_shared
                              : Icons.cloud,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            widget.serverConfig.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      _currentPath,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
          actions: [
            if (_isSearching)
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _isSearching = false;
                    _searchController.clear();
                  });
                  _applyFilters();
                },
              )
            else ...[
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: () {
                  setState(() => _isSearching = true);
                },
              ),
              IconButton(
                icon: Icon(_viewMode == ViewMode.list
                    ? Icons.grid_view
                    : Icons.view_list),
                onPressed: () {
                  setState(() {
                    _viewMode = _viewMode == ViewMode.list
                        ? ViewMode.grid
                        : ViewMode.list;
                  });
                },
              ),
              IconButton(
                icon: const Icon(Icons.sort),
                onPressed: _showSortDialog,
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => _loadFiles(_currentPath),
              ),
            ],
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _displayedFiles.isEmpty
                ? _buildEmptyState()
                : _viewMode == ViewMode.list
                    ? _buildListView()
                    : _buildGridView(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _searchController.text.isNotEmpty
                ? Icons.search_off
                : Icons.folder_open,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            _searchController.text.isNotEmpty ? '没有找到匹配的文件' : '此文件夹为空',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildListView() {
    return ListView.builder(
      itemCount: _displayedFiles.length,
      itemBuilder: (context, index) {
        final file = _displayedFiles[index];
        final isVideo = !file.isDirectory && _isVideoFile(file.name);

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: file.isDirectory
                ? Colors.blue[100]
                : isVideo
                    ? Colors.red[100]
                    : Colors.grey[300],
            child: Icon(
              file.isDirectory
                  ? Icons.folder
                  : isVideo
                      ? Icons.play_circle_filled
                      : Icons.insert_drive_file,
              color: file.isDirectory
                  ? Colors.blue
                  : isVideo
                      ? Colors.red
                      : Colors.grey[600],
            ),
          ),
          title: Text(
            file.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: file.isDirectory
              ? const Text('文件夹')
              : Text(_formatFileSize(file.size)),
          trailing: isVideo
              ? IconButton(
                  icon: const Icon(Icons.play_arrow, color: Colors.red),
                  onPressed: () => _playVideo(file),
                )
              : null,
          onTap: () => _onFileSelected(file),
          onLongPress: () => _showFileOptions(file),
        );
      },
    );
  }

  Widget _buildGridView() {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.85,
      ),
      itemCount: _displayedFiles.length,
      itemBuilder: (context, index) {
        final file = _displayedFiles[index];
        final isVideo = !file.isDirectory && _isVideoFile(file.name);

        return Card(
          elevation: 2,
          child: InkWell(
            onTap: () => _onFileSelected(file),
            onLongPress: () => _showFileOptions(file),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  file.isDirectory
                      ? Icons.folder
                      : isVideo
                          ? Icons.play_circle_filled
                          : Icons.insert_drive_file,
                  size: 48,
                  color: file.isDirectory
                      ? Colors.blue
                      : isVideo
                          ? Colors.red
                          : Colors.grey[600],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    file.name,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                if (!file.isDirectory) ...[
                  const SizedBox(height: 4),
                  Text(
                    _formatFileSize(file.size),
                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
