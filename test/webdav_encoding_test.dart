import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/webdav_auth.dart';
import 'package:aloeplayer/services/webdav_service.dart';
import 'package:aloeplayer/services/webdav_xml_encoding.dart';
import 'package:aloeplayer/services/webdav_multistatus.dart';
import 'webdav_compatibility_test.dart' show entry, multi, rootProps;

void main() {
  test('all failed properties on requested directory are not an empty success',
      () {
    expect(
        () => parseWebDavMultiStatus(
            '<D:multistatus xmlns:D="DAV:"><D:response><D:href>/</D:href><D:propstat><D:prop><D:resourcetype/></D:prop><D:status>HTTP/1.1 403 Forbidden</D:status></D:propstat></D:response></D:multistatus>',
            'http://nas/',
            'http://nas/'),
        throwsStateError);
  });
  test(
      'full compressed response validates decoded bytes independently of wire length',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final payload = List.generate(4096, (i) => i % 256);
    server.listen((request) async {
      if (request.method == 'PROPFIND') {
        request.response.statusCode = 207;
        request.response.write(multi(entry('/', props: rootProps)));
      } else {
        final compressed = gzip.encode(payload);
        request.response.headers.set('content-encoding', 'gzip');
        request.response.contentLength = compressed.length;
        request.response.add(compressed);
      }
      await request.response.close();
    });
    final service = WebDavService();
    try {
      await service.connect(
          baseUrl: 'http://127.0.0.1:${server.port}',
          username: '',
          password: '');
      expect(await service.downloadFile('/clip'), payload);
    } finally {
      await service.disconnect();
      await server.close(force: true);
    }
  });
  // RFC 7616 erratum 4897 corrects the original truncated-SHA-512 vector.
  test('Digest SHA-512-256 matches corrected RFC international username vector',
      () {
    final digest = WebDavDigest({
      'realm': 'api@example.org',
      'nonce': '5TsQWLVdgBdmrQ0XsxbDODV+57QdFR34I9HAbC/RVvkK',
      'algorithm': 'SHA-512-256',
      'qop': 'auth',
      'charset': 'UTF-8',
      'userhash': 'true',
    }, cnonce: 'NTg6RKcb9boFIAS3KrFK9BGeh+iDa/sm6jUMp2wds69v');
    final header = digest.authorization('Jäsøn Doe', 'Secret, or not?', 'GET',
        Uri.parse('https://example.org/doe.json'));
    expect(
        header,
        contains(
            'username="793263caabb707a56211940d90411ea4a575adeccb7e360aeb624ed06ece9b0b"'));
    expect(
        header,
        contains(
            'response="3798d4131c277846293534c3edc11bd8a5e4cdcbff78b05db9d95eeb1cec68a5"'));
  });

  for (final endian in [Endian.little, Endian.big]) {
    test('UTF-16 $endian DAV directory survives real HTTP transport', () async {
      final xml = multi(entry('/', props: rootProps) +
          entry('/%E4%B8%AD%E6%96%87.mp4',
              props:
                  '<z:displayname>中文🎬.mp4</z:displayname><z:getcontentlength>3</z:getcontentlength>'));
      final bytes = ByteData(2 + xml.length * 2)..setUint16(0, 0xfeff, endian);
      for (var i = 0; i < xml.length; i++) {
        bytes.setUint16(2 + 2 * i, xml.codeUnitAt(i), endian);
      }
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.statusCode = 207;
        request.response.headers
            .set('content-type', 'application/xml; charset=utf-16');
        request.response.add(bytes.buffer.asUint8List());
        await request.response.close();
      });
      final service = WebDavService();
      try {
        await service.connect(
            baseUrl: 'http://127.0.0.1:${server.port}',
            username: '',
            password: '');
        final file = (await service.listFiles('/')).single;
        expect(file.name, '中文🎬.mp4');
        expect(file.path, '/中文.mp4');
      } finally {
        await service.disconnect();
        await server.close(force: true);
      }
    });
  }

  test('XML declared Latin-1 and invalid encodings have explicit results', () {
    final xml = '<?xml version="1.0" encoding="ISO-8859-1"?><name>café</name>';
    expect(decodeWebDavXml(Uint8List.fromList(latin1.encode(xml))), xml);
    expect(() => decodeWebDavXml(Uint8List.fromList([0xff, 0xfe, 1])),
        throwsFormatException);
    expect(
        () => decodeWebDavXml(Uint8List.fromList([60]),
            contentType: 'application/xml; charset=unknown'),
        throwsFormatException);
  });

  test('Chinese Digest username uses an ASCII extended HTTP header', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var digestRequests = 0;
    server.listen((request) async {
      final auth = request.headers.value('authorization') ?? '';
      if (!auth.startsWith('Digest')) {
        request.response.statusCode = 401;
        request.response.headers.set('www-authenticate',
            'Digest realm="dav", nonce="test", algorithm=SHA-256, qop="auth", charset=UTF-8');
      } else {
        expect(auth, contains("username*=UTF-8''%E4%B8%AD%E6%96%87"));
        expect(auth.codeUnits.every((c) => c < 128), isTrue);
        digestRequests++;
        request.response.statusCode = 207;
        request.response.write(multi(entry('/', props: rootProps)));
      }
      await request.response.close();
    });
    final service = WebDavService();
    try {
      await service.connect(
          baseUrl: 'http://127.0.0.1:${server.port}',
          username: '中文',
          password: '密码');
      await service.listFiles('/');
      expect(digestRequests, 2);
    } finally {
      await service.disconnect();
      await server.close(force: true);
    }
  });

  for (final probe in ['range', 'full', 'empty', 'invalid']) {
    test('missing HEAD support falls back to bounded size probe: $probe',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var gets = 0;
      server.listen((request) async {
        if (request.method == 'PROPFIND') {
          request.response.statusCode = 207;
          request.response.write(multi(entry('/', props: rootProps) +
              entry('/clip', props: '<z:resourcetype/>')));
        } else if (request.method == 'HEAD') {
          request.response.statusCode = 405;
        } else {
          gets++;
          expect(request.headers.value('range'), 'bytes=0-0');
          if (probe == 'empty') {
            request.response.statusCode = 416;
            request.response.headers.set('content-range', 'bytes */0');
          } else if (probe == 'full') {
            request.response.contentLength = 123;
            request.response.add(List.filled(123, 1));
          } else {
            request.response.statusCode = 206;
            request.response.headers.set('content-range',
                probe == 'invalid' ? 'bytes 1-1/123' : 'bytes 0-0/123');
            request.response.add([1]);
          }
        }
        await request.response.close();
      });
      final service = WebDavService();
      try {
        await service.connect(
            baseUrl: 'http://127.0.0.1:${server.port}',
            username: '',
            password: '');
        if (probe == 'invalid') {
          await expectLater(service.getFileInfo('/clip'), throwsStateError);
        } else {
          expect((await service.getFileInfo('/clip'))!.size,
              probe == 'empty' ? 0 : 123);
        }
        expect(gets, 1);
      } finally {
        await service.disconnect();
        await server.close(force: true);
      }
    });
  }
}
