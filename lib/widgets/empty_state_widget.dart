import 'package:flutter/material.dart';

/// 空状态组件
/// 在列表或库为空时显示美观的提示界面
class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onActionPressed;
  final Color? color;

  const EmptyStateWidget({
    Key? key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onActionPressed,
    this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = color ?? theme.colorScheme.primary;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 动画图标
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 800),
              curve: Curves.elasticOut,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Opacity(
                    opacity: value.clamp(0.0, 1.0),
                    child: child,
                  ),
                );
              },
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: primaryColor.withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 60,
                  color: primaryColor,
                ),
              ),
            ),
            const SizedBox(height: 32),

            // 标题
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOut,
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, 20 * (1 - value)),
                  child: Opacity(
                    opacity: value,
                    child: child,
                  ),
                );
              },
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),

            // 消息
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOut,
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, 20 * (1 - value)),
                  child: Opacity(
                    opacity: value,
                    child: child,
                  ),
                );
              },
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? Colors.white70 : Colors.black54,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            // 操作按钮
            if (actionLabel != null && onActionPressed != null) ...[
              const SizedBox(height: 32),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 1000),
                curve: Curves.easeOut,
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Opacity(
                      opacity: value,
                      child: child,
                    ),
                  );
                },
                child: ElevatedButton.icon(
                  onPressed: onActionPressed,
                  icon: const Icon(Icons.add),
                  label: Text(actionLabel!),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 4,
                    shadowColor: primaryColor.withOpacity(0.4),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 预设的空状态样式
class EmptyStates {
  /// 视频库为空
  static EmptyStateWidget videoLibrary({
    VoidCallback? onAddVideo,
  }) {
    return EmptyStateWidget(
      icon: Icons.video_library_outlined,
      title: '视频库为空',
      message: '还没有添加任何视频\n点击下方按钮添加您的第一个视频',
      actionLabel: '添加视频',
      onActionPressed: onAddVideo,
      color: Colors.blue,
    );
  }

  /// 音频库为空
  static EmptyStateWidget audioLibrary({
    VoidCallback? onAddAudio,
  }) {
    return EmptyStateWidget(
      icon: Icons.library_music_outlined,
      title: '音频库为空',
      message: '还没有添加任何音频文件\n点击下方按钮添加您喜欢的音乐',
      actionLabel: '添加音频',
      onActionPressed: onAddAudio,
      color: Colors.purple,
    );
  }

  /// 网络媒体库为空
  static EmptyStateWidget networkLibrary({
    VoidCallback? onAddServer,
  }) {
    return EmptyStateWidget(
      icon: Icons.cloud_outlined,
      title: '未配置媒体服务器',
      message: '添加网络媒体服务器以访问云端内容\n支持 SMB 和 WebDAV 文件服务器',
      actionLabel: '添加服务器',
      onActionPressed: onAddServer,
      color: Colors.green,
    );
  }

  /// 搜索无结果
  static EmptyStateWidget noSearchResults({
    required String query,
  }) {
    return EmptyStateWidget(
      icon: Icons.search_off,
      title: '未找到结果',
      message: '没有找到与 "$query" 相关的内容\n请尝试其他关键词',
      color: Colors.orange,
    );
  }

  /// 播放列表为空
  static EmptyStateWidget emptyPlaylist({
    VoidCallback? onAddToPlaylist,
  }) {
    return EmptyStateWidget(
      icon: Icons.playlist_play,
      title: '播放列表为空',
      message: '播放列表中还没有任何内容\n添加一些媒体文件开始播放',
      actionLabel: '添加内容',
      onActionPressed: onAddToPlaylist,
      color: Colors.teal,
    );
  }

  /// 网络错误
  static EmptyStateWidget networkError({
    VoidCallback? onRetry,
  }) {
    return EmptyStateWidget(
      icon: Icons.wifi_off,
      title: '网络连接失败',
      message: '请检查您的网络连接\n然后点击下方按钮重试',
      actionLabel: '重试',
      onActionPressed: onRetry,
      color: Colors.red,
    );
  }
}
