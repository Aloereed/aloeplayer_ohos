/*
 * @Author: 
 * @Date: 2025-01-07 22:27:23
 * @LastEditors: Please set LastEditors
 * @LastEditTime: 2025-03-22 17:15:01
 * @Description: file content
 */
/*
 * @Author: 
 * @Date: 2025-01-07 17:00:15
 * @LastEditors: Please set LastEditors
 * @LastEditTime: 2025-01-07 22:37:09
 * @Description: file content
 * 
 */
import 'dart:convert';
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:aloeplayer/privacy_policy.dart';
import 'package:xml/xml.dart' as xml;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock/wakelock.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:just_audio_ohos/just_audio_ohos.dart';
import 'package:aloeplayer/chewie-1.8.5/lib/chewie.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:share_plus/share_plus.dart';
import 'package:simple_gesture_detector/simple_gesture_detector.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_subtitle/flutter_subtitle.dart' hide Subtitle;
import 'package:path/path.dart' as path;
import 'videolibrary.dart';
import 'audiolibrary.dart';
import 'smblibrary.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:audio_session/audio_session.dart';
import 'package:vivysub_utils/vivysub_utils.dart';
import 'package:audio_service/audio_service.dart';
import 'package:file_picker_ohos/file_picker_ohos.dart';
import 'settings.dart';
import 'theme_provider.dart';
import 'dart:typed_data';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'volumeview.dart';
import 'package:aloeplayer/chewie-1.8.5/lib/src/ffmpegview.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:dart_libass/dart_libass.dart';
import 'package:aloeplayer/player.dart';
import 'package:just_audio_background/just_audio_background.dart';

