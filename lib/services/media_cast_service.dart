import 'dart:async';
import 'dart:io';
import 'package:castscreen/castscreen.dart';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:xml/xml.dart';
import '../models/cast_device.dart';
import 'cast_media_relay.dart';
import 'http_service.dart';

class MediaCastService extends ChangeNotifier {
  static final _instance = MediaCastService._();
  factory MediaCastService() => _instance;
  MediaCastService._() : fileProxy = HttpService.instance;
  MediaCastService.forTesting({this.advertisedHost, HttpService? fileProxy})
      : fileProxy = fileProxy ?? HttpService.instance;
  final HttpService fileProxy;
  String? advertisedHost;
  CastMediaRelay? _relay;
  String? preferredInterfaceAddress;
  int get relayedBytes => _relay?.bytesServed ?? 0;
  int get relayRequests => _relay?.requestsServed ?? 0;
  bool _disposed = false;
  int _pendingCommands = 0;
  int _revision = 0;
  final devicesStreamController =
      StreamController<List<CastDevice>>.broadcast();
  Stream<List<CastDevice>> get devicesStream => devicesStreamController.stream;
  List<CastDevice> devices = [];
  CastDevice? activeDevice;
  String? currentMediaPath;
  String? currentMediaTitle;
  String? statusWarning;
  bool awaitingPlayback = false;
  bool _transportSupported = true;
  bool _positionSupported = true;
  int _statusFailures = 0;
  VoidCallback? _onPlaybackStarted;
  String? lastError;
  bool scanning = false;
  bool busy = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  Timer? _poll;
  bool _polling = false;
  Future<void> _tail = Future.value();
  int _scanId = 0;

  void _notify() {
    if (_disposed) return;
    devicesStreamController.add(List.unmodifiable(devices));
    notifyListeners();
  }

  Future<void> startDiscovery() async {
    if (scanning || _disposed) return;
    final id = ++_scanId;
    scanning = true;
    lastError = null;
    _notify();
    try {
      final found = await CastScreen.discoverDevice(onDevice: (device) {
        if (id != _scanId) return;
        if (!devices.any((d) => d.device.spec.uuid == device.spec.uuid)) {
          devices.add(CastDevice(device: device));
          _notify();
        }
      });
      if (id == _scanId) {
        devices = found
            .map((d) => activeDevice?.device.spec.uuid == d.spec.uuid
                ? activeDevice!
                : CastDevice(device: d))
            .toList();
        if (activeDevice != null && !devices.contains(activeDevice))
          devices.insert(0, activeDevice!);
      }
    } catch (e) {
      if (id == _scanId) lastError = e.toString();
    } finally {
      if (id == _scanId) {
        scanning = false;
        _notify();
      }
    }
  }

  Future<bool> addDevice(String location) => _command(() async {
        final device = await CastScreen.fetchDevice(location);
        devices.removeWhere(
            (d) => d.device.spec.uuid == device.spec.uuid && d != activeDevice);
        if (activeDevice?.device.spec.uuid != device.spec.uuid)
          devices.add(CastDevice(device: device));
      });

  Future<bool> _command(Future<void> Function() action) {
    if (_disposed) return Future.value(false);
    final result = Completer<bool>();
    _pendingCommands++;
    busy = true;
    _revision++;
    _notify();
    _tail = _tail.then((_) async {
      if (_disposed) {
        result.complete(false);
        return;
      }
      lastError = null;
      try {
        await action();
        result.complete(!_disposed);
      } catch (e) {
        lastError = e.toString();
        result.complete(false);
      } finally {
        _pendingCommands--;
        busy = _pendingCommands > 0;
        _notify();
      }
    });
    return result.future;
  }

  static Future<List<NetworkInterface>> localInterfaces() =>
      NetworkInterface.list(
          type: InternetAddressType.any,
          includeLoopback: false,
          includeLinkLocal: false);

