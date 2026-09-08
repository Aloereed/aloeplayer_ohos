import 'dart:io';
import 'package:xml/xml.dart';
import 'webdav_path.dart';

class WebDavFile {
  final String name;
  final String path;
  final int size;
  final bool isDirectory;
  final DateTime? lastModified;
  final String? contentType;
  final String? etag;
  final bool sizeKnown;

  const WebDavFile(
      {required this.name,
      required this.path,
      required this.size,
      required this.isDirectory,
      this.lastModified,
      this.contentType,
      this.etag,
      this.sizeKnown = true});

  @override
  String toString() =>
      'WebDavFile(name: $name, path: $path, isDir: $isDirectory)';
}

bool _isDav(XmlElement element, String name) =>
    element.name.local == name &&
    (element.namespaceUri == 'DAV:' ||
        element.namespaceUri == null ||
        element.namespaceUri == '');
Iterable<XmlElement> _children(XmlElement element, String name) =>
    element.childElements.where((child) => _isDav(child, name));
String? _text(XmlElement element, String name) =>
    _children(element, name).firstOrNull?.innerText;
int? _status(String? value) => value == null
    ? null
    : int.tryParse(RegExp(r'^HTTP/\S+\s+(\d{3})(?:\s|$)', caseSensitive: false)
            .firstMatch(value.trim())
            ?.group(1) ??
        '');

DateTime? webDavDate(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  try {
    return HttpDate.parse(value.trim());
  } catch (_) {
    return DateTime.tryParse(value.trim());
  }
}

/// Merge only successful propstat blocks, independent of namespace prefixes.
/// A malformed response is an error, never a successful empty directory.
List<WebDavFile> parseWebDavMultiStatus(
    String xml, String baseUrl, String requestUrl) {
  final paths = WebDavPaths(baseUrl);
  final request = Uri.parse(requestUrl);
  final requestedPath = paths.fromHref(request.toString(), request);
  final root = XmlDocument.parse(xml).rootElement;
  if (!_isDav(root, 'multistatus'))
    throw const FormatException('服务器未返回 WebDAV multistatus XML');
  final files = <String, WebDavFile>{};
  for (final response in _children(root, 'response')) {
    final href = _text(response, 'href');
    if (href == null) continue;
    final path = paths.fromHref(href, request);
    if (path == null) continue;
    final status = _status(_text(response, 'status'));
    if (status != null && (status < 200 || status >= 300)) {
      if (path == requestedPath)
        throw StateError('WebDAV 资源访问失败（HTTP $status）');
      continue;
    }
    final properties = <String, XmlElement>{};
    int? propertyFailure;
    for (final propstat in _children(response, 'propstat')) {
      final code = _status(_text(propstat, 'status'));
      if (code == null || code < 200 || code >= 300) {
        propertyFailure ??= code;
        continue;
      }
      for (final prop in _children(propstat, 'prop')) {
        for (final item in prop.childElements) {
          if (_isDav(item, item.name.local)) properties[item.name.local] = item;
        }
      }
    }
    if (properties.isEmpty) {
      if (path == requestedPath && propertyFailure != null) {
        throw StateError('WebDAV 无法读取资源属性（HTTP $propertyFailure）');
      }
      continue;
    }
    final resourceType = properties['resourcetype'];
    final directory = resourceType != null
        ? _children(resourceType, 'collection').isNotEmpty
        : href.endsWith('/');
    final size =
        int.tryParse(properties['getcontentlength']?.innerText.trim() ?? '');
    final displayName = properties['displayname']?.innerText;
    files[path] = WebDavFile(
        name: displayName != null && displayName.trim().isNotEmpty
            ? displayName
            : path.split('/').last,
        path: path,
        size: size != null && size >= 0 ? size : 0,
        sizeKnown: directory || (size != null && size >= 0),
        isDirectory: directory,
        lastModified: webDavDate(properties['getlastmodified']?.innerText),
        contentType: properties['getcontenttype']?.innerText.trim(),
        etag: properties['getetag']?.innerText.trim());
  }
  return files.values.toList();
}
