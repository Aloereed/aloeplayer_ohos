# OHOS native HDR output

This local fork starts from ErBWs/media-kit f609ef6244191d9ceaa6d7b547d76032f1f554af
(media_kit_video 1.3.1), retaining the project's output-size and texture-disposal fixes.

Opt in with `VideoControllerConfiguration(vo: 'ohcodec', hwdec: 'ohcodec')` and
`PlayerConfiguration(libass: false)`. `Video` mounts an ArkUI XComponent of type
SURFACE instead of a Flutter Texture. OHCodec delivers decoded buffers directly
to that surface; media-kit still owns demuxing, audio, seeking and tracks.
Surface IDs travel as decimal strings without conversion through JavaScript numbers.
The host application must mount the exported ArkUI `MediaKitNativeVideoHost` below
`FlutterPage({ viewId, xComponentColor: Color.Transparent })` in a full-size Stack.
The Dart video widget clears its rectangle with BlendMode.clear and synchronizes
physical bounds with the host. Ordinary OhosView uses RENDER_TYPE_TEXTURE in this
SDK; initExpensiveOhosView is also insufficient because hybrid composition is not
implemented. Neither is used in this implementation.

This requires the OHOS mpv fork's `ohcodec` VO and hardware decoder (both strings
are present in the bundled libmpv.so.2). It is **not** a generic upstream mpv option.
The original GPU/texture mode remains the default. In AloePlayer the switch is in
the collapsed Experimental section at the bottom of the MPV player's settings;
it reopens the current item at the current position. Native mode disables Flutter
backdrop blur and control-bar gradients to avoid veiling the independent video layer.

The direct decoder path avoids GPU tone mapping and SDR Flutter composition. Actual
HDR presentation still depends on codec, bit depth, metadata, display and device
support. Selecting this mode is not evidence that the screen activated HDR.
HDR10/PQ and HLG need on-device validation; HDR Vivid and Dolby Vision are not
claimed supported. There is no silent switch to SDR if hardware decoding fails.
Switch off native HDR to recover software decoding / GPU tone mapping.

Limitations: text subtitles use Flutter's subtitle layer; styled ASS, GPU shaders,
color adjustments and GPU screenshot capture are unavailable in direct output.
Only one native Video may be mounted in the host. Do not place it inside Opacity,
FadeTransition, or another offscreen saveLayer. Platform clipping, transforms,
overlays, rotation and background restoration need validation on physical devices.

Acceptance checks on an HDR-capable physical device:

- Play HDR10 HEVC Main10 and HLG samples; check `current-vo=ohcodec` and
  `hwdec-current=ohcodec`, source transfer function / pixel format, and the device's
  actual HDR presentation. Compare against the system player using the same sample.
- Repeat with SDR, unsupported codecs and a software-decoding-only sample.
- Seek repeatedly, pause/resume, change tracks and playlist items, rotate, background
  and foreground the app, leave and reopen the page, and toggle back to ordinary mode.
- Check subtitles, controls and danmaku overlay without covering or converting HDR.
- Verify rapid surface replacement does not detach a newer surface via an old view.

References: [mpv OHOS surface binding](https://github.com/dex2oat/mpv/blob/master/video/out/ohos_common.c),
[OHOS NativeWindow HDR metadata APIs](https://developer.huawei.com/consumer/en/doc/harmonyos-references-V13/external__window_8h-V13).