  Future<String> _localAddress() async {
    if (advertisedHost != null) return advertisedHost!;
    if (preferredInterfaceAddress != null) {
      final interfaces = await localInterfaces();
      if (!interfaces.any((i) =>
          i.addresses.any((a) => a.address == preferredInterfaceAddress))) {
        throw StateError('选择的网络已断开，请重新选择投屏网络');
      }
      return preferredInterfaceAddress!;
    }
    if (activeDevice != null) {
      final destination = Uri.parse(activeDevice!.device.client.LOCATION);
      final socket = await Socket.connect(destination.host, destination.port,
          timeout: const Duration(seconds: 4));
      try {
        return socket.address.address;
      } finally {
        socket.destroy();
      }
    }
    final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false);
    final addresses = interfaces.expand((i) => i.addresses).toList();
    if (addresses.isEmpty) throw StateError('未连接局域网，请连接 Wi-Fi');
    final wifi = interfaces.where((i) =>
        RegExp(r'wlan|wi-?fi|^en0$', caseSensitive: false).hasMatch(i.name));
    return wifi.isEmpty
        ? addresses.first.address
        : wifi.first.addresses.first.address;
  }

  Future<void> _closeRelay() async {
    final relay = _relay;
    _relay = null;
    await relay?.close();
  }

  Future<void> closeIdleRelay() async {
    if (activeDevice == null) await _closeRelay();
  }

  /// Public URLs may be sent directly; authenticated/local media always use a
  /// scoped LAN relay. The UI can also relay public URLs for HTTP-only TVs.
  Future<String> startLocalServer(String mediaPath,
      {Map<String, String> headers = const {}, bool forceRelay = false}) async {
    if (_disposed) throw StateError('投屏服务已关闭');
    final uri = Uri.tryParse(mediaPath);
    final remote =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    final loopback = remote &&
        (uri.host == 'localhost' ||
            InternetAddress.tryParse(uri.host)?.isLoopback == true);
    if (remote &&
        !loopback &&
        uri.userInfo.isEmpty &&
        headers.isEmpty &&
        !forceRelay) {
      await _closeRelay();
      return mediaPath;
    }
    final host = await _localAddress();
    final detached = await fileProxy.detachForCast(mediaPath);
    late CastMediaRelay next;
    try {
      if (_disposed) throw StateError('投屏服务已关闭');
      next = await CastMediaRelay.start(detached?.url ?? mediaPath,
          host: host,
          headers: headers,
          resolveReference: detached?.resolveReference,
          onClose: detached?.close, onError: (message) {
        if (!_disposed) {
          lastError = message;
          _notify();
        }
      });
    } catch (_) {
      await detached?.close();
      rethrow;
    }
    if (_disposed) {
      await next.close();
      throw StateError('投屏服务已关闭');
    }
    await _closeRelay();
    _relay = next;
    return next.url;
  }

  Future<bool> connectToDevice(CastDevice device) => _command(() async {
        if (device.device.avTransportService == null)
          throw StateError('设备不支持 DLNA 播放');
        if (activeDevice != null && activeDevice != device) {
          try {
            await _connected().device.stop(const StopInput());
          } catch (_) {}
          activeDevice!.isConnected = false;
          activeDevice!.isPlaying = false;
          await _closeRelay();
        }
        if (activeDevice != device) {
          _onPlaybackStarted = null;
          statusWarning = null;
          _transportSupported = true;
          _positionSupported = true;
          _statusFailures = 0;
          awaitingPlayback = false;
          currentMediaPath = null;
          currentMediaTitle = null;
          position = Duration.zero;
          duration = Duration.zero;
        }
        activeDevice = device;
        device.isConnected = true;
      });

  Future<bool> castMedia(String mediaPath,
          {Map<String, String> headers = const {},
          String? title,
          Duration startPosition = Duration.zero,
          bool relayNetwork = false,
          bool isAudio = false,
          Duration mediaDuration = Duration.zero,
          VoidCallback? onPlaybackStarted}) =>
      _command(() async {
        final device = activeDevice;
        if (device == null) throw StateError('请先选择播放设备');
        final operationRevision = _revision;
        final previous = _relay;
        var uriAccepted = false;
        _relay = null;
        try {
          final url = await startLocalServer(mediaPath,
              headers: headers, forceRelay: relayNetwork);
          final mime =
              lookupMimeType(Uri.tryParse(mediaPath)?.path ?? mediaPath) ??
                  (isAudio ? 'audio/mpeg' : 'video/mp4');
          final xb = XmlBuilder();
          xb.element('DIDL-Lite', namespaces: {
            'urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/': '',
            'http://purl.org/dc/elements/1.1/': 'dc',
            'urn:schemas-upnp-org:metadata-1-0/upnp/': 'upnp'
          }, nest: () {
            xb.element('item',
                attributes: {'id': '0', 'parentID': '-1', 'restricted': '1'},
                nest: () {
              xb.element('dc:title',
                  nest: title ??
                      Uri.tryParse(mediaPath)?.pathSegments.lastOrNull ??
                      'AloePlayer');
              xb.element('upnp:class',
                  nest: isAudio || mime.startsWith('audio/')
                      ? 'object.item.audioItem.musicTrack'
                      : 'object.item.videoItem');
              xb.element('res',
                  attributes: {'protocolInfo': 'http-get:*:$mime:*'},
                  nest: url);
            });
          });
          final metadata = xb.buildDocument().toXmlString();
          try {
            await device.device.setAVTransportURI(
                SetAVTransportURIInput(url, CurrentURIMetaData: metadata));
          } on CastProtocolException catch (error) {
            if (error.upnpCode == 701) {
              await device.device.stop(const StopInput());
              await device.device.setAVTransportURI(
                  SetAVTransportURIInput(url, CurrentURIMetaData: metadata));
            } else if (error.upnpCode == 402 || error.upnpCode == 714) {
              await device.device
                  .setAVTransportURI(SetAVTransportURIInput(url));
            } else {
              rethrow;
            }
          }
          uriAccepted = true;
          device.isPlaying = false;
          await _whenReady(() => device.device.play(const PlayInput()));
          if (_disposed) throw StateError('投屏服务已关闭');
          await previous?.close();
          duration = mediaDuration;
          currentMediaPath = mediaPath;
          currentMediaTitle = title ??
              Uri.tryParse(mediaPath)?.pathSegments.lastOrNull ??
              'AloePlayer';
          awaitingPlayback = true;
          statusWarning = null;
          _statusFailures = 0;
          _transportSupported = true;
          _positionSupported = true;
          _onPlaybackStarted = onPlaybackStarted;
          position = Duration.zero;
          if (startPosition > Duration.zero) {
            try {
              await _whenReady(() => _seek(startPosition));
            } catch (_) {
              lastError = '已开始投屏，但设备不支持从当前位置续播';
            }
          }
          await _initialStatus(device, operationRevision);
          _startPolling();
        } catch (_) {
          if (uriAccepted) {
            awaitingPlayback = false;
            _onPlaybackStarted = null;
          }
          await _closeRelay();
          if (_disposed)
            await previous?.close();
          else
            _relay = previous;
          rethrow;
        }
      });
  CastDevice _connected() {
    final device = activeDevice;
    if (device == null) throw StateError('请先选择播放设备');
    return device;
  }

  Future<void> _whenReady(Future<Object?> Function() action) async {
    for (var attempt = 0;; attempt++) {
      if (_disposed) throw StateError('投屏服务已关闭');
      try {
        await action();
        return;
      } on CastProtocolException catch (error) {
        if (error.upnpCode != 701 || attempt >= 2) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
      }
    }
  }

  Future<bool> pauseMedia() => _command(() async {
        await _connected().device.pause(const PauseInput());
        activeDevice!.isPlaying = false;
        awaitingPlayback = false;
        _onPlaybackStarted = null;
      });
  Future<bool> resumeMedia({VoidCallback? onPlaybackStarted}) =>
      _command(() async {
        final device = _connected();
        final revision = _revision;
        await _whenReady(() => device.device.play(const PlayInput()));
        awaitingPlayback = true;
        _onPlaybackStarted = onPlaybackStarted ?? _onPlaybackStarted;
        await _initialStatus(device, revision);
        _startPolling();
      });
  Future<bool> stopMedia() => _command(() async {
        await _connected().device.stop(const StopInput());
        activeDevice!.isPlaying = false;
        awaitingPlayback = false;
        _onPlaybackStarted = null;
        _poll?.cancel();
      });
  Future<bool> seek(Duration value) => _command(() => _seek(value));
  Future<void> _seek(Duration value) async {
    final s = value.inSeconds.clamp(0, 359999);
    await _connected().device.avTransportService!.invokeMap('Seek', {
      'InstanceID': '0',
      'Unit': 'REL_TIME',
      'Target':
          '${(s ~/ 3600).toString().padLeft(2, '0')}:${(s ~/ 60 % 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}'
    });
    position = value;
  }

  Future<bool> setVolume(int volume) => _command(() async {
        final control = activeDevice?.device.renderingControlService;
        if (control == null) throw StateError('设备没有音量控制服务');
        await control.invokeMap('SetVolume', {
          'InstanceID': '0',
          'Channel': 'Master',
          'DesiredVolume': '${volume.clamp(0, 100)}'
        });
      });
  static Duration parseTime(String? value) {
    final parts = value?.split(':') ?? [];
    if (parts.length != 3) return Duration.zero;
    final numbers = parts.map(double.tryParse).toList();
    if (numbers.any((n) => n == null || !n.isFinite || n < 0) ||
        numbers[1]! >= 60 ||
        numbers[2]! >= 60) return Duration.zero;
    final ms = (numbers[0]! * 3600 + numbers[1]! * 60 + numbers[2]!) * 1000;
    return ms.isFinite && ms < 1e15
        ? Duration(milliseconds: ms.round())
        : Duration.zero;
  }

  void _startPolling() {
    _poll?.cancel();
    if (!_disposed)
      _poll =
          Timer.periodic(const Duration(seconds: 2), (_) => refreshStatus());
  }

  Future<String?> _readTransport(CastDevice device) async {
    if (!_transportSupported) return null;
    try {
      final response = await device.device.avTransportService!.invokeMap(
          'GetTransportInfo', {'InstanceID': '0'},
          requestTimeout: const Duration(seconds: 2));
      final value = response['CurrentTransportState']?.trim().toUpperCase();
      if (value == null || value.isEmpty)
        throw const CastProtocolException('接收端未返回播放状态');
      _statusFailures = 0;
      statusWarning = null;
      return value;
    } catch (error) {
      _statusFailures++;
      if (error is CastProtocolException && error.upnpCode == 401) {
        _transportSupported = false;
        statusWarning = '接收端不提供播放状态。请在电视确认画面后手动暂停本机。';
      } else if (_statusFailures >= 3) {
        statusWarning = '暂时无法读取接收端状态，请检查电视；媒体转发仍保持运行。';
      }
      return null;
    }
  }

  void _applyTransport(CastDevice device, String state) {
    device.isPlaying = state == 'PLAYING';
    // With a relay, PLAYING before the first media byte may describe the old
    // item or just accepted loading. Wait until the receiver actually reads.
    if (device.isPlaying && (_relay == null || relayedBytes > 0)) {
      awaitingPlayback = false;
      final callback = _onPlaybackStarted;
      _onPlaybackStarted = null;
      try {
        callback?.call();
      } catch (_) {
        lastError = '电视已开始播放，但本机暂停失败，请手动暂停本机。';
      }
    }
  }

  Future<void> _initialStatus(CastDevice device, int revision) async {
    if (_disposed || _pendingCommands > 1 || revision != _revision) return;
    final state = await _readTransport(device);
    if (!_disposed &&
        _pendingCommands == 1 &&
        revision == _revision &&
        activeDevice == device &&
        state != null) {
      _applyTransport(device, state);
    }
  }

  Future<void> refreshStatus() {
    if (_disposed || busy || _polling || activeDevice == null)
      return Future.value();
    _polling = true;
    final revision = _revision;
    _tail = _tail.then((_) async {
      if (_disposed || busy || revision != _revision) {
        _polling = false;
        return;
      }
      final device = activeDevice;
      if (device == null) {
        _polling = false;
        return;
      }
      try {
        Map<String, String>? info;
        if (_positionSupported) {
          try {
            info = await device.device.avTransportService!.invokeMap(
                'GetPositionInfo', {'InstanceID': '0'},
                requestTimeout: const Duration(seconds: 2));
          } on CastProtocolException catch (error) {
            if (error.upnpCode == 401) _positionSupported = false;
          } catch (_) {}
        }
        if (_disposed || busy || revision != _revision) return;
        final state = await _readTransport(device);
        if (activeDevice == device &&
            !_disposed &&
            !busy &&
            revision == _revision) {
          if (info != null) {
            position = parseTime(info['RelTime']);
            final remoteDuration = parseTime(info['TrackDuration']);
            if (remoteDuration > Duration.zero) duration = remoteDuration;
          }
          if (state != null) _applyTransport(device, state);
          _notify();
        }
      } finally {
        _polling = false;
      }
    });
    return _tail;
  }

  Future<bool> disconnectFromDevice() => _command(() async {
        final device = activeDevice;
        _poll?.cancel();
        try {
          if (device != null) await device.device.stop(const StopInput());
        } finally {
          if (device != null) {
            device.isConnected = false;
            device.isPlaying = false;
          }
          activeDevice = null;
          currentMediaPath = null;
          currentMediaTitle = null;
          awaitingPlayback = false;
          _onPlaybackStarted = null;
          statusWarning = null;
          position = Duration.zero;
          duration = Duration.zero;
          await _closeRelay();
        }
      });
  // The service owns the cast session, not the screen. Closing the screen must
  // not terminate the media server while the receiver is still reading it.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _onPlaybackStarted = null;
    _scanId++;
    _revision++;
    _poll?.cancel();
    unawaited(_closeRelay());
    unawaited(devicesStreamController.close());
    super.dispose();
  }
}
