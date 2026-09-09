# Aloe MPV direct Surface port

Independent recipe for current tpc/lycium. All sources, dependencies, tools,
SDK, and build outputs are Linux-local; do not use /mnt drives for this build.

Run from ~/tpc_c_cplusplus-current/lycium:

    OHOS_SDK=$HOME/command-line-tools/sdk/default/openharmony bash build.sh aloe-mpv-direct

Install prefix: lycium/usr/aloe-mpv-direct/arm64-v8a.
Source revisions and FFmpeg archive hash: sources.json.

The added vo=ohcodec accepts upstream OHCodec one-shot frame tokens, renders
on mpv flip_page scheduling, and keeps VO_CAP_NORETAIN without UNTIMED.
PQ/HLG color and HDR metadata use upstream ohos_common.c. Repeated/redraw
frames are not resubmitted; reset, reconfigure, initialization failure, and
uninit release pending frames and owned resources.

Run python3 test_direct_lifecycle.py for ASan/UBSan host mock lifecycle tests.
This does not validate actual HarmonyOS decoder, HDR brightness, Surface
presentation, or EOF playback. Device tests are required before calling the
port production-ready. The working Windows app binary has not been replaced.

Dependencies: reuse current tpc static libraries where available; build a
private glslang, upstream patched libplacebo and upstream FFmpeg into the
separate prefix. Vulkan shader compilation uses glslang rather than shaderc.
The actual dependency closure must be checked after the shared library links.
