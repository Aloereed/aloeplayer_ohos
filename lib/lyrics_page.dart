import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/cupertino.dart';
import 'dart:ui';
import 'package:flutter_lyric/lyrics_reader.dart';


class LyricUISettings {
  double defaultSize;
  double defaultExtSize;
  double lineGap;
  double inlineGap;
  LyricAlign lyricAlign;
  HighlightDirection highlightDirection;
  bool highlight;
  double bias;
  LyricBaseLine lyricBaseLine;

  LyricUISettings({
    this.defaultSize = 18.0,
    this.defaultExtSize = 16.0,
    this.lineGap = 16.0,
    this.inlineGap = 10.0,
    this.lyricAlign = LyricAlign.CENTER,
    this.highlightDirection = HighlightDirection.LTR,
    this.highlight = true,
    this.bias = 0.5,
    this.lyricBaseLine = LyricBaseLine.CENTER,
  });

  // 从SharedPreferences加载设置
  static Future<LyricUISettings> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    
    return LyricUISettings(
      defaultSize: prefs.getDouble('lyric_defaultSize') ?? 18.0,
      defaultExtSize: prefs.getDouble('lyric_defaultExtSize') ?? 16.0,
      lineGap: prefs.getDouble('lyric_lineGap') ?? 16.0,
      inlineGap: prefs.getDouble('lyric_inlineGap') ?? 10.0,
      lyricAlign: LyricAlign.values[prefs.getInt('lyric_align') ?? 1],
      highlightDirection: HighlightDirection.values[prefs.getInt('lyric_highlightDirection') ?? 0],
      highlight: prefs.getBool('lyric_highlight') ?? true,
      bias: prefs.getDouble('lyric_bias') ?? 0.5,
      lyricBaseLine: LyricBaseLine.values[prefs.getInt('lyric_baseLine') ?? 1],
    );
  }

  // 保存设置到SharedPreferences
  Future<void> saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    
    await prefs.setDouble('lyric_defaultSize', defaultSize);
    await prefs.setDouble('lyric_defaultExtSize', defaultExtSize);
    await prefs.setDouble('lyric_lineGap', lineGap);
    await prefs.setDouble('lyric_inlineGap', inlineGap);
    await prefs.setInt('lyric_align', lyricAlign.index);
    await prefs.setInt('lyric_highlightDirection', highlightDirection.index);
    await prefs.setBool('lyric_highlight', highlight);
    await prefs.setDouble('lyric_bias', bias);
    await prefs.setInt('lyric_baseLine', lyricBaseLine.index);
  }
}

class LyricSettingsDialog extends StatefulWidget {
  final Function(LyricUISettings) onApplySettings;
  final LyricUISettings initialSettings;

  const LyricSettingsDialog({
    Key? key,
    required this.onApplySettings,
    required this.initialSettings,
  }) : super(key: key);

  @override
  _LyricSettingsDialogState createState() => _LyricSettingsDialogState();
}

class _LyricSettingsDialogState extends State<LyricSettingsDialog> {
  late LyricUISettings _settings;
  
