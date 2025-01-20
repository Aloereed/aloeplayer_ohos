/*
 * @Author: 
 * @Date: 2025-01-12 15:11:12
 * @LastEditors: Please set LastEditors
 * @LastEditTime: 2025-01-20 13:29:45
 * @Description: file content
 */
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme_provider.dart'; // 假设你已经有一个ThemeProvider
import 'package:url_launcher/url_launcher.dart';

class SettingsService {
  static const String _fontSizeKey = 'subtitle_font_size';
  static const String _backgroundPlayKey = 'background_play';

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
                Text('版本号: 0.9.8。 本版本默认全屏横屏、添加后台播放和系统集成、调节系统亮度和音量。'),
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
                    '官网: https://ohos.aloereed.com',
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
                SizedBox(height: 16),
                Text('手势说明和提示:'),
                SizedBox(height: 8),
                Text('1. 长按: 三倍速播放'),
                SizedBox(height: 4),
                Text('2. 双击播放界面左侧、右侧、中间: 快退、快进10秒、全屏，或者使用左右滑动来快退、快进'),
                SizedBox(height: 4),
                Text('3. 上下滑动: 靠左侧增减亮度，靠右侧增减音量，'),
                SizedBox(height: 4),
                Text('4. 添加媒体进入音频库或视频库需要时间。较大的文件不建议加入媒体库。如果长时间没反应可以再次尝试。'),
                SizedBox(height: 4),
                Text('5. 点击媒体控制的音量按钮可以切换静音。'),
                SizedBox(height: 4),
                Text('6. 添加字幕文件后，请在右上角打开“CC”。'),
                SizedBox(height: 4),
                Text('7. 新版本库文件默认位于“下载”文件夹下，测试版本中的视频不会被自动复制。'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
