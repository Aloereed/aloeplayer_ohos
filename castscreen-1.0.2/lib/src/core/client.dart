// ignore_for_file: non_constant_identifier_names

part of 'lib.dart';

/// The discover client
final class Client {
  /// The client ST from headers
  final String ST;

  /// The client USN from headers
  final String USN;

  /// The client LOCATION from headers
  final String LOCATION;

  /// The client SERVER from headers
  final String SERVER;

  /// The client headers
  final Map<String, String> headers;

  const Client(this.ST, this.USN, this.LOCATION, this.SERVER, this.headers);

  /// The factory method fromHeader
  factory Client.fromHeader(Map<String, String> headers) {
    return Client(
      _h(headers, 'ST'),
      _h(headers, 'USN'),
      _h(headers, 'LOCATION'),
      _h(headers, 'SERVER'),
      headers,
    );
  }

  static String _h(Map<String, String> headers, String name) =>
      headers[name] ?? '';

  @override
  String toString() {
    return '{ST: $ST, USN: $USN, LOCATION: $LOCATION, SERVER: $SERVER}';
  }
}
