import 'dart:io';

/// Verify reachability with an explicit source address. Socket.address on an
/// outbound Dart socket is the address used to connect, not getsockname().
Future<String> selectCastSourceAddress(
    Uri destination, Iterable<InternetAddress> candidates,
    {Duration timeout = const Duration(seconds: 2)}) async {
  final remote = InternetAddress.tryParse(destination.host);
  final elapsed = Stopwatch()..start();
  for (final source in candidates) {
    final remaining = const Duration(seconds: 8) - elapsed.elapsed;
    if (remaining <= Duration.zero) break;
    if (remote != null && source.type != remote.type) continue;
    Socket? socket;
    try {
      socket = await Socket.connect(destination.host, destination.port,
          sourceAddress: source,
          timeout: remaining < timeout ? remaining : timeout);
      return source.address;
    } on SocketException {
      // Try another local interface, never advertise the receiver's address.
    } finally {
      socket?.destroy();
    }
  }
  throw StateError('没有找到可连接接收端的本机网络，请检查 Wi-Fi 或选择投屏网络');
}
