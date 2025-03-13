/*
 * @Author: 
 * @Date: 2025-01-12 15:11:12
 * @LastEditors: Please set LastEditors
 * @LastEditTime: 2025-03-13 11:00:11
 * @Description: file content
 */
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme_provider.dart'; // 假设你已经有一个ThemeProvider
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
enum SortType {
  none,
  name,
  modifiedDate
}

enum SortOrder {
  ascending,
  descending
}
class SettingsService {
  static const String _fontSizeKey = 'subtitle_font_size';
  static const String _backgroundPlayKey = 'background_play';
  static const String _autoLoadSubtitleKey = 'auto_load_subtitle';
  static const String _extractAssSubtitleKey = 'extract_ass_subtitle';
  static const String _useFfmpegForPlayKey = 'use_ffmpeg_for_play';
  static const String _autoFfmpegAfterVpFailed = 'auto_ffmpeg_after_vp_failed';
  static const String _autoFullscreenBeginPlay = 'auto_fullscreen_begin_play';
  static const String _defaultListmode = 'default_listmode';
  static const String _usePlaylist = 'use_playlist';
  static const String _useSeekToLatest = 'use_seek_to_latest';
  static const String _useInnerThumbnail = 'use_inner_thumbnail';
  static const String _versionName = '2.0.1';
  static const int _versionNumber = 23;

  Future<bool> activatePersistPermission(String uri) async {
    final _platform = const MethodChannel('samples.flutter.dev/downloadplugin');
// 调用方法 getBatteryLevel
    String result = await _platform
            .invokeMethod<String>('activatePermission', {"uri": uri}) ??
        '';
    if (result != "") {
      return true;
    } else {
      return false;
    }
  }

  Future<String> getPersistPermission(String exts) async {
    final _platform = const MethodChannel('samples.flutter.dev/downloadplugin');
// 调用方法 getBatteryLevel
    String uri = await _platform
            .invokeMethod<String>('persistPermission', {"exts": exts}) ??
        '';
    return uri;
  }

  // 假设 fetchCover 是通过 platform channel 调用的函数
  Future<String> fetchCover(String uri) async {
    // 这里调用 platform channel 的 fetchCover 函数
    // 假设返回的是一个 Base64 字符串
    const platform = MethodChannel('samples.flutter.dev/ffmpegplugin');
    final String base64String =
        await platform.invokeMethod<String>('fetchCover', {'uri': uri}) ?? "";
    return base64String;
  }

// 将 Base64 字符串转换为 Uint8List
  Uint8List base64ToUint8List(String base64String) {
    return base64Decode(base64String);
  }

// 使用示例
  Future<Uint8List?> fetchCoverNative(String uri) async {
    try {
      // 调用 fetchCover 获取 Base64 字符串
      final String base64String = await fetchCover(uri);
      if (base64String == "") {
        return null;
      }
      // 将 Base64 字符串转换为 Uint8List
      final Uint8List uint8List = base64ToUint8List(base64String);

      return uint8List;
    } catch (e) {
      print('Error: $e');
      return null;
    }
  }

