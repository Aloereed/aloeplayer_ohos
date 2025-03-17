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
  final int playResX;
  final int playResY;

  AssStyle(
      {required this.name,
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
      this.playResX = 1920,
      this.playResY = 1080});
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

  final int marginL;
  final int marginR;
  final int marginV;

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
    required this.marginL,
    required this.marginR,
    required this.marginV,
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
  static Future<(List<AssStyle>, List<AssSubtitle>)> parseAssFile(
      String filePath) async {
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
    int playResX = 1920;
    int playResY = 1080;

    for (var line in lines) {
      line = line.trim();

      if (line.isEmpty || line.startsWith(';')) {
        continue; // 跳过空行和注释
      }

      if (line.startsWith('[Styles]') || line.startsWith('[V4+ Styles]')) {
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
      } else if (line.startsWith('PlayResX:')) {
        playResX =
            int.tryParse(line.substring('PlayResX:'.length).trim()) ?? 1920;
      } else if (line.startsWith('PlayResY:')) {
        playResY =
            int.tryParse(line.substring('PlayResY:'.length).trim()) ?? 1080;
      }
      print('Processing line: $line');

      if (inStyles) {
        if (line.startsWith('Format:')) {
          styleFormatLine = line;
        } else if (line.startsWith('Style:') && styleFormatLine != null) {
          final style =
              parseStyleLine(line, styleFormatLine, playResX, playResY);
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
  static AssStyle? parseStyleLine(
      String styleLine, String formatLine, int playResX, int playResY) {
    final formatFields = formatLine
        .substring('Format:'.length)
        .split(',')
        .map((field) => field.trim())
        .toList();
    print('FormatFields: $formatFields');
    final styleParts = styleLine.substring('Style:'.length).split(',');

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
    final outlineColor = _parseAssColor(
        styleData['OutlineColour'] ?? styleData['TertiaryColour']);
    final backColor = _parseAssColor(styleData['BackColour']);
    print("get style color done.");

    // 解析字体样式
    final bold =
        styleData['Bold'] == '1' || styleData['Bold']?.toLowerCase() == 'yes';
    final italic = styleData['Italic'] == '1' ||
        styleData['Italic']?.toLowerCase() == 'yes';
    final underline = styleData['Underline'] == '1' ||
        styleData['Underline']?.toLowerCase() == 'yes';
    final strikeOut = styleData['StrikeOut'] == '1' ||
        styleData['StrikeOut']?.toLowerCase() == 'yes';
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
      playResX: playResX,
      playResY: playResY,
    );
  }

  // 解析对话行
  static AssSubtitle? parseDialogueLine(
      String dialogueLine, String formatLine) {
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
    final marginLIndex = formatFields.indexOf('MarginL');
    final marginRIndex = formatFields.indexOf('MarginR');
    final marginVIndex = formatFields.indexOf('MarginV');

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

    int marginL = 0;
    int marginR = 0;
    int marginV = 0;
    if(marginVIndex >= 0 && marginVIndex < parts.length) {
      marginV = int.tryParse(parts[marginVIndex]) ?? 0;
    }
    if(marginLIndex >= 0 && marginLIndex < parts.length) {
      marginL = int.tryParse(parts[marginLIndex])?? 0; 
    }
    if(marginRIndex >= 0 && marginRIndex < parts.length) {
      marginR = int.tryParse(parts[marginRIndex])?? 0; 
    }

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
    String plainText = _removeAssMarkup(rawText);

    return AssSubtitle(
      startTime: startTime,
      endTime: endTime,
      text: plainText,
      rawText: rawText,
      styleName: styleName,
      marginL: marginL,
      marginR: marginR,
      marginV: marginV,
    );
  }

  // 将样式应用到字幕
  static void _applyStylesToSubtitles(
      List<AssStyle> styles, List<AssSubtitle> subtitles) {
    print("Apply styles to subtitles");
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
        marginL: subtitle.marginL,
        marginR: subtitle.marginR,
        marginV: subtitle.marginV,
      );

      result.add(processedSubtitle);
    }

    return result;
  }

  // 解析内联样式标签
  static (String, Map<String, dynamic>) _parseStyleOverrides(String text) {
    final Map<String, dynamic> overrides = {};

    // 匹配所有样式标签块 {...}
    final tagBlockRegex = RegExp(r'\{(\\[^}]*)\}');
    final tagBlocks = tagBlockRegex.allMatches(text);

    String cleanText = text;

    for (final block in tagBlocks) {
      // 获取完整的样式块内容
      final fullBlock = block.group(0)!;
      final styleContent = block.group(1)!;

      // 拆分多个样式指令
      final styleDirectives =
          styleContent.split('\\').where((s) => s.isNotEmpty).toList();

      for (final directive in styleDirectives) {
        // 处理位置指令 pos(x,y)
        if (directive.startsWith('pos(')) {
          final posMatch =
              RegExp(r'pos\((\d+\.?\d*),(\d+\.?\d*)\)').firstMatch(directive);
          if (posMatch != null) {
            overrides['posX'] = double.parse(posMatch.group(1)!);
            overrides['posY'] = double.parse(posMatch.group(2)!);
          }
        }
        // 处理对齐指令 an1-an9
        else if (directive.startsWith('an')) {
          final alignMatch = RegExp(r'an([1-9])').firstMatch(directive);
          if (alignMatch != null) {
            final alignValue = int.parse(alignMatch.group(1)!);
            overrides['alignment'] = _convertAssAlignmentToFlutter(alignValue);
          }
        }
        // 处理主要颜色 c&HBBGGRR&
        else if (directive.startsWith('c&H') || directive.startsWith('1c&H')) {
          final colorMatch =
              RegExp(r'(?:1)?c&H([0-9A-Fa-f]{2,6})&?').firstMatch(directive);
          if (colorMatch != null) {
            overrides['color'] = _parseAssColor('&H${colorMatch.group(1)!}&');
          }
        }
        // 处理边框颜色 3c&HBBGGRR&
        else if (directive.startsWith('3c&H')) {
          final outlineColorMatch =
              RegExp(r'3c&H([0-9A-Fa-f]{2,6})&?').firstMatch(directive);
          if (outlineColorMatch != null) {
            overrides['outlineColor'] =
                _parseAssColor('&H${outlineColorMatch.group(1)!}&');
          }
        }
        // 处理字体大小 fs20
        else if (directive.startsWith('fs')) {
          final fsMatch = RegExp(r'fs(\d+\.?\d*)').firstMatch(directive);
          if (fsMatch != null) {
            overrides['fontSize'] = double.parse(fsMatch.group(1)!);
          }
        }
        // 处理边框大小 bord3
        else if (directive.startsWith('bord')) {
          final bordMatch = RegExp(r'bord(\d+\.?\d*)').firstMatch(directive);
          if (bordMatch != null) {
            overrides['outlineWidth'] = double.parse(bordMatch.group(1)!);
          }
        }
        // 处理模糊效果 blur2
        else if (directive.startsWith('blur')) {
          final blurMatch = RegExp(r'blur(\d+\.?\d*)').firstMatch(directive);
          if (blurMatch != null) {
            overrides['blur'] = double.parse(blurMatch.group(1)!);
          }
        }
        // 处理粗体 b1 或 b0
        else if (directive.startsWith('b')) {
          final boldMatch = RegExp(r'b([01])').firstMatch(directive);
          if (boldMatch != null) {
            overrides['bold'] = boldMatch.group(1) == '1';
          }
        }
        // 处理斜体 i1 或 i0
        else if (directive.startsWith('i')) {
          final italicMatch = RegExp(r'i([01])').firstMatch(directive);
          if (italicMatch != null) {
            overrides['italic'] = italicMatch.group(1) == '1';
          }
        }
        // 处理下划线 u1 或 u0
        else if (directive.startsWith('u')) {
          final underlineMatch = RegExp(r'u([01])').firstMatch(directive);
          if (underlineMatch != null) {
            overrides['underline'] = underlineMatch.group(1) == '1';
          }
        }
        // 处理删除线 s1 或 s0
        else if (directive.startsWith('s')) {
          final strikeOutMatch = RegExp(r's([01])').firstMatch(directive);
          if (strikeOutMatch != null) {
            overrides['strikeOut'] = strikeOutMatch.group(1) == '1';
          }
        }
        // 可以继续添加更多样式解析...

        // 添加对阴影宽度 shad 的处理
        else if (directive.startsWith('shad')) {
          final shadMatch = RegExp(r'shad(\d+\.?\d*)').firstMatch(directive);
          if (shadMatch != null) {
            overrides['shadowWidth'] = double.parse(shadMatch.group(1)!);
          }
        }
      }

      // 从文本中移除整个样式块
      cleanText = cleanText.replaceFirst(fullBlock, '');
      cleanText = _removeAssMarkup(cleanText);
    }

    return (cleanText, overrides);
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
    result = result.replaceAll('\\N', '\n');
    result = result.replaceAll('\\n', '\n');
    result = result.replaceAll('\\h', ' ');
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
      case 1:
        return Alignment.bottomLeft;
      case 2:
        return Alignment.bottomCenter;
      case 3:
        return Alignment.bottomRight;
      case 4:
        return Alignment.centerLeft;
      case 5:
        return Alignment.center;
      case 6:
        return Alignment.centerRight;
      case 7:
        return Alignment.topLeft;
      case 8:
        return Alignment.topCenter;
      case 9:
        return Alignment.topRight;
      default:
        return Alignment.bottomCenter; // 默认
    }
  }
}

