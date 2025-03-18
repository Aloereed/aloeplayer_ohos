import 'package:flutter/material.dart';
import 'dart:ui';
import '../models/cast_device.dart';
import '../services/media_cast_service.dart';
import '../widgets/device_list_item.dart';
import '../widgets/media_controls.dart';
import 'castview.dart';
import 'package:video_player/video_player.dart';

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

class CastScreenPage extends StatefulWidget {
  final String mediaPath;

  const CastScreenPage({
    super.key,
    required this.mediaPath,
  });

  @override
  State<CastScreenPage> createState() => _CastScreenPageState();
}

class _CastScreenPageState extends State<CastScreenPage> {
  final MediaCastService _castService = MediaCastService();
  bool _isScanning = false;
  CastDevice? _selectedDevice;
  CastExample? _castExample;
  String? _serverAddress;

  @override
  void initState() async {
    super.initState();
    VideoPlayerController videoPlayerController =
        VideoPlayerController.network('');
    await videoPlayerController.closeLatestAVSession();
    videoPlayerController.dispose();
    _serverAddress = await _castService.startLocalServer(widget.mediaPath);
    _castExample = CastExample(
        initUri: pathToUri(widget.mediaPath) + '|||' + _serverAddress!,
        toggleFullScreen: () {});
    setState(() {});
    // Navigator.push(
    //           context,
    //           MaterialPageRoute(
    //             builder: (context) => _castExample!
    //           ),
    //         );
    _startScan();
  }

  @override
  void dispose() {
    _castService.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() async {
      _isScanning = true;
      // _castExample = _castExample = CastExample(
      //     initUri: pathToUri(widget.mediaPath) +
      //         '|||' +
      //         (await _castService.startLocalServer(widget.mediaPath)),
      //     toggleFullScreen: () {});
    });

    await _castService.startDiscovery();

