/*
 * @Author: 
 * @Date: 2025-01-12 15:11:12
 * @LastEditors: Please set LastEditors
 * @LastEditTime: 2025-04-02 17:45:58
 * @Description: file content
 */
import 'dart:convert';
import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme_provider.dart'; // 假设你已经有一个ThemeProvider
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:file_picker_ohos/file_picker_ohos.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

enum SortType { none, name, modifiedDate }

enum SortOrder { ascending, descending }

// 将字体缓存添加到全局状态，方便管理已加载的字体
class FontCache {
  static final Map<String, String> _loadedFonts = {}; // 路径到fontFamily的映射

  // 获取所有已加载字体的fontFamily
  static List<String> get loadedFontFamilies => _loadedFonts.values.toList();

  // 通过路径获取fontFamily
  static String? getFontFamily(String fontPath) {
    return _loadedFonts[fontPath];
  }

  // 添加字体到缓存
  static void addFont(String fontPath, String fontFamily) {
    _loadedFonts[fontPath] = fontFamily;
  }

  // 从缓存移除字体
  static void removeFont(String fontPath) {
    _loadedFonts.remove(fontPath);
  }

  // 检查字体是否已加载
  static bool isFontLoaded(String fontPath) {
    return _loadedFonts.containsKey(fontPath);
  }

  // 清空缓存
  static void clear() {
    _loadedFonts.clear();
  }
}

String sanitizeFileName(String input) {
  if (input == null || input.isEmpty) {
    return '_';
  }

  // 定义不允许在文件名中使用的字符的正则表达式
  // 这包括: / \ : * ? " < > | 以及其他控制字符
  final RegExp invalidChars = RegExp(r'[\\/:*?"<>|\x00-\x1F]');

  // 替换所有不合法字符为下划线
  String sanitized = input.replaceAll(invalidChars, '_');

  // 移除前导和尾随空格
  sanitized = sanitized.trim();

  // 如果结果为空字符串，返回一个下划线
  if (sanitized.isEmpty) {
    return '_';
  }

  // 在一些操作系统中，以点开头的文件可能会被视为隐藏文件
  // 所以如果字符串以点开头，添加一个下划线
  if (sanitized.startsWith('.')) {
    sanitized = '_' + sanitized;
  }

  return sanitized;
}

/// 解析字幕轨道信息并返回友好的中文描述
///
/// [jsonString]: 从FFmpeg获取的字幕轨道JSON字符串
/// [useOriginalIndices]: 是否使用原始索引（true）或从0开始重新编号（false）
Map<int, String> parseSubtitleTracks(String jsonString,
    {bool useOriginalIndices = true}) {
  // 如果JSON字符串为空，返回空Map
  if (jsonString.isEmpty) {
    return {};
  }

  try {
    // 解析JSON字符串
    final Map<String, dynamic> data = json.decode(jsonString);
    final List<dynamic> tracks = data['subtitleTracks'] ?? [];

    // 创建字幕轨道索引到友好描述的映射
    final Map<int, String> friendlyTracks = {};

    // 如果使用从0开始的索引，则需要一个计数器
    int newIndex = 0;

    for (final track in tracks) {
      final int originalIndex = track['index'] ?? -1;
      if (originalIndex == -1) continue; // 跳过无效索引

      // 确定要使用的索引
      final int indexToUse = useOriginalIndices ? originalIndex : newIndex++;

      // 获取各项参数
      final String language =
          _getSubtitleLanguageName(track['language'] ?? 'und');
      final String codec = _formatSubtitleCodec(track['codec'] ?? '');
      String title = track['title'] ?? '';

      // 构建友好的描述
      String description = language;

      // 如果有标题，添加到描述中
      if (title.isNotEmpty) {
        // 确保标题不是语言的重复
        if (!title.toLowerCase().contains(language.toLowerCase()) &&
            !language.toLowerCase().contains(title.toLowerCase())) {
          description += ' - $title';
        }
      }

      // 添加编解码器信息（如果不是太技术性的话）
      if (codec != '未知格式' && !codec.contains('未知')) {
        description += ' ($codec)';
      }

      friendlyTracks[indexToUse] = sanitizeFileName(description);
    }

    return friendlyTracks;
  } catch (e) {
    print('解析字幕轨道时出错: $e');
    return {};
  }
}

