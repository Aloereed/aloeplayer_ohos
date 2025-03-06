/*
 * @Author: 
 * @Date: 2025-01-12 15:11:12
 * @LastEditors: Please set LastEditors
 * @LastEditTime: 2025-03-06 15:00:31
 * @Description: file content
 */
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme_provider.dart'; // 假设你已经有一个ThemeProvider
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';

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

  Future<void> saveUseFfmpegForPlay(bool useFfmpeg) async{
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useFfmpegForPlayKey, useFfmpeg);
  }

  Future<bool> getUseFfmpegForPlay() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_useFfmpegForPlayKey) ?? false; // 默认值为false
  }

  Future<void> saveAutoFullscreenBeginPlay (bool autoFullscreen) async{
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoFullscreenBeginPlay, autoFullscreen); 
  }

  Future<bool> getAutoFullscreenBeginPlay() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoFullscreenBeginPlay)?? false; // 默认值为false 
  }

  Future<void> saveDefaultListmode (bool defaultListmode) async{
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_defaultListmode, defaultListmode); 
  }

  Future<bool> getDefaultListmode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_defaultListmode)?? false; // 默认值为false 
  }

  Future<void> saveUsePlaylist (bool usePlaylist) async{
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_usePlaylist, usePlaylist); 
  }

  Future<bool> getUsePlaylist() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_usePlaylist)?? true; // 默认值为true
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
    // const cachePath = '/data/storage/el2/base/haps/entry/cache/';
    // await deleteCacheDirectory(cachePath);
    final cacheDir = await getTemporaryDirectory();
    final directoryPath = cacheDir.path; // 缓存目录路径
    await deleteCacheDirectory(directoryPath);
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
        title: Text('设置'),
      ),
      body: ListView(
        children: [
          // 主题设置部分
          Column(
            children: [
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
          // 添加一个下拉列表，设置字幕的字体大小（默认为18）
          ListTile(
            title: Text('字幕字体大小(18以上的选择会导致字幕闪烁)'),
            subtitle: DropdownButton<int>(
              value: _subtitleFontSize.toInt(),
              items: List.generate(10, (index) {
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
                  _settingsService.saveSubtitleFontSize(value.toDouble());
                }
              },
            ),
          ),
          // 添加一个设置，是否使用FFmpeg作为播放内核
          ListTile(
            title: Text('使用FFmpeg软解播放（测试）'),
            subtitle: Text('默认情况下，播放器使用系统内置播放能力。设置后新播放有效。使用软解播放可以打开系统能力不支持的媒体文件，但可能会导致循环模式异常、播放器卡顿和功能缺失。'),
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
                    activeColor: Colors.blue, // 设置滑块的颜色为蓝色
                    activeTrackColor:
                        Colors.blue.withOpacity(0.5), // 设置滑轨的颜色为半透明蓝色
                  );
                } else {
                  return const CircularProgressIndicator();
                }
              },
            ),
          ),
          // 添加一个设置，是否默认为列表模式
          ListTile(
            title: Text('默认列表模式'),
            subtitle: Text('开启AloePlayer时，视频库和音频库为网格模式。设置后改为列表模式，下次启动有效。'),
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
                    activeColor: Colors.blue, // 设置滑块的颜色为蓝色
                    activeTrackColor:
                        Colors.blue.withOpacity(0.5), // 设置滑轨的颜色为半透明蓝色 
                  ); 
                }else{
                  return const CircularProgressIndicator();
                } 
              } 
            ) 
          ),
          // 添加一个设置，是否使用播放列表
          ListTile(
            title: Text('启用库内同级文件夹播放列表导入'),
            subtitle: Text('打开库内文件时，将同级文件夹内文件自动导入播放列表。文件过多时可能造成卡顿，重启应用后生效。'),
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
                    activeColor: Colors.blue, // 设置滑块的颜色为蓝色
                    activeTrackColor:
                        Colors.blue.withOpacity(0.5), // 设置滑轨的颜色为半透明蓝色 
                  ); 
                }else{
                  return const CircularProgressIndicator();
                } 
              } 
            ) 
          ),

          // 添加一个设置，是否在播放时自动全屏
          ListTile(
            title: Text('在播放时自动全屏'),
            subtitle: Text('默认情况下，播放器在播放时不会自动全屏。设置后对系统能力新播放有效。') ,
            trailing: FutureBuilder<bool>(
              future: _settingsService.getAutoFullscreenBeginPlay(),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return Switch(
                    value: snapshot.data!,
                    onChanged: (value) {
                      _settingsService.saveAutoFullscreenBeginPlay(value);
                      setState(() {});
                    }, 
                    activeColor: Colors.blue, // 设置滑块的颜色为蓝色
                    activeTrackColor:
                        Colors.blue.withOpacity(0.5), // 设置滑轨的颜色为半透明蓝色
                  ); 
                } else{
                  return const CircularProgressIndicator();
                }
              } 
            ) 
          ),
            
          // 添加一个设置，是否默认后台播放(使用_settingsService)
          ListTile(
            title: Text('默认后台播放'),
            subtitle: Text('默认情况下，播放器可以在后台播放音频。设置后新播放有效。'),
            trailing: FutureBuilder<bool>(
              future: _backgroundPlayFuture,
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return Switch(
                    value: snapshot.data!,
                    onChanged: _updateBackgroundPlay,
                    activeColor: Colors.blue, // 设置滑块的颜色为蓝色
                    activeTrackColor:
                        Colors.blue.withOpacity(0.5), // 设置滑轨的颜色为半透明蓝色
                  );
                } else {
                  return const CircularProgressIndicator();
                }
              },
            ),
          ),
          // 添加一个设置，是否自动尝试加载字幕
          ListTile(
            title: Text('自动尝试加载内挂字幕'),
            subtitle: Text('默认情况下，播放器会自动尝试加载视频文件内挂字幕。'),
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
                    activeColor: Colors.blue, // 设置滑块的颜色为蓝色
                    activeTrackColor:
                        Colors.blue.withOpacity(0.5), // 设置滑轨的颜色为半透明蓝色
                  );
                } else {
                  return const CircularProgressIndicator();
                }
              },
            ),
          ),
          ListTile(
            title: Text('库内抽取ASS字幕'),
            subtitle: Text('由于当前实现，转换为MP4和抽取ASS字幕只能在一次会话中进行一次，然后需要退出重新进入软件。'),
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
                    activeColor: Colors.blue, // 设置滑块的颜色为蓝色
                    activeTrackColor:
                        Colors.blue.withOpacity(0.5), // 设置滑轨的颜色为半透明蓝色
                  );
                } else {
                  return const CircularProgressIndicator();
                }
              },
            ),
          ),
          // 清除缓存按钮
          ListTile(
            title: Text('清除临时文件'),
            subtitle: Text('删除从图库中播放的临时文件、临时抽取的字幕等。'),
            trailing: Icon(Icons.delete, color: Colors.red), // 使用红色删除图标
            onTap: () {
              // 弹出确认对话框
              showDialog(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: Text('清除临时文件'),
                    content: Text('确定要删除所有临时文件吗？此操作不可恢复！'),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context); // 关闭对话框
                        },
                        child: Text('取消', style: TextStyle(color: Colors.grey)),
                      ),
                      TextButton(
                        onPressed: () async {
                          Navigator.pop(context); // 关闭对话框
                          // 调用清除临时文件的逻辑
                          await _settingsService.clearCache();
                          // 提示用户操作完成
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('临时文件已清除'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        child: Text('确定', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  );
                },
              );
            },
          ),
          Divider(), // 分割线

          // 关于此应用程序部分
          ListTile(
            title: Text('关于此应用程序'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 8),
                Text('AloePlayer'),
                SizedBox(height: 4),
                Text(
                    '版本号: 1.1.0。'),
                SizedBox(height: 4),
                Text('尽享视听盛宴'),
                SizedBox(height: 4),
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
                      Uri.parse('https://ohos.aloereed.com/index.php/2025/01/08/aloeplayer/'),
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
                      Uri.parse(
                          'https://beian.miit.gov.cn'),
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
                SizedBox(height: 16),
                Text('手势说明和提示:'),
                SizedBox(height: 8),
                Text('1. 长按: 三倍速播放。'),
                SizedBox(height: 4),
                Text('2. 双击播放界面左侧、右侧、中间: 快退、快进10秒、切换播放暂停，或者使用左右滑动来快退、快进。'),
                SizedBox(height: 4),
                Text('3. 上下滑动: 靠左侧增减亮度，靠右侧增减音量。'),
                SizedBox(height: 4),
                Text('4. 添加媒体进入音频库或视频库需要时间。推荐直接使用系统文件管理复制导入。'),
                SizedBox(height: 4),
                Text('5. 点击媒体控制的音量按钮可以切换静音。'),
                SizedBox(height: 4),
                Text('6. 添加字幕文件后，请在右上角打开“CC”。'),
                SizedBox(height: 4),
                Text('7. 新版本库文件默认位于“下载”文件夹下，长按添加按钮可以新建文件夹。'),
                SizedBox(height: 4),
                Text('8. 播放列表：播放器最右侧往左滑动唤出，播放列表从左往右滑动关闭。也可长按标题栏文件名打开或关闭。'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
