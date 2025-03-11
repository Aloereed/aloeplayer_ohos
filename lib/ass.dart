import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

class AssStyle {
  final String name;
  final Color primaryColor;
  final Color secondaryColor;
  final Color outlineColor;
  final Color backColor;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikeOut;
  final double fontSize;
  final String fontName;
  final double scaleX;
  final double scaleY;
  final double spacing;
  final double angle;
  final int borderStyle;
  final double outlineWidth;
  final double shadowWidth;
  final Alignment alignment;
  final int marginL;
  final int marginR;
  final int marginV;

  const AssStyle({
    required this.name,
    this.primaryColor = Colors.white,
    this.secondaryColor = Colors.white,
    this.outlineColor = Colors.black,
    this.backColor = Colors.transparent,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikeOut = false,
    this.fontSize = 20.0,
    this.fontName = 'Arial',
    this.scaleX = 1.0,
    this.scaleY = 1.0,
    this.spacing = 0.0,
    this.angle = 0.0,
    this.borderStyle = 1,
    this.outlineWidth = 2.0,
    this.shadowWidth = 2.0,
    this.alignment = Alignment.bottomCenter,
    this.marginL = 10,
    this.marginR = 10,
    this.marginV = 10,
  });
}

class AssSubtitle {
  final Duration startTime;
  final Duration endTime;
  final String text;
  final String rawText; // 保存原始标记文本
  
  // 基本样式属性
  final String styleName; // 引用的样式名
  AssStyle? style; // 应用的样式
  
  // 覆盖的样式属性，这些可能为空，表示使用样式中定义的默认值
  final Color? primaryColor;
  final double? fontSize;
  final bool? bold;
  final bool? italic;
  
  // 位置相关
  final double? posX;
  final double? posY;
  final Alignment? alignment;
  
  // 其他属性...

  AssSubtitle({
    required this.startTime,
    required this.endTime,
    required this.text,
    required this.rawText,
    required this.styleName,
    this.style,
    this.primaryColor,
    this.fontSize,
    this.bold,
    this.italic,
    this.posX,
    this.posY,
    this.alignment,
  });

  bool isVisibleAt(Duration currentTime) {
    return currentTime >= startTime && currentTime <= endTime;
  }
  
  // 获取实际使用的颜色
  Color getEffectiveColor() {
    return primaryColor ?? style?.primaryColor ?? Colors.white;
  }
  
  // 获取实际使用的字体大小
  double getEffectiveFontSize() {
    return fontSize ?? style?.fontSize ?? 20.0;
  }
  
  // 获取实际使用的字体粗细
  FontWeight getEffectiveFontWeight() {
    final isBold = bold ?? style?.bold ?? false;
    return isBold ? FontWeight.bold : FontWeight.normal;
  }
  
  // 获取实际使用的字体样式
  FontStyle getEffectiveFontStyle() {
    final isItalic = italic ?? style?.italic ?? false;
    return isItalic ? FontStyle.italic : FontStyle.normal;
  }
  
  // 获取实际使用的位置
  Alignment getEffectiveAlignment() {
    return alignment ?? style?.alignment ?? Alignment.bottomCenter;
  }
  
  // 获取实际的位置（如果定义了精确坐标则使用）
  Offset? getExactPosition(Size containerSize) {
    if (posX != null && posY != null) {
      return Offset(posX!, posY!);
    }
    return null;
  }
}
class AssParserPlus {
  // 解析 ASS 文件
  static Future<(List<AssStyle>, List<AssSubtitle>)> parseAssFile(String filePath) async {
    final file = File(filePath);
    final content = await file.readAsString();
    return parseAssContent(content);
  }

