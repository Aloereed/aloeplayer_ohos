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


# Anime4K v4.0.1

The unmodified GLSL files under `anime4k/` are from
https://github.com/bloc97/Anime4K at commit
`4029bf701ecaa15f163cdc49cffe5501c1acf410` (v4.0.1).
`anime4k/manifest.json` records each original path and SHA-256;
`anime4k/LICENSE` retains the MIT license. The same hashes are compiled into
`lib/services/anime4k_shaders.dart` and checked before loading.

The preset follows upstream Mode A (Fast), in order:
Clamp_Highlights, Restore_CNN_M, Upscale_CNN_x2_M,
AutoDownscalePre_x2, AutoDownscalePre_x4, Upscale_CNN_x2_S.
Reference: https://github.com/bloc97/Anime4K/blob/master/md/Template/GLSL_Windows_Low-end/input.conf

The app caps each axis at 2x and output at 4K (including portrait), enables the
chain only when the output exceeds the source by 1.2x as required by its upscale
hooks, and skips the chain on HDR/RGB video. FSR and Anime4K are mutually exclusive.