    setState(() {
      _isScanning = false;
    });
  }

  Future<void> _connectToDevice(CastDevice device) async {
    setState(() {
      _selectedDevice = device;
    });

    final connected = await _castService.connectToDevice(device);
    if (!connected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to connect to device'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() {
        _selectedDevice = null;
      });
    }
  }

  Future<void> _disconnectFromDevice() async {
    await _castService.disconnectFromDevice();
    setState(() {
      _selectedDevice = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 获取当前主题模式
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // 主题适配色彩
    final primaryColor =
        isDarkMode ? Colors.blue.shade300 : Colors.blue.shade600;
    final backgroundColor = isDarkMode ? Colors.grey.shade900 : Colors.white;
    final cardColor = isDarkMode
        ? Colors.grey.shade800.withOpacity(0.7)
        : Colors.white.withOpacity(0.85);
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final secondaryTextColor =
        isDarkMode ? Colors.grey.shade300 : Colors.grey.shade700;

    return Scaffold(
      backgroundColor: Colors.transparent, // 透明背景
      extendBodyBehindAppBar: true, // 内容延伸到AppBar下
      appBar: AppBar(
        title: Text(
          '投播',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        backgroundColor: backgroundColor.withOpacity(0.7),
        elevation: 0,
        centerTitle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(16),
          ),
        ),
        flexibleSpace: ClipRRect(
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(16),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
        actions: [
          IconButton(
            onPressed: _isScanning ? null : _startScan,
            icon: _isScanning
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                    ),
                  )
                : Icon(Icons.refresh, color: primaryColor),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDarkMode
                ? [
                    Colors.indigo.shade900,
                    Colors.black,
                  ]
                : [
                    Colors.blue.shade50,
                    Colors.indigo.shade100,
                  ],
          ),
          image: DecorationImage(
            image: AssetImage(_getMediaPreviewImage()),
            fit: BoxFit.cover,
            opacity: isDarkMode ? 0.15 : 0.2,
            colorFilter: isDarkMode
                ? ColorFilter.mode(
                    Colors.black.withOpacity(0.5), BlendMode.darken)
                : null,
          ),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                // 待投播媒体卡片
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.movie_filter_rounded,
                            color: primaryColor,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '待投播媒体',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // 媒体预览卡片
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: isDarkMode
                                  ? Colors.black.withOpacity(0.3)
                                  : Colors.black.withOpacity(0.08),
                              blurRadius: 15,
                              spreadRadius: 0,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                            child: Row(
                              children: [
                                Hero(
                                  tag: 'media_thumbnail',
                                  child: Container(
                                    width: 60,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      color: isDarkMode
                                          ? Colors.blue.shade900
                                              .withOpacity(0.6)
                                          : Colors.blue.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                      image: DecorationImage(
                                        image:
                                            AssetImage(_getMediaPreviewImage()),
                                        fit: BoxFit.cover,
                                        opacity: 0.7,
                                      ),
                                    ),
                                    child: Icon(
                                      _getMediaIcon(),
                                      color: primaryColor,
                                      size: 28,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _getMediaName(),
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: textColor,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color:
                                                  primaryColor.withOpacity(0.2),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              _getMediaType(),
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                color: primaryColor,
                                              ),
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
                      const SizedBox(width: 8),
                      Text(
                        '本页面前台时局域网设备可以使用 ${_serverAddress} 下载此媒体',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 14,
                        ),
                      ),

                      const SizedBox(height: 28),
                      // 可用设备标题栏
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.devices_rounded,
                                color: primaryColor,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '可用设备',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                            ],
                          ),
                          // 系统投播按钮或搜索中状态
                          if (_castExample != null)
                            Container(
                              width: 160,
                              height: 50,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  SizedBox.expand(
                                    child: _castExample!,
                                  ),
                                  Center(
                                    child: IgnorePointer(
                                      child: Container(
                                        width: 160,
                                        height: 50,
                                        decoration: BoxDecoration(
                                          color: cardColor,
                                          borderRadius:
                                              BorderRadius.circular(5),
                                          boxShadow: [
                                            BoxShadow(
                                              color: isDarkMode
                                                  ? Colors.black
                                                      .withOpacity(0.3)
                                                  : Colors.black
                                                      .withOpacity(0.1),
                                              blurRadius: 12,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(5),
                                          child: BackdropFilter(
                                            filter: ImageFilter.blur(
                                                sigmaX: 5, sigmaY: 5),
                                            child: Center(
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.cast,
                                                    color: primaryColor,
                                                    size: 20,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    '系统投播',
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      color: primaryColor,
                                                      fontWeight:
                                                          FontWeight.bold,
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
                                ],
                              ),
                            ),
                          if (_isScanning)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: primaryColor,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '搜索中...',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: primaryColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),
                // 设备列表
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '下方投屏功能只支持设备描述包含URLBase的设备。如果不工作，请尝试使用系统投播功能',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: StreamBuilder<List<CastDevice>>(
                    stream: _castService.devicesStream,
                    initialData: const [],
                    builder: (context, snapshot) {
                      final devices = snapshot.data ?? [];
                      if (devices.isEmpty) {
                        // 空状态
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: cardColor,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.cast_connected,
                                  size: 60,
                                  color: secondaryTextColor,
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                _isScanning ? '正在搜索设备...' : '没有找到可用设备',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: secondaryTextColor,
                                ),
                              ),
                              const SizedBox(height: 24),
                              if (!_isScanning)
                                ElevatedButton.icon(
                                  onPressed: _startScan,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('再次搜索'),
                                  style: ElevatedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    backgroundColor: primaryColor,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    elevation: 0,
                                  ),
                                ),
                            ],
                          ),
                        );
                      }
                      // 设备列表
                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: devices.length,
                        itemBuilder: (context, index) {
                          final device = devices[index];
                          final isSelected = _selectedDevice?.device.spec.udn ==
                              device.device.spec.udn;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? primaryColor
                                        .withOpacity(isDarkMode ? 0.3 : 0.15)
                                    : cardColor,
                                borderRadius: BorderRadius.circular(16),
                                border: isSelected
                                    ? Border.all(color: primaryColor, width: 2)
                                    : null,
                                boxShadow: [
                                  BoxShadow(
                                    color: isSelected
                                        ? primaryColor.withOpacity(0.2)
                                        : (isDarkMode
                                            ? Colors.black.withOpacity(0.2)
                                            : Colors.black.withOpacity(0.05)),
                                    blurRadius: 10,
                                    spreadRadius: 0,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: BackdropFilter(
                                  filter:
                                      ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => _connectToDevice(device),
                                      borderRadius: BorderRadius.circular(16),
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 52,
                                              height: 52,
                                              decoration: BoxDecoration(
                                                color: isDarkMode
                                                    ? Colors.grey.shade800
                                                    : Colors.grey.shade100,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Icon(
                                                _getDeviceIcon(device),
                                                color: isSelected
                                                    ? primaryColor
                                                    : secondaryTextColor,
                                                size: 28,
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    device.device.spec
                                                        .friendlyName,
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: textColor,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Row(
                                                    children: [
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 8,
                                                          vertical: 3,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: isSelected
                                                              ? primaryColor
                                                                  .withOpacity(
                                                                      0.2)
                                                              : (isDarkMode
                                                                  ? Colors.grey
                                                                      .shade700
                                                                  : Colors.grey
                                                                      .shade200),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(6),
                                                        ),
                                                        child: Text(
                                                          _getDeviceType(
                                                              device),
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            color: isSelected
                                                                ? primaryColor
                                                                : secondaryTextColor,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Container(
                                                        width: 8,
                                                        height: 8,
                                                        decoration:
                                                            BoxDecoration(
                                                          color: Colors.green,
                                                          shape:
                                                              BoxShape.circle,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        '在线',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color:
                                                              secondaryTextColor,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (isSelected)
                                              Container(
                                                padding:
                                                    const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: primaryColor,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.check,
                                                  color: Colors.white,
                                                  size: 16,
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
                        },
                      );
                    },
                  ),
                ),

                // 媒体控制条
                if (_selectedDevice != null)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutQuart,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? Colors.grey.shade900.withOpacity(0.8)
                          : cardColor,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isDarkMode
                              ? Colors.black.withOpacity(0.3)
                              : Colors.black.withOpacity(0.1),
                          blurRadius: 20,
                          spreadRadius: 0,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                        child: MediaControls(
                          device: _selectedDevice!,
                          mediaPath: widget.mediaPath,
                          onDisconnect: _disconnectFromDevice,
                          castService: _castService,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: _selectedDevice == null
          ? null
          : Theme(
              data: Theme.of(context).copyWith(
                colorScheme: Theme.of(context).colorScheme.copyWith(
                      secondary: primaryColor,
                    ),
              ),
              child: FloatingActionButton.extended(
                onPressed: () async {
                  await _castService.castMedia(widget.mediaPath);
                },
                icon: const Icon(Icons.cast),
                label: const Text('现在投播'),
                backgroundColor: primaryColor,
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
    );
  }

// 辅助设备图标选择
  IconData _getDeviceIcon(CastDevice device) {
    final name = device.device.spec.friendlyName.toLowerCase();
    if (name.contains('tv') || name.contains('电视')) {
      return Icons.tv_rounded;
    } else if (name.contains('speaker') || name.contains('音箱')) {
      return Icons.speaker_group_rounded;
    } else if (name.contains('chromecast')) {
      return Icons.cast_rounded;
    } else {
      return Icons.cast_connected_rounded;
    }
  }

// 获取设备类型
  String _getDeviceType(CastDevice device) {
    final name = device.device.spec.friendlyName.toLowerCase();
    if (name.contains('tv') || name.contains('电视')) {
      return '智能电视';
    } else if (name.contains('speaker') || name.contains('音箱')) {
      return '智能音箱';
    } else if (name.contains('chromecast')) {
      return 'Chromecast';
    } else {
      return 'DLNA设备';
    }
  }

  String _getMediaName() {
    return widget.mediaPath.split('/').last;
  }

  String _getMediaType() {
    final ext = widget.mediaPath.split('.').last.toLowerCase();
    switch (ext) {
      case 'mp4':
      case 'mkv':
        return '视频';
      case 'mp3':
      case 'wav':
      case 'flac':
        return '音频';
      case 'jpg':
      case 'jpeg':
      case 'png':
        return '图片';
      default:
        return '未知媒体类型';
    }
  }

  IconData _getMediaIcon() {
    final ext = widget.mediaPath.split('.').last.toLowerCase();
    switch (ext) {
      case 'mp4':
      case 'mkv':
        return Icons.video_file;
      case 'mp3':
      case 'wav':
      case 'flac':
        return Icons.audio_file;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }

  String _getMediaPreviewImage() {
    // 如果是实际项目中，这里可以返回媒体的预览图路径
    // 或者根据不同媒体类型使用不同的背景
    return 'assets/images/media_background.jpg';
  }
}
