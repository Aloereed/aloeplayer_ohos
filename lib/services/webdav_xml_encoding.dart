import 'dart:convert';
import 'dart:typed_data';

/// XML permits UTF-8 and UTF-16; older DAV servers also label Latin-1.
/// Decode before parsing so non-UTF-8 filenames are not silently corrupted.
String decodeWebDavXml(Uint8List bytes, {String? contentType}) {
  final httpEncoding =
      RegExp(r'''charset\s*=\s*["']?([^;\s"']+)''', caseSensitive: false)
          .firstMatch(contentType ?? '')
          ?.group(1)
          ?.toLowerCase();
  if (bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf) {
    return utf8.decode(bytes); // BOM takes precedence over a conflicting label.
  }
  var offset = 0;
  Endian? endian;
  if (bytes.length >= 2) {
    if (bytes[0] == 0xff && bytes[1] == 0xfe) {
      endian = Endian.little;
      offset = 2;
    }
    if (bytes[0] == 0xfe && bytes[1] == 0xff) {
      endian = Endian.big;
      offset = 2;
    }
    if (endian == null) {
      if ({'utf-16le', 'utf16le'}.contains(httpEncoding))
        endian = Endian.little;
      if ({'utf-16be', 'utf16be'}.contains(httpEncoding)) endian = Endian.big;
    }
    if (endian == null) {
      const starts = {0x3c, 0x20, 0x09, 0x0a, 0x0d};
      if (starts.contains(bytes[0]) && bytes[1] == 0) endian = Endian.little;
      if (bytes[0] == 0 && starts.contains(bytes[1])) endian = Endian.big;
    }
  }
  if (endian != null) {
    if ((bytes.length - offset).isOdd)
      throw const FormatException('WebDAV UTF-16 XML 数据不完整');
    final data = ByteData.sublistView(bytes);
    // Packed 16-bit units avoid allocating a pointer-sized int list for a
    // large UTF-16 directory response.
    final units = Uint16List((bytes.length - offset) ~/ 2);
    for (var i = 0; i < units.length; i++) {
      units[i] = data.getUint16(offset + 2 * i, endian);
    }
    return String.fromCharCodes(units);
  }
  final declaration = String.fromCharCodes(bytes.take(256));
  final xmlEncoding = RegExp(
          r'''^\s*<\?xml\s+[^>]*encoding\s*=\s*["']([^"']+)["']''',
          caseSensitive: false)
      .firstMatch(declaration)
      ?.group(1);
  final encoding = (httpEncoding ?? xmlEncoding ?? 'utf-8').toLowerCase();
  if ({'iso-8859-1', 'latin1', 'latin-1'}.contains(encoding))
    return latin1.decode(bytes);
  if (!{'utf-8', 'utf8', 'us-ascii', 'ascii'}.contains(encoding)) {
    throw FormatException('不支持的 WebDAV XML 编码：$encoding');
  }
  return utf8.decode(bytes);
}
