import 'dart:io';

/// libsmb2 splits unbracketed input at the first colon. Normalize IPv6 before
/// it reaches native code, and reject invalid ports without a network roundtrip.
String smbAuthority(String input, {bool url = false}) {
  var host = input;
  String? port;
  var ipv6 = false;
  if (input.startsWith('[')) {
    final close = input.indexOf(']');
    if (close < 0) throw const FormatException('SMB IPv6 地址缺少右方括号');
    host = input.substring(1, close);
    final suffix = input.substring(close + 1);
    if (suffix.isNotEmpty) {
      if (!suffix.startsWith(':'))
        throw const FormatException('SMB IPv6 地址后只能填写端口');
      port = suffix.substring(1);
    }
    ipv6 = true;
  } else {
    if (input.contains('[') || input.contains(']'))
      throw const FormatException('SMB 地址方括号无效');
    final colons = ':'.allMatches(input).length;
    if (colons > 1) {
      ipv6 = true;
    } else if (colons == 1) {
      final separator = input.indexOf(':');
      host = input.substring(0, separator);
      port = input.substring(separator + 1);
    }
  }
  if (host.isEmpty) throw const FormatException('SMB 主机地址不能为空');
  if (port != null) {
    final number = int.tryParse(port);
    if (!RegExp(r'^\d+$').hasMatch(port) ||
        number == null ||
        number < 1 ||
        number > 65535) {
      throw const FormatException('SMB 端口应为 1 到 65535；IPv6 加端口时请使用 [地址]:端口');
    }
    port = '$number';
  }
  if (ipv6) {
    if (url) host = host.replaceFirst('%25', '%');
    final scope = host.split('%');
    if (scope.length > 2 ||
        (scope.length == 2 && !RegExp(r'^[\w.-]+$').hasMatch(scope[1])) ||
        InternetAddress.tryParse(scope.first)?.type !=
            InternetAddressType.IPv6) {
      throw const FormatException('SMB IPv6 地址格式无效');
    }
    host = '[$host]';
  }
  return port == null ? host : '$host:$port';
}
