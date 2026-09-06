import 'dart:ffi';
import 'package:media_kit/ffi/ffi.dart';
import 'package:media_kit/generated/libmpv/bindings.dart' as mpv;
import 'fsr_diagnostics.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'mpv_image_enhancement.dart';

class PlayerImageBackend implements MpvImageBackend, FsrDiagnosticsBackend {
  final Player player;
  final VideoController controller;
  PlayerImageBackend(this.player, this.controller);
  NativePlayer get _native => player.platform as NativePlayer;
  @override Future<String> read(String property) => _native.getProperty(property);
  @override Future<void> write(String property, String value) => _native.setProperty(property, value);
  @override Future<void> resize(int? width, int? height) => controller.setSize(width: width, height: height);

  @override
  Future<Map<String, Object?>> fsrSnapshot() async {
    final native = _native;
    await native.handle;
    // All native reads below are synchronous: no disposal can interleave after
    // checking the context. Free both failed reads and successful node trees.
    if (native.disposed || native.ctx == nullptr) return {'passEvidence': 'player_disposed'};
    String? readString(String property) {
      final name = property.toNativeUtf8();
      Pointer<Int8> value = nullptr;
      try {
        value = native.mpv.mpv_get_property_string(native.ctx, name.cast());
        return value == nullptr ? null : value.cast<Utf8>().toDartString();
      } finally {
        if (value != nullptr) native.mpv.mpv_free(value.cast());
        calloc.free(name);
      }
    }
    final result = <String, Object?>{};
    for (final property in ['current-vo', 'hwdec-current', 'video-params/pixelformat',
      'video-params/gamma', 'video-out-params/w', 'video-out-params/h',
      'video-target-params/w', 'video-target-params/h', 'osd-width', 'osd-height',
      'frame-drop-count', 'decoder-frame-drop-count']) {
      result[property] = readString(property);
    }
    final shaders = readString('glsl-shaders');
    result['fsrShaderListed'] = shaders == null ? null : RegExp(r'FSR(?:-v1-[a-f0-9]+)?\.glsl').hasMatch(shaders);
    result['anime4kShaderFiles'] = shaders == null ? null : RegExp(r'Anime4K_[A-Za-z0-9_]+\.glsl')
        .allMatches(shaders).map((match) => match.group(0)!).toSet().toList();
    final rect = controller.rect.value;
    result['textureWidth'] = rect?.width;
    result['textureHeight'] = rect?.height;
    final name = 'vo-passes'.toNativeUtf8();
    final node = calloc<mpv.mpv_node>();
    var success = false;
    try {
      final code = native.mpv.mpv_get_property(native.ctx, name.cast(), mpv.mpv_format.MPV_FORMAT_NODE, node.cast());
      success = code >= 0;
      result['passesReadCode'] = code;
      final passes = success ? _nodeValue(node.ref, 0) : null;
      result.addAll(summarizeFsrPasses(passes));
      result.addAll(summarizeAnime4kPasses(passes));
    } finally {
      if (success) native.mpv.mpv_free_node_contents(node);
      calloc.free(node);
      calloc.free(name);
    }
    return result;
  }

  Object? _nodeValue(mpv.mpv_node node, int depth) {
    if (depth > 5) return null;
    switch (node.format) {
      case mpv.mpv_format.MPV_FORMAT_STRING:
        return node.u.string == nullptr ? null : node.u.string.cast<Utf8>().toDartString();
      case mpv.mpv_format.MPV_FORMAT_INT64:
        return node.u.int64;
      case mpv.mpv_format.MPV_FORMAT_DOUBLE:
        return node.u.double_;
      case mpv.mpv_format.MPV_FORMAT_NODE_ARRAY:
        if (node.u.list == nullptr) return null;
        final list = node.u.list.ref;
        return [for (var i = 0; i < list.num && i < 64; i++) _nodeValue(list.values[i], depth + 1)];
      case mpv.mpv_format.MPV_FORMAT_NODE_MAP:
        if (node.u.list == nullptr) return null;
        final list = node.u.list.ref;
        final result = <String, Object?>{};
        for (var i = 0; i < list.num && i < 64; i++) {
          final key = list.keys[i].cast<Utf8>().toDartString();
          // Omit raw samples, media names, URLs and unrelated properties.
          if (const ['fresh', 'redraw', 'desc', 'last', 'avg', 'peak', 'count'].contains(key)) {
            result[key] = _nodeValue(list.values[i], depth + 1);
          }
        }
        return result;
      default: return null;
    }
  }
}
