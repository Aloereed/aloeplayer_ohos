/// SMB addresses are decoded once at the input boundary. Browser paths are
/// ordinary filenames, not URLs: a literal percent sign must remain literal.
class SmbAddress {
  final String server;
  final String? share;
  final String basePath;

  const SmbAddress(this.server, this.share, this.basePath);

  factory SmbAddress.parse(String input) {
    var value = input.trim().replaceAll('\\', '/');
    final isUrl = value.toLowerCase().startsWith('smb://');
    if (isUrl) value = value.substring(6);
    if (value.contains('://')) throw const FormatException('请使用 SMB 地址');
    value = value.replaceFirst(RegExp(r'^/+'), '');
    final slash = value.indexOf('/');
    final server = slash < 0 ? value : value.substring(0, slash);
    if (server.isEmpty || server.contains(RegExp(r'[\s@?#\x00]'))) {
      throw const FormatException('SMB 主机地址无效，请在用户名和密码栏填写凭据');
    }
    var path = slash < 0 ? '' : value.substring(slash + 1);
    if (isUrl) {
      path = path.split('/').map((part) {
        final decoded = Uri.decodeComponent(part);
        if (decoded.contains('/') || decoded.contains('\\')) {
          throw const FormatException('SMB 文件名不能包含编码后的路径分隔符');
        }
        return decoded;
      }).join('/');
    }
    final parts = smbPathSegments(path);
    return SmbAddress(
        server, parts.isEmpty ? null : parts.first, parts.skip(1).join('/'));
  }
}

List<String> smbPathSegments(String path) {
  if (path.contains('\x00')) throw const FormatException('SMB 路径包含无效字符');
  final parts = <String>[];
  for (final part in path.replaceAll('\\', '/').split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (parts.isEmpty) throw const FormatException('SMB 路径超出根目录');
      parts.removeLast();
    } else {
      parts.add(part);
    }
  }
  return parts;
}

String smbCanonicalPath(String path) => '/${smbPathSegments(path).join('/')}';

/// Host URLs are encoded input, while a separately entered initial folder is
/// a logical filename. Join only after decoding the host, then use UNC form
/// so the native adapter never decodes a literal percent sign twice.
String smbConnectionAddress(String host, String initialPath) {
  final address = SmbAddress.parse(host);
  final parts = [
    if (address.share != null) address.share!,
    ...smbPathSegments(address.basePath),
    ...smbPathSegments(initialPath),
  ];
  return '//${address.server}/${parts.join('/')}';
}
