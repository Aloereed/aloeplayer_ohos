/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:io';
import 'dart:async';
import 'dart:collection';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';

import 'package:media_kit/media_kit.dart';

import 'package:media_kit_video/src/video_controller/platform_video_controller.dart';

/// {@template ohos_video_controller}
///
/// OhosVideoController
/// ----------------------
///
/// The [PlatformVideoController] implementation based on native C/C++ used on Ohos.
///
/// {@endtemplate}
class OhosVideoController extends PlatformVideoController {
  /// OHCodec sends decoded buffers directly to an ArkUI Surface. A Flutter
  /// texture cannot preserve the system HDR presentation path.
  bool get usesNativeSurface => configuration.vo == 'ohcodec';
  bool _disposed = false;
  int? _nativeViewId;
  String? _nativeSurfaceId;
  final nativeSurfaceError = ValueNotifier<String?>(null);

  Future<void> createNativeSurface(int viewId) => lock.synchronized(() async {
    if (_disposed || platform.disposed) return;
    if (_nativeViewId != null && _nativeViewId != viewId) {
      throw StateError('Only one native Video may use this controller.');
    }
    _nativeViewId = viewId;
    try {
      await _channel.invokeMethod('NativeSurface.Create', {
        'handle': (await player.handle).toString(), 'viewId': viewId,
      });
    } catch (_) {
      _nativeViewId = null;
      rethrow;
    }
  });

  Future<void> updateNativeRect(int viewId, Rect rect) => lock.synchronized(() async {
    if (_disposed || platform.disposed || _nativeViewId != viewId) return;
    await _channel.invokeMethod('NativeSurface.SetRect', {
      'handle': (await player.handle).toString(), 'viewId': viewId,
      'left': rect.left, 'top': rect.top, 'width': rect.width, 'height': rect.height,
    });
  });

  Future<void> attachNativeSurface(int viewId, String surfaceId) =>
      lock.synchronized(() async {
        if (_disposed || platform.disposed || !usesNativeSurface || _nativeViewId != viewId) return;
        final parsed = BigInt.tryParse(surfaceId);
        if (parsed == null || parsed <= BigInt.zero || parsed.bitLength > 63) {
          throw ArgumentError('Invalid OHOS surface ID');
        }
        if (_nativeViewId == viewId && _nativeSurfaceId == surfaceId) return;
        // Tear down the old VO before changing its native window.
        await setProperty('vo', 'null');
        await setProperty('wid', surfaceId);
        await setProperty('hwdec', 'ohcodec');
        await setProperty('vo', 'ohcodec');
        _nativeSurfaceId = surfaceId;
        if (player.state.duration > Duration.zero) {
          await player.seek(player.state.position);
        }
      });

  Future<void> detachNativeSurface(int viewId) => lock.synchronized(() async {
        if (_disposed || platform.disposed || _nativeViewId != viewId) return;
        await setProperty('vo', 'null');
        await setProperty('wid', '0');
        await _channel.invokeMethod('NativeSurface.Dispose', {
          'handle': (await player.handle).toString(), 'viewId': viewId,
        });
        _nativeViewId = null;
        _nativeSurfaceId = null;
      });
  /// Whether [OhosVideoController] is supported on the current platform or not.
  static bool get supported => Platform.operatingSystem == 'ohos';

  /// Pointer address to the global object reference of `OHNativeWindow`.
  final ValueNotifier<int?> wid = ValueNotifier<int?>(null);

  /// [Lock] used to synchronize [onLoadHooks], [onUnloadHooks] & [subscription].
  final lock = Lock();

  NativePlayer get platform => player.platform as NativePlayer;

  Future<void> setProperty(String key, String value) async {
    await platform.setProperty(key, value, waitForInitialization: false);
  }

  Future<void> setProperties(Map<String, String> properties) async {
    for (final entry in properties.entries) {
      await setProperty(entry.key, entry.value);
    }
  }

  /// Listener for updating the --wid property.
  Future<void> widListener() {
    return lock.synchronized(() async {
      final widValue = wid.value?.toString() ?? '0';
      await setProperties({'wid': widValue});
      // Instead of seeking to the start (Duration.zero), seek to the current playback position
      // without jumping the user to the start of the media.
      final currentPosition = player.state.position;
      await player.seek(currentPosition);
    });
  }

