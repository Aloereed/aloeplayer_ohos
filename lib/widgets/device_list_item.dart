import 'package:flutter/material.dart';
import '../models/cast_device.dart';

class DeviceListItem extends StatelessWidget {
  final CastDevice device;
  final bool isSelected;
  final Function(CastDevice) onTap;

  const DeviceListItem({
    super.key,
    required this.device,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.white.withOpacity(0.9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? Colors.blue : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: InkWell(
        onTap: () => onTap(device),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: isSelected ? Colors.blue.withOpacity(0.2) : Colors.grey.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Icon(
                  _getDeviceIcon(),
                  color: isSelected ? Colors.blue : Colors.grey.shade700,
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
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.blue : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${device.manufacturer} - ${device.model}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (device.isConnected)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: device.isPlaying ? Colors.green.withOpacity(0.2) : Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    device.isPlaying ? '正在播放' : '已连接',
                    style: TextStyle(
                      fontSize: 12,
                      color: device.isPlaying ? Colors.green : Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getDeviceIcon() {
    final deviceName = device.name.toLowerCase();
    if (deviceName.contains('tv')) {
      return Icons.tv;
    } else if (deviceName.contains('speaker') || deviceName.contains('audio')) {
      return Icons.speaker;
    } else if (deviceName.contains('chromecast')) {
      return Icons.cast;
    } else {
      return Icons.cast_connected;
    }
  }
}