  // 解析 ASS 内容
  static (List<AssStyle>, List<AssSubtitle>) parseAssContent(String content) {
    final List<AssStyle> styles = [];
    final List<AssSubtitle> subtitles = [];
    final lines = content.split('\n');
    
    bool inStyles = false;
    bool inEvents = false;
    String? styleFormatLine;
    String? eventFormatLine;
    
    for (var line in lines) {
      line = line.trim();
      
      if (line.isEmpty || line.startsWith(';')) {
        continue; // 跳过空行和注释
      }
      
      if (line.startsWith('[Styles]')|| line.startsWith('[V4+ Styles]')) {
        inStyles = true;
        inEvents = false;
        continue;
      } else if (line.startsWith('[Events]')) {
        inStyles = false;
        inEvents = true;
        continue;
      } else if (line.startsWith('[')) {
        inStyles = false;
        inEvents = false;
        continue;
      }
      print('Processing line: $line');
      
      if (inStyles) {
        if (line.startsWith('Format:')) {
          styleFormatLine = line;
        } else if (line.startsWith('Style:') && styleFormatLine != null) {
          final style = parseStyleLine(line, styleFormatLine);
          if (style != null) {
            styles.add(style);
          }
        }
      } else if (inEvents) {
        if (line.startsWith('Format:')) {
          eventFormatLine = line;
        } else if (line.startsWith('Dialogue:') && eventFormatLine != null) {
          final subtitle = parseDialogueLine(line, eventFormatLine);
          if (subtitle != null) {
            subtitles.add(subtitle);
          }
        }
      }
    }

    print("processing ass done.");
    
    // 将样式应用到字幕
    _applyStylesToSubtitles(styles, subtitles);
    
    // 解析字幕中的样式标签
    final processedSubtitles = _processStyleOverrides(subtitles);
    
    return (styles, processedSubtitles);
  }

  // 解析样式行
  static AssStyle? parseStyleLine(String styleLine, String formatLine) {
    final formatFields = formatLine
        .substring('Format:'.length)
        .split(',')
        .map((field) => field.trim())
        .toList();
    print('FormatFields: $formatFields');
    final styleParts = styleLine
        .substring('Style:'.length)
        .split(',');
    
    if (styleParts.length < formatFields.length) {
      return null; // 格式不匹配
    }
    
    final Map<String, String> styleData = {};
    for (int i = 0; i < formatFields.length; i++) {
      styleData[formatFields[i]] = styleParts[i].trim();
    }
    
    // 获取样式名
    final name = styleData['Name'] ?? 'Default';
    print("StyleName: $name");
    
    // 解析颜色 (ASS 使用 BGR 格式的十六进制颜色，如 &H0000FF& 表示红色)
    final primaryColor = _parseAssColor(styleData['PrimaryColour']);
    final secondaryColor = _parseAssColor(styleData['SecondaryColour']);
    final outlineColor = _parseAssColor(styleData['OutlineColour'] ?? styleData['TertiaryColour']);
    final backColor = _parseAssColor(styleData['BackColour']);
    print("get style color done.");

    // 解析字体样式
    final bold = styleData['Bold'] == '1' || styleData['Bold']?.toLowerCase() == 'yes';
    final italic = styleData['Italic'] == '1' || styleData['Italic']?.toLowerCase() == 'yes';
    final underline = styleData['Underline'] == '1' || styleData['Underline']?.toLowerCase() == 'yes';
    final strikeOut = styleData['StrikeOut'] == '1' || styleData['StrikeOut']?.toLowerCase() == 'yes';
    print("get style font done.");
    
    // 解析字体大小
    final fontSize = double.tryParse(styleData['Fontsize'] ?? '20') ?? 20.0;
    final fontName = styleData['Fontname'] ?? 'Arial';
    print("get style fontsize done.");
    
    // 解析缩放
    final scaleX = double.tryParse(styleData['ScaleX'] ?? '100')! / 100.0;
    final scaleY = double.tryParse(styleData['ScaleY'] ?? '100')! / 100.0;
    final spacing = double.tryParse(styleData['Spacing'] ?? '0') ?? 0.0;
    final angle = double.tryParse(styleData['Angle'] ?? '0') ?? 0.0;
    print("get style scale done.");
    
    // 解析边框样式
    final borderStyle = int.tryParse(styleData['BorderStyle'] ?? '1') ?? 1;
    final outlineWidth = double.tryParse(styleData['Outline'] ?? '2') ?? 2.0;
    final shadowWidth = double.tryParse(styleData['Shadow'] ?? '2') ?? 2.0;
    print("get style border done.");
    
    // 解析对齐方式 (SSA/ASS 使用不同的对齐方式编码)
    final alignValue = int.tryParse(styleData['Alignment'] ?? '2') ?? 2;
    final alignment = _convertAssAlignmentToFlutter(alignValue);
    print("get style align done.");
    
    // 解析边距
    final marginL = int.tryParse(styleData['MarginL'] ?? '10') ?? 10;
    final marginR = int.tryParse(styleData['MarginR'] ?? '10') ?? 10;
    final marginV = int.tryParse(styleData['MarginV'] ?? '10') ?? 10;
    print("get style margin done.");
    
    print("get style done.");
    // 解析编码
    // final encodingValue = int.tryParse(styleData['Encoding'] ?? '1') ?? 1;
    // final encoding = Encoding.getByName('utf8')!; // 简化处理，实际上应检查编码类型
    
    return AssStyle(
      name: name,
      primaryColor: primaryColor,
      secondaryColor: secondaryColor,
      outlineColor: outlineColor,
      backColor: backColor,
      bold: bold,
      italic: italic,
      underline: underline,
      strikeOut: strikeOut,
      fontSize: fontSize,
      fontName: fontName,
      scaleX: scaleX,
      scaleY: scaleY,
      spacing: spacing,
      angle: angle,
      borderStyle: borderStyle,
      outlineWidth: outlineWidth,
      shadowWidth: shadowWidth,
      alignment: alignment,
      marginL: marginL,
      marginR: marginR,
      marginV: marginV,
    );
  }

