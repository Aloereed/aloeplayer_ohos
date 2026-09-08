import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// RFC 7616 MD5/SHA-256/SHA-512-256, session variants and auth-int. The nonce
/// counter is assigned synchronously so concurrent GETs never reuse a count.
class WebDavDigest {
  final Map<String, String> parameters;
  final String cnonce;
  int _count = 0;

  WebDavDigest(this.parameters, {String? cnonce})
      : cnonce = cnonce ??
            List.generate(
                16,
                (_) => Random.secure()
                    .nextInt(256)
                    .toRadixString(16)
                    .padLeft(2, '0')).join();

  static WebDavDigest? fromChallenges(List<String> headers) {
    final candidates = <WebDavDigest>[];
    for (final header in headers) {
      final schemes =
          RegExp(r'(?:^|,\s*)(Digest|Basic)\s+', caseSensitive: false)
              .allMatches(header)
              .toList();
      for (var i = 0; i < schemes.length; i++) {
        if (schemes[i].group(1)!.toLowerCase() != 'digest') continue;
        final text = header.substring(schemes[i].end,
            i + 1 < schemes.length ? schemes[i + 1].start : header.length);
        final params = <String, String>{};
        for (final match
            in RegExp(r'([\w-]+)\s*=\s*(?:"((?:\\.|[^"\\])*)"|([^,\s]+))')
                .allMatches(text)) {
          params[match.group(1)!.toLowerCase()] = match
                  .group(2)
                  ?.replaceAllMapped(RegExp(r'\\(.)'), (m) => m.group(1)!) ??
              match.group(3)!;
        }
        final digest = WebDavDigest(params);
        if (digest.supported) candidates.add(digest);
      }
    }
    candidates.sort(
        (a, b) => b.algorithm.compareTo(a.algorithm)); // SHA-256 before MD5.
    return candidates.firstOrNull;
  }

  String get algorithm => (parameters['algorithm'] ?? 'MD5').toUpperCase();
  String? get qop {
    final choices =
        parameters['qop']?.toLowerCase().split(',').map((s) => s.trim());
    if (choices == null) return null;
    if (choices.contains('auth')) return 'auth';
    if (choices.contains('auth-int')) return 'auth-int';
    return 'unsupported';
  }

  bool get supported =>
      parameters.containsKey('realm') &&
      (parameters['nonce']?.isNotEmpty ?? false) &&
      {
        'MD5',
        'MD5-SESS',
        'SHA-256',
        'SHA-256-SESS',
        'SHA-512-256',
        'SHA-512-256-SESS'
      }.contains(algorithm) &&
      qop != 'unsupported';

  String authorization(String username, String password, String method, Uri uri,
      {String body = ''}) {
    if (!supported) throw StateError('不支持服务器要求的 Digest 认证算法');
    final hash = algorithm.startsWith('SHA-512-256')
        ? sha512256
        : algorithm.startsWith('SHA-256')
            ? sha256
            : md5;
    final charsetUtf8 = parameters['charset']?.toUpperCase() == 'UTF-8';
    List<int> encode(String value) =>
        charsetUtf8 || value.runes.any((r) => r > 255)
            ? utf8.encode(value)
            : latin1.encode(value);
    String h(String value) => hash.convert(encode(value)).toString();
    final realm = parameters['realm']!;
    final nonce = parameters['nonce']!;
    final target = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
    final nc = (++_count).toRadixString(16).padLeft(8, '0');
    var ha1 = h('$username:$realm:$password');
    if (algorithm.endsWith('-SESS')) ha1 = h('$ha1:$nonce:$cnonce');
    final entity = hash.convert(utf8.encode(body)).toString();
    final ha2 =
        h(qop == 'auth-int' ? '$method:$target:$entity' : '$method:$target');
    final response = h(
        qop == null ? '$ha1:$nonce:$ha2' : '$ha1:$nonce:$nc:$cnonce:$qop:$ha2');
    String quote(String value) {
      if (value.contains(RegExp(r'[\r\n]')))
        throw const FormatException('认证字段包含无效字符');
      return '"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
    }

    final userhash = parameters['userhash']?.toLowerCase() == 'true';
    final extendedUsername = !userhash &&
        (charsetUtf8 || username.runes.any((r) => r > 255)) &&
        username.runes.any((r) => r > 127);
    final encodedUsername = utf8
        .encode(username)
        .map((byte) =>
            '%${byte.toRadixString(16).padLeft(2, '0').toUpperCase()}')
        .join();
    return 'Digest ${[
      if (extendedUsername)
        "username*=UTF-8''$encodedUsername"
      else
        'username=${quote(userhash ? h('$username:$realm') : username)}',
      'realm=${quote(realm)}',
      'nonce=${quote(nonce)}',
      'uri=${quote(target)}',
      'response=${quote(response)}',
      'algorithm=$algorithm',
      if (parameters['opaque'] != null)
        'opaque=${quote(parameters['opaque']!)}',
      if (qop != null) 'qop=$qop',
      if (qop != null) 'nc=$nc',
      if (qop != null || algorithm.endsWith('-SESS')) 'cnonce=${quote(cnonce)}',
      if (userhash) 'userhash=true',
    ].join(', ')}';
  }
}
