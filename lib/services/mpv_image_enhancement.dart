import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'serial_executor.dart';

enum UpscaleMode { off, highQuality, fsr1080, fsr4k }

extension UpscaleModeLabel on UpscaleMode {
  String get label => switch (this) {
    UpscaleMode.off => '原始画质', UpscaleMode.highQuality => '高清缩放',
    UpscaleMode.fsr1080 => 'FSR 超分 · 均衡', UpscaleMode.fsr4k => 'FSR 超分 · 高画质',
  };
  String get description => switch (this) {
    UpscaleMode.off => '保持播放器默认渲染',
    UpscaleMode.highQuality => 'Lanczos 高质量缩放，最高 1080p 输出',
    UpscaleMode.fsr1080 => '边缘重建与自适应锐化，最高 1080p 输出',
    UpscaleMode.fsr4k => '最高 4K 输出，需要更强 GPU，功耗更高',
  };
  bool get isFsr => this == UpscaleMode.fsr1080 || this == UpscaleMode.fsr4k;
}

class ImageEnhancementSettings {
  final UpscaleMode mode;
  final bool deband;
  final double brightness, contrast, saturation, gamma;
  const ImageEnhancementSettings({this.mode = UpscaleMode.off, this.deband = false,
    this.brightness = 0, this.contrast = 0, this.saturation = 0, this.gamma = 0});
  bool get isDefault => mode == UpscaleMode.off && !deband && brightness == 0 && contrast == 0 && saturation == 0 && gamma == 0;
  ImageEnhancementSettings copyWith({UpscaleMode? mode, bool? deband, double? brightness,
    double? contrast, double? saturation, double? gamma}) => ImageEnhancementSettings(
      mode: mode ?? this.mode, deband: deband ?? this.deband, brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast, saturation: saturation ?? this.saturation, gamma: gamma ?? this.gamma);
  Map<String, Object> toJson() => {'mode': mode.name, 'deband': deband, 'brightness': brightness,
    'contrast': contrast, 'saturation': saturation, 'gamma': gamma};
  factory ImageEnhancementSettings.fromJson(Map<String, dynamic> json) {
    double number(String key) { final n = json[key]; return n is num && n.isFinite ? n.toDouble().clamp(-50, 50) : 0; }
    return ImageEnhancementSettings(mode: UpscaleMode.values.where((m) => m.name == json['mode']).firstOrNull ?? UpscaleMode.off,
      deband: json['deband'] == true, brightness: number('brightness'), contrast: number('contrast'),
      saturation: number('saturation'), gamma: number('gamma'));
  }
}

/// Keep aspect ratio, cap each axis and never downscale an already large source.
({int width, int height})? enhancedOutputSize(UpscaleMode mode, int width, int height) {
  if (mode == UpscaleMode.off || width <= 0 || height <= 0) return null;
  final longLimit = mode == UpscaleMode.fsr4k ? 3840 : 1920;
  final shortLimit = mode == UpscaleMode.fsr4k ? 2160 : 1080;
  final scale = math.min(2.0, math.min(longLimit / math.max(width, height), shortLimit / math.min(width, height)));
  if (scale <= 1.01) return null;
  return (width: ((width * scale) / 2).floor() * 2, height: ((height * scale) / 2).floor() * 2);
}

abstract interface class MpvImageBackend {
  Future<String> read(String property);
  Future<void> write(String property, String value);
  Future<void> resize(int? width, int? height);
}

class MpvImageEnhancer extends ChangeNotifier {
  final MpvImageBackend backend;
  final Future<String> Function() shaderPath;
  final SerialExecutor _serial = SerialExecutor();
  final Map<String, String> _original = {}, _applied = {};
  static const _key = 'mpv.image-enhancement.v1';
  ImageEnhancementSettings settings = const ImageEnhancementSettings();
  ImageEnhancementSettings _desired = const ImageEnhancementSettings();
  bool busy = false, _disposed = false, _initialized = false;
  int _width = 0, _height = 0;
  bool _hdr = false, _rgb = false;
  String status = '保持播放器默认渲染';
  String? error;
  MpvImageEnhancer({required this.backend, Future<String> Function()? shaderPath}) : shaderPath = shaderPath ?? _installShader;

