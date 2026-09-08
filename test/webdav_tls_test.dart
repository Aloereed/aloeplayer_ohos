import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/webdav_service.dart';
import 'package:aloeplayer/services/webdav_tls.dart';
import 'package:aloeplayer/models/server_config.dart';
import 'webdav_compatibility_test.dart' show entry, multi, rootProps;

Future<HttpServer> tlsServer() => HttpServer.bindSecure(
    InternetAddress.loopbackIPv4,
    0,
    SecurityContext()
      ..useCertificateChain('test/fixtures/tls/localhost-cert.pem')
      ..usePrivateKey('test/fixtures/tls/localhost-test-key.pem'));

void main() {
  final pin = File('test/fixtures/tls/sha256.txt').readAsStringSync().trim();
  test('certificate pin parses separators, persists and rejects invalid values',
      () {
    expect(
        normalizeCertificateFingerprint(pin.toUpperCase().split('').join(':')),
        pin);
    expect(normalizeCertificateFingerprint(' '), isNull);
    expect(() => normalizeCertificateFingerprint('not a fingerprint'),
        throwsFormatException);
    expect(() => webDavHttpAdapter(Uri.parse('http://nas'), fingerprint: pin),
        throwsFormatException);
    final config = ServerConfig(
        id: 'nas',
        name: 'nas',
        type: ServerType.webdav,
        host: 'https://nas',
        username: '',
        password: '',
        createdAt: DateTime(2026),
        webdavCertificateSha256: pin);
    expect(
        ServerConfig.fromJson(config.copyWith(name: 'new').toJson())
            .webdavCertificateSha256,
        pin);
    expect(
        ServerConfig.fromJson(
                config.toJson()..remove('webdavCertificateSha256'))
            .webdavCertificateSha256,
        isNull);
  });

  for (final trusted in [false, true]) {
    test(
        'self-signed TLS is ${trusted ? 'accepted with the exact pin' : 'rejected by default'}',
        () async {
      final server = await tlsServer();
      var received = 0;
      server.listen((request) async {
        received++;
        request.response.statusCode = 207;
        request.response.write(multi(entry('/', props: rootProps)));
        await request.response.close();
      }, onError: (Object _) {});
      final service = WebDavService();
      try {
        final connection = service.connect(
            baseUrl: 'https://127.0.0.1:${server.port}',
            username: 'test',
            password: 'test',
            certificateSha256: trusted ? pin : null);
        if (trusted) {
          expect(await connection, isTrue);
          await service.listFiles('/');
          expect(received, 2);
        } else {
          await expectLater(connection, throwsA(anything));
          expect(received, 0);
          expect(service.isConnected, isFalse);
        }
      } finally {
        await service.disconnect();
        await server.close(force: true);
      }
    });
  }

  test('wrong pin rejects TLS before any HTTP credentials are sent', () async {
    final server = await tlsServer();
    var received = 0;
    server.listen((request) async {
      received++;
      await request.response.close();
    }, onError: (Object _) {});
    final service = WebDavService();
    try {
      await expectLater(
          service.connect(
              baseUrl: 'https://127.0.0.1:${server.port}',
              username: 'test',
              password: 'test',
              certificateSha256: '0' * 64),
          throwsA(anything));
      expect(received, 0);
    } finally {
      await service.disconnect();
      await server.close(force: true);
    }
  });

  test('origin pin never trusts a self-signed CDN at a different port',
      () async {
    final origin = await tlsServer();
    final cdn = await tlsServer();
    var received = 0;
    cdn.listen((request) async {
      received++;
      await request.response.close();
    }, onError: (Object _) {});
    origin.listen((request) async {
      if (request.method == 'PROPFIND') {
        request.response.statusCode = 207;
        request.response.write(multi(entry('/', props: rootProps)));
      } else {
        request.response.statusCode = 302;
        request.response.headers
            .set('location', 'https://127.0.0.1:${cdn.port}/clip');
      }
      await request.response.close();
    }, onError: (Object _) {});
    final service = WebDavService();
    try {
      await service.connect(
          baseUrl: 'https://127.0.0.1:${origin.port}',
          username: 'test',
          password: 'test',
          certificateSha256: pin);
      await expectLater(service.getFileStream('/clip'), throwsA(anything));
      expect(received, 0);
    } finally {
      await service.disconnect();
      await origin.close(force: true);
      await cdn.close(force: true);
    }
  });
}
