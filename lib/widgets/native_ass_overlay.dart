import 'dart:typed_data';
import 'dart:async';
import 'dart:ffi';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

typedef _OpenNative = Pointer<Void> Function(Pointer<Utf8>, Int32, Pointer<Utf8>);
typedef _Open = Pointer<Void> Function(Pointer<Utf8>, int, Pointer<Utf8>);
typedef _RenderNative = Int32 Function(Pointer<Void>, Int64, Int32, Int32, Pointer<Uint8>);
typedef _Render = int Function(Pointer<Void>, int, int, int, Pointer<Uint8>);

/// A transparent libass plane above the HDR Surface. The native worker demuxes
/// only subtitle packets and fonts; mpv remains the authoritative playback clock.
class NativeAssOverlay extends StatefulWidget {
  final Player player;
  final VideoController controller;
  final VoidCallback onUnavailable;
  const NativeAssOverlay({super.key, required this.player, required this.controller, required this.onUnavailable});
  @override
  State<NativeAssOverlay> createState() => _NativeAssOverlayState();
}

class _NativeAssOverlayState extends State<NativeAssOverlay> {
  late final _Open _open;
  late final _Render _render;
  late final void Function(Pointer<Void>) _close;
  Pointer<Void> _handle = nullptr;
  Pointer<Uint8> _pixels = nullptr;
  Timer? _metadataTimer, _frameTimer;
  StreamSubscription<Duration>? _positionSubscription;
  final _clock = Stopwatch();
  Duration _position = Duration.zero;
  ui.Image? _image;
  int _width = 0, _height = 0, _generation = 0;
  bool _reading = false, _decoding = false, _failed = false;
  String? _source;
  double _delay = 0, _speed = 1;
  bool _visible = true;
  bool _textFallback = true;
  NativePlayer get _native => widget.player.platform as NativePlayer;