/// 获取字幕语言的友好中文名称
String _getSubtitleLanguageName(String languageCode) {
  // 语言代码到友好中文名称的映射
  const languageMap = {
    'und': '未知语言',
    'eng': '英语',
    'en': '英语',
    'chi': '中文',
    'zh': '中文',
    'zho': '中文',
    'cmn': '普通话',
    'yue': '粤语',
    'jpn': '日语',
    'ja': '日语',
    'kor': '韩语',
    'ko': '韩语',
    'fre': '法语',
    'fra': '法语',
    'fr': '法语',
    'ger': '德语',
    'deu': '德语',
    'de': '德语',
    'spa': '西班牙语',
    'es': '西班牙语',
    'ita': '意大利语',
    'it': '意大利语',
    'rus': '俄语',
    'ru': '俄语',
    'por': '葡萄牙语',
    'pt': '葡萄牙语',
    'ara': '阿拉伯语',
    'ar': '阿拉伯语',
    'hin': '印地语',
    'hi': '印地语',
    'ben': '孟加拉语',
    'bn': '孟加拉语',
    'pan': '旁遮普语',
    'pa': '旁遮普语',
    'tam': '泰米尔语',
    'ta': '泰米尔语',
    'tel': '泰卢固语',
    'te': '泰卢固语',
    'mar': '马拉地语',
    'mr': '马拉地语',
    'vie': '越南语',
    'vi': '越南语',
    'tha': '泰语',
    'th': '泰语',
    'ind': '印尼语',
    'id': '印尼语',
    'may': '马来语',
    'ms': '马来语',
    'msa': '马来语',
    'tur': '土耳其语',
    'tr': '土耳其语',
    'nld': '荷兰语',
    'dut': '荷兰语',
    'nl': '荷兰语',
    'swe': '瑞典语',
    'sv': '瑞典语',
    'nor': '挪威语',
    'no': '挪威语',
    'fin': '芬兰语',
    'fi': '芬兰语',
    'dan': '丹麦语',
    'da': '丹麦语',
    'pol': '波兰语',
    'pl': '波兰语',
    'hun': '匈牙利语',
    'hu': '匈牙利语',
    'ces': '捷克语',
    'cze': '捷克语',
    'cs': '捷克语',
    'gre': '希腊语',
    'ell': '希腊语',
    'el': '希腊语',
    'heb': '希伯来语',
    'he': '希伯来语',
    'urd': '乌尔都语',
    'ur': '乌尔都语',
    'fas': '波斯语',
    'per': '波斯语',
    'fa': '波斯语',
    // 简称和双字符代码
    'cn': '中文',
    'tw': '繁体中文',
    'hk': '繁体中文(香港)',
  };

  return languageMap[languageCode.toLowerCase()] ?? '未知语言';
}

/// 格式化字幕编解码器名称为友好的中文描述
String _formatSubtitleCodec(String codec) {
  // 编解码器友好中文名称映射
  const codecMap = {
    'subrip': 'SRT字幕',
    'srt': 'SRT字幕',
    'ass': 'ASS字幕',
    'ssa': 'SSA字幕',
    'mov_text': 'MOV文本',
    'webvtt': 'WebVTT字幕',
    'dvb_subtitle': 'DVB字幕',
    'dvd_subtitle': 'DVD字幕',
    'hdmv_pgs_subtitle': 'PGS字幕',
    'xsub': 'XSUB字幕',
    'dvb_teletext': '图文字幕',
    'microdvd': 'MicroDVD字幕',
    'jacosub': 'JacoSub字幕',
    'sami': 'SAMI字幕',
    'realtext': 'RealText字幕',
    'subviewer': 'SubViewer字幕',
    'subviewer1': 'SubViewer 1字幕',
    'pjs': 'PJS字幕',
    'mpl2': 'MPL2字幕',
    'vplayer': 'VPlayer字幕',
    'stl': 'STL字幕',
    'cc_dec': '闭路字幕',
  };

  return codecMap[codec.toLowerCase()] ?? '未知格式';
}

/// 解析音频轨道信息并返回友好的显示格式
Map<int, String> parseAudioTracks(String jsonString) {
  // 如果JSON字符串为空，返回空Map
  if (jsonString.isEmpty) {
    return {};
  }

  try {
    // 解析JSON字符串
    final Map<String, dynamic> data = json.decode(jsonString);
    final List<dynamic> tracks = data['audioTracks'] ?? [];

    // 创建音轨索引到友好描述的映射
    final Map<int, String> friendlyTracks = {};

    for (final track in tracks) {
      final int index = track['index'] ?? -1;
      if (index == -1) continue; // 跳过无效索引

      // 获取各项参数
      final String language = _getLanguageName(track['language'] ?? 'und');
      final String codec = _formatCodec(track['codec'] ?? '');
      final int channels = track['channels'] ?? 0;
      final int sampleRate = track['sampleRate'] ?? 0;

      // 构建友好的描述
      final String channelDesc = _formatChannels(channels);
      final String sampleRateDesc = _formatSampleRate(sampleRate);

      // 组合成最终描述
      friendlyTracks[index] = '$language-$codec-$channelDesc-$sampleRateDesc';
    }

    return friendlyTracks;
  } catch (e) {
    print('Error parsing audio tracks: $e');
    return {};
  }
}

