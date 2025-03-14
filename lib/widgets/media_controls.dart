import 'package:flutter/material.dart';
import '../models/cast_device.dart';
import '../services/media_cast_service.dart';

class MediaControls extends StatelessWidget {
  final CastDevice device;
  final String? mediaPath;
  final Function() onDisconnect;
  final MediaCastService castService;

  const MediaControls({
    super.key,
    required this.device,
    required this.mediaPath,
    required this.onDisconnect,
    required this.castService,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: const Icon(
                  Icons.cast_connected,
                  color: Colors.blue,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      device.isPlaying ? '正在播放媒体' : '已连接',
                      style: TextStyle(
                        fontSize: 14,
                        color: device.isPlaying ? Colors.green : Colors.blue,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onDisconnect,
                icon: const Icon(Icons.close),
                color: Colors.grey.shade700,
              ),
            ],
          ),
          const Divider(height: 30),
          if (mediaPath != null)
            Text(
              _getMediaName(mediaPath!),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ControlButton(
                icon: Icons.cast,
                label: '投播',
                onPressed: () async {
                  if (mediaPath != null) {
                    await castService.castMedia(mediaPath!);
                  }
                },
              ),
              if (device.isPlaying)
                _ControlButton(
                  icon: Icons.pause,
                  label: '暂停',
                  onPressed: () async {
                    await castService.pauseMedia();
                  },
                )
              else
                _ControlButton(
                  icon: Icons.play_arrow,
                  label: '播放',
                  onPressed: () async {
                    if (mediaPath != null && !device.isPlaying) {
                      if (castService.currentMediaPath == mediaPath) {
                        await castService.resumeMedia();
                      } else {
                        await castService.castMedia(mediaPath!);
                      }
                    }
                  },
                ),
              _ControlButton(
                icon: Icons.stop,
                label: '停止',
                onPressed: () async {
                  await castService.stopMedia();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getMediaName(String path) {
    return path.split('/').last;
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Function() onPressed;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 28, color: Colors.blue),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.blue,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}