  @override
  void initState() {
    super.initState();
    try {
      final library = DynamicLibrary.open('libentry.so');
      _open = library.lookupFunction<_OpenNative, _Open>('aloe_ass_open');
      _render = library.lookupFunction<_RenderNative, _Render>('aloe_ass_render');
      _close = library.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('aloe_ass_close');
      _position = widget.player.state.position;
      _clock.start();
      _positionSubscription = widget.player.stream.position.listen((value) {
        _position = value;
        _clock..reset()..start();
      });
      _metadataTimer = Timer.periodic(const Duration(milliseconds: 400), (_) => _readTrack());
      _frameTimer = Timer.periodic(const Duration(milliseconds: 33), (_) => _frame());
      unawaited(_readTrack());
    } catch (_) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fail());
    }
  }

  void _fail() {
    if (!mounted || _failed) return;
    _failed = true;
    widget.onUnavailable();
  }

  Future<void> _readTrack() async {
    if (_reading || _failed || !mounted) return;
    _reading = true;
    try {
      final path = await _native.getProperty('path');
      final sid = await _native.getProperty('sid');
      final count = int.tryParse(await _native.getProperty('track-list/count')) ?? 0;
      String? source;
      int index = -1;
      String codec = '';
      for (var i = 0; i < count; i++) {
        if (await _native.getProperty('track-list/$i/type') != 'sub') continue;
        if (await _native.getProperty('track-list/$i/selected') != 'yes') continue;
        codec = await _native.getProperty('track-list/$i/codec');
        final external = await _native.getProperty('track-list/$i/external');
        source = external == 'yes'
            ? await _native.getProperty('track-list/$i/external-filename') : path;
        if (external != 'yes') index = int.tryParse(await _native.getProperty('track-list/$i/ff-index')) ?? -1;
        break;
      }
      final delay = double.tryParse(await _native.getProperty('sub-delay')) ?? 0;
      final speed = double.tryParse(await _native.getProperty('sub-speed')) ?? 1;
      final visible = await _native.getProperty('sub-visibility') != 'no';
      if (!mounted || _failed) return;
      _delay = delay;
      _speed = speed > 0 && speed.isFinite ? speed : 1;
      if (_visible != visible) setState(() => _visible = visible);
      if (sid == 'no') source = null;
      final key = source == null ? null : '$path\n$sid\n$source\n$index';
      if (key == _source) return;
      _source = key;
      _clear();
      if (source == null || source.isEmpty) return;
      if (codec != 'ass' && codec != 'ssa') {
        // Plain text remains on Flutter's subtitle plane. Bitmap formats need
        // mpv's texture compositor; do not silently drop selected image tracks.
        if (!const {'subrip', 'srt', 'webvtt', 'text', 'mov_text'}.contains(codec)) _fail();
        return;
      }
      // Reuse the exact authenticated media headers without logging them.
      final playlist = widget.player.state.playlist;
      final headers = playlist.medias.isNotEmpty && playlist.index < playlist.medias.length && playlist.index >= 0
          ? playlist.medias[playlist.index].httpHeaders ?? <String, String>{} : <String, String>{};
      final uri = source.toNativeUtf8();
      final header = headers.entries.where((e) => !e.key.contains(RegExp(r'[\r\n]')) && !e.value.contains(RegExp(r'[\r\n]')))
          .map((e) => '${e.key}: ${e.value}\r\n').join().toNativeUtf8();
      try { _handle = _open(uri, index, header); }
      finally { calloc.free(uri); calloc.free(header); }
      if (_handle == nullptr) _fail();
    } catch (_) {
      if (mounted) _fail();
    } finally { _reading = false; }
  }

  void _clear() {
    _generation++;
    _textFallback = true;
    if (_handle != nullptr) { _close(_handle); _handle = nullptr; }
    final old = _image;
    if (mounted) setState(() => _image = null);
    else _image = null;
    old?.dispose();
  }

  void _frame() {
    if (!mounted || _failed || _handle == nullptr || _decoding) return;
    final video = widget.player.state.videoParams;
    final sourceWidth = video.dw ?? 0, sourceHeight = video.dh ?? 0;
    if (sourceWidth <= 0 || sourceHeight <= 0) return;
    final scale = math.min(1.0, 1920 / math.max(sourceWidth, sourceHeight));
    final width = math.max(1, (sourceWidth * scale).round());
    final height = math.max(1, (sourceHeight * scale).round());
    if (width != _width || height != _height) {
      if (_pixels != nullptr) calloc.free(_pixels);
      _pixels = calloc<Uint8>(width * height * 4);
      _width = width; _height = height;
    }
    final state = widget.player.state;
    final elapsed = state.playing && !state.buffering ? math.min(250, _clock.elapsedMilliseconds) * state.rate : 0;
    final time = ((_position.inMilliseconds + elapsed - _delay * 1000) / _speed).round();
    final result = _render(_handle, time, width, height, _pixels);
    if (result < 0) { _fail(); return; }
    if (result == 0) return;
    if (_textFallback) setState(() => _textFallback = false);
    if (result == 2) return;
    final generation = _generation;
    _decoding = true;
    // Copy before the async decoder: the native buffer may be freed on dispose.
    final bytes = Uint8List.fromList(_pixels.asTypedList(width * height * 4));
    ui.decodeImageFromPixels(bytes, width, height, ui.PixelFormat.rgba8888, (image) {
      _decoding = false;
      if (!mounted || generation != _generation) { image.dispose(); return; }
      final old = _image;
      setState(() => _image = image);
      old?.dispose();
    });
  }

  @override
  void dispose() {
    _metadataTimer?.cancel(); _frameTimer?.cancel();
    _positionSubscription?.cancel();
    _generation++;
    if (_handle != nullptr) _close(_handle);
    if (_pixels != nullptr) calloc.free(_pixels);
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(child: !_visible
      ? const SizedBox.expand()
      : _textFallback
          ? SubtitleView(controller: widget.controller, configuration: const SubtitleViewConfiguration())
          : _image != null
              ? RawImage(image: _image, fit: BoxFit.contain, filterQuality: FilterQuality.medium)
              : const SizedBox.expand());
}
