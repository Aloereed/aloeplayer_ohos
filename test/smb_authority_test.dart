import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/libsmb2_service/smb_authority.dart';

void main() {
  test('SMB normalizes IPv6, scoped literals and custom ports', () {
    expect(smbAuthority('::1'), '[::1]');
    expect(smbAuthority('[2001:db8::1]:1445'), '[2001:db8::1]:1445');
    expect(smbAuthority('fe80::1%12'), '[fe80::1%12]');
    expect(
        smbAuthority('[fe80::1%25eth0]:445', url: true), '[fe80::1%eth0]:445');
    expect(smbAuthority('nas:0445'), 'nas:445');
    expect(smbAuthority('NAS_Name'), 'NAS_Name');
  });
  test('SMB rejects malformed ports and IPv6 authorities before connecting',
      () {
    for (final value in [
      'nas:0',
      'nas:65536',
      'nas:abc',
      ':445',
      '[::1',
      '[nas]',
      '[::1]junk',
      '[::1]:',
      'bad:host:value'
    ]) {
      expect(() => smbAuthority(value), throwsFormatException, reason: value);
    }
  });
}
