import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/libsmb2_service/smb_path.dart';

void main() {
  test('separate initial path is not decoded as part of an SMB URL', () {
    final value =
        smbConnectionAddress('smb://nas/Share%20Name', '/100% #中文/literal%20');
    final address = SmbAddress.parse(value);
    expect(address.share, 'Share Name');
    expect(address.basePath, '100% #中文/literal%20');
    expect(SmbAddress.parse(smbConnectionAddress('nas', '/Videos')).share,
        'Videos');
    expect(() => smbConnectionAddress('nas/Videos', '../escape'),
        throwsFormatException);
  });
  test('SMB accepts bare hosts, UNC, URLs, ports and nested roots', () {
    for (final value in ['nas', '//nas/', 'smb://nas/', r'\\nas\']) {
      final address = SmbAddress.parse(value);
      expect(address.server, 'nas');
      expect(address.share, isNull);
    }
    final unc = SmbAddress.parse(r'\\nas\影视\动画\第一季');
    expect(unc.share, '影视');
    expect(unc.basePath, '动画/第一季');
    final url = SmbAddress.parse('smb://[::1]:1445/Movies/100%25%20%23%3F');
    expect(url.server, '[::1]:1445');
    expect(url.share, 'Movies');
    expect(url.basePath, '100% #?');
    expect(SmbAddress.parse('nas/Movies/100%25').basePath, '100%25');
  });
  test('browser paths preserve literal URL characters and stay in the root',
      () {
    expect(smbCanonicalPath('/影视/./第一季/../100%25 #?.mkv'), '/影视/100%25 #?.mkv');
    expect(() => smbCanonicalPath('/../outside'), throwsFormatException);
    expect(() => smbCanonicalPath('/bad\x00file'), throwsFormatException);
    expect(() => SmbAddress.parse('smb://nas/share%2fother'),
        throwsFormatException);
    expect(() => SmbAddress.parse('smb://user:password@nas/'),
        throwsFormatException);
    expect(() => SmbAddress.parse('https://nas/'), throwsFormatException);
  });
}