/// 获取语言的友好名称
String _getLanguageName(String languageCode) {
  // 语言代码到友好名称的映射
  const languageMap = {
    'und': '未知语言',
    'eng': '英语',
    'chi': '汉语',
    'zho': '汉语',
    'cmn': '普通话',
    'yue': '粤语',
    'jpn': '日语',
    'kor': '韩语',
    'fre': '法语',
    'fra': '法语',
    'ger': '德语',
    'deu': '德语',
    'spa': '西班牙语',
    'ita': '意大利语',
    'rus': '俄语',
    'por': '葡萄牙语',
    'ara': '阿拉伯语',
    'hin': '印地语',
    'ben': '孟加拉语',
    'pan': '旁遮普语',
    'tam': '泰米尔语',
    'tel': '泰卢固语',
    'mar': '马拉地语',
    'vie': '越南语',
    'tha': '泰语',
    'ind': '印尼语',
    'may': '马来语',
    'msa': '马来语',
    'tur': '土耳其语',
    'nld': '荷兰语',
    'dut': '荷兰语',
    'swe': '瑞典语',
    'nor': '挪威语',
    'fin': '芬兰语',
    'dan': '丹麦语',
    'pol': '波兰语',
    'hun': '匈牙利语',
    'ces': '捷克语',
    'cze': '捷克语',
    'gre': '希腊语',
    'ell': '希腊语',
    'heb': '希伯来语',
    'urd': '乌尔都语',
    'fas': '波斯语',
    'per': '波斯语',
    // 可以根据需要添加更多语言
  };

  return languageMap[languageCode.toLowerCase()] ?? languageCode;
}

/// 格式化编解码器名称
String _formatCodec(String codec) {
  // 编解码器友好名称映射
  const codecMap = {
    'aac': 'AAC',
    'mp3': 'MP3',
    'ac3': 'AC3',
    'eac3': 'E-AC3',
    'dts': 'DTS',
    'truehd': 'TrueHD',
    'opus': 'Opus',
    'vorbis': 'Vorbis',
    'flac': 'FLAC',
    'alac': 'ALAC',
    'pcm_s16le': 'PCM',
    'pcm_s24le': 'PCM',
    'pcm_s32le': 'PCM',
    // 添加更多编解码器
  };

  return codecMap[codec.toLowerCase()] ?? codec.toUpperCase();
}

/// 根据通道数格式化通道描述
String _formatChannels(int channels) {
  switch (channels) {
    case 1:
      return '单声道';
    case 2:
      return '双声道/立体声';
    case 6:
      return '5.1声道';
    case 8:
      return '7.1声道';
    default:
      return channels > 0 ? '$channels声道' : '未知声道';
  }
}

/// 格式化采样率
String _formatSampleRate(int sampleRate) {
  if (sampleRate <= 0) {
    return '未知采样率';
  }

  // 转换为kHz并格式化
  final double kHz = sampleRate / 1000.0;
  if (kHz.toInt() == kHz) {
    return '${kHz.toInt()}kHz';
  } else {
    return '${kHz.toStringAsFixed(1)}kHz';
  }
}

class DeviceInfo {
  final bool isTablet;
  final bool isLandscape;

  DeviceInfo({required this.isTablet, required this.isLandscape});

  @override
  String toString() {
    String deviceType = isTablet ? "平板" : "手机";
    String orientation = isLandscape ? "横屏" : "竖屏";
    return "$deviceType，$orientation";
  }
}

DeviceInfo getDeviceInfo(BuildContext context) {
  // 获取媒体查询对象
  final MediaQueryData mediaQuery = MediaQuery.of(context);

  // 获取屏幕宽度和高度（像素）
  final Size size = mediaQuery.size;
  final double width = size.width;
  final double height = size.height;

  // 获取设备像素比
  final double devicePixelRatio = mediaQuery.devicePixelRatio;

  // 计算物理像素大小
  final double physicalWidth = width * devicePixelRatio;
  final double physicalHeight = height * devicePixelRatio;

  // 计算屏幕对角线尺寸（英寸）
  // 假设像素密度为160dpi，平板与手机的分界线通常为7英寸
  final double diagonalInches = math.sqrt(
          physicalWidth * physicalWidth + physicalHeight * physicalHeight) /
      (160 * devicePixelRatio);

  // 判断是否为平板（对角线尺寸大于7英寸）
  final bool isTablet = diagonalInches >= 7.0;

  // 判断当前是否为横屏
  final bool isLandscape = width > height;

  return DeviceInfo(isTablet: isTablet, isLandscape: isLandscape);
}