// late MyAudioHandler audioHandler;
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // audioHandler = await AudioService.init(
  //   builder: () => MyAudioHandler(),
  //   config: const AudioServiceConfig(
  //     androidNotificationChannelId: 'com.aloereed.aloeplayer',
  //     androidNotificationChannelName: '后台音频播放',
  //   ),
  // );
  // 初始化音频会话
  // final session = await AudioSession.instance;
  // await session.configure(AudioSessionConfiguration.music());
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.aloereed.aloeplayer.channel.audio',
    androidNotificationChannelName: 'Audio playback',
    androidNotificationOngoing: true,
  );

  runApp(
    ChangeNotifierProvider(
      create: (context) => ThemeProvider(),
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    Wakelock.enable();

    // 自定义浅蓝色主题
    // final lightTheme = ThemeData(
    //   primarySwatch: Colors.blue, // 主色调为蓝色
    //   primaryColor: Colors.lightBlue[200], // 浅蓝色
    //   colorScheme: ColorScheme.light(
    //     primary: Colors.lightBlue[200]!, // 主色调
    //     secondary: Colors.blueAccent[100]!, // 次要色调
    //     surface: Colors.white, // 背景色
    //     background: Colors.lightBlue[50]!, // 背景色
    //   ),
    //   scaffoldBackgroundColor: Colors.lightBlue[50], // 页面背景色
    //   appBarTheme: AppBarTheme(
    //     color: Colors.lightBlue[200], // AppBar 背景色
    //     elevation: 0, // 去掉阴影
    //     iconTheme: IconThemeData(color: Colors.white), // AppBar 图标颜色
    //     titleTextStyle: TextStyle(
    //       color: Colors.white,
    //       fontSize: 20,
    //       fontWeight: FontWeight.bold,
    //     ), // AppBar 文字样式
    //   ),
    //   textTheme: TextTheme(
    //     bodyLarge: TextStyle(color: Colors.black87), // 正文文字颜色
    //     bodyMedium: TextStyle(color: Colors.black87),
    //     titleLarge:
    //         TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
    //   ),
    //   buttonTheme: ButtonThemeData(
    //     buttonColor: Colors.lightBlue[200], // 按钮背景色
    //     textTheme: ButtonTextTheme.primary, // 按钮文字颜色
    //   ),
    //   floatingActionButtonTheme: FloatingActionButtonThemeData(
    //     backgroundColor: Colors.lightBlue[200], // FloatingActionButton 背景色
    //   ),
    // );
    // 定义主色调和辅助色调
    final primaryColor = Colors.lightBlue;
    final Color primaryLightColor = Colors.lightBlue.shade300;
    final Color primaryDarkColor = Colors.lightBlue.shade800;
    final Color accentColor = Colors.lightBlue.shade200;

// 亮色主题
    final lightTheme = ThemeData(
      useMaterial3: true, // 使用 Material 3 设计
      colorScheme: ColorScheme.light(
        primary: primaryColor,
        onPrimary: Colors.white,
        primaryContainer: primaryLightColor.withOpacity(0.15),
        onPrimaryContainer: primaryDarkColor,
        secondary: primaryColor.withOpacity(0.8),
        onSecondary: Colors.white,
        secondaryContainer: primaryLightColor.withOpacity(0.1),
        onSecondaryContainer: primaryDarkColor,
        tertiary: Colors.lightBlue.shade100,
        onTertiary: Colors.blueGrey.shade800,
        background: const Color(0xFFF8F9FA),
        onBackground: const Color(0xFF1D1D1D),
        surface: Colors.white,
        onSurface: const Color(0xFF1D1D1D),
        surfaceVariant: Colors.grey.shade100,
        onSurfaceVariant: Colors.blueGrey.shade700,
        outline: Colors.blueGrey.shade200,
        shadow: Colors.black.withOpacity(0.05),
        inverseSurface: Colors.blueGrey.shade900,
        onInverseSurface: Colors.white,
        inversePrimary: accentColor,
        error: Colors.redAccent.shade200,
        onError: Colors.white,
      ),

      // 圆角设置
      cardTheme: CardTheme(
        elevation: 2,
        shadowColor: Colors.black.withOpacity(0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
      ),

      // 应用栏主题
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1.0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: Colors.blueGrey.shade800,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        iconTheme: IconThemeData(color: primaryColor),
        actionsIconTheme: IconThemeData(color: primaryColor),
        toolbarHeight: 60,
      ),

      // 底部导航栏主题
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        elevation: 8,
        selectedItemColor: primaryColor,
        unselectedItemColor: Colors.blueGrey.shade300,
        selectedLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.normal,
        ),
        type: BottomNavigationBarType.fixed,
        selectedIconTheme: IconThemeData(size: 26, color: primaryColor),
        unselectedIconTheme:
            IconThemeData(size: 24, color: Colors.blueGrey.shade300),
      ),

      // 文本主题
      textTheme: TextTheme(
        displayLarge: TextStyle(
          color: Colors.blueGrey.shade900,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        displayMedium: TextStyle(
          color: Colors.blueGrey.shade900,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
        displaySmall: TextStyle(
          color: Colors.blueGrey.shade900,
          fontWeight: FontWeight.w600,
        ),
        headlineMedium: TextStyle(
          color: Colors.blueGrey.shade900,
          fontWeight: FontWeight.w600,
        ),
        titleLarge: TextStyle(
          color: Colors.blueGrey.shade800,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        titleMedium: TextStyle(
          color: Colors.blueGrey.shade800,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
        ),
        titleSmall: TextStyle(
          color: Colors.blueGrey.shade700,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: TextStyle(
          color: Colors.blueGrey.shade800,
          fontWeight: FontWeight.normal,
        ),
        bodyMedium: TextStyle(
          color: Colors.blueGrey.shade700,
          fontWeight: FontWeight.normal,
        ),
        bodySmall: TextStyle(
          color: Colors.blueGrey.shade600,
          fontWeight: FontWeight.normal,
        ),
        labelLarge: TextStyle(
          color: primaryColor,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
        ),
        labelSmall: TextStyle(
          color: Colors.blueGrey.shade600,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
        ),
      ),

      // 悬浮按钮主题
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        largeSizeConstraints:
            const BoxConstraints.tightFor(width: 64, height: 64),
        extendedSizeConstraints: const BoxConstraints.tightFor(height: 56),
        extendedPadding: const EdgeInsets.symmetric(horizontal: 20),
        extendedTextStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
        ),
      ),

      // 图标按钮主题
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          backgroundColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.pressed)) {
              return primaryColor.withOpacity(0.1);
            }
            return Colors.transparent;
          }),
          foregroundColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.pressed)) {
              return primaryColor;
            }
            return Colors.blueGrey.shade700;
          }),
          overlayColor:
              MaterialStateProperty.all(primaryColor.withOpacity(0.05)),
          shape: MaterialStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          iconSize: MaterialStateProperty.all(24),
        ),
      ),

      // 其他按钮主题
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: BorderSide(color: primaryColor, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
          ),
        ),
      ),

      // 列表瓦片主题
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minLeadingWidth: 24,
        minVerticalPadding: 12,
        iconColor: primaryColor,
        textColor: Colors.blueGrey.shade800,
        titleTextStyle: TextStyle(
          color: Colors.blueGrey.shade800,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        subtitleTextStyle: TextStyle(
          color: Colors.blueGrey.shade600,
          fontSize: 14,
          fontWeight: FontWeight.normal,
        ),
      ),

      // 滑块主题
      sliderTheme: SliderThemeData(
        activeTrackColor: primaryColor,
        inactiveTrackColor: primaryLightColor.withOpacity(0.2),
        thumbColor: primaryColor,
        overlayColor: primaryColor.withOpacity(0.2),
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
      ),

      // 开关主题
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return primaryColor;
          }
          return Colors.grey.shade400;
        }),
        trackColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return primaryColor.withOpacity(0.3);
          }
          return Colors.grey.shade300;
        }),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),

      // 复选框主题
      checkboxTheme: CheckboxThemeData(
        fillColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return primaryColor;
          }
          return Colors.transparent;
        }),
        checkColor: MaterialStateProperty.all(Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        side: BorderSide(color: Colors.grey.shade400, width: 1.5),
      ),

      // 单选按钮主题
      radioTheme: RadioThemeData(
        fillColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return primaryColor;
          }
          return Colors.grey.shade400;
        }),
      ),

      // 对话框主题
      dialogTheme: DialogTheme(
        backgroundColor: Colors.white,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: TextStyle(
          color: Colors.blueGrey.shade800,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: TextStyle(
          color: Colors.blueGrey.shade700,
          fontSize: 16,
        ),
      ),

      // 输入装饰主题
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryColor, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.redAccent.shade200, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.redAccent.shade200, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        hintStyle: TextStyle(color: Colors.grey.shade400),
        labelStyle: TextStyle(color: Colors.blueGrey.shade600),
        errorStyle: const TextStyle(
          color: Colors.redAccent,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),

      // 分割线主题
      dividerTheme: DividerThemeData(
        color: Colors.grey.shade200,
        thickness: 1,
        space: 1,
      ),

      // 其他设置
      scaffoldBackgroundColor: const Color(0xFFF8F9FA),
      visualDensity: VisualDensity.adaptivePlatformDensity,
      iconTheme: IconThemeData(color: Colors.blueGrey.shade700, size: 24),
      primaryIconTheme: IconThemeData(color: primaryColor, size: 24),
    );

