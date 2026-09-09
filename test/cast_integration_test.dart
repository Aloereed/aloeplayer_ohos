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
  var receivedUri = '';
  setUp(() async {
    actions.clear(); fault = false; receivedUri = '';
    renderer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${renderer.port}';
    renderer.listen((request) async {
      if (request.method == 'GET' && request.uri.path == '/desc/device.xml') {
        request.response.write('''<d:root xmlns:d="urn:schemas-upnp-org:device-1-0"><d:device><d:deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</d:deviceType><d:friendlyName>客厅电视</d:friendlyName><d:UDN>uuid:living-room</d:UDN><d:serviceList>
<d:service><d:serviceType>urn:schemas-upnp-org:service:AVTransport:2</d:serviceType><d:serviceId>vendor:transport</d:serviceId><d:controlURL>../control/av</d:controlURL><d:SCPDURL>/missing.xml</d:SCPDURL></d:service>
<d:service><d:serviceType>urn:schemas-upnp-org:service:RenderingControl:1</d:serviceType><d:serviceId>vendor:volume</d:serviceId><d:controlURL>$base/control/volume</d:controlURL></d:service>
</d:serviceList></d:device></d:root>''');
      } else if (request.method == 'POST' && request.uri.path.startsWith('/control/')) {
        final xml = XmlDocument.parse(await utf8.decoder.bind(request).join());
        final body = xml.descendants.whereType<XmlElement>().firstWhere((e) => e.name.local == 'Body');
        final action = body.childElements.first;
        actions.add(action.name.local);
        final args = {for (final e in action.childElements) e.name.local:e.innerText};
        expect(args['InstanceID'], '0');
        if (action.name.local == 'SetAVTransportURI') {
          receivedUri = args['CurrentURI']!;
          expect(XmlDocument.parse(args['CurrentURIMetaData']!).rootElement.name.local, 'DIDL-Lite');
        }
        if (fault) {
          request.response.statusCode = 500;
          request.response.write('<e:Envelope xmlns:e="http://schemas.xmlsoap.org/soap/envelope/"><e:Body><e:Fault><detail><UPnPError><errorCode>701</errorCode><errorDescription>Transition not available</errorDescription></UPnPError></detail></e:Fault></e:Body></e:Envelope>');
        } else if (action.name.local.startsWith('Get')) {
          final values = action.name.local == 'GetPositionInfo' ? '<RelTime>00:01:03.500</RelTime><TrackDuration>01:20:00</TrackDuration>' : '<CurrentTransportState>PLAYING</CurrentTransportState>';
          request.response.write('<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><different:${action.name.local}Response xmlns:different="${action.name.namespaceUri}">$values</different:${action.name.local}Response></s:Body></s:Envelope>');
        } else { request.response.statusCode = 204; }
      } else { request.response.statusCode = 404; }
      await request.response.close();
    });
  });
  tearDown(() => renderer.close(force: true));

  test('missing URLBase, vendor service IDs, relative and absolute control URLs work', () async {
    final device = await CastScreen.fetchDevice('$base/desc/device.xml');
    expect(device.spec.friendlyName, '客厅电视');
    expect(device.avTransportService!.spec.controlReqURL, '$base/control/av');
    expect(device.renderingControlService!.spec.controlReqURL, '$base/control/volume');
    await device.play(const PlayInput());
    await device.pause(const PauseInput());
    await device.stop(const StopInput());
    expect(actions, ['Play','Pause','Stop']);
    fault = true;
    await expectLater(device.play(const PlayInput()), throwsA(isA<CastProtocolException>().having((e) => e.upnpCode, 'code',701)));
  });

  test('real UDP discovery waits for descriptions and overlapping scans are independent', () async {
    final udp = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(udp.close);
    udp.listen((event) {
      if (event != RawSocketEvent.read) return;
      final packet = udp.receive(); if (packet == null) return;
      expect(utf8.decode(packet.data), contains('MAN: "ssdp:discover"'));
      udp.send(utf8.encode('HTTP/1.1 200 OK\r\nlocation: $base/desc/device.xml\r\nst: upnp:rootdevice\r\nusn: uuid:living-room\r\n\r\n'),packet.address,packet.port);
    });
    Future<List<Device>> scan() => CastScreen.discoverDevice(bindAddresses:[InternetAddress.loopbackIPv4], discoveryAddress: InternetAddress.loopbackIPv4,
      discoveryPort:udp.port,timeout: const Duration(milliseconds:100));
    final results = await Future.wait([scan(),scan()]);
    expect(results[0].single.spec.uuid, 'living-room');
    expect(results[1].single.spec.uuid, 'living-room');
    expect(CastScreen.parseSsdpPacket(utf8.encode('garbage')), isNull);
    expect(CastScreen.parseSsdpPacket(utf8.encode('NOTIFY * HTTP/1.1\r\nLOCATION: $base/desc/device.xml\r\nNT: upnp:rootdevice\r\n'))!['ST'],'upnp:rootdevice');
  });

  test('local file and loopback relay support HEAD, ranges and token protection', () async {
    final service = MediaCastService.forTesting(advertisedHost:'127.0.0.1');
    final dir = await Directory.systemTemp.createTemp('cast-media-');
    final file = File('${dir.path}/中文 #%.mp4');
    await file.writeAsBytes(List.generate(1024,(i)=>i%256));
    addTearDown(() async { await service.disconnectFromDevice(); service.dispose(); await dir.delete(recursive:true); });
    final url = await service.startLocalServer(file.path);
    final client = HttpClient(); addTearDown(() => client.close(force:true));
    final head = await (await client.headUrl(Uri.parse(url))).close();
    expect(head.statusCode,200); expect(head.contentLength,1024); await head.drain<void>();
    final req = await client.getUrl(Uri.parse(url)); req.headers.set('Range','bytes=100-199');
    final res = await req.close(); expect(res.statusCode,206);
    expect(await res.expand((b)=>b).toList(),List.generate(100,(i)=>i+100));
    final denied = await (await client.getUrl(Uri.parse(url).replace(query:''))).close(); expect(denied.statusCode,403); await denied.drain<void>();
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4,0); addTearDown(() => upstream.close(force:true));
    upstream.listen((r) async { expect(r.headers.value('Authorization'),'Bearer test'); expect(r.headers.value('Range'),'bytes=1-2'); r.response.statusCode=206; r.response.headers.set('Content-Range','bytes 1-2/4');r.response.contentLength=2;r.response.add([8,9]);await r.response.close(); });
    final relay = await service.startLocalServer('http://127.0.0.1:${upstream.port}/sample.mp4',headers:{'Authorization':'Bearer test'});
    final rr = await client.getUrl(Uri.parse(relay)); rr.headers.set('Range','bytes=1-2'); final rs=await rr.close();
    expect(rs.statusCode,206); expect(await rs.expand((b)=>b).toList(),[8,9]);
  });

  test('network cast carries metadata, starts at current position and surfaces receiver errors', () async {
    final service = MediaCastService.forTesting(advertisedHost:'127.0.0.1');
    addTearDown(() async { await service.disconnectFromDevice(); service.dispose(); });
    final device = CastDevice(device:await CastScreen.fetchDevice('$base/desc/device.xml'));
    expect(await service.connectToDevice(device),isTrue);
    expect(await service.castMedia('https://example.com/a.mp4?one=1&two=2',title:'中文 & 标题',startPosition:const Duration(seconds:30)),isTrue);
    expect(receivedUri,'https://example.com/a.mp4?one=1&two=2');
    expect(actions.take(3),['SetAVTransportURI','Play','Seek']);
    await service.refreshStatus(); expect(service.position,const Duration(milliseconds:63500));
    fault=true; expect(await service.pauseMedia(),isFalse); expect(service.lastError,contains('701'));
    fault=false; expect(await service.disconnectFromDevice(),isTrue); expect(service.activeDevice,isNull);
  });
}
