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