// 暗色主题
    final darkTheme = ThemeData.dark().copyWith(
      useMaterial3: true,
      colorScheme: ColorScheme.dark(
        primary: primaryColor.shade300,
        onPrimary: Colors.black,
        primaryContainer: primaryColor.shade800.withOpacity(0.3),
        onPrimaryContainer: primaryColor.shade200,
        secondary: primaryColor.shade300.withOpacity(0.8),
        onSecondary: Colors.black,
        secondaryContainer: primaryColor.shade800.withOpacity(0.2),
        onSecondaryContainer: primaryColor.shade200,
        tertiary: primaryColor.shade800,
        onTertiary: primaryColor.shade200,
        background: const Color(0xFF121212),
        onBackground: Colors.grey.shade300,
        surface: const Color(0xFF1D1D1D),
        onSurface: Colors.grey.shade300,
        surfaceVariant: const Color(0xFF2C2C2C),
        onSurfaceVariant: Colors.grey.shade400,
        outline: Colors.grey.shade700,
        shadow: Colors.black,
        inverseSurface: Colors.grey.shade300,
        onInverseSurface: const Color(0xFF1D1D1D),
        inversePrimary: primaryColor.shade800,
        error: Colors.redAccent.shade200,
        onError: Colors.black,
      ),

      // 卡片主题
      cardTheme: CardTheme(
        color: const Color(0xFF1D1D1D),
        elevation: 4,
        shadowColor: Colors.black.withOpacity(0.4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      // 应用栏主题
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFF1D1D1D),
        elevation: 0,
        scrolledUnderElevation: 2.0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: Colors.grey.shade300,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        iconTheme: IconThemeData(color: primaryColor.shade300),
        actionsIconTheme: IconThemeData(color: primaryColor.shade300),
        toolbarHeight: 60,
      ),

      // 底部导航栏主题
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: const Color(0xFF1D1D1D),
        elevation: 8,
        selectedItemColor: primaryColor.shade300,
        unselectedItemColor: Colors.grey.shade600,
        selectedLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.normal,
        ),
        type: BottomNavigationBarType.fixed,
        selectedIconTheme:
            IconThemeData(size: 26, color: primaryColor.shade300),
        unselectedIconTheme:
            IconThemeData(size: 24, color: Colors.grey.shade600),
      ),

      // 文本主题
      textTheme: TextTheme(
        displayLarge: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        displayMedium: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
        displaySmall: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        headlineMedium: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        titleLarge: TextStyle(
          color: Colors.grey.shade300,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        titleMedium: TextStyle(
          color: Colors.grey.shade300,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
        ),
        titleSmall: TextStyle(
          color: Colors.grey.shade400,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: TextStyle(
          color: Colors.grey.shade300,
          fontWeight: FontWeight.normal,
        ),
        bodyMedium: TextStyle(
          color: Colors.grey.shade400,
          fontWeight: FontWeight.normal,
        ),
        bodySmall: TextStyle(
          color: Colors.grey.shade500,
          fontWeight: FontWeight.normal,
        ),
        labelLarge: TextStyle(
          color: primaryColor.shade300,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
        ),
        labelSmall: TextStyle(
          color: Colors.grey.shade500,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
        ),
      ),

      // 悬浮按钮主题
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryColor.shade300,
        foregroundColor: Colors.black,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        largeSizeConstraints:
            const BoxConstraints.tightFor(width: 64, height: 64),
        extendedSizeConstraints: const BoxConstraints.tightFor(height: 56),
        extendedPadding: const EdgeInsets.symmetric(horizontal: 20),
        extendedTextStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
        ),
      ),

      // 图标按钮主题
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          backgroundColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.pressed)) {
              return primaryColor.shade700.withOpacity(0.2);
            }
            return const Color(0xFF2C2C2C);
          }),
          foregroundColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.pressed)) {
              return primaryColor.shade300;
            }
            return Colors.grey.shade400;
          }),
          overlayColor:
              MaterialStateProperty.all(primaryColor.shade800.withOpacity(0.1)),
          shape: MaterialStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          iconSize: MaterialStateProperty.all(24),
        ),
      ),

      // 其他按钮主题
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor.shade300,
          foregroundColor: Colors.black,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryColor.shade300,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor.shade300,
          side: BorderSide(color: primaryColor.shade300, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
          ),
        ),
      ),

      // 列表瓦片主题
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minLeadingWidth: 24,
        minVerticalPadding: 12,
        iconColor: primaryColor.shade300,
        textColor: Colors.grey.shade300,
        titleTextStyle: TextStyle(
          color: Colors.grey.shade300,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        subtitleTextStyle: TextStyle(
          color: Colors.grey.shade500,
          fontSize: 14,
          fontWeight: FontWeight.normal,
        ),
      ),

      // 滑块主题
      sliderTheme: SliderThemeData(
        activeTrackColor: primaryColor.shade300,
        inactiveTrackColor: primaryColor.shade700,
        thumbColor: primaryColor.shade300,
        overlayColor: primaryColor.shade300.withOpacity(0.2),
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
      ),

      // 开关主题
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return primaryColor.shade300;
          }
          return Colors.grey.shade600;
        }),
        trackColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return primaryColor.shade700;
          }
          return Colors.grey.shade800;
        }),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),

      // 复选框主题
      checkboxTheme: CheckboxThemeData(
        fillColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return primaryColor.shade300;
          }
          return Colors.transparent;
        }),
        checkColor: MaterialStateProperty.all(Colors.black),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        side: BorderSide(color: Colors.grey.shade600, width: 1.5),
      ),

      // 单选按钮主题
      radioTheme: RadioThemeData(
        fillColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return primaryColor.shade300;
          }
          return Colors.grey.shade600;
        }),
      ),

      // 对话框主题
      dialogTheme: DialogTheme(
        backgroundColor: const Color(0xFF1D1D1D),
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: TextStyle(
          color: Colors.grey.shade300,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: TextStyle(
          color: Colors.grey.shade400,
          fontSize: 16,
        ),
      ),

      // 输入装饰主题
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF2C2C2C),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade700, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade700, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryColor.shade300, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.redAccent.shade200, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.redAccent.shade200, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        hintStyle: TextStyle(color: Colors.grey.shade600),
        labelStyle: TextStyle(color: Colors.grey.shade500),
        errorStyle: const TextStyle(
          color: Colors.redAccent,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),

      // 分割线主题
      dividerTheme: DividerThemeData(
        color: Colors.grey.shade800,
        thickness: 1,
        space: 1,
      ),

      // 其他设置
      scaffoldBackgroundColor: const Color(0xFF121212),
      visualDensity: VisualDensity.adaptivePlatformDensity,
      iconTheme: IconThemeData(color: Colors.grey.shade400, size: 24),
      primaryIconTheme: IconThemeData(color: primaryColor.shade300, size: 24),
    );

    return MaterialApp(
      theme: lightTheme, // 使用自定义的浅蓝色主题
      darkTheme: darkTheme,
      themeMode: themeProvider.themeMode,
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  final PageController _pageController = PageController();
  int videoHeight = 0;
  int videoWidth = 0;
  bool _isFullScreen = false;
  String _openfile = '';
  bool _isPolicyAccepted = false;
  final _settingsService = SettingsService();
  final EventChannel _eventChannel2 = EventChannel('com.example.app/events');
  @override
  void initState() {
    super.initState();
    _settingsService.loadAllFonts();
    _checkPrivacyPolicyStatus();
    _checkAndOpenUriFile();
    _eventChannel2
        .receiveBroadcastStream()
        .listen(_onEventOpenuri, onError: _onErrorOpenuri);
  }

  void _onEventOpenuri(dynamic uri) {
    if (uri is String && uri.isNotEmpty) {
      _openfile = uri;
      startPlayerPage(context);
    }
  }

  void _onErrorOpenuri(Object error) {
    print('Error receiving event: $error');
  }

  void setHomeWH(int width, int height) {
    setState(() {
      videoHeight = height;
      videoWidth = width;
    });
  }

  Future<void> _checkAndOpenUriFile() async {
    try {
      final file = File('/data/storage/el2/base/openuri.txt'); // 构建文件路径

      if (await file.exists()) {
        final uri = await file.readAsString(); // 读取文件内容
        if (uri.isNotEmpty) {
          // await _openUri(uri,wantFirst: true); // 打开URI
          // await _openUri(uri,wantFirst: true); // 打开URI
          _openfile = uri;
          startPlayerPage(context);
          // setState(() {
          //   widget.openfile = uri;
          // });
        }
        await file.delete(); // 删除文件
      }
    } catch (e) {
      print('Error reading or deleting openuri.txt: $e');
    }
  }

  void _toggleFullScreen() {
    setState(() {
      _isFullScreen = !_isFullScreen;
    });

    if (_isFullScreen) {
      // 进入全屏时隐藏状态栏
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      final _videoWidth = videoWidth;
      final _videoHeight = videoHeight;

      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);

      // if (widget.controller.systemOverlaysOnEnterFullScreen != null) {
      //   /// Optional user preferred settings
      //   SystemChrome.setEnabledSystemUIMode(
      //     SystemUiMode.manual,
      //     overlays: widget.controller.systemOverlaysOnEnterFullScreen,
      //   );
      // } else {
      //   /// Default behavior
      //   SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
      // }

      final isLandscapeVideo = videoWidth > videoHeight;
      final isPortraitVideo = videoWidth < videoHeight;

      /// Default behavior
      /// Video w > h means we force landscape
      if (isLandscapeVideo) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }

      /// Video h > w means we force portrait
      else if (isPortraitVideo) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      }

      /// Otherwise if h == w (square video)
      else {
        SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      }
    } else {
      // 退出全屏时显示状态栏
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
  }

  Future<bool> _onWillPop() async {
    if (_isFullScreen) {
      _toggleFullScreen();
      return false; // 阻止退出程序
    }
    return true; // 允许退出程序
  }

  void _getopenfile(String openfile) {
    setState(() {
      _openfile = openfile;
    });
  }

  Future<void> _checkPrivacyPolicyStatus() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool? isAccepted = prefs.getBool('privacy_policy_accepted');

    // 如果尚未接受隐私政策，显示对话框
    if (isAccepted == null || !isAccepted) {
      Future.delayed(Duration.zero, () {
        _showPrivacyPolicyDialog();
      });
    } else {
      setState(() {
        _isPolicyAccepted = true;
      });
      // 创建实例
      final _platform =
          const MethodChannel('samples.flutter.dev/downloadplugin');
// 调用方法 getBatteryLevel
      final result =
          await _platform.invokeMethod<String>('getDownloadPermission');
      final result2 = await _platform.invokeMethod<String>('startBgTask');
    }
  }

  void _showPrivacyPolicyDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // 禁止点击外部关闭对话框
      builder: (BuildContext context) {
        return OnboardingPrivacyDialog(
          onAccept: () async {
            SharedPreferences prefs = await SharedPreferences.getInstance();
            await prefs.setBool('privacy_policy_accepted', true);
            setState(() {
              _isPolicyAccepted = true;
            });
            Navigator.of(context).pop(); // 关闭对话框
            // 创建实例
            final _platform =
                const MethodChannel('samples.flutter.dev/downloadplugin');
// 调用方法 getBatteryLevel
            final result =
                await _platform.invokeMethod<String>('getDownloadPermission');
          },
          onDecline: () {
            // 用户拒绝，退出应用
            Navigator.of(context).pop(); // 关闭对话框
            Future.delayed(Duration(milliseconds: 200), () {
              // 退出应用
              // SystemNavigator.pop();
              exit(0);
            });
          },
        );
      },
    );
  }

  Future<String> getPlaylist(String path) async {
    List<String> results = [  ];
    //提取文件夹路径
    if (!await _settingsService.getUsePlaylist()) {
      return '';
    }
    if (path.contains(':')) {
      return '';
    }
    String folderPath = path.substring(0, path.lastIndexOf('/'));
    List<String> excludeExts = ['ux_store', 'srt', 'ass', 'jpg','pdf','aac'];
    // 如果文件夹位于 /storage/Users/currentUser/Download/com.aloereed.aloeplayer/下，打开该文件夹
    if (folderPath.startsWith(
        '/storage/Users/currentUser/Download/com.aloereed.aloeplayer/')) {
      final directory = Directory(folderPath);
      // 提取文件夹下所有文件（不包括子文件夹）
      List<FileSystemEntity> files = directory.listSync();
      // 把<文件名, 文件路径>添加到_playlist中
      for (FileSystemEntity file in files) {
        if (file is File) {
          if (excludeExts.contains(file.path.split('.').last)||file.path==path) {
            continue;
          }
          results.add(pathToUri(file.path));
        }
      }
      return results.join('[:newPlay:]');
    } else {
      return '';
    }
  }

  void startPlayerPage(BuildContext context) async {
    if (await _settingsService.getUseFfmpegForPlay() != 4) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PlayerTab(
            key: ValueKey(_openfile),
            toggleFullScreen: _toggleFullScreen,
            isFullScreen: _isFullScreen,
            getopenfile: _getopenfile,
            openfile: _openfile,
            setHomeWH: setHomeWH,
          ),
        ),
      );
    } else {
      if(_openfile.contains('http')){
        // 弹出通知，流心视频方式不支持播放网络视频
        Fluttertoast.showToast(
          msg: "流心视频方式不支持播放网络视频",
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.CENTER,
          timeInSecForIosWeb: 1,
          backgroundColor: Colors.red,
          textColor: Colors.white,
          fontSize: 16.0
        );
        return;
      }
      final _platform = const MethodChannel('samples.flutter.dev/hdrplugin');
      String waitToStart = _openfile;
      // 调用原生方法
      if (_openfile.endsWith('.lnk')) {
        waitToStart = File(_openfile).readAsStringSync();
      }
      _platform.invokeMethod<String>(
          'createNewWindow', {'path': pathToUri(waitToStart),'uris':await getPlaylist(waitToStart)});
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
        onWillPop: _onWillPop,
        child: Scaffold(
          body: PageView(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            children: [
              // PlayerTab(
              //   key: ValueKey(_openfile),
              //   toggleFullScreen: _toggleFullScreen,
              //   isFullScreen: _isFullScreen,
              //   getopenfile: _getopenfile,
              //   openfile: _openfile,
              //   setHomeWH: setHomeWH,
              // ),
              VideoLibraryTab(
                getopenfile: _getopenfile,
                changeTab: (index) {
                  setState(() {
                    _selectedIndex = index;
                  });
                  _pageController.animateToPage(
                    index,
                    duration: Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
                toggleFullScreen: () {},
                startPlayerPage: startPlayerPage,
              ),
              AudioLibraryTab(
                getopenfile: _getopenfile,
                changeTab: (index) {
                  setState(() {
                    _selectedIndex = index;
                  });
                  _pageController.animateToPage(
                    index,
                    duration: Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
                toggleFullScreen: () {},
                startPlayerPage: startPlayerPage,
              ),
              // MediaLibraryPage(
              //   getopenfile: _getopenfile,
              //   startPlayerPage: startPlayerPage,
              // ),
              SettingsTab(),
            ],
          ),
          bottomNavigationBar: _isFullScreen
              ? null
              : BottomNavigationBar(
                  currentIndex: _selectedIndex,
                  onTap: (index) {
                    setState(() {
                      _selectedIndex = index;
                    });
                    _pageController.animateToPage(
                      index,
                      duration: Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                  items: [
                    // BottomNavigationBarItem(
                    //   icon: Icon(Icons.play_arrow),
                    //   label: '播放器',
                    // ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.video_library),
                      label: '视频库',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.library_music),
                      label: '音频库',
                    ),
                    // BottomNavigationBarItem(
                    //   icon: Icon(Icons.library_books),
                    //   label: '网络媒体库'
                    // ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.settings),
                      label: '设置',
                    ),
                  ],
                  type: BottomNavigationBarType.fixed,
                ),
        ));
  }
}
