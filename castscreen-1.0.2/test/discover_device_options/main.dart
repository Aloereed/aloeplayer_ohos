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
