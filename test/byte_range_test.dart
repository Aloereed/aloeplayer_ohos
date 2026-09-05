import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/byte_range.dart';

void main() {
  test('explicit, open and suffix ranges preserve inclusive bounds', () {
    expect(ByteRange.parse('bytes=20-29', 100)!.length, 10);
    expect(ByteRange.parse('bytes=20-', 100)!.end, 99);
    expect(ByteRange.parse('bytes=-20', 100)!.start, 80);
    expect(ByteRange.parse('bytes=-200', 100)!.start, 0);
    expect(ByteRange.parse('bytes=20-200', 100)!.end, 99);
  });
  test('invalid, multiple and unsatisfiable ranges are rejected', () {
    for (final input in ['bytes=-', 'bytes=-0', 'bytes=100-', 'bytes=40-20', 'bytes=0-1,3-4', 'bytes=0-1junk']) {
      expect(ByteRange.parse(input, 100), isNull, reason: input);
    }
    expect(ByteRange.parse('bytes=0-', 0), isNull);
  });
}