  Future<void> saveSubtitleFontSize(double fontSize) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontSizeKey, fontSize);
  }

  Future<double> getSubtitleFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_fontSizeKey) ?? 18.0; // 默认值为18
  }

  Future<void> saveBackgroundPlay(bool backgroundPlay) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_backgroundPlayKey, backgroundPlay);
  }

  Future<bool> getBackgroundPlay() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_backgroundPlayKey) ?? true; // 默认值为true
  }

  // 是否自动加载字幕
  Future<void> saveAutoLoadSubtitle(bool autoLoadSubtitle) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoLoadSubtitleKey, autoLoadSubtitle);
  }

  Future<bool> getAutoLoadSubtitle() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoLoadSubtitleKey) ?? true; // 默认值为true
  }

  // 是否抽取ASS字幕
  Future<void> saveExtractAssSubtitle(bool extractAssSubtitle) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_extractAssSubtitleKey, extractAssSubtitle);
  }

  Future<bool> getExtractAssSubtitle() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_extractAssSubtitleKey) ?? false; // 默认值为false
  }

  Future<void> saveUseFfmpegForPlay(bool useFfmpeg) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useFfmpegForPlayKey, useFfmpeg);
  }

  Future<bool> getUseFfmpegForPlay() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_useFfmpegForPlayKey) ?? false; // 默认值为false
  }

  Future<void> saveAutoFullscreenBeginPlay(bool autoFullscreen) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoFullscreenBeginPlay, autoFullscreen);
  }

  Future<bool> getAutoFullscreenBeginPlay() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoFullscreenBeginPlay) ?? false; // 默认值为false
  }

  Future<void> saveDefaultListmode(bool defaultListmode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_defaultListmode, defaultListmode);
  }

  Future<bool> getDefaultListmode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_defaultListmode) ?? false; // 默认值为false
  }

  Future<void> saveUsePlaylist(bool usePlaylist) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_usePlaylist, usePlaylist);
  }

  Future<bool> getUsePlaylist() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_usePlaylist) ?? true; // 默认值为true
  }

  Future<void> saveUseSeekToLatest(bool useSeekToLatest) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useSeekToLatest, useSeekToLatest);
  }

  Future<bool> getUseSeekToLatest() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_useSeekToLatest) ?? false; // 默认值为false
  }

  Future<void> saveUseInnerThumbnail(bool useInnerThumbnail) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useInnerThumbnail, useInnerThumbnail);
  }

  Future<bool> getUseInnerThumbnail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_useInnerThumbnail) ?? false; // 默认值为false
  }

  // 清除缓存 递归删除“/data/storage/el2/base/haps/entry/cache/”下的所有文件

  Future<void> deleteCacheDirectory(String path) async {
    final directory = Directory(path);

    // 检查目录是否存在
    if (await directory.exists()) {
      // 递归遍历目录
      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) {
          // 删除文件
          await entity.delete();
          print('Deleted file: ${entity.path}');
        } else if (entity is Directory) {
          // 删除目录（如果是空目录）
          try {
            await entity.delete(recursive: true);
            print('Deleted directory: ${entity.path}');
          } catch (e) {
            print('Failed to delete directory: ${entity.path}, error: $e');
          }
        }
      }

      // 最后删除根目录
      // try {
      //   await directory.delete(recursive: true);
      //   print('Deleted root directory: ${directory.path}');
      // } catch (e) {
      //   print('Failed to delete root directory: ${directory.path}, error: $e');
      // }
    } else {
      print('Directory does not exist: ${directory.path}');
    }
  }

// 调用方法
  Future<void> clearCache() async {
    final cacheDir = await getTemporaryDirectory();
    final directoryPath = cacheDir.path; // 缓存目录路径
    await deleteCacheDirectory(directoryPath);
    const cachePath = '/data/storage/el2/base/haps/entry/cache/';
    await deleteCacheDirectory(cachePath);
  }
}

class SettingsTab extends StatefulWidget {
  @override
  _SettingsTabState createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  double _subtitleFontSize = 18.0;
  late Future<bool> _backgroundPlayFuture;
  final SettingsService _settingsService = SettingsService();

  @override
  void initState() {
    super.initState();
    _loadSubtitleFontSize();
    _backgroundPlayFuture = _settingsService.getBackgroundPlay();
  }

  Future<void> _loadSubtitleFontSize() async {
    final fontSize = await _settingsService.getSubtitleFontSize();
    setState(() {
      _subtitleFontSize = fontSize;
    });
  }