class SettingsService {
  static const String _fontSizeKey = 'subtitle_font_size';
  static const String _backgroundPlayKey = 'background_play';
  static const String _autoLoadSubtitleKey = 'auto_load_subtitle';
  static const String _extractAssSubtitleKey = 'extract_ass_subtitle';
  static const String _useFfmpegForPlayKey = 'use_ffmpeg_for_play_2';
  static const String _autoFfmpegAfterVpFailed = 'auto_ffmpeg_after_vp_failed';
  static const String _autoFullscreenBeginPlay = 'auto_fullscreen_begin_play';
  static const String _defaultListmode = 'default_listmode';
  static const String _usePlaylist = 'use_playlist';
  static const String _useSeekToLatest = 'use_seek_to_latest';
  static const String _useInnerThumbnail = 'use_inner_thumbnail';
  static const String _disableThumbnail = 'disable_thumbnail';
  static const String _subtitleFont = 'subtitle_font';
  static const String _hdrForHdr = 'hdr_for_hdr';
  static const String _subtitleMany = 'subtitle_many';
  static const String _versionName = '2.0.7';
  static const int _versionNumber = 31;

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
    return prefs.getBool(_extractAssSubtitleKey) ?? true; // 默认值为true
  }

  Future<void> saveSubtitleFont(String subtitleFont) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_subtitleFont, subtitleFont);
  }

  Future<String> getSubtitleFont() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_subtitleFont) ??
        ""; // 默认值为"assets/fonts/NotoSansSC-Regular.ttf"
  }

  Future<void> saveUseFfmpegForPlay(int useFfmpeg) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_useFfmpegForPlayKey, useFfmpeg);
  }

  Future<int> getUseFfmpegForPlay() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_useFfmpegForPlayKey) ?? 0; // 默认值为false
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

  Future<void> saveDisableThumbnail(bool disableThumbnail) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_disableThumbnail, disableThumbnail);
  }

  Future<bool> getDisableThumbnail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_disableThumbnail) ?? false; // 默认值为false
  }

  Future<void> saveHdrForHdr(bool hdrForHdr) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hdrForHdr, hdrForHdr);
  }

  Future<bool> getHdrForHdr() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hdrForHdr) ?? false; // 默认值为false
  }

  Future<void> saveSubtitleMany(int subtitleMany) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_subtitleMany, subtitleMany);
  }

  Future<int> getSubtitleMany() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_subtitleMany) ?? 0; // 默认值为0
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

// 应用启动时加载所有字体
  Future<void> loadAllFonts() async {
    final fontPaths = await _getCustomFonts();
    for (final fontPath in fontPaths) {
      await loadFontFromFile(fontPath);
    }
    print('已加载${fontPaths.length}个自定义字体');
  }

// 从文件加载字体
  Future<String?> loadFontFromFile(String fontPath) async {
    try {
      if (fontPath.isEmpty) return null;

      // 检查字体是否已加载
      if (FontCache.isFontLoaded(fontPath)) {
        return FontCache.getFontFamily(fontPath);
      }

      final File file = File(fontPath);
      if (!await file.exists()) {
        debugPrint('字体文件不存在: $fontPath');
        return null;
      }

      final fontFileName = path.basenameWithoutExtension(fontPath);
      // 生成唯一的fontFamily名称，避免冲突
      final String fontFamily =
          'custom_font_${DateTime.now().millisecondsSinceEpoch}_$fontFileName';

      final Uint8List bytes = await file.readAsBytes();
      final FontLoader loader = FontLoader(fontFamily);
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();

      // 缓存已加载的字体
      FontCache.addFont(fontPath, fontFamily);
      debugPrint('成功加载字体: $fontFamily (路径: $fontPath)');
      return fontFamily;
    } catch (e) {
      debugPrint('加载字体出错: $e (路径: $fontPath)');
      return null;
    }
  }

  // 获取显示的字体名称
  String getDisplayFontName(String fontPath) {
    if (fontPath.isEmpty) return '系统默认';
    // 尝试从缓存获取字体名称，否则使用文件名
    final cachedFamily = FontCache.getFontFamily(fontPath);
    if (cachedFamily != null) return cachedFamily;
    return path.basenameWithoutExtension(fontPath);
  }

// 获取字体目录
  Future<Directory> get _fontsDir async {
    final Directory appDocDir = await getApplicationDocumentsDirectory();
    final Directory fontsDir = Directory('${appDocDir.path}/fonts');
    if (!await fontsDir.exists()) {
      await fontsDir.create(recursive: true);
    }
    return fontsDir;
  }

// 列出所有自定义字体
  Future<List<String>> _getCustomFonts() async {
    try {
      final dir = await _fontsDir;
      final List<FileSystemEntity> entities = await dir.list().toList();
      return entities
          .whereType<File>()
          .where((file) => ['.ttf', '.otf']
              .contains(path.extension(file.path).toLowerCase()))
          .map((file) => file.path)
          .toList();
    } catch (e) {
      debugPrint('获取字体列表出错: $e');
      return [];
    }
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

  // 辅助方法: 构建单个选项行
  Widget _buildOptionTile(BuildContext context, int value, String label,
      dynamic icon, int groupValue, Function(int?) onChanged) {
    final isSelected = value == groupValue;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onChanged(value),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary.withOpacity(0.5)
                : Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            icon is String
                ? buildIcon(icon)
                : Icon(
                    icon,
                    size: 22,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).iconTheme.color,
                  ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                  color:
                      isSelected ? Theme.of(context).colorScheme.primary : null,
                ),
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }

// 应用启动时加载所有字体
  Future<void> loadAllFonts() async {
    final fontPaths = await _getCustomFonts();
    for (final fontPath in fontPaths) {
      await loadFontFromFile(fontPath);
    }
    print('已加载${fontPaths.length}个自定义字体');
  }

