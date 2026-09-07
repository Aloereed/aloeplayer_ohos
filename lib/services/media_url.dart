import 'dart:async';
import 'dart:io';

const mediaUrlHint = '需要视频文件或媒体流的直接链接（如 MP4、MKV、M3U8），不支持视频网页、网盘分享页或短视频分享页。可粘贴包含链接的整段文本。';
const mediaUrlFailure = '链接无法播放。请确认它是视频文件的直接链接；网页分享链接不能直接播放。链接也可能已过期、需要登录或服务器拒绝访问，请获取新的直链并检查网络后重试。';

List<String> extractMediaUrls(String text) {
  final matches = RegExp(r'''https?://[^\s<>"'，。！？；、【】“”‘’]+''', caseSensitive: false).allMatches(text);
  final urls = <String>{};
  for (final match in matches) {
    var value = match.group(0)!;
    value = value.replaceFirst(RegExp(r'[.,;!?:]+$'), '');
    for (final pair in [['(', ')'], ['[', ']'], ['（', '）']]) {
      while (value.endsWith(pair[1]) && pair[1].allMatches(value).length > pair[0].allMatches(value).length) {
        value = value.substring(0, value.length - 1);
      }
    }
    final uri = Uri.tryParse(value);
    if (uri != null && uri.host.isNotEmpty && !uri.host.contains('%') && uri.userInfo.isEmpty) urls.add(value);
  }
  return urls.toList();
}

/// Inspect headers only; do not download a video or reject extensionless streams.
Future<void> validateMediaUrl(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
  try {
    final request = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 12));
    final response = await request.close().timeout(const Duration(seconds: 12));
    if (response.statusCode >= 400) {
      throw FormatException(response.statusCode == 401 || response.statusCode == 403
          ? '服务器拒绝访问，链接可能需要登录或已过期。请获取可直接访问的视频链接。'
          : '链接无法访问（HTTP ${response.statusCode}），请检查地址或获取新的直链。');
    }
    final type = response.headers.contentType?.mimeType;
    if (type == 'text/html' || type == 'application/xhtml+xml') {
      throw const FormatException('这个链接返回的是网页，不是视频文件。请复制视频文件或媒体流的直接链接。');
    }
  } on TimeoutException {
    throw const FormatException('连接超时，请检查网络或更换视频直链后重试。');
  } on IOException {
    throw const FormatException('无法连接服务器，请检查网络、链接地址及服务器证书后重试。');
  } finally {
    client.close(force: true);
  }
}
