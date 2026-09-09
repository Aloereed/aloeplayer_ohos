import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/cast_network_address.dart';

void main() {
  test('advertises explicit sender address, never the receiver address', () async {
    // Both addresses are loopback fixtures; no user device is contacted.
    final receiver = await ServerSocket.bind('127.0.0.2', 0);
    final accepted = receiver.first;
    final source = await selectCastSourceAddress(
        Uri.parse('http://127.0.0.2:${receiver.port}/description.xml'),
        [InternetAddress('127.0.0.1')]);
    final peer = await accepted;
    expect(source, '127.0.0.1');
    expect(peer.remoteAddress.address, source);
    peer.destroy();
    await receiver.close();
  });

  test('no usable local address fails instead of advertising receiver', () async {
    await expectLater(
        selectCastSourceAddress(Uri.parse('http://127.0.0.2:12345'), []),
        throwsStateError);
  });
}
