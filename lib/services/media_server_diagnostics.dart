import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'media_server_client.dart';
import 'media_server_catalog.dart';

String mediaServerFailureMessage(Object error) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    if (status == 401) return '登录已失效，请重新登录';
    if (status == 403) return '当前账号没有访问权限，请检查服务器用户设置';
    if (status == 404 || status == 405) return '接口或内容不存在，请检查服务器地址中的路径前缀和版本';
    if (status == 429) return '服务器限制了请求频率，请稍后重试';
    if (status == 502 || status == 504) return '反向代理无法连接媒体服务器，请检查代理上游';
    if (status == 503) return '服务器正在启动或暂时繁忙，请稍后重试';
    if (error.type == DioExceptionType.badCertificate ||
        error.error is HandshakeException) {
      return 'HTTPS 证书验证失败，请检查证书有效期、域名和设备信任链';
    }
    if ({
      DioExceptionType.connectionTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.sendTimeout
    }.contains(error.type)) return '连接超时，请检查网络和服务器响应';
    if (error.type == DioExceptionType.connectionError)
      return '无法连接服务器，请检查域名、端口和网络';
  }
  if (error is TimeoutException) return '检查超时，请检查网络和服务器响应';
  if (error is FormatException) return '地址没有返回媒体服务器数据，请检查地址和反向代理路径';
  return '加载失败，请检查网络或重新登录后重试';
}

enum MediaServerDiagnosticStatus { passed, warning, failed }

class MediaServerDiagnostic {
  final String title, detail;
  final MediaServerDiagnosticStatus status;
  final int elapsedMs;
  const MediaServerDiagnostic(
      this.title, this.detail, this.status, this.elapsedMs);
  String get statusLabel => switch (status) {
        MediaServerDiagnosticStatus.passed => '通过',
        MediaServerDiagnosticStatus.warning => '提示',
        MediaServerDiagnosticStatus.failed => '失败',
      };
}

String mediaServerDiagnosticSummary(
        String kind, List<MediaServerDiagnostic> rows) =>
    [
      'AloePlayer 4.0.1 · ${kind == 'Emby' ? 'Emby' : 'Jellyfin'} 连接诊断',
      for (final row in rows)
        '${row.title}：${row.statusLabel}（${row.elapsedMs} ms）\n${row.detail}'
    ].join('\n');

class MediaServerDiagnostics {
  final MediaServerClient client;
  MediaServerDiagnostics(this.client);
  Stream<MediaServerDiagnostic> run(CancelToken cancel) async* {
    final checks =
        <String, Future<({String detail, bool warning})> Function(CancelToken)>{
      '服务器地址与版本': (token) async {
        final response = await client.dio
            .get<dynamic>('System/Info/Public', cancelToken: token);
        final data = response.data;
        if (data is! Map || data['Version'] is! String)
          throw const FormatException();
        final version = data['Version'] as String;
        if (!RegExp(r'^\d+(\.\d+){1,4}([a-zA-Z0-9.+_-]{0,32})?$')
            .hasMatch(version)) throw const FormatException();
        final product = data['ProductName'];
        final mismatch = product is String &&
            product.toLowerCase().contains('jellyfin') &&
            client.connection.kind == 'Emby';
        return (
          detail: '服务器版本 $version${mismatch ? '；建议把连接类型改为 Jellyfin' : ''}',
          warning: mismatch
        );
      },
      if (client.connection.userId.isNotEmpty) ...{
        '登录与账号权限': (token) async {
          final response = await client.dio.get<dynamic>(
              'Users/${Uri.encodeComponent(client.connection.userId)}',
              cancelToken: token);
          if (response.data is! Map || response.data['Policy'] is! Map)
            throw const FormatException();
          final policy = response.data['Policy'] as Map;
          final lines = <String>[];
          var warning = policy['IsDisabled'] == true;
          if (warning) lines.add('账号已停用');
          for (final entry in {
            '媒体播放': 'EnableMediaPlayback',
            '原文件下载': 'EnableContentDownloading',
            '视频转码': 'EnableVideoPlaybackTranscoding',
            '音频转码': 'EnableAudioPlaybackTranscoding'
          }.entries) {
            final value = policy[entry.value];
            lines.add(
                '${entry.key}：${value == true ? '允许' : value == false ? '未允许' : '服务器未声明'}');
            warning = warning || value == false;
          }
          return (detail: lines.join('\n'), warning: warning);
        },
        '媒体库读取': (token) async {
          final page = await client.shelf(MediaServerShelf.libraries,
              limit: 1, cancelToken: token);
          return (
            detail: page.items.isEmpty ? '账号下暂未返回媒体库，请检查库访问权限' : '媒体库接口读取成功',
            warning: page.items.isEmpty
          );
        },
        '目录与分页读取': (token) async {
          final page = await client.itemPage(limit: 1, cancelToken: token);
          return (
            detail: page.items.isEmpty ? '目录接口正常，当前没有可见内容' : '目录分页接口读取成功',
            warning: false
          );
        },
      }
    };
    for (final check in checks.entries) {
      if (cancel.isCancelled) break;
      final token = CancelToken();
      unawaited(cancel.whenCancel.then((_) {
        token.cancel('Diagnostic closed');
      }));
      final watch = Stopwatch()..start();
      late String detail;
      late MediaServerDiagnosticStatus status;
      try {
        final outcome = await check
            .value(token)
            .timeout(const Duration(seconds: 6), onTimeout: () {
          token.cancel('Diagnostic timeout');
          throw TimeoutException('Diagnostic timeout');
        });
        detail = outcome.detail;
        status = outcome.warning
            ? MediaServerDiagnosticStatus.warning
            : MediaServerDiagnosticStatus.passed;
      } catch (error) {
        detail = mediaServerFailureMessage(error);
        status = MediaServerDiagnosticStatus.failed;
      } finally {
        watch.stop();
      }
      if (cancel.isCancelled) break;
      yield MediaServerDiagnostic(
          check.key, detail, status, watch.elapsedMilliseconds);
    }
  }
}
