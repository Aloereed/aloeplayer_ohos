import '../services/network_directory_controller.dart';
import '../services/network_sort.dart';
import 'dart:async';
import '../services/webdav_path.dart';
import '../libsmb2_service/smb_path.dart';
import '../widgets/member_badge.dart';
import '../services/member_access.dart';
import '../widgets/member_feature_prompt.dart';
import '../widgets/batch_download_sheet.dart';
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
import '../mpvplayer.dart';

enum ViewMode { list, grid }

enum SortType { name, size, modified }

enum SortOrder { ascending, descending }

class BrowserPage extends StatefulWidget {
  final ServerConfig serverConfig;

  final FileService? fileService;
  final HttpService? httpService;
  const BrowserPage(
      {Key? key,
      required this.serverConfig,
      this.fileService,
      this.httpService})
      : super(key: key);

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  late final FileService _fileService;
  late final HttpService _httpService;
  late final NetworkDirectoryController _directory;
  String? _connectionError;
  final ServerConfigService _configService = ServerConfigService();

  bool _isLoading = false;

  List<FileItem> _allFiles = [];
  List<FileItem> _displayedFiles = [];
  List<FileItem> _sortedFiles = [];
  List<FileItem>? _sortedInput;
  SortType? _cachedSortType;
  SortOrder? _cachedSortOrder;
  String _currentPath = '/';
  List<String> get _pathHistory => _directory.history;

  // UI设置
  ViewMode _viewMode = ViewMode.list;
  SortType _sortType = SortType.name;
  SortOrder _sortOrder = SortOrder.ascending;

  // 搜索
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _fileService = widget.fileService ??
        FileServiceFactory.createService(widget.serverConfig.type);
    _httpService = widget.httpService ?? HttpService.instance;
    _directory = NetworkDirectoryController(_fileService)
      ..addListener(_syncDirectory);

