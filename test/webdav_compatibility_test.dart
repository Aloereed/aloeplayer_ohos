import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/webdav_service.dart';
import 'package:aloeplayer/services/webdav_path.dart';
import 'package:aloeplayer/services/webdav_multistatus.dart';
import 'package:aloeplayer/services/webdav_auth.dart';
import 'package:aloeplayer/models/server_config.dart';

String entry(String href,
        {String props = '<z:getcontentlength>6</z:getcontentlength>',
        String before = ''}) =>
    '<z:response><z:href>$href</z:href>$before<z:propstat><z:prop>$props</z:prop>'
    '<z:status>HTTP/1.1 200 OK</z:status></z:propstat></z:response>';
String multi(String entries) =>
    '<z:multistatus xmlns:z="DAV:">$entries</z:multistatus>';
const rootProps = '<z:resourcetype><z:collection/></z:resourcetype>';

void main() {
  test('URL inputs preserve full paths, IPv6 and explicit ports', () {
    ServerConfig config(String host, {int? port, bool https = false}) =>
        ServerConfig(
            id: 'dav',
            name: 'DAV',
            type: ServerType.webdav,
            host: host,
            username: '',
            password: '',
            createdAt: DateTime(2026),
            port: port,
            useHttps: https);
    expect(config('https://nas:5006/dav/%E5%BD%B1%E8%A7%86').webdavUrl,
        'https://nas:5006/dav/%E5%BD%B1%E8%A7%86');
    expect(config('[::1]:5005/dav').webdavUrl, 'http://[::1]:5005/dav');
    expect(
        config('http://nas/dav', port: 5005).webdavUrl, 'http://nas:5005/dav');
    expect(config('nas', https: true).webdavUrl, 'https://nas');
    expect(() => config('nas', port: 65536).webdavUrl, throwsFormatException);
    expect(
        () => config('http://user:pass@nas').webdavUrl, throwsFormatException);
  });

  test(
      'decoded paths round trip literal percent, unicode, query and fragment characters',
      () {
    final paths = WebDavPaths('https://nas/dav/%E5%BD%B1%E8%A7%86');
    const name = '/100%20 #?+ &中文.mkv';
    final uri = paths.resolve(name);
    expect(uri.pathSegments.last, '100%20 #?+ &中文.mkv');
    expect(uri.hasQuery, isFalse);
    expect(uri.hasFragment, isFalse);
    expect(paths.fromHref(uri.toString(), paths.base), name);
    expect(paths.fromHref('../outside.mkv', paths.base), isNull);
    expect(paths.fromHref('https://other/dav/movie', paths.base), isNull);
    expect(paths.fromHref('/dav/影视2/movie', paths.base), isNull);
    expect(paths.fromHref('/dav/影视/bad%2fname', paths.base), isNull);
    expect(paths.fromHref('clip.mkv', paths.base), '/clip.mkv');
  });

  test(
      'multistatus merges successful properties and ignores other namespaces, ancestors and failed entries',
      () {
    final xml = multi(entry('/dav/', props: rootProps) +
        entry('/dav/%E5%BD%B1%E8%A7%86/', props: rootProps) +
        entry('/dav/100%2520%20%23%3F.mkv',
            before:
                '<z:propstat><z:prop><z:displayname>WRONG</z:displayname><z:getcontentlength>999</z:getcontentlength></z:prop>'
                '<z:status>HTTP/1.1 404 Not Found</z:status></z:propstat>',
            props:
                '<z:getcontentlength>4294967297</z:getcontentlength><z:getlastmodified>2026-09-08T00:00:00Z</z:getlastmodified>'
                '<foreign:resourcetype xmlns:foreign="urn:other"><foreign:collection/></foreign:resourcetype>') +
        '<z:response><z:href>/dav/denied</z:href><z:status>HTTP/1.1 403 Forbidden</z:status></z:response>');
    final files =
        parseWebDavMultiStatus(xml, 'https://nas/dav/', 'https://nas/dav/');
    expect(files.length, 3);
    expect(files[1].isDirectory, isTrue);
    expect(files[2].path, '/100%20 #?.mkv');
    expect(files[2].name, '100%20 #?.mkv');
    expect(files[2].size, 4294967297);
    expect(files[2].isDirectory, isFalse);
    expect(files[2].lastModified, DateTime.utc(2026, 9, 8));
    expect(
        files.where((f) => WebDavPaths.isDirectChild('/', f.path)).length, 2);
    expect(
        () => parseWebDavMultiStatus(
            '<html/>', 'https://nas/dav/', 'https://nas/dav/'),
        throwsFormatException);
    expect(
        () => parseWebDavMultiStatus(
            '<broken', 'https://nas/dav/', 'https://nas/dav/'),
        throwsA(anything));
  });

  test(
      'Digest matches RFC MD5 example and supports stronger and session challenges',
      () {
    final digest = WebDavDigest({
      'realm': 'testrealm@host.com',
      'nonce': 'dcd98b7102dd2f0e8b11d0f600bfb0c093',
      'qop': 'auth',
      'opaque': '5ccc069c403ebaf9f0171e9517f40e41'
    }, cnonce: '0a4f113b');
    final header = digest.authorization('Mufasa', 'Circle Of Life', 'GET',
        Uri.parse('http://host/dir/index.html'));
    expect(header, contains('response="6629fae49393a05397450978507c4ef1"'));
    expect(header, contains('nc=00000001'));
    expect(
        digest.authorization('Mufasa', 'Circle Of Life', 'GET',
            Uri.parse('http://host/dir/index.html')),
        contains('nc=00000002'));
    final preferred = WebDavDigest.fromChallenges([
      'Basic realm="NAS", Digest realm="NAS", nonce="a", algorithm=MD5, qop="auth,auth-int"',
      'Digest realm="NAS", nonce="b", algorithm=SHA-256-sess, qop="auth-int", charset=UTF-8'
    ]);
    expect(preferred!.algorithm, 'SHA-256-SESS');
    expect(
        preferred.authorization(
            '用户', '密码', 'PROPFIND', Uri.parse('http://nas/dav/'),
            body: '<propfind/>'),
        contains('qop=auth-int'));
    expect(
        WebDavDigest.fromChallenges(
            ['Digest realm="x", nonce="x", algorithm=unknown']),
        isNull);
    final sha = WebDavDigest({
      'realm': 'http-auth@example.org',
      'nonce': '7ypf/xlj9XXwfDPEoM4URrv/xwf94BcCAzFZH4GiTo0v',
      'qop': 'auth',
      'algorithm': 'SHA-256'
    }, cnonce: 'f2/wE4q74E6zIJEtWaHKaf5wv/H5QzzpXusqGemxURZJ');
    expect(
        sha.authorization('Mufasa', 'Circle of Life', 'GET',
            Uri.parse('http://www.example.org/dir/index.html')),
        contains(
            '753927fa0e85d155564e2e272a28d1802ca10daf4496794697cf8db5856cb6c1'));
  });

  test(
      'real HTTP browsing, encoded GET, stat and same-origin redirects keep DAV methods',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final observed = <String>[];
    server.listen((request) async {
      observed.add('${request.method} ${request.uri}');
      if (request.method == 'PROPFIND') {
        request.response.statusCode = 207;
        request.response.write(multi(entry('/dav/', props: rootProps) +
            entry('/dav/100%2520%20%23%3F.mkv') +
            entry('/dav/Folder/', props: rootProps) +
            entry('/dav/Folder/nested.mkv')));
      } else if (request.uri.path == '/dav/redirect') {
        request.response.statusCode = 307;
        request.response.headers.set('location', '/dav/100%2520%20%23%3F.mkv');
      } else {
        expect(request.uri.pathSegments.last, '100%20 #?.mkv');
        request.response.add([0, 1, 2, 3, 4, 5]);
      }
      await request.response.close();
    });
    final service = WebDavService();
    try {
      expect(
          await service.connect(
              baseUrl: 'http://127.0.0.1:${server.port}/dav',
              username: '',
              password: ''),
          isTrue);
      final files = await service.listFiles('/');
      expect(files.map((f) => f.path), ['/100%20 #?.mkv', '/Folder']);
      expect((await service.getFileInfo(files.first.path))!.size, 6);
      expect(
          await (await service.getFileStream(files.first.path))
              .expand((x) => x)
              .toList(),
          [0, 1, 2, 3, 4, 5]);
      expect(await service.downloadFile('/redirect'), [0, 1, 2, 3, 4, 5]);
      expect(observed.first, 'PROPFIND /dav/');
    } finally {
      await service.disconnect();
      await server.close(force: true);
    }
  });

  test('Digest challenge is retried with PROPFIND body and reused for GET',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final auth = <String>[];
    server.listen((request) async {
      final header = request.headers.value('authorization') ?? '';
      auth.add(header);
      final body = await utf8.decoder.bind(request).join();
      if (!header.startsWith('Digest ')) {
        request.response.statusCode = 401;
        request.response.headers.set('www-authenticate',
            'Digest realm="NAS", nonce="nonce", qop="auth", algorithm=SHA-256');
      } else if (request.method == 'PROPFIND') {
        expect(body, contains('propfind'));
        request.response.statusCode = 207;
        request.response.write(multi(entry('/dav/', props: rootProps)));
      } else {
        request.response.add([1, 2]);
      }
      await request.response.close();
    });
    final service = WebDavService();
    try {
      await service.connect(
          baseUrl: 'http://127.0.0.1:${server.port}/dav',
          username: 'user',
          password: 'pass');
      expect(await service.downloadFile('/clip'), [1, 2]);
      expect(auth.length, 3);
      expect(auth[1], contains('nc=00000001'));
      expect(auth[2], contains('nc=00000002'));
      expect(auth[2], contains('uri="/dav/clip"'));
    } finally {
      await service.disconnect();
      await server.close(force: true);
    }
  });

  test('cross-origin media redirect never forwards credentials', () async {
    final destination = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    destination.listen((request) async {
      expect(request.headers.value('authorization'), isNull);
      expect(request.headers.value('range'), 'bytes=1-2');
      request.response.statusCode = 206;
      request.response.headers.set('content-range', 'bytes 1-2/3');
      request.response.add([1, 2]);
      await request.response.close();
    });
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      expect(request.headers.value('authorization'), startsWith('Basic '));
      if (request.method == 'PROPFIND') {
        request.response.statusCode = 207;
        request.response.write(multi(''));
      } else {
        request.response.statusCode = 302;
        request.response.headers.set(
            'location', 'http://127.0.0.1:${destination.port}/signed?key=x');
      }
      await request.response.close();
    });
    final service = WebDavService();
    try {
      await service.connect(
          baseUrl: 'http://127.0.0.1:${server.port}',
          username: 'user',
          password: 'pass');
      expect(
          await (await service.getFileStream('/file', start: 1, end: 2))
              .expand((x) => x)
              .toList(),
          [1, 2]);
    } finally {
      await service.disconnect();
      await server.close(force: true);
      await destination.close(force: true);
    }
  });

  test(
      'failed authentication leaves disconnected state and never exposes an HTML page as a directory',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var status = 401;
    server.listen((request) async {
      request.response.statusCode = status;
      request.response.write('<html>Login</html>');
      await request.response.close();
    });
    final service = WebDavService();
    try {
      await expectLater(
          service.connect(
              baseUrl: 'http://127.0.0.1:${server.port}',
              username: '',
              password: ''),
          throwsStateError);
      expect(service.isConnected, isFalse);
      status = 200;
      await expectLater(
          service.connect(
              baseUrl: 'http://127.0.0.1:${server.port}',
              username: '',
              password: ''),
          throwsFormatException);
      expect(service.isConnected, isFalse);
    } finally {
      await service.disconnect();
      await server.close(force: true);
    }
  });
}