  // 解析对话行
  static AssSubtitle? parseDialogueLine(String dialogueLine, String formatLine) {
    final formatFields = formatLine
        .substring('Format:'.length)
        .split(',')
        .map((field) => field.trim())
        .toList();
    
    // 找出字段位置
    final startTimeIndex = formatFields.indexOf('Start');
    final endTimeIndex = formatFields.indexOf('End');
    final styleIndex = formatFields.indexOf('Style');
    final textIndex = formatFields.lastIndexOf('Text'); // 使用最后一个Text字段
    
    if (startTimeIndex == -1 || endTimeIndex == -1 || textIndex == -1) {
      return null; // 所需字段缺失
    }
    
    // 解析对话行
    String dialogueStr = dialogueLine.substring('Dialogue:'.length);
    
    // 确保正确处理文本中的逗号
    List<String> parts = [];
    bool inText = false;
    String buffer = '';
    int commaCount = 0;
    
    for (int i = 0; i < dialogueStr.length; i++) {
      if (dialogueStr[i] == ',' && !inText) {
        parts.add(buffer.trim());
        buffer = '';
        commaCount++;
        if (commaCount == textIndex) {
          inText = true;
        }
        continue;
      }
      buffer += dialogueStr[i];
    }
    if (buffer.isNotEmpty) {
      parts.add(buffer.trim());
    }
    
    // 确保有足够的部分
    if (parts.length <= textIndex) {
      return null;
    }
    
    // 解析时间
    final startTimeStr = parts[startTimeIndex];
    final endTimeStr = parts[endTimeIndex];
    
    final startTime = _parseAssTime(startTimeStr);
    final endTime = _parseAssTime(endTimeStr);
    
    if (startTime == null || endTime == null) {
      return null;
    }
    
    // 获取样式名
    final styleName = styleIndex >= 0 && styleIndex < parts.length 
        ? parts[styleIndex] 
        : 'Default';
    
    // 获取原始文本
    final rawText = textIndex < parts.length ? parts[textIndex] : '';
    
    // 删除样式标签，获取纯文本
    final plainText = _removeAssMarkup(rawText);
    
    return AssSubtitle(
      startTime: startTime,
      endTime: endTime,
      text: plainText,
      rawText: rawText,
      styleName: styleName,
    );
  }

  // 将样式应用到字幕
  static void _applyStylesToSubtitles(List<AssStyle> styles, List<AssSubtitle> subtitles) {
    print ("Apply styles to subtitles");
    final Map<String, AssStyle> styleMap = {
      for (var style in styles) style.name: style
    };

    print("Styles: $styleMap");
    
    for (var subtitle in subtitles) {
      print("Subtitle style name: ${subtitle.styleName}");
      if (styleMap.containsKey(subtitle.styleName)) {
        subtitle.style = styleMap[subtitle.styleName];
        
      } else if (styleMap.containsKey('Default')) {
        subtitle.style = styleMap['Default'];
      }
    }
  }

