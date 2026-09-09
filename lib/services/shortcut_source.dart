import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

const shortcutAccessMessage = '无法访问快捷方式的原文件，请确认文件未移动或删除，并重新添加快捷方式授权。';

bool isMediaShortcut(String source) => source.toLowerCase().endsWith('.lnk');

/// Keep picker URIs intact; legacy links contain decoded absolute paths.
String shortcutPermissionUri(String source) {
  if (source.startsWith('/')) {
    return Uri(
            scheme: 'file',
            host: source.startsWith('/Photos/') ? 'media' : 'docs',
            pathSegments: source.split('/'))
        .toString();
  }
  return source;
}

String shortcutPlaybackSource(String source) {
  final uri = Uri.tryParse(source);
  if (uri?.scheme == 'file' && uri?.host == 'docs') {
    return Uri.decodeComponent(uri!.path);
  }
  if (uri?.scheme == 'file' && uri?.host.isEmpty == true)
    return uri!.toFilePath();
  return source;
}

Future<void> activateShortcutSource(
  String source, {
  Future<bool> Function(String)? activatePermission,
  Duration timeout = const Duration(seconds: 8),
}) async {
  final uri = shortcutPermissionUri(source);
  if (!uri.startsWith('file://docs/') && !uri.startsWith('file://media/'))
    return;
  if (activatePermission == null && Platform.operatingSystem != 'ohos') return;
  try {
    final activate = activatePermission ??
        (String value) async {
          const channel = MethodChannel('samples.flutter.dev/downloadplugin');
          final result = await channel
              .invokeMethod<String>('activatePermission', {'uri': value});
          return result != null && result.isNotEmpty;
        };
    if (!await activate(uri).timeout(timeout))
      throw const FileSystemException(shortcutAccessMessage);
  } on TimeoutException {
    throw const FileSystemException('快捷方式授权响应超时，请返回后重试或重新添加快捷方式。');
  } on PlatformException {
    throw const FileSystemException(shortcutAccessMessage);
  }
}

Future<String> resolveMediaShortcut(
  String filePath, {
  bool activate = true,
  bool checkReadable = true,
  Future<bool> Function(String)? activatePermission,
  Duration timeout = const Duration(seconds: 8),
}) async {
  if (!isMediaShortcut(filePath)) return shortcutPlaybackSource(filePath);
  String source;
  try {
    source = (await File(shortcutPlaybackSource(filePath))
            .readAsString()
            .timeout(timeout))
        .trim();
  } catch (_) {
    throw const FileSystemException('快捷方式无法读取，请重新添加。');
  }
  if (source.isEmpty) throw const FileSystemException('快捷方式为空，请重新添加。');
  if (activate)
    await activateShortcutSource(source,
        activatePermission: activatePermission, timeout: timeout);
  final target = shortcutPlaybackSource(source);
  if (checkReadable &&
      (target.startsWith('/') ||
          Uri.tryParse(target)?.hasScheme != true ||
          RegExp(r'^[A-Za-z]:[\\/]').hasMatch(target))) {
    try {
      // Opening checks actual access, not only whether a directory entry exists.
      await (() async {
        final handle = await File(target).open();
        await handle.close();
      })()
          .timeout(timeout);
    } catch (_) {
      throw const FileSystemException(shortcutAccessMessage);
    }
  }
  return target;
}
