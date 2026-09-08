import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

String? normalizeCertificateFingerprint(String? input) {
  final value = (input ?? '').replaceAll(RegExp(r'[:\s]'), '').toLowerCase();
  if (value.isEmpty) return null;
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw const FormatException('证书 SHA-256 指纹应为 64 位十六进制字符，可包含空格或冒号');
  }
  return value;
}

/// Pin before sending HTTP credentials, including when the certificate has a
/// publicly trusted chain. This client deliberately has no trusted CA roots.
/// Cross-origin redirects must use a separate client with normal system trust.
HttpClientAdapter webDavHttpAdapter(Uri origin, {String? fingerprint}) {
  final pin = normalizeCertificateFingerprint(fingerprint);
  if (pin != null && origin.scheme != 'https') {
    throw const FormatException('证书指纹只能用于 HTTPS WebDAV 地址');
  }
  return IOHttpClientAdapter(createHttpClient: () {
    final client = pin == null
        ? HttpClient()
        : HttpClient(context: SecurityContext(withTrustedRoots: false));
    client.maxConnectionsPerHost = 6;
    client.idleTimeout = const Duration(seconds: 30);
    if (pin != null) {
      client.badCertificateCallback = (certificate, host, port) {
        final now = DateTime.now();
        return host.toLowerCase() == origin.host.toLowerCase() &&
            port == origin.port &&
            !now.isBefore(certificate.startValidity) &&
            !now.isAfter(certificate.endValidity) &&
            sha256.convert(certificate.der).toString() == pin;
      };
    }
    return client;
  });
}