  // 处理内联样式标签
  static List<AssSubtitle> _processStyleOverrides(List<AssSubtitle> subtitles) {
    final List<AssSubtitle> result = [];
    
    for (var subtitle in subtitles) {
      // 解析内联样式
      final (processedText, overrides) = _parseStyleOverrides(subtitle.rawText);
      
      // 创建新的字幕对象，应用样式覆盖
      final processedSubtitle = AssSubtitle(
        startTime: subtitle.startTime,
        endTime: subtitle.endTime,
        text: processedText,
        rawText: subtitle.rawText,
        styleName: subtitle.styleName,
        style: subtitle.style,
        primaryColor: overrides['color'] as Color?,
        fontSize: overrides['fontSize'] as double?,
        bold: overrides['bold'] as bool?,
        italic: overrides['italic'] as bool?,
        posX: overrides['posX'] as double?,
        posY: overrides['posY'] as double?,
        alignment: overrides['alignment'] as Alignment?,
      );
      
      result.add(processedSubtitle);
    }
    
    return result;
  }

  // 解析内联样式标签
  static (String, Map<String, dynamic>) _parseStyleOverrides(String text) {
    final Map<String, dynamic> overrides = {};
    
    // 解析位置标签 {\pos(x,y)}
    final posRegex = RegExp(r'\{\\pos\((\d+\.?\d*),(\d+\.?\d*)\)\}');
    final posMatch = posRegex.firstMatch(text);
    if (posMatch != null) {
      overrides['posX'] = double.parse(posMatch.group(1)!);
      overrides['posY'] = double.parse(posMatch.group(2)!);
      text = text.replaceFirst(posRegex, '');
    }
    
    // 解析对齐标签 {\an1} 到 {\an9}
    final alignRegex = RegExp(r'\{\\an([1-9])\}');
    final alignMatch = alignRegex.firstMatch(text);
    if (alignMatch != null) {
      final alignValue = int.parse(alignMatch.group(1)!);
      overrides['alignment'] = _convertAssAlignmentToFlutter(alignValue);
      text = text.replaceFirst(alignRegex, '');
    }
    
    // 解析颜色标签 {\c&HBBGGRR&} 或 {\1c&HBBGGRR&}
    final colorRegex = RegExp(r'\{\\([1-4])?c&H([0-9A-Fa-f]{2,6})&\}');
    final colorMatches = colorRegex.allMatches(text);
    for (final match in colorMatches) {
      final colorType = match.group(1); // null 表示主要颜色
      final hexColor = match.group(2)!;
      
      if (colorType == null || colorType == '1') {
        // 主要颜色
        overrides['color'] = _parseAssColor('&H$hexColor&');
      }
      
      // 可以添加对其他颜色类型的处理
      
      text = text.replaceFirst(match.pattern, '');
    }
    
    // 解析字体大小标签 {\fs20}
    final fsRegex = RegExp(r'\{\\fs(\d+\.?\d*)\}');
    final fsMatch = fsRegex.firstMatch(text);
    if (fsMatch != null) {
      overrides['fontSize'] = double.parse(fsMatch.group(1)!);
      text = text.replaceFirst(fsRegex, '');
    }
    
    // 解析粗体标签 {\b1} 或 {\b0}
    final boldRegex = RegExp(r'\{\\b([01])\}');
    final boldMatch = boldRegex.firstMatch(text);
    if (boldMatch != null) {
      overrides['bold'] = boldMatch.group(1) == '1';
      text = text.replaceFirst(boldRegex, '');
    }
    
    // 解析斜体标签 {\i1} 或 {\i0}
    final italicRegex = RegExp(r'\{\\i([01])\}');
    final italicMatch = italicRegex.firstMatch(text);
    if (italicMatch != null) {
      overrides['italic'] = italicMatch.group(1) == '1';
      text = text.replaceFirst(italicRegex, '');
    }
    
    // 移除所有剩余的标签
    text = _removeAssMarkup(text);
    
    return (text, overrides);
  }

