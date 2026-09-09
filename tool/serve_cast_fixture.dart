// Serves generated media to the real decoder test, on loopback only.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../lib/services/byte_range.dart';
import '../lib/services/cast_media_relay.dart';

Future<void> main(List<String> args) async {
  final root = Directory(args.single).absolute.path;
  final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var requests = 0;
  origin.listen((request) async {
    final response = request.response;
    try {
      if (request.headers.value('authorization') !=
          'Basic Zml4dHVyZTpmaXh0dXJl') {
        response.statusCode = 401;
        response.headers.set('WWW-Authenticate', 'Basic realm="fixture"');
      } else if (request.uri.path == '/start') {
        response.statusCode = 302;
        response.headers.set('Location', '/master.m3u8');
      } else {
        final local =
            p.normalize(p.joinAll([root, ...request.uri.pathSegments]));
        if (!p.isWithin(root, local) ||
            !['.m3u8', '.ts', '.bin'].contains(p.extension(local))) {
          response.statusCode = 403;
        } else {
          requests++;
          final file = File(local);
          final size = await file.length();
          final value = request.headers.value('range');
          final range = value == null ? null : ByteRange.parse(value, size);
          if (value != null && range == null) {
            response.statusCode = 416;
            response.headers.set('Content-Range', 'bytes */$size');
          } else {
            response.statusCode = range == null ? 200 : 206;
            response.headers.set(
                'Content-Type',
                local.endsWith('.m3u8')
                    ? 'application/vnd.apple.mpegurl'
                    : 'application/octet-stream');
            response.contentLength = range?.length ?? size;
            if (range != null)
              response.headers.set(
                  'Content-Range', 'bytes ${range.start}-${range.end}/$size');
            if (request.method == 'GET')
              await response.addStream(file.openRead(
                  range?.start ?? 0, range == null ? null : range.end + 1));
          }
        }
      }
      await response.close();
    } catch (_) {
      try {
        response.statusCode = 500;
        await response.close();
      } catch (_) {}
    }
  });
  final relay = await CastMediaRelay.start(
      'http://127.0.0.1:${origin.port}/start',
      host: '127.0.0.1',
      headers: {'Authorization': 'Basic Zml4dHVyZTpmaXh0dXJl'});
  stdout.writeln(jsonEncode({'url': relay.url}));
  await stdin.transform(utf8.decoder).transform(const LineSplitter()).first;
  await relay.close();
  await origin.close(force: true);
  stdout.writeln(jsonEncode(
      {'originRequests': requests, 'forwardedBytes': relay.bytesServed}));
}
