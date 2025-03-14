// ignore_for_file: non_constant_identifier_names

part of 'extension.dart';

// The GetProtocolInfo action input
final class GetProtocolInfoInput {
  const GetProtocolInfoInput();

  /// The static method toMap
  static Map<String, String> toMap(GetProtocolInfoInput input) {
    return {};
  }
}

// The GetProtocolInfo action output
final class GetProtocolInfoOutput {
  /// The output argument Source
  final String Source;

  /// The output argument Sink
  final String Sink;

  const GetProtocolInfoOutput(this.Source, this.Sink);

  /// The factory method fromMap
  factory GetProtocolInfoOutput.fromMap(Map<String, String> m) {
    return GetProtocolInfoOutput(m['Source'] ?? '', m['Sink'] ?? '');
  }
}
