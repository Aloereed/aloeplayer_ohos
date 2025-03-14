# dart_castscreen

A dart package can cast video streams to UPnP & DLNA devices.

## Features
- Discover UPnP Client/Device
- Specs for Client/Device/Service/Action
- Invoking action for map/generics
- Provided wonderful Extensions

## Examples
- [Discover client](https://github.com/rwscode/dart_castscreen/blob/main/test/discover_client/main.dart)
```dart
import 'package:castscreen/castscreen.dart';

void main(List<String> args) async {
  final clients = await CastScreen.discoverClient();
  for (var client in clients) {
    print(client);
  }
}
```

- [Discover client with options](https://github.com/rwscode/dart_castscreen/blob/main/test/discover_client_options/main.dart)
```dart
import 'package:castscreen/castscreen.dart';

void main(List<String> args) async {
  final clients = await CastScreen.discoverClient(
    ipv4: true,
    ipv6: false,
    port: 1900,
    ST: 'upnp:rootdevice',
    timeout: const Duration(seconds: 3),
    onError: (Exception e) => print('error: $e'),
  );
  for (var client in clients) {
    print(client);
  }
}
```

- [Discover device](https://github.com/rwscode/dart_castscreen/blob/main/test/discover_device/main.dart)
```dart
import 'package:castscreen/castscreen.dart';

void main(List<String> args) async {
  final devices = await CastScreen.discoverDevice();
  for (var device in devices) {
    print(device);
  }
}
```

- [Discover device with options](https://github.com/rwscode/dart_castscreen/blob/main/test/discover_device_options/main.dart)
```dart
import 'package:castscreen/castscreen.dart';

void main(List<String> args) async {
  final devices = await CastScreen.discoverDevice(
    ipv4: true,
    ipv6: false,
    port: 1900,
    ST: 'upnp:rootdevice',
    timeout: const Duration(seconds: 3),
    onError: (Exception e) => print('error: $e'),
  );
  for (var device in devices) {
    print(device);
  }
}
```

- [Invoke action for generics](https://github.com/rwscode/dart_castscreen/blob/main/test/invoke_action_generics/main.dart)
```dart
import 'package:castscreen/castscreen.dart';

void main(List<String> args) async {
  final devices = await CastScreen.discoverDevice();
  final dev = devices.first;
  final alive = await dev.alive();
  if (!alive) {
    print('Device is not alive.');
    return;
  }
  final output = await dev.avTransportService!
      .invoke<CustomActionInput, CustomActionOutput>(
    'Custom',
    CustomActionInput(),
    CustomActionInput.toMap,
    CustomActionOutput.fromMap,
  );
  print(output);
}

final class CustomActionInput {
  const CustomActionInput();
  static Map<String, String> toMap(CustomActionInput input) {
    return {};
  }
}

final class CustomActionOutput {
  const CustomActionOutput();
  factory CustomActionOutput.fromMap(Map<String, String> m) {
    return const CustomActionOutput();
  }
}
```

- [Invoke action for map](https://github.com/rwscode/dart_castscreen/blob/main/test/invoke_action_map/main.dart)
```dart
import 'package:castscreen/castscreen.dart';

void main(List<String> args) async {
  final devices = await CastScreen.discoverDevice();
  final dev = devices.first;
  final alive = await dev.alive();
  if (!alive) {
    print('Device is not alive.');
    return;
  }
  final output = await dev.avTransportService!.invokeMap('Custom', {});
  print(output);
}
```

- [Invoke setAVTransportURI](https://github.com/rwscode/dart_castscreen/blob/main/test/invoke_set_av_transport_uri/main.dart)
```dart
import 'package:castscreen/castscreen.dart';

void main(List<String> args) async {
  final devices = await CastScreen.discoverDevice();
  final dev = devices.first;
  final alive = await dev.alive();
  if (!alive) {
    print('Device is not alive.');
    return;
  }
  final output = await dev
      .setAVTransportURI(SetAVTransportURIInput('http://example.com/v.mp4'));
  print(output);
}
```

- [Invoke stop](https://github.com/rwscode/dart_castscreen/blob/main/test/invoke_stop/main.dart)
```dart
import 'package:castscreen/castscreen.dart';

void main(List<String> args) async {
  final devices = await CastScreen.discoverDevice();
  final dev = devices.first;
  final alive = await dev.alive();
  if (!alive) {
    print('Device is not alive.');
    return;
  }
  final output = await dev.stop(StopInput());
  print(output);
}
```

## [Extensions](https://github.com/rwscode/dart_castscreen/blob/main/lib/src/extensions/lib.dart)
- [AVTransport](https://github.com/rwscode/dart_castscreen/blob/main/lib/src/extensions/av_transport/extension.dart)
  - [Next](https://github.com/rwscode/dart_castscreen/blob/main/lib/src/extensions/av_transport/next.dart)
  - [Pause](https://github.com/rwscode/dart_castscreen/blob/main/lib/src/extensions/av_transport/pause.dart)
  - [Play](https://github.com/rwscode/dart_castscreen/blob/main/lib/src/extensions/av_transport/play.dart)
  - [Previous](https://github.com/rwscode/dart_castscreen/blob/main/lib/src/extensions/av_transport/previous.dart)
  - [SetAVTransportURI](https://github.com/rwscode/dart_castscreen/blob/main/lib/src/extensions/av_transport/set_av_transport_uri.dart)
  - [Stop](https://github.com/rwscode/dart_castscreen/blob/main/lib/src/extensions/av_transport/stop.dart)
- [ConnectionManager](https://github.com/rwscode/dart_castscreen/blob/main/lib/src/extensions/connection_manager/extension.dart)
  - [GetCurrentConnectionIDs](https://github.com/rwscode/dart_castscreen/blob/main/lib/src/extensions/connection_manager/get_current_connection_ids.dart)
  - [GetCurrentConnectionInfo](https://github.com/rwscode/dart_castscreen/blob/main/lib/src/extensions/connection_manager/get_current_connection_info.dart)
  - [GetProtocolInfo](https://github.com/rwscode/dart_castscreen/blob/main/lib/src/extensions/connection_manager/get_protocol_info.dart)
- [RenderingControl](https://github.com/rwscode/dart_castscreen/blob/main/lib/src/extensions/rendering_control/extension.dart)
  - [GetMute](https://github.com/rwscode/dart_castscreen/blob/main/lib/src/extensions/rendering_control/get_mute.dart)
  - [GetVolumeDBRange](https://github.com/rwscode/dart_castscreen/blob/main/lib/src/extensions/rendering_control/get_volume_db_range.dart)
  - [GetVolumeDB](https://github.com/rwscode/dart_castscreen/blob/main/lib/src/extensions/rendering_control/get_volume_db.dart)
  - [GetVolume](https://github.com/rwscode/dart_castscreen/blob/main/lib/src/extensions/rendering_control/get_volume.dart)
  - [SetMute](https://github.com/rwscode/dart_castscreen/blob/main/lib/src/extensions/rendering_control/set_mute.dart)
  - [SetVolume](https://github.com/rwscode/dart_castscreen/blob/main/lib/src/extensions/rendering_control/set_volume.dart)

## SCPD files
- [Root.xml](https://github.com/rwscode/dart_castscreen/blob/main/scpd_files/Root.xml)
- [AVTransport_scpd.xml](https://github.com/rwscode/dart_castscreen/blob/main/scpd_files/AVTransport_scpd.xml)
- [RControl_scpd.xml](https://github.com/rwscode/dart_castscreen/blob/main/scpd_files/RControl_scpd.xml)
- [ConnectionManager_scpd.xml](https://github.com/rwscode/dart_castscreen/blob/main/scpd_files/ConnectionManager_scpd.xml)
- [RenderingControl_scpd.xml](https://github.com/rwscode/dart_castscreen/blob/main/scpd_files/RenderingControl_scpd.xml)

## Protocol
- [SSDP](https://en.wikipedia.org/wiki/Simple_Service_Discovery_Protocol)
- [UPnP](https://en.wikipedia.org/wiki/Universal_Plug_and_Play)
