part of 'lib.dart';

/// Each scan owns its sockets and pending descriptions; overlapping scans cannot
/// clear another scan's devices or close another scan's sockets.
abstract final class CastScreen {
  static Future<Device> fetchDevice(String location) async {
    final uri = Uri.tryParse(location.trim());
    if (uri == null || !['http', 'https'].contains(uri.scheme) || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const CastProtocolException('请输入设备描述的 HTTP/HTTPS 地址');
    }
    final client = Client('', '', uri.toString(), '', {});
    final response = await Http.get(uri.toString(), (xml) => Device.create(client, xml, uri.toString()));
    await response.data._init();
    if (!response.data._realDevice) throw const CastProtocolException('该设备不支持 DLNA 媒体播放');
    return response.data;
  }

  static Map<String, String>? parseSsdpPacket(List<int> bytes) {
    final lines = utf8.decode(bytes, allowMalformed: true).split(RegExp(r'\r?\n'));
    if (lines.isEmpty || !(RegExp(r'^HTTP/1\.[01]\s+200\b', caseSensitive: false).hasMatch(lines.first) ||
        lines.first.toUpperCase().startsWith('NOTIFY '))) return null;
    final headers = <String, String>{};
    for (final line in lines.skip(1)) {
      final colon = line.indexOf(':');
      if (colon > 0) headers[line.substring(0, colon).trim().toUpperCase()] = line.substring(colon + 1).trim();
    }
    if (headers['NTS']?.toLowerCase() == 'ssdp:byebye') return null;
    final uri = Uri.tryParse(headers['LOCATION'] ?? '');
    if (uri == null || !['http', 'https'].contains(uri.scheme) || uri.host.isEmpty || uri.userInfo.isNotEmpty) return null;
    headers['ST'] ??= headers['NT'] ?? '';
    return headers;
  }

  static Future<List<Device>> discoverDevice({bool ipv4 = true, bool ipv6 = true,
      int port = 0, String ST = 'upnp:rootdevice', Duration timeout = const Duration(seconds: 5),
      void Function(Exception)? onError, void Function(Device)? onDevice,
      InternetAddress? discoveryAddress, int discoveryPort = 1900,
      List<InternetAddress>? bindAddresses}) async {
    final scan = _CastScan(onError, onDevice);
    await scan.run(ipv4: ipv4, ipv6: ipv6, port: port, st: ST, timeout: timeout,
        target: discoveryAddress, targetPort: discoveryPort, bindAddresses: bindAddresses);
    return scan.devices.values.toList();
  }

  static Future<List<Client>> discoverClient({bool ipv4 = true, bool ipv6 = true,
      int port = 0, String ST = 'upnp:rootdevice', Duration timeout = const Duration(seconds: 5),
      void Function(Exception)? onError}) async => (await discoverDevice(ipv4: ipv4,
      ipv6: ipv6, port: port, ST: ST, timeout: timeout, onError: onError)).map((d) => d.client).toList();
}

class _CastScan {
  final void Function(Exception)? onError;
  final void Function(Device)? onDevice;
  final devices = <String, Device>{};
  final _locations = <String>{};
  final _queue = <String>[];
  final _sockets = <RawDatagramSocket>[];
  final _pending = <Future<void>>{};
  bool _closed = false;
  _CastScan(this.onError, this.onDevice);

  void _pump() {
    while (!_closed && _queue.isNotEmpty && _pending.length < 4) {
      final location = _queue.removeAt(0);
      late Future<void> pending;
      pending = CastScreen.fetchDevice(location).then<void>((device) {
        if (_closed) return;
        devices[device.spec.uuid] = device;
        onDevice?.call(device);
      }, onError: (Object e, StackTrace _) {
        if (!_closed) onError?.call(e is Exception ? e : Exception(e.toString()));
      }).whenComplete(() { _pending.remove(pending); _pump(); });
      _pending.add(pending);
    }
  }

  Future<void> run({required bool ipv4, required bool ipv6, required int port,
      required String st, required Duration timeout, InternetAddress? target,
      required int targetPort, List<InternetAddress>? bindAddresses}) async {
    final interfaces = bindAddresses == null ? await NetworkInterface.list(includeLoopback: false, includeLinkLocal: true) : <NetworkInterface>[];
    final bindings = <(InternetAddress, NetworkInterface?)>[
      if (bindAddresses != null) for (final address in bindAddresses) (address, null),
      for (final interface in interfaces) for (final address in interface.addresses)
        if ((ipv4 && address.type == InternetAddressType.IPv4) || (ipv6 && address.type == InternetAddressType.IPv6)) (address, interface),
    ];
    Timer? repeat;
    try {
      for (final binding in bindings) {
        RawDatagramSocket? socket;
        try {
          socket = await RawDatagramSocket.bind(binding.$1, port, reuseAddress: true);
          socket.writeEventsEnabled = false;
          socket.multicastHops = 2;
          final isV4 = binding.$1.type == InternetAddressType.IPv4;
          if (binding.$2 != null) {
            final option = isV4 ? ((Platform.isWindows || Platform.isMacOS) ? 9 : 32) :
                ((Platform.isWindows || Platform.isMacOS) ? 9 : 17);
            socket.setRawOption(RawSocketOption(isV4 ? RawSocketOption.levelIPv4 : RawSocketOption.levelIPv6,
              option, isV4 ? binding.$1.rawAddress : (Uint32List(1)..[0] = binding.$2!.index).buffer.asUint8List()));
          }
          _sockets.add(socket);
          final receiver = socket;
          socket.listen((event) {
            if (event != RawSocketEvent.read || _closed) return;
            Datagram? packet;
            while ((packet = receiver.receive()) != null) {
              final headers = CastScreen.parseSsdpPacket(packet!.data);
              if (headers == null) continue;
              final location = headers['LOCATION']!;
              if (_locations.length < 64 && _locations.add(location)) { _queue.add(location); _pump(); }
            }
          }, onError: (Object e) { if (!_closed) onError?.call(Exception(e.toString())); });
        } catch (e) { socket?.close(); onError?.call(Exception(e.toString())); }
      }
      if (_sockets.isEmpty) throw const CastProtocolException('没有可用的局域网接口，请连接 Wi-Fi 后重试');
      void search() {
        for (final socket in _sockets) {
          final destination = target ?? InternetAddress(socket.address.type == InternetAddressType.IPv4 ? '239.255.255.250' : 'ff02::c');
          final host = destination.type == InternetAddressType.IPv6 ? '[${destination.address}]' : destination.address;
          for (final type in {st, 'urn:schemas-upnp-org:device:MediaRenderer:1', 'urn:schemas-upnp-org:service:AVTransport:1'}) {
            try { socket.send(utf8.encode('M-SEARCH * HTTP/1.1\r\nHOST: $host:$targetPort\r\nMAN: "ssdp:discover"\r\nMX: 2\r\nST: $type\r\n\r\n'), destination, targetPort); }
            catch (e) { onError?.call(Exception(e.toString())); }
          }
        }
      }
      search();
      repeat = Timer(const Duration(seconds: 1), search);
      await Future<void>.delayed(timeout);
      repeat.cancel();
      for (final socket in _sockets) { socket.close(); }
      // Include descriptions already received near the discovery deadline.
      final deadline = DateTime.now().add(const Duration(seconds: 9));
      while (_pending.isNotEmpty && DateTime.now().isBefore(deadline)) {
        await Future.any([Future.wait(_pending.toList()), Future<void>.delayed(deadline.difference(DateTime.now()))]);
      }
    } finally {
      _closed = true; repeat?.cancel();
      for (final socket in _sockets) { socket.close(); }
    }
  }
}