class AssSubtitleRenderer extends StatelessWidget {
  final List<AssSubtitle> subtitles;
  final Duration currentPosition;
  final Size videoSize;
  final double subtitleScale;
  final String? fontFamily;

  const AssSubtitleRenderer({
    Key? key,
    required this.subtitles,
    required this.currentPosition,
    required this.videoSize,
    this.subtitleScale = 1.0,
    this.fontFamily
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

          // 获取边距并应用缩放
          final marginL = (style == null ? 10 : subtitle.marginL + style.marginL) * subtitleScale;
          final marginR = (style == null ? 10 : subtitle.marginR + style.marginR) * subtitleScale;
          final marginV = (style == null ? 10 : subtitle.marginV + style.marginV) * subtitleScale;

          // 准备字幕文本小部件
          final subtitleText = _buildSubtitleText(
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
            fontFamily,
          );

          // 检查是否有精确位置
          final exactPos = subtitle.getExactPosition(videoSize);

          if (exactPos != null) {
            // 获取 ASS 文件中定义的播放分辨率
            final playResX = style?.playResX.toDouble() ?? videoSize.width;
            final playResY = style?.playResY.toDouble() ?? videoSize.height;

            // 计算缩放比例
            final scaleX = videoSize.width / playResX;
            final scaleY = videoSize.height / playResY;

            // 应用缩放比例到坐标
            final scaledX = exactPos.dx * scaleX;
            final scaledY = exactPos.dy * scaleY;

            // 使用缩放后的精确位置
            return Positioned(
              left: scaledX,
              top: scaledY,
              child: FractionalTranslation(
                translation: const Offset(-0.5, -0.5), // 居中显示文本
                child: subtitleText,
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
                      marginV.toDouble()),
                  child: subtitleText,
                ),
              ),
            );
          }
        }).toList(),
      ),
    );
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
    String? fontFamily,
  ) {
    // 创建文本装饰
    final TextDecoration? decoration = underline
        ? (strikeOut
            ? TextDecoration.combine(
                [TextDecoration.underline, TextDecoration.lineThrough])
            : TextDecoration.underline)
        : (strikeOut ? TextDecoration.lineThrough : null);

    // 创建阴影效果
    final List<Shadow> shadows = [];

    // 添加描边效果
    if (outlineWidth > 0) {
      shadows.addAll([
        Shadow(
            offset: const Offset(1, 1),
            blurRadius: outlineWidth,
            color: outlineColor),
        Shadow(
            offset: const Offset(-1, -1),
            blurRadius: outlineWidth,
            color: outlineColor),
        Shadow(
            offset: const Offset(1, -1),
            blurRadius: outlineWidth,
            color: outlineColor),
        Shadow(
            offset: const Offset(-1, 1),
            blurRadius: outlineWidth,
            color: outlineColor),
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

    // 返回文本组件
    return Text(
      subtitle.text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        fontFamily: fontFamily,
        shadows: shadows,
        decoration: decoration,
        decorationColor: color,
      ),
      textAlign: TextAlign.center,
    );
  }

  EdgeInsets _getPaddingForAlignment(
      Alignment alignment, double marginL, double marginR, double marginV) {
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
}