  Future<void> initialize() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw != null) settings = ImageEnhancementSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) { settings = const ImageEnhancementSettings(); }
    _initialized = true;
    if (!_disposed) await apply(settings, save: false);
  }
  void videoChanged({required int width, required int height, String? gamma, String? format}) {
    final hdr = ['pq', 'smpte2084', 'hlg', 'arib-std-b67'].contains(gamma?.toLowerCase());
    final rgb = RegExp(r'rgb|bgr|gbr').hasMatch(format?.toLowerCase() ?? '');
    if (_width == width && _height == height && _hdr == hdr && _rgb == rgb) return;
    _width = width; _height = height; _hdr = hdr; _rgb = rgb;
    if (_initialized && !_disposed) apply(_desired, save: false);
  }
  Future<void> _snapshot() async {
    if (_original.isNotEmpty) return;
    for (final key in ['scale', 'cscale', 'deband', 'glsl-shaders', 'brightness', 'contrast', 'saturation', 'gamma']) {
      if (_disposed) return;
      final value = await backend.read(key);
      if (value.isNotEmpty || key == 'glsl-shaders') _original[key] = value;
    }
    _applied.addAll(_original);
  }
  Future<void> _set(String key, String value) async {
    if (_disposed || _applied[key] == value) return;
    await backend.write(key, value);
    if (_disposed) return;
    final readback = await backend.read(key);
    final equal = readback == value || (double.tryParse(value) != null && double.tryParse(readback) == double.tryParse(value));
    if (!equal) throw StateError('当前渲染器不支持 $key');
    _applied[key] = value;
  }
  Future<void> _restore() async {
    for (final entry in _original.entries) {
      if (_disposed) return;
      try { await backend.write(entry.key, entry.value); } catch (_) {}
    }
    if (!_disposed) { try { await backend.resize(null, null); } catch (_) {} }
    _applied..clear()..addAll(_original);
  }
  Future<void> apply(ImageEnhancementSettings next, {bool save = true}) {
    _desired = next;
    return _serial.run(() async {
    if (_disposed) return;
    busy = true; error = null; notifyListeners();
    try {
      if (!next.isDefault || _original.isNotEmpty) {
        await _snapshot();
        final mode = next.mode.isFsr && (_hdr || _rgb) ? UpscaleMode.highQuality : next.mode;
        final size = enhancedOutputSize(mode, _width, _height);
        var shaders = _original['glsl-shaders'] ?? '';
        if (mode.isFsr && size != null) {
          final file = await shaderPath();
          shaders = shaders.isEmpty ? file : '$shaders${Platform.isWindows ? ';' : ':'}$file';
        }
        await _set('glsl-shaders', shaders);
        await _set('scale', mode == UpscaleMode.off ? (_original['scale'] ?? 'lanczos') : 'ewa_lanczossharp');
        await _set('cscale', mode == UpscaleMode.off ? (_original['cscale'] ?? 'bilinear') : 'lanczos');
        await _set('deband', next.deband ? 'yes' : (_original['deband'] ?? 'no'));
        for (final entry in {'brightness': next.brightness, 'contrast': next.contrast,
          'saturation': next.saturation, 'gamma': next.gamma}.entries) {
          await _set(entry.key, entry.value == 0 ? (_original[entry.key] ?? '0') : entry.value.round().toString());
        }
        if (!_disposed) await backend.resize(size?.width, size?.height);
        status = size == null ? (mode == UpscaleMode.off ? '保持原始输出尺寸' : '视频已达到本档输出上限，无需放大')
          : '$_width × $_height → ${size.width} × ${size.height}';
        if (next.mode.isFsr && (_hdr || _rgb)) status = '${_hdr ? 'HDR' : 'RGB'} 视频使用高清缩放，跳过 SDR 超分着色器';
        if (_width == 0 || _height == 0) status = '等待视频画面后应用';
      } else { status = '保持播放器默认渲染'; }
      settings = next;
    } catch (_) {
      await _restore();
      settings = const ImageEnhancementSettings();
      if (identical(_desired, next)) _desired = settings;
      error = '此设备未能应用画质增强，已恢复默认画质';
      status = '默认画质';
    } finally {
      if (save && !_disposed) {
        try { await (await SharedPreferences.getInstance()).setString(_key, jsonEncode(settings.toJson())); }
        catch (_) { error ??= '当前画质已应用，但无法保存设置'; }
      }
      if (!_disposed) { busy = false; notifyListeners(); }
    }
    });
  }
  Future<void> shaderFailed() async {
    if (_disposed || settings.isDefault) return;
    await apply(const ImageEnhancementSettings());
    if (!_disposed) { error = 'GPU 着色器运行失败，已恢复默认画质'; notifyListeners(); }
  }
  @override void dispose() { _disposed = true; super.dispose(); }

  static Future<String> _installShader() async {
    const digest = '56d8597fc6b7bf6d13f8c3b2bdf1cdc43b06175d51746aab44cf1dca16929b9e';
    final directory = Directory('${(await getApplicationSupportDirectory()).path}/shaders');
    await directory.create(recursive: true);
    final file = File('${directory.path}/FSR-v1-$digest.glsl');
    if (await file.exists() && sha256.convert(await file.readAsBytes()).toString() == digest) return file.path;
    final data = await rootBundle.load('Assets/shaders/FSR.glsl');
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    if (sha256.convert(bytes).toString() != digest) throw StateError('Shader integrity check failed');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