// 获取显示的字体名称
  String getDisplayFontName(String fontPath) {
    if (fontPath.isEmpty) return '系统默认';
    // 尝试从缓存获取字体名称，否则使用文件名
    final cachedFamily = FontCache.getFontFamily(fontPath);
    if (cachedFamily != null) return cachedFamily;
    return path.basenameWithoutExtension(fontPath);
  }

// 获取字体目录
  Future<Directory> get _fontsDir async {
    final Directory appDocDir = await getApplicationDocumentsDirectory();
    final Directory fontsDir = Directory('${appDocDir.path}/fonts');
    if (!await fontsDir.exists()) {
      await fontsDir.create(recursive: true);
    }
    return fontsDir;
  }

// 列出所有自定义字体
  Future<List<String>> _getCustomFonts() async {
    try {
      final dir = await _fontsDir;
      final List<FileSystemEntity> entities = await dir.list().toList();
      return entities
          .whereType<File>()
          .where((file) => ['.ttf', '.otf']
              .contains(path.extension(file.path).toLowerCase()))
          .map((file) => file.path)
          .toList();
    } catch (e) {
      debugPrint('获取字体列表出错: $e');
      return [];
    }
  }

// 从文件加载字体
  Future<String?> loadFontFromFile(String fontPath) async {
    try {
      if (fontPath.isEmpty) return null;

      // 检查字体是否已加载
      if (FontCache.isFontLoaded(fontPath)) {
        return FontCache.getFontFamily(fontPath);
      }

      final File file = File(fontPath);
      if (!await file.exists()) {
        debugPrint('字体文件不存在: $fontPath');
        return null;
      }

      final fontFileName = path.basenameWithoutExtension(fontPath);
      // 生成唯一的fontFamily名称，避免冲突
      final String fontFamily =
          'custom_font_${DateTime.now().millisecondsSinceEpoch}_$fontFileName';

      final Uint8List bytes = await file.readAsBytes();
      final FontLoader loader = FontLoader(fontFamily);
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();

      // 缓存已加载的字体
      FontCache.addFont(fontPath, fontFamily);
      debugPrint('成功加载字体: $fontFamily (路径: $fontPath)');
      return fontFamily;
    } catch (e) {
      debugPrint('加载字体出错: $e (路径: $fontPath)');
      return null;
    }
  }

// 导入字体文件
  Future<String?> _importFont() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ttf', 'otf'],
      );

      if (result != null) {
        File sourceFile = File(result.files.single.path!);
        final fontFileName = path.basename(sourceFile.path);
        final dir = await _fontsDir;
        final targetPath = path.join(dir.path, fontFileName);

        // 检查文件是否已存在
        if (await File(targetPath).exists()) {
          // 可以添加提示用户文件已存在的逻辑
          debugPrint('字体文件已存在: $targetPath');
          // 仍然加载字体
          await loadFontFromFile(targetPath);
          return targetPath;
        }

        // 复制字体文件到应用的字体目录
        await sourceFile.copy(targetPath);

        // 立即加载新导入的字体
        await loadFontFromFile(targetPath);

        return targetPath;
      }
    } catch (e) {
      debugPrint('导入字体出错: $e');
    }
    return null;
  }

// 删除字体
  Future<bool> _deleteFont(String fontPath) async {
    try {
      final file = File(fontPath);
      if (await file.exists()) {
        await file.delete();
        // 从缓存中移除字体
        FontCache.removeFont(fontPath);
        return true;
      }
    } catch (e) {
      debugPrint('删除字体出错: $e');
    }
    return false;
  }