  // 解析ASS时间格式
  static Duration? _parseAssTime(String timeStr) {
    // ASS时间格式: H:MM:SS.CC
    final regex = RegExp(r'(\d+):(\d+):(\d+)\.(\d+)');
    final match = regex.firstMatch(timeStr);
    
    if (match != null) {
      final hours = int.parse(match.group(1)!);
      final minutes = int.parse(match.group(2)!);
      final seconds = int.parse(match.group(3)!);
      final centiseconds = int.parse(match.group(4)!);
      
      return Duration(
        hours: hours,
        minutes: minutes,
        seconds: seconds,
        milliseconds: centiseconds * 10,
      );
    }
    
    return null;
  }

  // 移除ASS标记指令，只保留纯文本
  static String _removeAssMarkup(String text) {
    // 移除花括号中的ASS标记
    var result = text.replaceAll(RegExp(r'\{[^}]*\}'), '');
    // 处理换行符
    result = result.replaceAll(r'\N', '\n');
    result = result.replaceAll(r'\n', '\n');
    result = result.replaceAll(r'\h', ' ');
    return result;
  }

  // 解析ASS颜色格式
  static Color _parseAssColor(String? colorStr) {
    if (colorStr == null || colorStr.isEmpty) {
      return Colors.white;
    }
    
    // 去掉 &H 和 &
    colorStr = colorStr.replaceAll('&H', '').replaceAll('&', '');
    
    // 如果长度不够，补全
    while (colorStr!.length < 6) {
      colorStr = '0$colorStr';
    }
    
    if (colorStr.length > 6) {
      // 处理透明度
      colorStr = colorStr.substring(colorStr.length - 6);
    }
    
    // ASS 颜色是 BGR 格式
    final b = int.parse(colorStr.substring(0, 2), radix: 16);
    final g = int.parse(colorStr.substring(2, 4), radix: 16);
    final r = int.parse(colorStr.substring(4, 6), radix: 16);
    
    return Color.fromARGB(255, r, g, b);
  }

  // 将 ASS 的对齐方式转换为 Flutter 的 Alignment
  static Alignment _convertAssAlignmentToFlutter(int alignValue) {
    // ASS 的对齐方式为:
    // 7 8 9
    // 4 5 6
    // 1 2 3
    
    switch (alignValue) {
      case 1: return Alignment.bottomLeft;
      case 2: return Alignment.bottomCenter;
      case 3: return Alignment.bottomRight;
      case 4: return Alignment.centerLeft;
      case 5: return Alignment.center;
      case 6: return Alignment.centerRight;
      case 7: return Alignment.topLeft;
      case 8: return Alignment.topCenter;
      case 9: return Alignment.topRight;
      default: return Alignment.bottomCenter; // 默认
    }
  }
}

class AssSubtitleRenderer extends StatelessWidget {
  final List<AssSubtitle> subtitles;
  final Duration currentPosition;
  final Size videoSize;
  final double subtitleScale; // 字幕缩放
  