  /// [StreamSubscription] for listening to video [Rect].
  StreamSubscription<VideoParams>? videoParamsSubscription;
  int? _requestedWidth, _requestedHeight;
  int _sourceWidth = 0, _sourceHeight = 0;

  /// {@macro ohos_video_controller}
  OhosVideoController._(
    super.player,
    super.configuration,
  ) {
    wid.addListener(widListener);
    videoParamsSubscription = player.stream.videoParams.listen(
      (event) => lock.synchronized(() async {
        if (_disposed) return;
        final int sourceWidth;
        final int sourceHeight;
        if (event.rotate == 0 || event.rotate == 180) {
          sourceWidth = event.dw ?? 0;
          sourceHeight = event.dh ?? 0;
        } else {
          // width & height are swapped for 90 or 270 degrees rotation.
          sourceWidth = event.dh ?? 0;
          sourceHeight = event.dw ?? 0;
        }

        _sourceWidth = sourceWidth;
        _sourceHeight = sourceHeight;
        final width = _requestedWidth ?? sourceWidth;
        final height = _requestedHeight ?? sourceHeight;
        final isZero = width == 0 || height == 0;
        final isSame = width == rect.value?.width.toInt() &&
            height == rect.value?.height.toInt();
        if (isZero || isSame) {
          return;
        }

        final handle = await player.handle;

        if (!usesNativeSurface) await _channel.invokeMethod(
          'VideoOutputManager.SetSurfaceSize',
          {
            'handle': handle.toString(),
            'width': width.toString(),
            'height': height.toString(),
          },
        );
        await setProperties({
          'ohos-surface-size': [width, height].join('x'),
        });

        rect.value = Rect.fromLTWH(
          0.0,
          0.0,
          width.toDouble(),
          height.toDouble(),
        );

        if (!waitUntilFirstFrameRenderedCompleter.isCompleted) {
          waitUntilFirstFrameRenderedCompleter.complete();
        }
      }),
    );
  }

  /// {@macro ohos_video_controller}
  static Future<PlatformVideoController> create(
    Player player,
    VideoControllerConfiguration configuration,
  ) async {
    final bool isEmulator = await _channel.invokeMethod('Utils.IsEmulator');
    if (isEmulator) {
      throw UnsupportedError(
        '[VideoController] does not support emulator.'
        ' '
        'Please use actual device.',
      );
    }

    Future<String> getDefaultHwdec() async {
      bool hw = configuration.enableHardwareAcceleration;
      return hw ? 'auto' : 'no';
    }

    // Update [configuration] to have default values.
    configuration = configuration.copyWith(
      vo: configuration.vo ?? 'gpu-next',
      hwdec: configuration.hwdec ?? await getDefaultHwdec(),
    );

    // Retrieve the native handle of the [Player].
    final handle = await player.handle;
    // Return the existing [VideoController] if it's already created.
    if (_controllers.containsKey(handle)) {
      return _controllers[handle]!;
    }

    // Creation:
    final controller = OhosVideoController._(
      player,
      configuration,
    );

    // Register [_dispose] for execution upon [Player.dispose].
    player.platform?.release.add(controller._dispose);

    // Store the [VideoController] in the [_controllers].
    _controllers[handle] = controller;

    if (!controller.usesNativeSurface) await _channel.invokeMethod(
      'VideoOutputManager.Create',
      {
        'handle': handle.toString(),
      },
    );

    await controller.setProperties(
      {
        'vo': controller.usesNativeSurface ? 'null' : configuration.vo!,
        'hwdec': controller.usesNativeSurface ? 'ohcodec' : configuration.hwdec!,
        'vid': 'auto',
        'force-window': 'yes',
        'sub-use-margins': 'no',
        'sub-scale-with-window': 'no',
        'osd-font': 'HarmonyOS Sans SC',
      },
    );

    await controller.setProperties({'ohos-surface-size': '1x1'});
    if (controller.usesNativeSurface) {
      controller.rect.value = const Rect.fromLTWH(0, 0, 1, 1);
    }

    // Return the [PlatformVideoController].
    return controller;
  }