  void _updateBackgroundPlay(bool value) async {
    await _settingsService.saveBackgroundPlay(value);
    setState(() {
      // 重新触发 FutureBuilder 的 future
      _backgroundPlayFuture = _settingsService.getBackgroundPlay();
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('设置',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          // 主题设置部分
          Card(
            elevation: 2,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('主题设置',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  RadioListTile<ThemeMode>(
                    title: const Text('亮色模式'),
                    value: ThemeMode.light,
                    groupValue: themeProvider.themeMode,
                    onChanged: (ThemeMode? value) {
                      if (value != null) {
                        themeProvider.setThemeMode(value);
                      }
                    },
                    activeColor: Colors.lightBlue,
                  ),
                  RadioListTile<ThemeMode>(
                    title: const Text('暗色模式'),
                    value: ThemeMode.dark,
                    groupValue: themeProvider.themeMode,
                    onChanged: (ThemeMode? value) {
                      if (value != null) {
                        themeProvider.setThemeMode(value);
                      }
                    },
                    activeColor: Colors.lightBlue,
                  ),
                  RadioListTile<ThemeMode>(
                    title: const Text('跟随系统'),
                    value: ThemeMode.system,
                    groupValue: themeProvider.themeMode,
                    onChanged: (ThemeMode? value) {
                      if (value != null) {
                        themeProvider.setThemeMode(value);
                      }
                    },
                    activeColor: Colors.lightBlue,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 16),

          // 字幕设置部分
          Card(
            elevation: 2,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('字幕设置',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  ListTile(
                    leading: Icon(Icons.text_fields, color: Colors.lightBlue),
                    title: Text('字幕字体大小'),
                    subtitle: Text('ASS字幕为比例调整'),
                    trailing: DropdownButton<int>(
                      value: _subtitleFontSize.toInt(),
                      items: List.generate(20, (index) {
                        return DropdownMenuItem<int>(
                          value: 18 + 3 * index,
                          child: Text('${18 + 3 * index}'),
                        );
                      }),
                      onChanged: (int? value) {
                        if (value != null) {
                          setState(() {
                            _subtitleFontSize = value * 1.0;
                          });
                          _settingsService
                              .saveSubtitleFontSize(value.toDouble());
                        }
                      },
                    ),
                  ),
                  ListTile(
                    leading: Icon(Icons.subtitles, color: Colors.lightBlue),
                    title: Text('自动尝试加载内挂和同级外挂字幕'),
                    subtitle: Text('优先加载外挂ASS字幕'),
                    trailing: FutureBuilder<bool>(
                      future: _settingsService.getAutoLoadSubtitle(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          return Switch(
                            value: snapshot.data!,
                            onChanged: (value) {
                              _settingsService.saveAutoLoadSubtitle(value);
                              setState(() {});
                            },
                            activeColor: Colors.lightBlue,
                          );
                        } else {
                          return const CircularProgressIndicator();
                        }
                      },
                    ),
                  ),
                  ListTile(
                    leading: Icon(Icons.subtitles, color: Colors.lightBlue),
                    title: Text('库内抽取ASS字幕'),
                    subtitle: Text('转换为MP4和抽取ASS字幕只能在一次会话中进行一次'),
                    trailing: FutureBuilder<bool>(
                      future: _settingsService.getExtractAssSubtitle(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          return Switch(
                            value: snapshot.data!,
                            onChanged: (value) {
                              _settingsService.saveExtractAssSubtitle(value);
                              setState(() {});
                            },
                            activeColor: Colors.lightBlue,
                          );
                        } else {
                          return const CircularProgressIndicator();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 16),

          // 播放设置部分
          Card(
            elevation: 2,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('播放设置',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  ListTile(
                    leading:
                        Icon(Icons.play_circle_filled, color: Colors.lightBlue),
                    title: Text('使用FFmpeg软解播放（测试）'),
                    subtitle: Text('可能导致循环模式异常、播放器卡顿和功能缺失'),
                    trailing: FutureBuilder<bool>(
                      future: _settingsService.getUseFfmpegForPlay(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          return Switch(
                            value: snapshot.data!,
                            onChanged: (value) {
                              _settingsService.saveUseFfmpegForPlay(value);
                              setState(() {});
                            },
                            activeColor: Colors.lightBlue,
                          );
                        } else {
                          return const CircularProgressIndicator();
                        }
                      },
                    ),
                  ),
                  ListTile(
                    leading: Icon(Icons.list, color: Colors.lightBlue),
                    title: Text('默认列表模式'),
                    subtitle: Text('启动时视频库和音频库为列表模式'),
                    trailing: FutureBuilder<bool>(
                      future: _settingsService.getDefaultListmode(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          return Switch(
                            value: snapshot.data!,
                            onChanged: (value) {
                              _settingsService.saveDefaultListmode(value);
                              setState(() {});
                            },
                            activeColor: Colors.lightBlue,
                          );
                        } else {
                          return const CircularProgressIndicator();
                        }
                      },
                    ),
                  ),
                  ListTile(
                    leading: Icon(Icons.playlist_play, color: Colors.lightBlue),
                    title: Text('启用库内同级文件夹播放列表导入'),
                    subtitle: Text('文件过多时可能造成卡顿'),
                    trailing: FutureBuilder<bool>(
                      future: _settingsService.getUsePlaylist(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          return Switch(
                            value: snapshot.data!,
                            onChanged: (value) {
                              _settingsService.saveUsePlaylist(value);
                              setState(() {});
                            },
                            activeColor: Colors.lightBlue,
                          );
                        } else {
                          return const CircularProgressIndicator();
                        }
                      },
                    ),
                  ),
                  ListTile(
                    leading: Icon(Icons.fullscreen, color: Colors.lightBlue),
                    title: Text('在播放时自动全屏'),
                    trailing: FutureBuilder<bool>(
                      future: _settingsService.getAutoFullscreenBeginPlay(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          return Switch(
                            value: snapshot.data!,
                            onChanged: (value) {
                              _settingsService
                                  .saveAutoFullscreenBeginPlay(value);
                              setState(() {});
                            },
                            activeColor: Colors.lightBlue,
                          );
                        } else {
                          return const CircularProgressIndicator();
                        }
                      },
                    ),
                  ),
                  ListTile(
                    leading: Icon(Icons.backup_table_rounded,
                        color: Colors.lightBlue),
                    title: Text('默认后台播放'),
                    trailing: FutureBuilder<bool>(
                      future: _backgroundPlayFuture,
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          return Switch(
                            value: snapshot.data!,
                            onChanged: _updateBackgroundPlay,
                            activeColor: Colors.lightBlue,
                          );
                        } else {
                          return const CircularProgressIndicator();
                        }
                      },
                    ),
                  ),
                  ListTile(
                      leading: Icon(Icons.loop, color: Colors.lightBlue),
                      title: Text('使用上次播放位置'),
                      subtitle: Text('视频播放器在播放时自动从上次播放位置续播'),
                      trailing: FutureBuilder<bool>(
                          future: _settingsService.getUseSeekToLatest(),
                          builder: (context, snapshot) {
                            if (snapshot.hasData) {
                              return Switch(
                                value: snapshot.data!,
                                onChanged: (value) {
                                  _settingsService.saveUseSeekToLatest(value);
                                  setState(() {});
                                },
                                activeColor: Colors.lightBlue,
                              );
                            } else {
                              return const CircularProgressIndicator();
                            }
                          }))
                ],
              ),
            ),
          ),
          SizedBox(height: 16),

          // 清除缓存部分
          Card(
            elevation: 2,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('缓存文件管理',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  ListTile(
                      leading:
                          Icon(Icons.download_rounded, color: Colors.lightBlue),
                      title: Text('使用应用沙箱存储视频缩略图'),
                      subtitle: Text('之后你可以自行删除下载文件夹内的缩略图'),
                      trailing: FutureBuilder<bool>(
                          future: _settingsService.getUseInnerThumbnail(),
                          builder: (context, snapshot) {
                            if (snapshot.hasData) {
                              return Switch(
                                value: snapshot.data!,
                                onChanged: (value) {
                                  _settingsService.saveUseInnerThumbnail(value);
                                  setState(() {});
                                },
                                activeColor: Colors.lightBlue,
                              );
                            } else {
                              return const CircularProgressIndicator();
                            }
                          })),
                  ListTile(
                    leading: Icon(Icons.delete, color: Colors.red),
                    title: Text('清除临时文件'),
                    subtitle: Text('删除临时文件、临时抽取的字幕等'),
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) {
                          return AlertDialog(
                            title: Text('清除临时文件'),
                            content: Text('确定要删除所有临时文件吗？此操作不可恢复！'),
                            actions: [
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                },
                                child: Text('取消',
                                    style: TextStyle(color: Colors.grey)),
                              ),
                              TextButton(
                                onPressed: () async {
                                  Navigator.pop(context);
                                  await _settingsService.clearCache();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('临时文件已清除'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                },
                                child: Text('确定',
                                    style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          // 添加“部分设置重启应用后生效”的说明
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: Colors.amber.withOpacity(0.3), width: 1),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Colors.amber[800],
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '部分设置重启应用后生效',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.amber[800],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: 16),

          // 关于此应用程序部分
          Card(
            elevation: 2,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('关于此应用程序',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('AloePlayer', style: TextStyle(fontSize: 16)),
                  SizedBox(height: 4),
                  Text('版本号: ${SettingsService._versionName}',
                      style: TextStyle(fontSize: 14, color: Colors.grey)),
                  SizedBox(height: 4),
                  Text('尽享视听盛宴',
                      style: TextStyle(fontSize: 14, color: Colors.grey)),
                  SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      await launchUrl(
                        Uri.parse('https://ohos.aloereed.com'),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                    child: Text(
                      '官网鸿蒙站',
                      style: TextStyle(
                        color: Colors.blue,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  SizedBox(height: 4),
                  GestureDetector(
                    onTap: () async {
                      await launchUrl(
                        Uri.parse(
                            'https://ohos.aloereed.com/index.php/2025/01/08/aloeplayer/'),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                    child: Text(
                      '更新日志',
                      style: TextStyle(
                        color: Colors.blue,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  SizedBox(height: 4),
                  GestureDetector(
                    onTap: () async {
                      await launchUrl(
                        Uri.parse(
                            'https://aloereed.com/aloeplayer/privacy-statement.html'),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                    child: Text(
                      '隐私政策',
                      style: TextStyle(
                        color: Colors.blue,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  SizedBox(height: 4),
                  GestureDetector(
                    onTap: () async {
                      await launchUrl(
                        Uri.parse('https://beian.miit.gov.cn'),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                    child: Text(
                      '沪ICP备2025110508号-2A',
                      style: TextStyle(
                        color: Colors.blue,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  SizedBox(height: 4),
                  GestureDetector(
                    onTap: () {
                      showLicensePage(
                        context: context,
                        applicationName: 'AloePlayer',
                        applicationVersion: SettingsService._versionName,
                        applicationLegalese: '© 2025 Aloereed',
                      );
                    },
                    child: Text(
                      '开源项目和许可',
                      style: TextStyle(
                        color: Colors.blue,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  SizedBox(height: 16),
                  Text('手势说明和提示:',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('1. 长按: 三倍速播放。'),
                  SizedBox(height: 4),
                  Text('2. 双击播放界面左侧、右侧、中间: 快退、快进10秒、切换播放暂停。'),
                  SizedBox(height: 4),
                  Text('3. 上下滑动: 靠左侧增减亮度，靠右侧增减音量。'),
                  SizedBox(height: 4),
                  Text('4. 添加媒体进入音频库或视频库需要时间。'),
                  SizedBox(height: 4),
                  Text('5. 点击媒体控制的音量按钮可以切换静音。'),
                  SizedBox(height: 4),
                  Text('6. 添加字幕文件后，请在右上角打开“CC”。'),
                  SizedBox(height: 4),
                  Text('7. 新版本库文件默认位于“下载”文件夹下。'),
                  SizedBox(height: 4),
                  Text('8. 播放列表：播放器最右侧往左滑动唤出。'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
