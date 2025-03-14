// ignore_for_file: non_constant_identifier_names

part of 'extension.dart';

/// The Stop action input
final class StopInput {
  /// The input argument InstanceID
  final String InstanceID;

  const StopInput({this.InstanceID = _defaultInstanceID});

  /// The static method toMap
  static Map<String, String> toMap(StopInput input) {
    return {'InstanceID': input.InstanceID};
  }
}

/// The Stop action output
final class StopOutput {
  const StopOutput();

  /// The factory method fromMap
  factory StopOutput.fromMap(Map<String, String> m) {
    return const StopOutput();
  }
}