  /// Sets the required size of the video output.
  /// This may yield substantial performance improvements if a small [width] & [height] is specified.
  ///
  /// Remember:
  /// * “Premature optimization is the root of all evil”
  /// * “With great power comes great responsibility”
  @override
  Future<void> setSize({int? width, int? height}) => lock.synchronized(() async {
    if (_disposed || usesNativeSurface) return;
    if ((width == null) != (height == null) || (width != null && (width <= 0 || height! <= 0))) {
      throw ArgumentError('Set both positive output dimensions, or clear both.');
    }
    _requestedWidth = width;
    _requestedHeight = height;
    final outputWidth = width ?? _sourceWidth;
    final outputHeight = height ?? _sourceHeight;
    if (outputWidth == 0 || outputHeight == 0) return;
    if (rect.value?.width.toInt() == outputWidth && rect.value?.height.toInt() == outputHeight) return;
    final handle = await player.handle;
    await _channel.invokeMethod('VideoOutputManager.SetSurfaceSize', {
      'handle': handle.toString(), 'width': outputWidth.toString(), 'height': outputHeight.toString(),
    });
    await setProperty('ohos-surface-size', '${outputWidth}x$outputHeight');
    rect.value = Rect.fromLTWH(0, 0, outputWidth.toDouble(), outputHeight.toDouble());
  });

  /// Disposes the instance. Releases allocated resources back to the system.
  Future<void> _dispose() async {
    _disposed = true;
    wid.removeListener(widListener);
    wid.dispose();
    await videoParamsSubscription?.cancel();
    final handle = await player.handle;
    _controllers.remove(handle);
    if (usesNativeSurface && _nativeViewId != null) {
      await _channel.invokeMethod('NativeSurface.Dispose', {
        'handle': handle.toString(), 'viewId': _nativeViewId,
      });
    }
    nativeSurfaceError.dispose();
    if (!usesNativeSurface) await _channel.invokeMethod(
      'VideoOutputManager.Dispose',
      {
        'handle': handle.toString(),
      },
    );
    super.dispose();
  }

  /// Currently created [OhosVideoController]s.
  static final _controllers = HashMap<int, OhosVideoController>();

  /// [MethodChannel] for invoking platform specific native implementation.
  static final _channel =
      const MethodChannel('com.alexmercerind/media_kit_video')
        ..setMethodCallHandler(
          (MethodCall call) async {
            try {
              debugPrint(call.method.toString());
              debugPrint(call.arguments.toString());
              switch (call.method) {
                case 'NativeSurface.Created':
                  final controller = _controllers[int.parse(call.arguments['handle'] as String)];
                  try {
                    await controller?.attachNativeSurface(call.arguments['viewId'] as int, call.arguments['surfaceId'] as String);
                  } catch (error) {
                    if (controller != null && !controller._disposed) {
                      controller.nativeSurfaceError.value = error.toString();
                    }
                  }
                  break;
                case 'NativeSurface.Destroyed':
                  await _controllers[int.parse(call.arguments['handle'] as String)]?.detachNativeSurface(call.arguments['viewId'] as int);
                  break;
                case 'VideoOutput.Resize':
                  {
                    // Notify about updated texture ID & [Rect].
                    final int handle = call.arguments['handle'];
                    final Rect rect = Rect.fromLTWH(
                      call.arguments['rect']['left'] * 1.0,
                      call.arguments['rect']['top'] * 1.0,
                      call.arguments['rect']['width'] * 1.0,
                      call.arguments['rect']['height'] * 1.0,
                    );
                    final int id = call.arguments['id'];
                    final int wid = call.arguments['wid'];
                    _controllers[handle]?.rect.value = rect;
                    _controllers[handle]?.id.value = id;
                    _controllers[handle]?.wid.value = wid;
                    break;
                  }
                default:
                  {
                    break;
                  }
              }
            } catch (exception, stacktrace) {
              debugPrint(exception.toString());
              debugPrint(stacktrace.toString());
            }
          },
        );
}
