import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:castscreen/castscreen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:aloeplayer/services/media_cast_service.dart';
import 'package:aloeplayer/models/cast_device.dart';

void main() {
  late HttpServer renderer;
  late String base;
  final actions = <String>[];
  var fault = false;
  var transportState = 'PLAYING';
  var receivedUri = '';
  final commandFaults = <String, List<int>>{};
  final metadataSent = <String>[];
  Completer<void>? positionGate;
  Completer<void>? positionStarted;
  setUp(() async {
    actions.clear();
    fault = false;
    transportState = 'PLAYING';
    receivedUri = '';
    commandFaults.clear();
    metadataSent.clear();
    positionGate = null;
    positionStarted = null;
    renderer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${renderer.port}';
    renderer.listen((request) async {
      if (request.method == 'GET' && request.uri.path == '/desc/device.xml') {
        request.response.write(
            '''<d:root xmlns:d="urn:schemas-upnp-org:device-1-0"><d:device><d:deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</d:deviceType><d:friendlyName>客厅电视</d:friendlyName><d:UDN>uuid:living-room</d:UDN><d:serviceList>
<d:service><d:serviceType>urn:schemas-upnp-org:service:AVTransport:2</d:serviceType><d:serviceId>vendor:transport</d:serviceId><d:controlURL>../control/av</d:controlURL><d:SCPDURL>/missing.xml</d:SCPDURL></d:service>
<d:service><d:serviceType>urn:schemas-upnp-org:service:RenderingControl:1</d:serviceType><d:serviceId>vendor:volume</d:serviceId><d:controlURL>$base/control/volume</d:controlURL></d:service>
</d:serviceList></d:device></d:root>''');
      } else if (request.method == 'POST' &&
          request.uri.path.startsWith('/control/')) {
        final xml = XmlDocument.parse(await utf8.decoder.bind(request).join());
        final body = xml.descendants
            .whereType<XmlElement>()
            .firstWhere((e) => e.name.local == 'Body');
        final action = body.childElements.first;
        actions.add(action.name.local);
        final args = {
          for (final e in action.childElements) e.name.local: e.innerText
        };
        expect(args['InstanceID'], '0');
        if (action.name.local == 'SetAVTransportURI') {
          receivedUri = args['CurrentURI']!;
          metadataSent.add(args['CurrentURIMetaData']!);
          if (args['CurrentURIMetaData']!.isNotEmpty)
            expect(
                XmlDocument.parse(args['CurrentURIMetaData']!)
                    .rootElement
                    .name
                    .local,
                'DIDL-Lite');
        }
        if (action.name.local == 'GetPositionInfo' && positionGate != null) {
          positionStarted?.complete();
          await positionGate!.future;
        }
        final pendingFaults = commandFaults[action.name.local];
        final faultCode = pendingFaults != null && pendingFaults.isNotEmpty
            ? pendingFaults.removeAt(0)
            : (fault ? 701 : null);
        if (faultCode != null) {
          request.response.statusCode = 500;
          request.response.write(
              '<e:Envelope xmlns:e="http://schemas.xmlsoap.org/soap/envelope/"><e:Body><e:Fault><detail><UPnPError><errorCode>$faultCode</errorCode><errorDescription>Transition not available</errorDescription></UPnPError></detail></e:Fault></e:Body></e:Envelope>');
        } else if (action.name.local.startsWith('Get')) {
          final values = action.name.local == 'GetPositionInfo'
              ? '<RelTime>00:01:03.500</RelTime><TrackDuration>01:20:00</TrackDuration>'
              : '<CurrentTransportState>$transportState</CurrentTransportState>';
          request.response.write(
              '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><different:${action.name.local}Response xmlns:different="${action.name.namespaceUri}">$values</different:${action.name.local}Response></s:Body></s:Envelope>');
        } else {
          request.response.statusCode = 204;
        }
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
  });
  tearDown(() => renderer.close(force: true));

  test(
      'missing URLBase, vendor service IDs, relative and absolute control URLs work',
      () async {
    final device = await CastScreen.fetchDevice('$base/desc/device.xml');
    expect(device.spec.friendlyName, '客厅电视');
    expect(device.avTransportService!.spec.controlReqURL, '$base/control/av');
    expect(device.renderingControlService!.spec.controlReqURL,
        '$base/control/volume');
    await device.play(const PlayInput());
    await device.pause(const PauseInput());
    await device.stop(const StopInput());
    expect(actions, ['Play', 'Pause', 'Stop']);
    fault = true;
    await expectLater(
        device.play(const PlayInput()),
        throwsA(isA<CastProtocolException>()
            .having((e) => e.upnpCode, 'code', 701)));
  });

  test(
      'real UDP discovery waits for descriptions and overlapping scans are independent',
      () async {
    final udp = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(udp.close);
    udp.listen((event) {
      if (event != RawSocketEvent.read) return;
      final packet = udp.receive();
      if (packet == null) return;
      expect(utf8.decode(packet.data), contains('MAN: "ssdp:discover"'));
      udp.send(
          utf8.encode(
              'HTTP/1.1 200 OK\r\nlocation: $base/desc/device.xml\r\nst: upnp:rootdevice\r\nusn: uuid:living-room\r\n\r\n'),
          packet.address,
          packet.port);
    });
    Future<List<Device>> scan() => CastScreen.discoverDevice(
        bindAddresses: [InternetAddress.loopbackIPv4],
        discoveryAddress: InternetAddress.loopbackIPv4,
        discoveryPort: udp.port,
        timeout: const Duration(milliseconds: 100));
    final results = await Future.wait([scan(), scan()]);
    expect(results[0].single.spec.uuid, 'living-room');
    expect(results[1].single.spec.uuid, 'living-room');
    expect(CastScreen.parseSsdpPacket(utf8.encode('garbage')), isNull);
    expect(
        CastScreen.parseSsdpPacket(utf8.encode(
                'NOTIFY * HTTP/1.1\r\nLOCATION: $base/desc/device.xml\r\nNT: upnp:rootdevice\r\n'))![
            'ST'],
        'upnp:rootdevice');
  });

  test(
      'local file and loopback relay support HEAD, ranges and token protection',
      () async {
    final service = MediaCastService.forTesting(advertisedHost: '127.0.0.1');
    final dir = await Directory.systemTemp.createTemp('cast-media-');
    final file = File('${dir.path}/中文 #%.mp4');
    await file.writeAsBytes(List.generate(1024, (i) => i % 256));
    addTearDown(() async {
      await service.disconnectFromDevice();
      service.dispose();
      await dir.delete(recursive: true);
    });
    final url = await service.startLocalServer(file.path);
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final head = await (await client.headUrl(Uri.parse(url))).close();
    expect(head.statusCode, 200);
    expect(head.contentLength, 1024);
    await head.drain<void>();
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set('Range', 'bytes=100-199');
    final res = await req.close();
    expect(res.statusCode, 206);
    expect(await res.expand((b) => b).toList(),
        List.generate(100, (i) => i + 100));
    final denied =
        await (await client.getUrl(Uri.parse(url).replace(query: ''))).close();
    expect(denied.statusCode, 403);
    await denied.drain<void>();
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => upstream.close(force: true));
    upstream.listen((r) async {
      expect(r.headers.value('Authorization'), 'Bearer test');
      expect(r.headers.value('Range'), 'bytes=1-2');
      r.response.statusCode = 206;
      r.response.headers.set('Content-Range', 'bytes 1-2/4');
      r.response.contentLength = 2;
      r.response.add([8, 9]);
      await r.response.close();
    });
    final relay = await service.startLocalServer(
        'http://127.0.0.1:${upstream.port}/sample.mp4',
        headers: {'Authorization': 'Bearer test'});
    final rr = await client.getUrl(Uri.parse(relay));
    rr.headers.set('Range', 'bytes=1-2');
    final rs = await rr.close();
    expect(rs.statusCode, 206);
    expect(await rs.expand((b) => b).toList(), [8, 9]);
  });

  test(
      'network cast carries metadata, starts at current position and surfaces receiver errors',
      () async {
    final service = MediaCastService.forTesting(advertisedHost: '127.0.0.1');
    addTearDown(() async {
      await service.disconnectFromDevice();
      service.dispose();
    });
    final device = CastDevice(
        device: await CastScreen.fetchDevice('$base/desc/device.xml'));
    expect(await service.connectToDevice(device), isTrue);
    expect(
        await service.castMedia('https://example.com/a.mp4?one=1&two=2',
            title: '中文 & 标题', startPosition: const Duration(seconds: 30)),
        isTrue);
    expect(receivedUri, 'https://example.com/a.mp4?one=1&two=2');
    expect(actions.take(3), ['SetAVTransportURI', 'Play', 'Seek']);
    await service.refreshStatus();
    expect(service.position, const Duration(milliseconds: 63500));
    fault = true;
    expect(await service.pauseMedia(), isFalse);
    expect(service.lastError, contains('701'));
    fault = false;
    expect(await service.disconnectFromDevice(), isTrue);
    expect(service.activeDevice, isNull);
  });

  test(
      'metadata rejection and transient PLAY state have bounded compatibility retries',
      () async {
    final service = MediaCastService.forTesting(advertisedHost: '127.0.0.1');
    addTearDown(() async {
      await service.disconnectFromDevice();
      service.dispose();
    });
    await service.connectToDevice(CastDevice(
        device: await CastScreen.fetchDevice('$base/desc/device.xml')));
    commandFaults['SetAVTransportURI'] = [714];
    commandFaults['Play'] = [701, 701];
    expect(await service.castMedia('https://example.com/video.mp4'), isTrue);
    expect(metadataSent.length, 2);
    expect(metadataSent.last, isEmpty);
    expect(actions.where((action) => action == 'Play').length, 3);
  });

  test(
      'failed replacement retains the existing media relay; disconnect releases it',
      () async {
    final service = MediaCastService.forTesting(advertisedHost: '127.0.0.1');
    addTearDown(service.dispose);
    final temp = await Directory.systemTemp.createTemp('cast-replace-');
    addTearDown(() => temp.delete(recursive: true));
    final media = File('${temp.path}/movie.mp4');
    await media.writeAsBytes([1, 2, 3, 4]);
    await service.connectToDevice(CastDevice(
        device: await CastScreen.fetchDevice('$base/desc/device.xml')));
    expect(await service.castMedia(media.path), isTrue);
    final old = Uri.parse(receivedUri);
    fault = true;
    expect(await service.castMedia('https://example.com/next.mp4'), isFalse);
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final response = await (await client.getUrl(old)).close();
    expect(await response.fold<List<int>>([], (all, next) => all..addAll(next)),
        [1, 2, 3, 4]);
    fault = false;
    await service.disconnectFromDevice();
    await expectLater(() async {
      await (await client.getUrl(old)).close();
    }, throwsA(anyOf(isA<SocketException>(), isA<HttpException>())));
  });

  test(
      'queued pause invalidates an older status read and no command runs after disposal',
      () async {
    final service = MediaCastService.forTesting();
    await service.connectToDevice(CastDevice(
        device: await CastScreen.fetchDevice('$base/desc/device.xml')));
    positionGate = Completer<void>();
    positionStarted = Completer<void>();
    final poll = service.refreshStatus();
    await positionStarted!.future;
    final paused = service.pauseMedia();
    expect(service.busy, isTrue);
    positionGate!.complete();
    await poll;
    expect(await paused, isTrue);
    expect(actions, ['GetPositionInfo', 'Pause']);
    expect(service.position, Duration.zero);
    expect(service.activeDevice!.isPlaying, isFalse);
    service.dispose();
    service.dispose();
    expect(await service.resumeMedia(), isFalse);
  });
  test('handover waits for playback even when position queries are unsupported',
      () async {
    final service = MediaCastService.forTesting();
    addTearDown(service.dispose);
    await service.connectToDevice(CastDevice(
        device: await CastScreen.fetchDevice('$base/desc/device.xml')));
    transportState = 'TRANSITIONING';
    var started = 0;
    expect(
        await service.castMedia('https://example.com/a.mp4',
            mediaDuration: const Duration(minutes: 5),
            onPlaybackStarted: () => started++),
        isTrue);
    expect(started, 0);
    expect(service.awaitingPlayback, isTrue);
    commandFaults['GetPositionInfo'] = [401];
    transportState = 'PLAYING';
    await service.refreshStatus();
    expect(started, 1);
    expect(service.awaitingPlayback, isFalse);
    expect(service.duration, const Duration(minutes: 5));
    await service.refreshStatus();
    expect(started, 1);
    expect(actions.where((a) => a == 'GetPositionInfo').length, 1);
    await service.stopMedia();
    transportState = 'TRANSITIONING';
    await service.resumeMedia(onPlaybackStarted: () => started++);
    transportState = 'PLAYING';
    await Future<void>.delayed(const Duration(milliseconds: 2300));
    expect(started, 2, reason: 'resume restarts polling after stop');
  });

  test('relay handover requires media bytes as well as PLAYING', () async {
    final service = MediaCastService.forTesting(advertisedHost: '127.0.0.1');
    addTearDown(service.dispose);
    final temp = await Directory.systemTemp.createTemp('cast-confirm-');
    addTearDown(() => temp.delete(recursive: true));
    final file =
        await File('${temp.path}/sample.mp4').writeAsBytes([1, 2, 3, 4]);
    await service.connectToDevice(CastDevice(
        device: await CastScreen.fetchDevice('$base/desc/device.xml')));
    var started = 0;
    await service.castMedia(file.path, onPlaybackStarted: () => started++);
    expect(started, 0);
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    await (await (await client.getUrl(Uri.parse(receivedUri))).close())
        .drain<void>();
    await service.refreshStatus();
    expect(started, 1);
    await service.refreshStatus();
    expect(started, 1);
    await service.disconnectFromDevice();
  });

  test('unsupported transport status does not falsely pause local playback',
      () async {
    final service = MediaCastService.forTesting();
    addTearDown(service.dispose);
    await service.connectToDevice(CastDevice(
        device: await CastScreen.fetchDevice('$base/desc/device.xml')));
    commandFaults['GetTransportInfo'] = [401];
    var started = 0;
    expect(
        await service.castMedia('https://example.com/a.mp4',
            onPlaybackStarted: () => started++),
        isTrue);
    await service.refreshStatus();
    expect(started, 0);
    expect(service.statusWarning, contains('手动暂停'));
    expect(actions.where((a) => a == 'GetTransportInfo').length, 1);
  });

  test('malformed receiver time is bounded and fractional seconds survive', () {
    for (final time in [
      '00:00:NaN',
      'Infinity:00:00',
      '-1:00:00',
      '00:60:00',
      '00:00:60',
      'NOT_IMPLEMENTED'
    ]) {
      expect(MediaCastService.parseTime(time), Duration.zero);
    }
    expect(MediaCastService.parseTime('01:02:03.456'),
        const Duration(milliseconds: 3723456));
  });
}
