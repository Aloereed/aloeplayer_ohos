import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/mpv_output_policy.dart';

void main() {
  test('HDR transfer functions cover PQ and HLG aliases, SDR stays textured', () {
    for (final gamma in ['pq', 'smpte2084', 'HLG', 'arib-std-b67']) {
      expect(isMpvHdrGamma(gamma), isTrue);
    }
    for (final gamma in [null, '', 'bt.1886', 'srgb', 'gamma2.2']) {
      expect(isMpvHdrGamma(gamma), isFalse);
    }
  });
  test('SDR defaults to texture and can be switched to direct for debugging', () {
    bool direct(MpvOutputMode mode, {bool hdr = false, bool feature = false, bool failed = false}) =>
      useMpvDirectOutput(ohos: true, hdr: hdr, mode: mode, textureFeature: feature, failed: failed);
    expect(direct(MpvOutputMode.automatic), isFalse);
    expect(direct(MpvOutputMode.direct), isTrue);
    expect(direct(MpvOutputMode.automatic, hdr: true), isTrue);
    expect(direct(MpvOutputMode.texture, hdr: true), isFalse);
    expect(direct(MpvOutputMode.direct, feature: true), isFalse);
    expect(direct(MpvOutputMode.direct, failed: true), isFalse);
    expect(useMpvDirectOutput(ohos: false, hdr: true, mode: MpvOutputMode.direct,
      textureFeature: false, failed: false), isFalse);
  });
}
