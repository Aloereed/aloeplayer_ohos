# FSR 1.0.2 for mpv

`FSR.glsl` is the unmodified AMD FidelityFX Super Resolution 1.0.2 shader,
ported to mpv by agyild. The MIT license and attribution are included in the file.

- Upstream: https://gist.github.com/agyild/82219c545228d70c5604f865ce0b0ce5
- Pinned raw revision: https://gist.githubusercontent.com/agyild/82219c545228d70c5604f865ce0b0ce5/raw/f1794d720013ccd9c5c86a0f20fddd71e0375f94/FSR.glsl
- SHA-256: `56d8597fc6b7bf6d13f8c3b2bdf1cdc43b06175d51746aab44cf1dca16929b9e`

Bundled for offline use. Two spatial passes (EASU + RCAS), not an AI model or
temporal frame generation. This variant operates on SDR luma. The application
skips FSR for HDR/RGB sources and uses the high-quality scaler instead.
The output surface must be larger than the input for its upscale hook to run.
