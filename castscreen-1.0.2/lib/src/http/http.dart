part of 'lib.dart';

abstract final class Http {
  static Future<int> head(String url) async {
    int statusCode = 0;
    try {
      await http.get(Uri.parse(url));
      //ignored response statusCode
      statusCode = 200;
    } catch (error) {
      // ignored
    }
    return statusCode;
  }

  static Future<Model<T>> get<T>(String url, Converter<T> converter) async {
    var m = <String, dynamic>{};
    http.Response response;
    int statusCode = 0;
    try {
      response = await http.get(Uri.parse(url));
      statusCode = response.statusCode;
      switch (statusCode) {
        case 200:
          final body = utf8.decode(response.bodyBytes);
          m['xml'] = XmlDocument.parse(body);
          break;
        default:
          m['msg'] = response.body;
          break;
      }
    } catch (error) {
      m['msg'] = '$error';
    }
    m['code'] = statusCode;
    return Model.fromMap(m, converter);
  }

  static Future<Model<T>> post<T>(
    String url,
    Converter<T> converter, {
    String? body,
    Map<String, String>? headers,
  }) async {
    var m = <String, dynamic>{};
    http.Response response;
    int statusCode = 0;
    try {
      response = await http.post(Uri.parse(url), headers: headers, body: body);
      statusCode = response.statusCode;
      switch (statusCode) {
        case 200:
          final body = utf8.decode(response.bodyBytes);
          m['xml'] = XmlDocument.parse(body);
          break;
        default:
          m['msg'] = response.body;
          break;
      }
    } catch (error) {
      m['msg'] = '$error';
    }
    m['code'] = statusCode;
    return Model.fromMap(m, converter);
  }
}

class Model<T> {
  final int code;
  final String msg;
  final T data;
  const Model(this.code, this.msg, this.data);
  factory Model.fromMap(Map<String, dynamic> m, Converter<T> converter) {
    return Model(
        m.containsKey("code") ? m["code"] as int : 0,
        m.containsKey("msg") ? m["msg"] as String : "ok",
        converter(m.containsKey("xml") && m["xml"] != null
            ? m["xml"]
            : XmlDocument()));
  }

  @override
  String toString() {
    return '{code: $code, msg: $msg, data: $data}';
  }
}

typedef Converter<T> = T Function(XmlDocument xml);
