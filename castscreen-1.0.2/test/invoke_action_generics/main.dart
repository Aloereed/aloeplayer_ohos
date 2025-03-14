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
