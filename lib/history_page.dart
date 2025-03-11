import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'history_service.dart';
import 'settings.dart';
import 'package:path_provider/path_provider.dart';

class HistoryPage extends StatefulWidget {
  final Function(String) getOpenFile;
  final Function(BuildContext) startPlayerPage;

  const HistoryPage({
    Key? key,
    required this.getOpenFile,
    required this.startPlayerPage,
  }) : super(key: key);

  @override
  _HistoryPageState createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage>
    with SingleTickerProviderStateMixin {
  final HistoryService _historyService = HistoryService();
  late TabController _tabController;
  List<HistoryItem> _allHistory = [];
  List<HistoryItem> _audioHistory = [];
  List<HistoryItem> _videoHistory = [];
  bool _isLoading = true;
  String? _selectedMediaPath;
  bool _isGridView = false;
  String _thumbnailPath =
      '/storage/Users/currentUser/Download/com.aloereed.aloeplayer/Thumbnails';
  final _settingsService = SettingsService();
  @override
  void initState() async {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      setState(() {}); // Refresh UI when tab changes
    });
    bool useinnerthumb = await _settingsService.getUseInnerThumbnail();
    if (useinnerthumb) {
      // path join
      _thumbnailPath =
          path.join((await getTemporaryDirectory()).path, 'Thumbnails');
    }
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
    });

    try {
      _allHistory = await _historyService.getRecentHistory(limit: 100);
      _audioHistory = await _historyService.getRecentAudioHistory(limit: 100);
      _videoHistory = await _historyService.getRecentVideoHistory(limit: 100);
    } catch (e) {
      _showErrorSnackBar('加载历史记录失败: $e');
    } finally {
      setState(() {
        _isLoading = false;
        if (_selectedMediaPath != null) {
          // Keep selection if it exists in new data
          bool exists =
              _allHistory.any((item) => item.filePath == _selectedMediaPath);
          if (!exists) {
            _selectedMediaPath = null;
          }
        }
      });
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  void _playMedia(HistoryItem item) {
    try {
      widget.getOpenFile(item.filePath);
      widget.startPlayerPage(context);
    } catch (e) {
      _showErrorSnackBar('无法播放文件: $e');
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history_outlined,
            size: 80,
            color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无播放历史',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '播放媒体文件后会在此显示',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          // Add a subtle gradient background
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.surfaceVariant,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(),
              _buildTabBar(),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildTabBarView(),
              ),
              if (_selectedMediaPath != null) _buildNowPlayingBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '播放历史',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          Row(
            children: [
              IconButton(
                icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
                onPressed: () {
                  setState(() {
                    _isGridView = !_isGridView;
                  });
                },
                tooltip: _isGridView ? '列表视图' : '网格视图',
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onSelected: (value) async {
                  switch (value) {
                    case 'clear_all':
                      _showClearHistoryDialog(clearType: 'all');
                      break;
                    case 'clear_audio':
                      _showClearHistoryDialog(clearType: 'audio');
                      break;
                    case 'clear_video':
                      _showClearHistoryDialog(clearType: 'video');
                      break;
                    case 'refresh':
                      await _loadHistory();
                      break;
                  }
                },
                itemBuilder: (BuildContext context) => [
                  PopupMenuItem<String>(
                    value: 'refresh',
                    child: Row(
                      children: const [
                        Icon(Icons.refresh, size: 20),
                        SizedBox(width: 8),
                        Text('刷新'),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem<String>(
                    value: 'clear_all',
                    child: Row(
                      children: const [
                        Icon(Icons.delete_outline, size: 20),
                        SizedBox(width: 8),
                        Text('清除全部历史'),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'clear_audio',
                    child: Row(
                      children: const [
                        Icon(Icons.audiotrack_outlined, size: 20),
                        SizedBox(width: 8),
                        Text('清除音频历史'),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'clear_video',
                    child: Row(
                      children: const [
                        Icon(Icons.video_library_outlined, size: 20),
                        SizedBox(width: 8),
                        Text('清除视频历史'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25),
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.7),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(
              borderRadius: BorderRadius.circular(25),
              color: Theme.of(context).colorScheme.primary,
            ),
            labelColor: Theme.of(context).colorScheme.onPrimary,
            unselectedLabelColor: Theme.of(context).colorScheme.onSurface,
            tabs: [
              Tab(
                icon: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.history),
                    const SizedBox(width: 8),
                    Text('全部 (${_allHistory.length})'),
                  ],
                ),
              ),
              Tab(
                icon: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.audiotrack),
                    const SizedBox(width: 8),
                    Text('音频 (${_audioHistory.length})'),
                  ],
                ),
              ),
              Tab(
                icon: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.movie),
                    const SizedBox(width: 8),
                    Text('视频 (${_videoHistory.length})'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabBarView() {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildHistoryList(_allHistory),
        _buildHistoryList(_audioHistory),
        _buildHistoryList(_videoHistory),
      ],
    );
  }

  Widget _buildHistoryList(List<HistoryItem> historyItems) {
    if (historyItems.isEmpty) {
      return _buildEmptyState();
    }

    return _isGridView
        ? _buildGridView(historyItems)
        : _buildListView(historyItems);
  }

  Widget _buildGridView(List<HistoryItem> historyItems) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.75,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: historyItems.length,
        itemBuilder: (context, index) {
          final item = historyItems[index];
          return _buildGridItem(item);
        },
      ),
    );
  }

  Widget _buildGridItem(HistoryItem item) {
    final isSelected = item.filePath == _selectedMediaPath;
    final fileName = path.basename(item.filePath);

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedMediaPath = item.filePath;
        });
        _playMedia(item);
      },
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: isSelected ? 6 : 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: isSelected
              ? BorderSide(
                  color: Theme.of(context).colorScheme.primary, width: 2)
              : BorderSide.none,
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildMediaThumbnail(item),
                      if (item.lastPosition > 0)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: LinearProgressIndicator(
                            value: item.lastPosition / item.durationMs,
                            minHeight: 4,
                            backgroundColor: Colors.black38,
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title ?? fileName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        if (item.mediaType == 'audio' && item.artist != null)
                          Text(
                            item.artist!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.7),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        const Spacer(),
                        Text(
                          _formatDuration(item.durationMs),
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item.mediaType == 'audio'
                          ? Icons.audiotrack
                          : Icons.videocam,
                      color: Colors.white,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListView(List<HistoryItem> historyItems) {
    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: historyItems.length,
      itemBuilder: (context, index) {
        final item = historyItems[index];
        return _buildListItem(item, index);
      },
    );
  }

  Widget _buildListItem(HistoryItem item, int index) {
    final isSelected = item.filePath == _selectedMediaPath;
    final fileName = path.basename(item.filePath);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16.0),
        child: BackdropFilter(
          filter: ImageFilter.blur(
              sigmaX: isSelected ? 5 : 0, sigmaY: isSelected ? 5 : 0),
          child: Dismissible(
            key: Key(item.filePath),
            background: Container(
              decoration: BoxDecoration(
                color: Colors.red.shade700,
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20.0),
              child: const Icon(Icons.delete_sweep, color: Colors.white),
            ),
            direction: DismissDirection.endToStart,
            confirmDismiss: (direction) async {
              return await showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: const Text("确认删除"),
                    content: const Text("确定要从历史记录中删除这个项目吗？"),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text("取消"),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text("删除"),
                      ),
                    ],
                  );
                },
              );
            },
            onDismissed: (direction) async {
              try {
                await _historyService.deleteHistory(item.filePath);
                if (item.filePath == _selectedMediaPath) {
                  setState(() {
                    _selectedMediaPath = null;
                  });
                }
                _loadHistory();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('已从历史记录中删除'),
                    action: SnackBarAction(
                      label: '撤销',
                      onPressed: () {
                        // Unfortunately, we can't easily undo a delete without
                        // saving the full item beforehand
                        _loadHistory();
                      },
                    ),
                  ),
                );
              } catch (e) {
                _showErrorSnackBar('删除失败: $e');
              }
            },
            child: Material(
              color: isSelected
                  ? Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withOpacity(0.7)
                  : Theme.of(context).colorScheme.surface.withOpacity(0.7),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: isSelected
                    ? BorderSide(
                        color: Theme.of(context).colorScheme.primary, width: 2)
                    : BorderSide(
                        color: Theme.of(context)
                            .colorScheme
                            .outline
                            .withOpacity(0.1)),
              ),
              child: InkWell(
                onTap: () {
                  setState(() {
                    _selectedMediaPath = item.filePath;
                  });
                  _playMedia(item);
                },
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      // Thumbnail
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 80,
                          height: 80,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _buildMediaThumbnail(item),
                              // Play progress indicator
                              if (item.lastPosition > 0)
                                Positioned(
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  child: LinearProgressIndicator(
                                    value: item.lastPosition / item.durationMs,
                                    minHeight: 4,
                                    backgroundColor: Colors.black38,
                                  ),
                                ),
                              // Play icon overlay
                              if (isSelected)
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.play_circle_fill,
                                    color: Colors.white,
                                    size: 40,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Content
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title ?? fileName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            if (item.mediaType == 'audio') ...[
                              if (item.artist != null || item.album != null)
                                Text(
                                  [
                                    if (item.artist != null) item.artist,
                                    if (item.album != null) item.album,
                                  ].where((e) => e != null).join(' • '),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withOpacity(0.7),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ] else ...[
                              // For video, show file path
                              Text(
                                item.filePath,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withOpacity(0.7),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                // Media type indicator
                                Container(
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  child: Row(
                                    children: [
                                      Icon(
                                        item.mediaType == 'audio'
                                            ? Icons.audiotrack
                                            : Icons.videocam,
                                        size: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        item.mediaType == 'audio' ? '音频' : '视频',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Duration
                                Text(
                                  _formatDuration(item.durationMs),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withOpacity(0.6),
                                  ),
                                ),
                                const Spacer(),
                                // Last played time
                                Text(
                                  _formatLastPlayed(item.lastPlayed),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withOpacity(0.6),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMediaThumbnail(HistoryItem item) {
    if (item.thumbnailPath != null) {
      // Try to show actual thumbnail if available
      return Image.file(
        File(item.thumbnailPath!),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          final fileName = path.basename(item.filePath);

          // 尝试读取_thumbnailPath+fileName.jpg的文件
          if (File(path.join(_thumbnailPath, fileName + ".jpg")).existsSync()) {
            return Image.file(
              File(path.join(_thumbnailPath, fileName+ ".jpg")),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return _buildDefaultThumbnail(item);
              },
            );
          }
          return _buildDefaultThumbnail(item);
        },
        
      );
    } else {
      final fileName = path.basename(item.filePath);
      print("History Page: start get ${_thumbnailPath+"/"+fileName}.jpg");

      // 尝试读取_thumbnailPath+fileName.jpg的文件
      if (File(path.join(_thumbnailPath, fileName + ".jpg")).existsSync()) {
        return Image.file(
          File(path.join(_thumbnailPath, fileName+ ".jpg")),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildDefaultThumbnail(item);
          },
        );
      }
      return _buildDefaultThumbnail(item);
    }
  }

  Widget _buildDefaultThumbnail(HistoryItem item) {
    if (item.mediaType == 'audio') {
      // Audio thumbnail
      return Container(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Center(
          child: Icon(
            Icons.audiotrack,
            size: 40,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
      );
    } else {
      // Video thumbnail
      return Container(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: Center(
          child: Icon(
            Icons.movie,
            size: 40,
            color: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
        ),
      );
    }
  }

  Widget _buildNowPlayingBar() {
    final currentItem = _allHistory.firstWhere(
      (item) => item.filePath == _selectedMediaPath,
      orElse: () => _allHistory.first,
    );

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            color:
                Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.9),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: _buildMediaThumbnail(currentItem),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      currentItem.title ?? path.basename(currentItem.filePath),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      currentItem.mediaType == 'audio' &&
                              currentItem.artist != null
                          ? currentItem.artist!
                          : _formatDuration(currentItem.durationMs),
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.7),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.play_arrow),
                onPressed: () => _playMedia(currentItem),
                color: Theme.of(context).colorScheme.primary,
                iconSize: 32,
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _selectedMediaPath = null;
                  });
                },
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }

  String _formatLastPlayed(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return '刚刚';
        } else {
          return '${difference.inMinutes}分钟前';
        }
      } else {
        return '${difference.inHours}小时前';
      }
    } else if (difference.inDays < 7) {
      return '${difference.inDays}天前';
    } else {
      return DateFormat('MM-dd').format(dateTime);
    }
  }

  Future<void> _showClearHistoryDialog({required String clearType}) async {
    String title, content;
    switch (clearType) {
      case 'all':
        title = '清除全部历史';
        content = '确定要清除所有播放历史记录吗？此操作无法撤销。';
        break;
      case 'audio':
        title = '清除音频历史';
        content = '确定要清除所有音频播放历史记录吗？此操作无法撤销。';
        break;
      case 'video':
        title = '清除视频历史';
        content = '确定要清除所有视频播放历史记录吗？此操作无法撤销。';
        break;
      default:
        return;
    }

    bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('清除'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      try {
        switch (clearType) {
          case 'all':
            await _historyService.clearAllHistory();
            break;
          case 'audio':
            await _historyService.clearHistoryByType('audio');
            break;
          case 'video':
            await _historyService.clearHistoryByType('video');
            break;
        }

        setState(() {
          _selectedMediaPath = null;
        });
        await _loadHistory();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('历史记录已清除')),
          );
        }
      } catch (e) {
        _showErrorSnackBar('清除历史记录失败: $e');
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}
