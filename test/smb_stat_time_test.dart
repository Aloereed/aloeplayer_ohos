import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/libsmb2_service/smb_stat_time.dart';

void main() {
  test('native SMB stat timestamps preserve Unix epoch and fractional revision', () {
    expect(smbStatTime(1700000000, 123000000).millisecondsSinceEpoch, 1700000000123);
    expect(smbStatTime(0, 0), DateTime.utc(1970));
    expect(smbStatTime(1700000000, 456000000).difference(smbStatTime(1700000000, 123000000)).inMilliseconds, 333);
  });
}