    _connectAndLoad();
  }

  @override
  void dispose() {
    _directory.dispose();
    _fileService.disconnect();
    _searchController.dispose();
    super.dispose();
  }

  void _syncDirectory() {
    if (!mounted) return;
    setState(() {
      _isLoading = _directory.loading;
      _currentPath = _directory.path;
      _allFiles = _directory.files;
    });
    _applyFilters();
  }

  Future<void> _connectAndLoad(
      {bool resume = false, String? targetPath}) async {
    if (!mounted) return;
    final target = targetPath ??
        (resume
            ? (_directory.failedPath ?? _currentPath)
            : (widget.serverConfig.type == ServerType.smb
                ? '/'
                : widget.serverConfig.initialPath));
    setState(() {
      _isLoading = true;
      _connectionError = null;
    });
    try {
      if (!await _httpService.startServer()) throw StateError('无法启动本地播放服务');
      final config = widget.serverConfig.type == ServerType.webdav
          ? widget.serverConfig.copyWith(initialPath: target)
          : widget.serverConfig;
      if (!await _fileService.connect(config))
        throw StateError('连接失败，请检查服务器配置');
      if (!mounted) {
        await _fileService.disconnect();
        return;
      }
      _httpService.setFileService(_fileService);
      // Remembering a timestamp must not turn a working NAS connection into a
      // failure if the local preferences/keystore are busy or unavailable.
      unawaited(_configService
          .updateLastConnected(widget.serverConfig.id)
          .catchError((Object _) {}));
      if (mounted) await _loadFiles(target);
    } catch (error) {
      if (mounted) setState(() => _connectionError = error.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _loadFiles(String target, {bool remember = false}) async {
    if (!mounted || !_fileService.isConnected) return false;
    return _directory.open(target, remember: remember);
  }

  Future<void> _openPath() async {
    var target = _directory.failedPath ?? _currentPath;
    final chosen = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('打开路径'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(
                    initialValue: target,
                    autofocus: true,
                    onChanged: (value) => target = value,
                    onFieldSubmitted: (value) => Navigator.pop(ctx, value),
                    decoration: const InputDecoration(
                        labelText: '目录路径', hintText: '/共享名/文件夹')),
                const SizedBox(height: 12),
                Text(widget.serverConfig.type == ServerType.smb
                    ? '服务器根目录下可直接填写 /共享名。若连接时已指定共享，则填写该共享内的路径。'
                    : '填写相对于服务器 URL 的目录路径。'),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, target),
                    child: const Text('打开'))
              ],
            ));
    if (chosen == null || !mounted) return;
    try {
      final normalized = widget.serverConfig.type == ServerType.smb
          ? smbCanonicalPath(chosen)
          : WebDavPaths.canonical(chosen);
      if (!_fileService.isConnected || _connectionError != null) {
        await _connectAndLoad(targetPath: normalized);
      } else {
        await _loadFiles(normalized, remember: true);
      }
    } catch (error) {
      _showError(error.toString());
    }
  }

  void _applyFilters() {
    // Sort once per directory snapshot / order change, not on each keystroke
    // or loading notification. Filtering an already sorted list preserves order.
    if (!identical(_sortedInput, _allFiles) ||
        _cachedSortType != _sortType ||
        _cachedSortOrder != _sortOrder) {
      final sorted = List<FileItem>.of(_allFiles);
      sorted.sort((a, b) {
        int comparison;
        switch (_sortType) {
          case SortType.name:
            // 文件夹优先
            if (a.isDirectory && !b.isDirectory) return -1;
            if (!a.isDirectory && b.isDirectory) return 1;
            comparison = compareNetworkNames(a.name, b.name);
            break;
          case SortType.size:
            if (a.isDirectory && !b.isDirectory) return -1;
            if (!a.isDirectory && b.isDirectory) return 1;
            comparison = a.size.compareTo(b.size);
            break;
          case SortType.modified:
            if (a.isDirectory && !b.isDirectory) return -1;
            if (!a.isDirectory && b.isDirectory) return 1;
            comparison = (a.modified ?? DateTime(1970))
                .compareTo(b.modified ?? DateTime(1970));
            break;
        }
        if (comparison == 0) comparison = compareNetworkNames(a.path, b.path);
        return _sortOrder == SortOrder.ascending ? comparison : -comparison;
      });
      _sortedFiles = sorted;
      _sortedInput = _allFiles;
      _cachedSortType = _sortType;
      _cachedSortOrder = _sortOrder;
    }
    final query = _searchController.text.toLowerCase();
    final filtered = query.isEmpty
        ? _sortedFiles
        : _sortedFiles
            .where((file) => file.name.toLowerCase().contains(query))
            .toList();
    setState(() => _displayedFiles = filtered);
  }

  void _onFileSelected(FileItem file) async {
    if (file.isDirectory) {
      _loadFiles(file.path, remember: true);
    } else {
      // 检查是否为视频文件
      if (isNetworkMedia(file)) {
        await _playVideo(file);
      } else {
        _showFileOptions(file);
      }
    }
  }

  Future<void> _playVideo(FileItem file) async {
    try {
      // 生成HTTP链接
      final queue =
          networkQueue(widget.serverConfig, _displayedFiles, _httpService);
      final httpUrl = queue
          .firstWhere((m) =>
              m.id == PlaybackMedia.remoteId(widget.serverConfig.id, file.path))
          .url;

      // 导航到播放器
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                MPVPlayer(filePath: httpUrl, mediaQueue: queue),
          ),
        );
      }
    } catch (e) {
      _showError('播放失败: $e');
    }
  }

  bool _addingBatch = false;
  Future<void> _batchDownload() async {
    if (_addingBatch || _isLoading) return;
    final files =
        _displayedFiles.where((f) => !f.isDirectory && f.size >= 0).toList();
    if (files.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('当前列表没有可下载的文件')));
      return;
    }
    setState(() => _addingBatch = true);
    try {
      final selected = await selectBatchDownloads(context, files);
      if (selected == null || !mounted) return;
      if (!await requestMemberFeature(context, MemberFeature.batchDownload) ||
          !mounted) return;
      final resolved = <FileItem>[];
      var metadataFailures = 0;
      for (var i = 0; i < selected.length; i += 4) {
        final batch =
            await Future.wait(selected.skip(i).take(4).map((file) async {
          try {
            return await resolveFileSize(_fileService, file);
          } catch (_) {
            return null;
          }
        }));
        for (final file in batch) {
          if (file != null) {
            resolved.add(file);
          } else {
            metadataFailures++;
          }
        }
        if (!mounted) return;
      }
      if (resolved.isEmpty) {
        _showError('无法取得文件大小，请刷新目录后重试');
        return;
      }
      final result = await DownloadManager.instance
          .addBatch(widget.serverConfig, resolved);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '已加入 ${result.added} 个，跳过已有任务 ${result.skipped} 个，失败 ${result.failed + metadataFailures} 个')));
      if (result.added > 0)
        await Navigator.push(
            context, MaterialPageRoute(builder: (_) => const DownloadsPage()));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('部分任务可能已加入，请在下载任务中查看后重试')));
    } finally {
      if (mounted) setState(() => _addingBatch = false);
    }
  }

  Future<void> _downloadFile(FileItem file) async {
    try {
      final resolved = await resolveFileSize(_fileService, file);
      if (!mounted) return;
      await DownloadManager.instance.add(widget.serverConfig, resolved);
      if (!mounted) return;
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => const DownloadsPage()));
    } catch (e) {
      if (mounted) _showError('添加下载失败: $e');
    }
  }

  void _showFileOptions(FileItem file) async {
    if (!mounted) return;
    final httpUrl =
        file.isDirectory ? null : _httpService.getFileUrlLocalhost(file.path);

    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
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
              '大小: ${hasKnownFileSize(file) ? _formatFileSize(file.size) : '待获取'}',
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
            if (!file.isDirectory)
              ListTile(
                  leading: const Icon(Icons.share),
                  title: const Text('生成局域网共享链接'),
                  onTap: () async {
                    try {
                      await _httpService.enableLanSharing();
                      final url = _httpService.getFileUrl(file.path);
                      await Clipboard.setData(ClipboardData(text: url));
                      if (mounted) _showSuccess('共享链接已复制，24 小时有效');
                    } catch (e) {
                      if (mounted) _showError('$e');
                    }
                  }),
            ListTile(
                leading: const Icon(Icons.stop_circle_outlined),
                title: const Text('停止文件共享'),
                onTap: () async {
                  await _httpService.disableLanSharing();
                  if (context.mounted) Navigator.pop(context);
                }),
            const Divider(height: 16),
            if (httpUrl != null)
              const Text(
                '本机播放链接:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            const SizedBox(height: 8),
            if (httpUrl != null)
              ListTile(
                leading: const Icon(Icons.link),
                title: Text(httpUrl,
                    style: const TextStyle(fontSize: 12),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: httpUrl));
                      Navigator.pop(context);
                      _showSuccess('链接已复制');
                    }),
              ),
          ],
        )),
      ),
    );
  }

  void _goBack() {
    if (_pathHistory.isNotEmpty) {
      _directory.back();
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
                  _sortOrder =
                      value ? SortOrder.descending : SortOrder.ascending;
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
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
                  ),
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
              PopupMenuButton<String>(
                  tooltip: '更多操作',
                  onSelected: (value) {
                    if (value == 'refresh')
                      _fileService.isConnected
                          ? _loadFiles(_directory.failedPath ?? _currentPath)
                          : _connectAndLoad(resume: true);
                    if (value == 'path') _openPath();
                    if (value == 'reconnect') _connectAndLoad(resume: true);
                    if (value == 'batch') _batchDownload();
                  },
                  itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'refresh', child: Text('刷新')),
                        PopupMenuItem(
                            value: 'path',
                            enabled: _fileService.isConnected,
                            child: const Text('打开路径')),
                        const PopupMenuItem(
                            value: 'reconnect', child: Text('重新连接')),
                        PopupMenuItem(
                            value: 'batch',
                            enabled: !_isLoading && !_addingBatch,
                            child: _addingBatch
                                ? const Text('正在添加下载…')
                                : const MemberFeatureLabel('批量下载')),
                      ]),
            ],
          ],
        ),
        body: _isLoading
            ? const Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在连接或读取目录…')
              ]))
            : _connectionError != null
                ? Center(
                    child: SingleChildScrollView(
                        child: _buildFailure(_connectionError!)))
                : Column(children: [
                    if (_directory.error != null)
                      _buildFailure(_directory.error!),
                    Expanded(
                        child: _displayedFiles.isEmpty
                            ? (_directory.error == null
                                ? _buildEmptyState()
                                : const SizedBox.shrink())
                            : RefreshIndicator(
                                onRefresh: () async {
                                  await _loadFiles(_currentPath);
                                },
                                child: _viewMode == ViewMode.list
                                    ? _buildListView()
                                    : _buildGridView())),
                  ]),
      ),
    );
  }

  Widget _buildFailure(String message) => Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_connectionError != null ? '无法连接服务器' : '无法读取目录',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(message, maxLines: 4, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  FilledButton.tonal(
                      onPressed: () => _fileService.isConnected &&
                              _connectionError == null
                          ? _loadFiles(_directory.failedPath ?? _currentPath)
                          : _connectAndLoad(resume: true),
                      child: const Text('重试')),
                  TextButton(onPressed: _openPath, child: const Text('打开路径')),
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('返回服务器列表')),
                ]),
              ])));

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
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _displayedFiles.length,
      itemBuilder: (context, index) {
        final file = _displayedFiles[index];
        final isVideo = !file.isDirectory && isNetworkMedia(file);

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
              : Text(hasKnownFileSize(file)
                  ? _formatFileSize(file.size)
                  : '大小待获取'),
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
      physics: const AlwaysScrollableScrollPhysics(),
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
        final isVideo = !file.isDirectory && isNetworkMedia(file);

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
                    hasKnownFileSize(file)
                        ? _formatFileSize(file.size)
                        : '大小待获取',
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
