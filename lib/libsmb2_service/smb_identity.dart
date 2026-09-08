class SmbIdentity {
  final String username, domain;
  const SmbIdentity(this.username, this.domain);
}

SmbIdentity smbIdentity(String username, String domain,
    {bool anonymous = false}) {
  if (anonymous) return const SmbIdentity('', '');
  if (username.contains('\x00') || domain.contains('\x00')) {
    throw const FormatException('SMB 用户名或域包含无效字符');
  }
  final separator = username.indexOf('\\');
  if (separator < 0) return SmbIdentity(username, domain);
  if (separator == 0 ||
      separator == username.length - 1 ||
      username.indexOf('\\', separator + 1) >= 0) {
    throw const FormatException('SMB 域账户格式应为 域名\\用户名');
  }
  final prefix = username.substring(0, separator);
  if (domain.isNotEmpty && prefix.toLowerCase() != domain.toLowerCase()) {
    throw const FormatException('用户名中的域名与域设置不一致');
  }
  return SmbIdentity(
      username.substring(separator + 1), domain.isEmpty ? prefix : domain);
}
