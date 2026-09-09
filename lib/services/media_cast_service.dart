import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:castscreen/castscreen.dart';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:xml/xml.dart';
import '../models/cast_device.dart';
import 'byte_range.dart';

class MediaCastService extends ChangeNotifier {
  static final _instance = MediaCastService._();
  factory MediaCastService() => _instance;
  MediaCastService._();
  MediaCastService.forTesting({this.advertisedHost});
  String? advertisedHost;
  HttpServer? _httpServer;
  final _clients = <HttpClient>{};
  final devicesStreamController = StreamController<List<CastDevice>>.broadcast();
  Stream<List<CastDevice>> get devicesStream => devicesStreamController.stream;
  List<CastDevice> devices = [];
  CastDevice? activeDevice;
  String? currentMediaPath;
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
    devicesStreamController.add(List.unmodifiable(devices));
    notifyListeners();
  }

  Future<void> startDiscovery() async {
    if (scanning) return;
    final id = ++_scanId;
    scanning = true; lastError = null; _notify();
    try {
      final found = await CastScreen.discoverDevice(onDevice: (device) {
        if (id != _scanId) return;
        if (!devices.any((d) => d.device.spec.uuid == device.spec.uuid)) {
          devices.add(CastDevice(device: device)); _notify();
        }
      });
      if (id == _scanId) {
        devices = found.map((d) => activeDevice?.device.spec.uuid == d.spec.uuid ? activeDevice! : CastDevice(device: d)).toList();
        if (activeDevice != null && !devices.contains(activeDevice)) devices.insert(0, activeDevice!);
      }
    } catch (e) { if (id == _scanId) lastError = e.toString(); }
    finally { if (id == _scanId) { scanning = false; _notify(); } }
  }

  Future<bool> addDevice(String location) => _command(() async {
    final device = await CastScreen.fetchDevice(location);
    devices.removeWhere((d) => d.device.spec.uuid == device.spec.uuid && d != activeDevice);
    if (activeDevice?.device.spec.uuid != device.spec.uuid) devices.add(CastDevice(device: device));
  });

  Future<bool> _command(Future<void> Function() action) {
    final result = Completer<bool>();
    _tail = _tail.then((_) async {
      busy = true; lastError = null; _notify();
      try { await action(); result.complete(true); }
      catch (e) { lastError = e.toString(); result.complete(false); }
      finally { busy = false; _notify(); }
    });
    return result.future;
  }

  Future<String> _localAddress() async {
    if (advertisedHost != null) return advertisedHost!;
    if (activeDevice != null) {
      final destination = Uri.parse(activeDevice!.device.client.LOCATION);
      final socket = await Socket.connect(destination.host, destination.port, timeout: const Duration(seconds: 4));
      try { return socket.address.address; } finally { socket.destroy(); }
    }
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false, includeLinkLocal: false);
    final addresses = interfaces.expand((i) => i.addresses).toList();
    if (addresses.isEmpty) throw StateError('未连接局域网，请连接 Wi-Fi');
    return addresses.first.address;
  }

  Future<void> _closeRelay() async {
    for (final client in _clients.toList()) { client.close(force: true); }
    _clients.clear();
    await _httpServer?.close(force: true); _httpServer = null;
  }

  /// Normal public URLs go directly to the renderer. Loopback URLs (including
  /// SMB/WebDAV grants) and authenticated URLs use a scoped LAN relay.
  Future<String> startLocalServer(String mediaPath, {Map<String, String> headers = const {}}) async {
    final uri = Uri.tryParse(mediaPath);
    final remote = uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    final loopback = remote && (uri.host == 'localhost' || InternetAddress.tryParse(uri.host)?.isLoopback == true);
    if (remote && !loopback && headers.isEmpty) {
      await _closeRelay();
      return mediaPath;
    }
    final file = remote ? null : File(uri?.scheme == 'file' ? uri!.path : mediaPath);
    if (file != null && !await file.exists()) throw StateError('本地媒体不可读，请重新选择文件或尝试系统投播');
    final host = await _localAddress();
    await _closeRelay();
    final isV6 = InternetAddress.tryParse(host)?.type == InternetAddressType.IPv6;
    final server = await HttpServer.bind(isV6 ? InternetAddress.anyIPv6 : InternetAddress.anyIPv4, 0);
    _httpServer = server;
    final token = base64UrlEncode(List.generate(24, (_) => Random.secure().nextInt(256)));
    final name = uri?.pathSegments.lastOrNull ?? mediaPath.split(RegExp(r'[/\\]')).last;
    final mediaRoute = '/media/${Uri.encodeComponent(name.isEmpty ? 'video.mp4' : name)}';
    server.listen((request) async {
      final response = request.response;
      try {
        if (request.uri.path != Uri.parse(mediaRoute).path || request.uri.queryParameters['token'] != token) {
          response.statusCode = 403;
        } else if (!['GET', 'HEAD'].contains(request.method)) {
          response.statusCode = 405; response.headers.set('Allow', 'GET, HEAD');
        } else {
          response.headers.set('Accept-Ranges', 'bytes');
          response.headers.set('transferMode.dlna.org', 'Streaming');
          response.headers.set('contentFeatures.dlna.org', 'DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000');
          response.headers.set('Cache-Control', 'no-store');
          if (remote) {
            await _relay(request, uri, headers);
          } else {
            final size = await file!.length();
            final rangeHeader = request.headers.value('range');
            final range = rangeHeader == null ? null : ByteRange.parse(rangeHeader, size);
            if (rangeHeader != null && range == null) {
              response.statusCode = 416; response.headers.set('Content-Range', 'bytes */$size');
            } else {
              response.statusCode = range == null ? 200 : 206;
              response.headers.contentType = ContentType.parse(lookupMimeType(file.path) ?? 'application/octet-stream');
              response.contentLength = range?.length ?? size;
              if (range != null) response.headers.set('Content-Range', 'bytes ${range.start}-${range.end}/$size');
              if (request.method == 'GET') await response.addStream(file.openRead(range?.start ?? 0, range == null ? null : range.end + 1));
            }
          }
        }
        await response.close();
      } catch (_) { try { response.statusCode = 502; await response.close(); } catch (_) {} }
    });
    return Uri(scheme: 'http', host: host, port: server.port, path: Uri.parse(mediaRoute).path, queryParameters: {'token': token}).toString();
  }

  Future<void> _relay(HttpRequest incoming, Uri uri, Map<String, String> headers) async {
    final client = HttpClient()..autoUncompress = false..connectionTimeout = const Duration(seconds: 12);
    _clients.add(client);
    try {
      final forwarded = Map<String, String>.from(headers)..removeWhere((k, _) => ['host','content-length','connection'].contains(k.toLowerCase()));
      if (incoming.headers.value('range') != null) forwarded['Range'] = incoming.headers.value('range')!;
      forwarded['Accept-Encoding'] = 'identity';
      for (var redirects = 0; redirects < 6; redirects++) {
        final request = await client.openUrl(incoming.method, uri).timeout(const Duration(seconds: 12));
        request.followRedirects = false;
        forwarded.forEach((k, v) => request.headers.set(k, v));
        final response = await request.close().timeout(const Duration(seconds: 12));
        if ([301,302,303,307,308].contains(response.statusCode)) {
          final location = response.headers.value('location');
          await response.listen((_) {}).cancel();
          if (location == null) throw StateError('重定向缺少地址');
          final next = uri.resolve(location);
          if (uri.scheme == 'https' && next.scheme != 'https') throw StateError('不允许降级到不安全的媒体地址');
          if (!['http','https'].contains(next.scheme)) throw StateError('不支持的媒体重定向');
          if (uri.origin != next.origin) forwarded.removeWhere((k, _) => ['authorization','cookie','proxy-authorization'].contains(k.toLowerCase()));
          uri = next; continue;
        }
        incoming.response.statusCode = response.statusCode;
        for (final name in ['content-type','content-length','content-range','accept-ranges','etag','last-modified']) {
          final value = response.headers.value(name);
          if (value != null) incoming.response.headers.set(name, value);
        }
        if (incoming.method == 'GET') await incoming.response.addStream(response);
        else await response.listen((_) {}).cancel();
        return;
      }
      throw StateError('媒体地址重定向次数过多');
    } finally { client.close(force: true); _clients.remove(client); }
  }

  Future<bool> connectToDevice(CastDevice device) => _command(() async {
    if (device.device.avTransportService == null) throw StateError('设备不支持 DLNA 播放');
    if (activeDevice != null && activeDevice != device) {
      try { await activeDevice!.device.stop(const StopInput()); } catch (_) {}
      activeDevice!.isConnected = false; activeDevice!.isPlaying = false;
      await _closeRelay();
    }
    activeDevice = device; device.isConnected = true;
  });

  Future<bool> castMedia(String mediaPath, {Map<String, String> headers = const {}, String? title, Duration startPosition = Duration.zero}) => _command(() async {
    final device = activeDevice;
    if (device == null) throw StateError('请先选择播放设备');
    final url = await startLocalServer(mediaPath, headers: headers);
    final mime = lookupMimeType(Uri.tryParse(mediaPath)?.path ?? mediaPath) ?? 'video/mp4';
    final xb = XmlBuilder();
    xb.element('DIDL-Lite', namespaces: {'urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/':'', 'http://purl.org/dc/elements/1.1/':'dc', 'urn:schemas-upnp-org:metadata-1-0/upnp/':'upnp'}, nest: () {
      xb.element('item', attributes: {'id':'0','parentID':'-1','restricted':'1'}, nest: () {
        xb.element('dc:title', nest: title ?? Uri.tryParse(mediaPath)?.pathSegments.lastOrNull ?? 'AloePlayer');
        xb.element('upnp:class', nest: mime.startsWith('audio/') ? 'object.item.audioItem.musicTrack' : 'object.item.videoItem');
        xb.element('res', attributes: {'protocolInfo':'http-get:*:$mime:*'}, nest: url);
      });
    });
    await device.device.setAVTransportURI(SetAVTransportURIInput(url, CurrentURIMetaData: xb.buildDocument().toXmlString()));
    await device.device.play(const PlayInput());
    currentMediaPath = mediaPath; device.isPlaying = true; position = Duration.zero;
    if (startPosition > Duration.zero) {
      try { await _seek(startPosition); } catch (_) { lastError = '已开始投屏，但设备不支持从当前位置续播'; }
    }
    _poll?.cancel(); _poll = Timer.periodic(const Duration(seconds: 2), (_) => refreshStatus());
  });
  Future<bool> pauseMedia() => _command(() async { await activeDevice!.device.pause(const PauseInput()); activeDevice!.isPlaying = false; });
  Future<bool> resumeMedia() => _command(() async { await activeDevice!.device.play(const PlayInput()); activeDevice!.isPlaying = true; });
  Future<bool> stopMedia() => _command(() async { await activeDevice!.device.stop(const StopInput()); activeDevice!.isPlaying = false; _poll?.cancel(); });
  Future<bool> seek(Duration value) => _command(() => _seek(value));
  Future<void> _seek(Duration value) async {
    final s = value.inSeconds;
    await activeDevice!.device.avTransportService!.invokeMap('Seek', {'InstanceID':'0','Unit':'REL_TIME','Target':'${(s~/3600).toString().padLeft(2,'0')}:${(s~/60%60).toString().padLeft(2,'0')}:${(s%60).toString().padLeft(2,'0')}'});
    position = value;
  }
  Future<bool> setVolume(int volume) => _command(() async {
    final control = activeDevice?.device.renderingControlService;
    if (control == null) throw StateError('设备没有音量控制服务');
    await control.invokeMap('SetVolume', {'InstanceID':'0','Channel':'Master','DesiredVolume':'${volume.clamp(0,100)}'});
  });
  static Duration parseTime(String? value) {
    final parts = value?.split(':') ?? [];
    if (parts.length != 3) return Duration.zero;
    return Duration(milliseconds: (((double.tryParse(parts[0]) ?? 0)*3600+(double.tryParse(parts[1]) ?? 0)*60+(double.tryParse(parts[2]) ?? 0))*1000).round());
  }
  Future<void> refreshStatus() async {
    if (busy || _polling || activeDevice == null) return;
    _polling = true; final device = activeDevice!;
    try {
      final info = await device.device.avTransportService!.invokeMap('GetPositionInfo', {'InstanceID':'0'});
      final state = await device.device.avTransportService!.invokeMap('GetTransportInfo', {'InstanceID':'0'});
      if (activeDevice == device && !busy) {
        position = parseTime(info['RelTime']); duration = parseTime(info['TrackDuration']);
        device.isPlaying = state['CurrentTransportState'] == 'PLAYING'; _notify();
      }
    } catch (_) { /* Optional polling must not interrupt a functioning stream. */ }
    finally { _polling = false; }
  }
  Future<bool> disconnectFromDevice() => _command(() async {
    final device = activeDevice; _poll?.cancel();
    try { if (device != null) await device.device.stop(const StopInput()); }
    finally {
      if (device != null) { device.isConnected = false; device.isPlaying = false; }
      activeDevice = null; currentMediaPath = null; await _closeRelay();
    }
  });
  // The service owns the cast session, not the screen. Closing the screen must
  // not terminate the media server while the receiver is still reading it.
  @override
  void dispose() { _poll?.cancel(); unawaited(_closeRelay()); super.dispose(); }
}
