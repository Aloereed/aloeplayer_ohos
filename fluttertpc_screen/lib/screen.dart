/*
 * @Author: 
 * @Date: 2025-01-19 11:16:39
 * @LastEditors: 
 * @LastEditTime: 2025-01-19 12:29:40
 * @Description: file content
 */
import 'dart:async';

import 'package:flutter/services.dart';

class Screen {
  static const MethodChannel _channel = const MethodChannel('github.com/clovisnicolas/flutter_screen');

  static Future<double?> get brightness async{
    
    return await _channel.invokeMethod('brightness')
    // 如果上面的类型为int，先转换为double
    .then((value) => value is int ? value.toDouble() : value) as double?;
  }
  static Future setBrightness(double brightness) =>_channel.invokeMethod('setBrightness',{"brightness" : brightness});
  static Future<bool?> get isKeptOn async => (await _channel.invokeMethod('isKeptOn')) as bool?;
  static Future keepOn(bool on) => _channel.invokeMethod('keepOn', {"on" : on});
}
