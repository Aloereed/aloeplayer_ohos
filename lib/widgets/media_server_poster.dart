import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../services/media_server_client.dart';
import '../services/media_server_diagnostics.dart';

String mediaServerError(Object error) {
  // Do not display Dio's raw request or authentication headers in the UI.
  if (error is DioException) {
    final status = error.response?.statusCode;
    if (status == 401) return '登录已失效，请重新登录';
    if (status == 403) return '当前账号没有访问权限';
    if (status == 404 || status == 405) return '当前服务器版本不支持此功能，或内容已移除';
  }
  return mediaServerFailureMessage(error);
}

class MediaServerPoster extends StatelessWidget {
  final MediaServerClient client;
  final MediaServerItem item;
  final VoidCallback onTap;
  const MediaServerPoster(
      {super.key,
      required this.client,
      required this.item,
      required this.onTap});
  @override
  Widget build(BuildContext context) => Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
          onTap: onTap,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
                child: Stack(fit: StackFit.expand, children: [
              Image.network(client.imageUrl(item.id),
                  headers: client.headers,
                  cacheWidth: 360,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(
                      item.isFolder
                          ? Icons.folder_outlined
                          : Icons.movie_outlined,
                      size: 48)),
              if (item.played)
                const Positioned(
                    right: 4,
                    top: 4,
                    child: Tooltip(
                        message: '已看',
                        child: CircleAvatar(
                            radius: 13, child: Icon(Icons.check, size: 18)))),
              if (item.favorite)
                const Positioned(
                    left: 4,
                    top: 4,
                    child: Tooltip(
                        message: '已收藏',
                        child: CircleAvatar(
                            radius: 13,
                            child: Icon(Icons.favorite, size: 16)))),
            ])),
            if (item.durationMs > 0 && item.resumeMs > 0)
              LinearProgressIndicator(
                  value: (item.resumeMs / item.durationMs).clamp(0, 1)),
            Padding(
                padding: const EdgeInsets.all(8),
                child: Text(item.name,
                    maxLines: 2, overflow: TextOverflow.ellipsis)),
            if (item.type == 'Episode')
              Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                  child: Text(
                      '${item.seasonIndex == null ? '' : 'S${item.seasonIndex} '}E${item.index ?? '?'}',
                      style: Theme.of(context).textTheme.bodySmall)),
          ])));
}
