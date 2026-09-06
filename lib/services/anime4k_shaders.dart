import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'serial_executor.dart';

/// Official Mode A (Fast), pinned to Anime4K v4.0.1. Preserve this order.
class Anime4kShaders {
  static const version = '4.0.1';
  static const revision = '4029bf701ecaa15f163cdc49cffe5501c1acf410';
  static const files = <String, String>{
    'Anime4K_Clamp_Highlights.glsl': 'a2a9bf7fbc1d75d09660ca2e701e4d7fb0cf5457b94da47e1825032fa2b3671a',
    'Anime4K_Restore_CNN_M.glsl': '67ea3ed26539e8de3b7d307688535d2ff17e8d147e11dda0247da7770dbecf41',
    'Anime4K_Upscale_CNN_x2_M.glsl': '716e02098a68f0d648761f2b96b4dd139e1cb09b174bb369fca3aa34328fff7e',
    'Anime4K_AutoDownscalePre_x2.glsl': '8c58291740146bd766a4d73f132775a797fe80f7d07919b5d767e27a5dc85656',
    'Anime4K_AutoDownscalePre_x4.glsl': '5af62d8cd844916dc1126613e13bad3beab195787f93a71200b47c6ec78f2e41',
    'Anime4K_Upscale_CNN_x2_S.glsl': '4c53ec2e287908f7ee7bcb266b0170421626d663576468b7d7dafc62962649a4',
  };
  static final _serial = SerialExecutor();
  static bool _licenseRegistered = false;
  static void registerLicense() {
    if (_licenseRegistered) return;
    _licenseRegistered = true;
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks(['Anime4K'], await rootBundle.loadString('Assets/shaders/anime4k/LICENSE'));
    });
  }
  static bool valid(String name, List<int> bytes) => files[name] == sha256.convert(bytes).toString();

  static Future<List<String>> install() => _serial.run(() async {
    final directory = Directory('${(await getApplicationSupportDirectory()).path}/shaders/anime4k-v$version');
    await directory.create(recursive: true);
    final paths = <String>[];
    for (final entry in files.entries) {
      final file = File('${directory.path}/${entry.key}');
      if (!await file.exists() || !valid(entry.key, await file.readAsBytes())) {
        final data = await rootBundle.load('Assets/shaders/anime4k/${entry.key}');
        final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        if (!valid(entry.key, bytes)) throw StateError('Anime4K shader integrity check failed');
        await file.writeAsBytes(bytes, flush: true);
      }
      paths.add(file.path);
    }
    return paths;
  });
}
