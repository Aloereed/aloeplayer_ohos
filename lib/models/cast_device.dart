/*
 * @Author: 
 * @Date: 2025-03-14 15:52:03
 * @LastEditors: Please set LastEditors
 * @LastEditTime: 2025-03-14 16:01:28
 * @Description: file content
 */
import 'package:castscreen/castscreen.dart';

class CastDevice {
  final Device device;
  bool isConnected;
  bool isPlaying;

  CastDevice({
    required this.device,
    this.isConnected = false,
    this.isPlaying = false,
  });

  String get name => device.spec.friendlyName ?? 'Unknown Device';
  String get model => device.spec.modelName ?? 'Unknown Model';
  String get manufacturer => device.spec.manufacturer ?? 'Unknown Manufacturer';
}