  const AssSubtitleRenderer({
    Key? key,
    required this.subtitles,
    required this.currentPosition,
    required this.videoSize,
    this.subtitleScale = 1.0,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    // 过滤出当前时间应该显示的字幕
    final visibleSubtitles = subtitles
        .where((subtitle) => subtitle.isVisibleAt(currentPosition))
        .toList();
        
    return SizedBox(
      width: videoSize.width,
      height: videoSize.height,
      child: Stack(
        children: visibleSubtitles.map((subtitle) {
          // 获取样式
          final color = subtitle.getEffectiveColor();
          final fontSize = subtitle.getEffectiveFontSize() * subtitleScale;
          final fontWeight = subtitle.getEffectiveFontWeight();
          final fontStyle = subtitle.getEffectiveFontStyle();
          final alignment = subtitle.getEffectiveAlignment();
          
          // 安全地获取样式属性
          final style = subtitle.style;
          final outlineColor = style?.outlineColor ?? Colors.black;
          final outlineWidth = style?.outlineWidth ?? 2.0;
          final shadowWidth = style?.shadowWidth ?? 2.0;
          final underline = style?.underline ?? false;
          final strikeOut = style?.strikeOut ?? false;
          
          // 获取边距
          final marginL = (style?.marginL ?? 10)*subtitleScale;
          final marginR = (style?.marginR ?? 10)*subtitleScale;
          final marginV = (style?.marginV ?? 10)*subtitleScale;
          
          // 检查是否有精确位置
          final exactPos = subtitle.getExactPosition(videoSize);
          
          if (exactPos != null) {
            // 使用精确位置
            return Positioned(
              left: exactPos.dx,
              top: exactPos.dy,
              child: _buildSubtitleText(
                subtitle, 
                color, 
                fontSize, 
                fontWeight, 
                fontStyle,
                outlineColor,
                outlineWidth,
                shadowWidth,
                underline,
                strikeOut,
              ),
            );
          } else {
            // 使用对齐方式和边距
            return Positioned.fill(
              child: Align(
                alignment: alignment,
                child: Padding(
                  // 根据对齐方式应用不同的边距
                  padding: _getPaddingForAlignment(
                    alignment,
                    marginL.toDouble(), 
                    marginR.toDouble(), 
                    marginV.toDouble()
                  ),
                  child: _buildSubtitleText(
                    subtitle, 
                    color, 
                    fontSize, 
                    fontWeight, 
                    fontStyle,
                    outlineColor,
                    outlineWidth,
                    shadowWidth,
                    underline,
                    strikeOut,
                  ),
                ),
              ),
            );
          }
        }).toList(),
      ),
    );
  }
  
  // 根据对齐方式计算合适的边距
  EdgeInsets _getPaddingForAlignment(
    Alignment alignment,
    double marginL,
    double marginR,
    double marginV
  ) {
    // 顶部对齐
    if (alignment == Alignment.topLeft || 
        alignment == Alignment.topCenter || 
        alignment == Alignment.topRight) {
      return EdgeInsets.fromLTRB(marginL, marginV, marginR, 0);
    }
    // 底部对齐
    else if (alignment == Alignment.bottomLeft || 
             alignment == Alignment.bottomCenter || 
             alignment == Alignment.bottomRight) {
      return EdgeInsets.fromLTRB(marginL, 0, marginR, marginV);
    }
    // 中间对齐
    else {
      return EdgeInsets.fromLTRB(marginL, marginV / 2, marginR, marginV / 2);
    }
  }
  
  Widget _buildSubtitleText(
    AssSubtitle subtitle, 
    Color color, 
    double fontSize, 
    FontWeight fontWeight, 
    FontStyle fontStyle,
    Color outlineColor,
    double outlineWidth,
    double shadowWidth,
    bool underline,
    bool strikeOut,
  ) {
    // 创建文本装饰
    final TextDecoration? decoration = underline 
        ? (strikeOut ? TextDecoration.combine([TextDecoration.underline, TextDecoration.lineThrough]) 
                    : TextDecoration.underline)
        : (strikeOut ? TextDecoration.lineThrough : null);
    
    // 创建阴影效果
    final List<Shadow> shadows = [];
    
    // 添加描边效果
    if (outlineWidth > 0) {
      shadows.addAll([
        Shadow(offset: const Offset(1, 1), blurRadius: outlineWidth, color: outlineColor),
        Shadow(offset: const Offset(-1, -1), blurRadius: outlineWidth, color: outlineColor),
        Shadow(offset: const Offset(1, -1), blurRadius: outlineWidth, color: outlineColor),
        Shadow(offset: const Offset(-1, 1), blurRadius: outlineWidth, color: outlineColor),
      ]);
    }
    
    // 添加阴影效果
    if (shadowWidth > 0) {
      shadows.add(
        Shadow(
          offset: Offset(shadowWidth / 2, shadowWidth / 2),
          blurRadius: shadowWidth,
          color: Colors.black.withOpacity(0.6),
        ),
      );
    }
    
    // 去除了半透明黑框，直接返回Text组件
    return Text(
      subtitle.text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        shadows: shadows,
        decoration: decoration,
        decorationColor: color,
      ),
      textAlign: TextAlign.center,
    );
  }
}