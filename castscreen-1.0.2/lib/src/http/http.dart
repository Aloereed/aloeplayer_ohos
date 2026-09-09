part of 'lib.dart';

/// A bounded HTTP/SOAP failure, retained for useful receiver diagnostics.
class CastProtocolException implements Exception {
  final String message;
  final int? statusCode;
  final int? upnpCode;
  const CastProtocolException(this.message, {this.statusCode, this.upnpCode});
  @override
  String toString() => '$message${upnpCode == null ? '' : ' (UPnP $upnpCode)'}${statusCode == null ? '' : ' [HTTP $statusCode]'}';
}

abstract final class Http {
  static const timeout = Duration(seconds: 8);
  static const maxXmlBytes = 2 * 1024 * 1024;

  static Future<int> head(String url) async {
    final client = http.Client();
    try {
      final response = await client.send(http.Request('GET', Uri.parse(url))).timeout(timeout);
      await response.stream.listen((_) {}).cancel();
      return response.statusCode;
    } finally { client.close(); }
  }

  static Future<Model<T>> get<T>(String url, Converter<T> converter) =>
      _request('GET', url, converter);

  static Future<Model<T>> post<T>(String url, Converter<T> converter,
      {String? body, Map<String, String>? headers, Duration requestTimeout = timeout}) =>
      _request('POST', url, converter, body: body, headers: headers, requestTimeout: requestTimeout);

  static Future<Model<T>> _request<T>(String method, String url, Converter<T> converter,
      {String? body, Map<String, String>? headers, Duration requestTimeout = timeout}) async {
    final client = http.Client();
    try {
      return await (() async {
        final request = http.Request(method, Uri.parse(url));
        request.headers.addAll(headers ?? {});
        if (body != null) request.bodyBytes = utf8.encode(body);
        final response = await client.send(request);
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > maxXmlBytes) {
            throw const CastProtocolException('设备描述或控制响应过大');
          }
          bytes.addAll(chunk);
        }
        XmlDocument xml;
        try { xml = bytes.isEmpty ? XmlDocument() : XmlDocument.parse(utf8.decode(bytes)); }
        catch (_) { throw CastProtocolException('设备返回了无法解析的 XML', statusCode: response.statusCode); }
        final faults = xml.descendants.whereType<XmlElement>().where((e) => e.name.local == 'Fault');
        if (faults.isNotEmpty) {
          String field(String name) => faults.first.descendants.whereType<XmlElement>()
              .where((e) => e.name.local == name).map((e) => e.innerText.trim()).firstOrNull ?? '';
          throw CastProtocolException(field('errorDescription').isNotEmpty ? field('errorDescription') : '设备拒绝控制命令',
              statusCode: response.statusCode, upnpCode: int.tryParse(field('errorCode')));
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw CastProtocolException('设备请求失败', statusCode: response.statusCode);
        }
        return Model(response.statusCode, 'ok', converter(xml));
      })().timeout(requestTimeout);
    } on TimeoutException {
      throw const CastProtocolException('设备响应超时，请确认设备在线且位于同一网络');
    } finally { client.close(); }
  }
}

class Model<T> {
  final int code;
  final String msg;
  final T data;
  const Model(this.code, this.msg, this.data);
}
typedef Converter<T> = T Function(XmlDocument xml);
