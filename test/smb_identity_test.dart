import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/libsmb2_service/smb_identity.dart';

void main() {
  test(
      'Windows domain-qualified credentials are split without altering passwords or UPNs',
      () {
    final identity = smbIdentity(r'WORKGROUP\用户', '');
    expect(identity.username, '用户');
    expect(identity.domain, 'WORKGROUP');
    expect(smbIdentity(r'DOMAIN\user', 'domain').domain, 'domain');
    expect(smbIdentity('user@example.org', '').username, 'user@example.org');
    expect(() => smbIdentity(r'DOMAIN\user', 'other'), throwsFormatException);
    expect(() => smbIdentity('user\x00hidden', ''), throwsFormatException);
  });
  test('anonymous identity omits both user and domain', () {
    final identity = smbIdentity(r'DOMAIN\old', 'DOMAIN', anonymous: true);
    expect(identity.username, isEmpty);
    expect(identity.domain, isEmpty);
  });
}