// 优雅的字体选择对话框
  void _showFontSelectionDialog(BuildContext context) async {
    final currentFont = await _settingsService.getSubtitleFont();
    final customFonts = await _getCustomFonts();
    // 添加系统默认选项
    final allFonts = [''].followedBy(customFonts).toList();
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent, // 使对话框背景透明
        elevation: 0, // 移除阴影
        insetPadding: EdgeInsets.zero, // 移除内边距
        child: FractionallySizedBox(
          widthFactor: 0.95,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.black.withOpacity(0.5)
                      : Colors.white.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '字幕字体管理',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.add_circle_outline),
                          color: Colors.lightBlue,
                          tooltip: '导入字体',
                          onPressed: () async {
                            final newFont = await _importFont();
                            if (newFont != null) {
                              Navigator.of(context).pop();
                              _showFontSelectionDialog(context); // 刷新对话框
                            }
                          },
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    Divider(),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.5,
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: allFonts.length,
                        itemBuilder: (context, index) {
                          final String fontPath = allFonts[index];
                          final bool isSelected = fontPath == currentFont;
                          final bool isDefault = fontPath.isEmpty;
                          return FutureBuilder<String?>(
                            // 对于非默认字体，确保字体已加载
                            future: isDefault
                                ? Future.value(null)
                                : loadFontFromFile(fontPath),
                            builder: (context, snapshot) {
                              final String? fontFamily = snapshot.data;
                              final bool fontLoaded =
                                  fontFamily != null || isDefault;
                              return ListTile(
                                title: Text(
                                  isDefault
                                      ? '系统默认'
                                      : getDisplayFontName(fontPath),
                                  style: TextStyle(
                                    fontFamily: isDefault ? null : fontFamily,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  isDefault ? '使用系统默认字体' : '示例文字：中文English123',
                                  style: TextStyle(
                                    fontFamily: isDefault ? null : fontFamily,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (!fontLoaded)
                                      SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                    else if (isSelected)
                                      Icon(Icons.check_circle,
                                          color: Colors.lightBlue),
                                    if (!isDefault)
                                      IconButton(
                                        icon: Icon(Icons.delete_outline,
                                            color: Colors.redAccent),
                                        onPressed: () async {
                                          bool deleted =
                                              await _deleteFont(fontPath);
                                          if (deleted) {
                                            if (fontPath == currentFont) {
                                              await _settingsService
                                                  .saveSubtitleFont('');
                                            }
                                            Navigator.of(context).pop();
                                            _showFontSelectionDialog(
                                                context); // 刷新对话框
                                          }
                                        },
                                      ),
                                  ],
                                ),
                                onTap: () async {
                                  if (fontLoaded) {
                                    await _settingsService
                                        .saveSubtitleFont(fontPath);
                                    setState(() {});
                                    Navigator.of(context).pop();
                                  }
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                    Divider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        '提示: 点击字体选择，点击加号导入新字体',
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                    Center(
                      child: TextButton(
                        child: Text('关闭'),
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildIcon(dynamic icon) {
    try {
      if (icon is String) {
        print('加载PNG图片: ${icon}');
        // PNG图片处理
        return Image.asset(
          icon,
          width: 24, // 设置合适的宽度
          height: 24, // 设置合适的高度
        );
      } else {
        return Icon(icon as IconData, color: Colors.lightBlue);
      }
    } catch (e) {
      print('加载图标出错: $e');
      return SizedBox(); // 默认返回空Widget
    }
  }

// 字体选择Tile
  ListTile buildFontSelectionTile() {
    return ListTile(
      leading: Icon(Icons.font_download_outlined, color: Colors.lightBlue),
      title: Text('字幕字体'),
      subtitle: FutureBuilder<String>(
        future: _settingsService.getSubtitleFont(),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return Text(snapshot.data!.isEmpty
                ? '系统默认'
                : getDisplayFontName(snapshot.data!));
          } else {
            return const Text('加载中...');
          }
        },
      ),
      onTap: () {
        _showFontSelectionDialog(context);
      },
    );
  }

// 获取字幕文本样式的辅助方法
  Future<TextStyle> getSubtitleTextStyle([TextStyle? baseStyle]) async {
    final fontPath = await _settingsService.getSubtitleFont();
    if (fontPath.isEmpty) {
      // 使用默认样式
      return baseStyle ?? TextStyle();
    }

    // 确保字体已加载
    final fontFamily = await loadFontFromFile(fontPath);
    if (fontFamily == null) {
      return baseStyle ?? TextStyle();
    }

    // 返回带有自定义字体的样式
    return (baseStyle ?? TextStyle()).copyWith(fontFamily: fontFamily);
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
                    subtitle: Text('打开视频闪退可尝试关闭此项'),
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
                  FutureBuilder<bool>(
                    future: _settingsService.getAutoLoadSubtitle(),
                    builder: (context, snapshot) {
                      if (snapshot.hasData && snapshot.data!) {
                        return ListTile(
                          leading: Icon(Icons.subtitles_outlined,
                              color: Colors.lightBlue),
                          title: Text('自动提取字幕副轨道数量'),
                          subtitle: Text('提取副轨道可能导致闪退和卡顿'),
                          trailing: FutureBuilder<int>(
                            future: _settingsService.getSubtitleMany(),
                            builder: (context, subtitleManySnapshot) {
                              if (subtitleManySnapshot.hasData) {
                                final value = subtitleManySnapshot.data!;
                                return DropdownButton<int>(
                                  value: value,
                                  onChanged: (newValue) {
                                    if (newValue != null) {
                                      _settingsService
                                          .saveSubtitleMany(newValue);
                                      setState(() {});
                                    }
                                  },
                                  items: [
                                    DropdownMenuItem<int>(
                                      value: 0,
                                      child: Text('不提取'),
                                    ),
                                    DropdownMenuItem<int>(
                                      value: 1,
                                      child: Text('1个'),
                                    ),
                                    DropdownMenuItem<int>(
                                      value: 2,
                                      child: Text('2个'),
                                    ),
                                    DropdownMenuItem<int>(
                                      value: 3,
                                      child: Text('3个'),
                                    ),
                                    DropdownMenuItem<int>(
                                      value: -1,
                                      child: Text('不限制'),
                                    ),
                                  ],
                                );
                              } else {
                                return const CircularProgressIndicator();
                              }
                            },
                          ),
                        );
                      } else {
                        return Container(); // Return empty container when auto load subtitle is false
                      }
                    },
                  ),
                  ListTile(
                    leading:
                        Icon(Icons.subtitles_outlined, color: Colors.lightBlue),
                    title: Text('库内抽取ASS字幕'),
                    subtitle: Text('不选中则抽取SRT文本字幕'),
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
                  ListTile(
                    leading: Icon(Icons.font_download_outlined,
                        color: Colors.lightBlue),
                    title: Text('字幕字体'),
                    subtitle: FutureBuilder<String>(
                      future: _settingsService.getSubtitleFont(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          return Text(snapshot.data!.isEmpty
                              ? '系统默认'
                              : getDisplayFontName(snapshot.data!));
                        } else {
                          return const Text('加载中...');
                        }
                      },
                    ),
                    onTap: () {
                      _showFontSelectionDialog(context);
                    },
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
                  Card(
                    margin:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: Theme.of(context).dividerColor.withOpacity(0.5),
                        width: 1,
                      ),
                    ),
                    child: Theme(
                      data: Theme.of(context)
                          .copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        collapsedShape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        leading: Icon(
                          Icons.play_circle_filled,
                          color: Colors.lightBlue,
                          size: 26,
                        ),
                        title: Text(
                          '播放器选择',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Text(
                          '选择视频播放引擎',
                          style: TextStyle(
                            fontSize: 14,
                          ),
                        ),
                        children: [
                          FutureBuilder<int>(
                            future: _settingsService.getUseFfmpegForPlay(),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) {
                                return const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }

                              final currentValue = snapshot.data!;
                              final options = [
                                {
                                  'value': 0,
                                  'label': '系统播放能力(推荐)',
                                  'icon': Icons.phone_android
                                },
                                {
                                  'value': 1,
                                  'label': 'FFmpeg软解',
                                  'icon': Icons.settings_applications
                                },
                                {
                                  'value': 2,
                                  'label': '系统播放(PlatformView)',
                                  'icon': Icons.view_module
                                },
                                {
                                  'value': 3,
                                  'label': '系统播放(仅音频软解)',
                                  'icon': Icons.mic_external_on_sharp
                                },
                                {
                                  'value': 4,
                                  'label': '流心视频(HDR)',
                                  'icon': 'Assets/sweet_video.png'
                                }
                              ];

                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).cardColor,
                                  borderRadius: BorderRadius.only(
                                    bottomLeft: Radius.circular(12),
                                    bottomRight: Radius.circular(12),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 0, 16, 16),
                                      child: Row(
                                        children: [
                                          currentValue == 4
                                              ? buildIcon(options.firstWhere(
                                                      (opt) =>
                                                          opt['value'] ==
                                                          currentValue)['icon']
                                                  as String)
                                              : Icon(
                                                  options.firstWhere((opt) =>
                                                          opt['value'] ==
                                                          currentValue)['icon']
                                                      as IconData,
                                                  color: Colors.lightBlue),
                                          const SizedBox(width: 8),
                                          Text(
                                            '当前选择: ${options.firstWhere((opt) => opt['value'] == currentValue)['label']}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    ...options
                                        .map((option) => _buildOptionTile(
                                              context,
                                              option['value'] as int,
                                              option['label'] as String,
                                              option['icon'] as dynamic,
                                              currentValue,
                                              (value) {
                                                if (value != null) {
                                                  _settingsService
                                                      .saveUseFfmpegForPlay(
                                                          value);
                                                  setState(() {});
                                                }
                                              },
                                            ))
                                        .toList(),
                                    SizedBox(height: 4),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  ListTile(
                    leading: Icon(Icons.hdr_auto_select_outlined, color: Colors.lightBlue),
                    title: Text('使用HDR播放器打开HDR视频'),
                    subtitle: Text('仅限从视频库中点击时'),
                    trailing: FutureBuilder<bool>(
                      future: _settingsService.getHdrForHdr(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          return Switch(
                            value: snapshot.data!,
                            onChanged: (value) {
                              _settingsService.saveHdrForHdr(value);
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
                      leading: Icon(Icons.display_settings_rounded,
                          color: Colors.lightBlue),
                      title: Text('禁用视频库缩略图和时长获取'),
                      subtitle: Text('HDR获取也会禁用以临时缓解闪退'),
                      trailing: FutureBuilder<bool>(
                          future: _settingsService.getDisableThumbnail(),
                          builder: (context, snapshot) {
                            if (snapshot.hasData) {
                              return Switch(
                                value: snapshot.data!,
                                onChanged: (value) {
                                  _settingsService.saveDisableThumbnail(value);
                                  setState(() {});
                                },
                                activeColor: Colors.lightBlue,
                              );
                            } else {
                              return const CircularProgressIndicator();
                            }
                          })),
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
          SizedBox(height: 4),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: Colors.orange.withOpacity(0.3), width: 1),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Colors.orange[800],
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '请不要从“最近”选项卡导入文件; AloePlayer的视频库除了链接文件外均为实际媒体文件，请慎重删改并做好备份。',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.orange[800],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: 16),

          // 关于此应用程序部分（简化版）
          Card(
            elevation: 2,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('关于此应用程序',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: Icon(Icons.info_outline, color: Colors.lightBlue),
                        onPressed: () => _showAboutDialog(context),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text('AloePlayer', style: TextStyle(fontSize: 16)),
                  SizedBox(height: 4),
                  Text('版本号: ${SettingsService._versionName}',
                      style: TextStyle(fontSize: 14, color: Colors.grey)),
                  SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    children: [
                      _buildLinkButton(
                          context, '官网', 'https://ohos.aloereed.com'),
                      _buildLinkButton(context, '更新日志',
                          'https://ohos.aloereed.com/index.php/2025/01/08/aloeplayer/'),
                      _buildLinkButton(context, '隐私政策',
                          'https://aloereed.com/aloeplayer/privacy-statement.html'),
                      _buildLinkButton(context, '沪ICP备2025110508号-2A',
                          'https://beian.miit.gov.cn'),
                      _buildLinkButton(
                        context,
                        '支持作者',
                        'https://afdian.com/a/aloereed', // 替换为您的爱发电链接
                        icon: Icons.favorite,
                        color: Colors.redAccent,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 构建链接按钮
Widget _buildLinkButton(BuildContext context, String label, String url,
    {IconData icon = Icons.link, Color? color}) {
  return InkWell(
    onTap: () async {
      await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    },
    borderRadius: BorderRadius.circular(20),
    child: Padding(
      padding: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color ?? Colors.lightBlue),
          SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color ?? Colors.lightBlue,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}

// 显示详细信息的高斯模糊对话框
void _showAboutDialog(BuildContext context) {
  final isDarkMode = Theme.of(context).brightness == Brightness.dark;

  showDialog(
    context: context,
    builder: (context) {
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Dialog(
          backgroundColor: isDarkMode
              ? Colors.black.withOpacity(0.7)
              : Colors.white.withOpacity(0.8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 0,
          child: SingleChildScrollView(
            physics: BouncingScrollPhysics(),
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      height: 80,
                      width: 80,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      // 使用应用Logo
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.asset(
                          'Assets/icon.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 16),
                  Center(
                    child: Text(
                      'AloePlayer',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  Center(
                    child: Text(
                      '尽享视听盛宴',
                      style: TextStyle(
                        fontSize: 16,
                        color: isDarkMode ? Colors.white70 : Colors.black54,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                  SizedBox(height: 24),
                  _buildSectionTitle(context, '手势说明和提示', isDarkMode),
                  SizedBox(height: 12),
                  _buildTipItem(context, '1. 长按: 三倍速播放', isDarkMode),
                  _buildTipItem(context, '2. 双击播放界面左侧、右侧、中间: 快退、快进10秒、切换播放暂停',
                      isDarkMode),
                  _buildTipItem(
                      context, '3. 上下滑动: 靠左侧增减亮度，靠右侧增减音量', isDarkMode),
                  _buildTipItem(context, '4. 添加媒体进入音频库或视频库需要时间', isDarkMode),
                  _buildTipItem(context, '5. 点击媒体控制的音量按钮可以切换静音', isDarkMode),
                  _buildTipItem(context, '6. 添加字幕文件后，请在右上角打开"CC"', isDarkMode),
                  _buildTipItem(context, '7. 新版本库文件默认位于"下载"文件夹下', isDarkMode),
                  _buildTipItem(context, '8. 播放列表：播放器最右侧往左滑动唤出', isDarkMode),
                  SizedBox(height: 24),
                  _buildSectionTitle(context, '备案和许可', isDarkMode),
                  SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      await launchUrl(
                        Uri.parse('https://beian.miit.gov.cn'),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        '沪ICP备2025110508号-2A',
                        style: TextStyle(
                          color: Colors.lightBlue,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 8),
                  InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      showLicensePage(
                        context: context,
                        applicationName: 'AloePlayer',
                        applicationVersion: SettingsService._versionName,
                        applicationLegalese: '© 2025 Aloereed',
                      );
                    },
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        '开源项目和许可',
                        style: TextStyle(
                          color: Colors.lightBlue,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 24),
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('关闭'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.lightBlue,
                        padding:
                            EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(color: Colors.lightBlue),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

// 构建小节标题
Widget _buildSectionTitle(BuildContext context, String title, bool isDarkMode) {
  return Text(
    title,
    style: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.bold,
      color: isDarkMode ? Colors.white : Colors.black87,
    ),
  );
}

// 构建提示项
Widget _buildTipItem(BuildContext context, String text, bool isDarkMode) {
  return Padding(
    padding: EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.arrow_right,
          size: 20,
          color: isDarkMode ? Colors.white70 : Colors.black54,
        ),
        SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: isDarkMode ? Colors.white70 : Colors.black54,
            ),
          ),
        ),
      ],
    ),
  );
}
