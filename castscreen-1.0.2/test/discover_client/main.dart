import 'package:castscreen/castscreen.dart';

void main(List<String> args) async {
  final clients = await CastScreen.discoverClient();
  for (var client in clients) {
    print(client);
  }
}