  @override
  void initState() {
    super.initState();
    // 克隆初始设置，以便在用户取消时不会影响原始设置
    _settings = LyricUISettings(
      defaultSize: widget.initialSettings.defaultSize,
      defaultExtSize: widget.initialSettings.defaultExtSize,
      lineGap: widget.initialSettings.lineGap,
      inlineGap: widget.initialSettings.inlineGap,
      lyricAlign: widget.initialSettings.lyricAlign,
      highlightDirection: widget.initialSettings.highlightDirection,
      highlight: widget.initialSettings.highlight,
      bias: widget.initialSettings.bias,
      lyricBaseLine: widget.initialSettings.lyricBaseLine,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        padding: const EdgeInsets.only(top: 12, left: 20, right: 20, bottom: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            _buildHeader(),
            const SizedBox(height: 20),
            // 设置项列表
            Flexible(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildSliderSetting(
                            title: "主歌词字体大小",
                            value: _settings.defaultSize,
                            min: 12.0,
                            max: 30.0,
                            onChanged: (value) {
                              setState(() {
                                _settings.defaultSize = value;
                              });
                            },
                            suffix: "px",
                          ),
                          _buildDivider(),
                          _buildSliderSetting(
                            title: "副歌词字体大小",
                            value: _settings.defaultExtSize,
                            min: 10.0,
                            max: 28.0,
                            onChanged: (value) {
                              setState(() {
                                _settings.defaultExtSize = value;
                              });
                            },
                            suffix: "px",
                          ),
                          _buildDivider(),
                          _buildSliderSetting(
                            title: "行间距",
                            value: _settings.lineGap,
                            min: 8.0,
                            max: 40.0,
                            onChanged: (value) {
                              setState(() {
                                _settings.lineGap = value;
                              });
                            },
                            suffix: "px",
                          ),
                          _buildDivider(),
                          _buildSliderSetting(
                            title: "主副歌词间距",
                            value: _settings.inlineGap,
                            min: 5.0,
                            max: 30.0,
                            onChanged: (value) {
                              setState(() {
                                _settings.inlineGap = value;
                              });
                            },
                            suffix: "px",
                          ),
                          _buildDivider(),
                          _buildAlignmentSetting(),
                          _buildDivider(),
                          _buildHighlightDirectionSetting(),
                          _buildDivider(),
                          _buildSwitchSetting(
                            title: "启用高亮效果",
                            value: _settings.highlight,
                            onChanged: (value) {
                              setState(() {
                                _settings.highlight = value;
                              });
                            },
                          ),
                          _buildDivider(),
                          _buildSliderSetting(
                            title: "选中行偏移比例",
                            value: _settings.bias,
                            min: 0.0,
                            max: 1.0,
                            onChanged: (value) {
                              setState(() {
                                _settings.bias = value;
                              });
                            },
                            suffix: "",
                            fractionDigits: 2,
                          ),
                          _buildDivider(),
                          _buildBaseLineSetting(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // 操作按钮
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 40,
          height: 5,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.5),
            borderRadius: BorderRadius.circular(2.5),
          ),
        ),
        const Expanded(
          child: Center(
            child: Text(
              "歌词显示设置",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        Material(
          color: Colors.transparent,
          child: IconButton(
            icon: Icon(Icons.restore, color: Colors.white.withOpacity(0.8)),
            tooltip: '重置为默认',
            onPressed: _resetToDefaults,
          ),
        ),
      ],
    );
  }

  void _resetToDefaults() {
    setState(() {
      _settings = LyricUISettings(); // 使用默认构造参数重置所有设置
    });
  }

  Widget _buildDivider() {
    return Divider(color: Colors.white.withOpacity(0.1), height: 20);
  }

  Widget _buildSliderSetting({
    required String title,
    required double value,
    required double min,
    required double max,
    required Function(double) onChanged,
    required String suffix,
    int fractionDigits = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
            Text(
              '${value.toStringAsFixed(fractionDigits)}$suffix',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Colors.blueAccent,
            inactiveTrackColor: Colors.white.withOpacity(0.2),
            thumbColor: Colors.white,
            overlayColor: Colors.blueAccent.withOpacity(0.3),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildSwitchSetting({
    required String title,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
          ),
        ),
        CupertinoSwitch(
          value: value,
          activeColor: Colors.blueAccent,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildAlignmentSetting() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "歌词对齐方式",
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _buildAlignOption(LyricAlign.LEFT, "左对齐"),
            const SizedBox(width: 10),
            _buildAlignOption(LyricAlign.CENTER, "居中"),
            const SizedBox(width: 10),
            _buildAlignOption(LyricAlign.RIGHT, "右对齐"),
          ],
        ),
      ],
    );
  }

  Widget _buildAlignOption(LyricAlign align, String label) {
    final isSelected = _settings.lyricAlign == align;
    
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _settings.lyricAlign = align;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blueAccent : Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white.withOpacity(0.7),
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHighlightDirectionSetting() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "高亮方向",
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _buildDirectionOption(HighlightDirection.LTR, "从左到右"),
            const SizedBox(width: 10),
            _buildDirectionOption(HighlightDirection.RTL, "从右到左"),
          ],
        ),
      ],
    );
  }

  Widget _buildDirectionOption(HighlightDirection direction, String label) {
    final isSelected = _settings.highlightDirection == direction;
    
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _settings.highlightDirection = direction;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blueAccent : Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white.withOpacity(0.7),
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBaseLineSetting() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "偏移基准线",
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _buildBaseLineOption(LyricBaseLine.EXT_CENTER, "外中间"),
            const SizedBox(width: 10),
            _buildBaseLineOption(LyricBaseLine.CENTER, "中间"),
            const SizedBox(width: 10),
            _buildBaseLineOption(LyricBaseLine.MAIN_CENTER, "主中间"),
          ],
        ),
      ],
    );
  }

  Widget _buildBaseLineOption(LyricBaseLine baseLine, String label) {
    final isSelected = _settings.lyricBaseLine == baseLine;
    
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _settings.lyricBaseLine = baseLine;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blueAccent : Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white.withOpacity(0.7),
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.2),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: const Text(
              "取消",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: ElevatedButton(
            onPressed: () async {
              await _settings.saveToPrefs(); // 保存设置
              widget.onApplySettings(_settings);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: const Text(
              "应用",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}