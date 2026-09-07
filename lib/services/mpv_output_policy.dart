enum MpvOutputMode { automatic, direct, texture }

bool isMpvHdrGamma(String? gamma) => const {
  'pq', 'smpte2084', 'hlg', 'arib-std-b67',
}.contains(gamma?.toLowerCase());

bool useMpvDirectOutput({required bool ohos, required bool hdr,
  required MpvOutputMode mode, required bool textureFeature, required bool failed}) =>
    ohos && !textureFeature && !failed &&
    (mode == MpvOutputMode.direct || (mode == MpvOutputMode.automatic && hdr));
