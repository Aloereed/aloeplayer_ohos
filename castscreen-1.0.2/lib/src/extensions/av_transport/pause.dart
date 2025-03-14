// ignore_for_file: non_constant_identifier_names

part of 'extension.dart';

/// The Pause action input
final class PauseInput {
  /// The input argument InstanceID
  final String InstanceID;

  const PauseInput({this.InstanceID = _defaultInstanceID});

  /// The static method toMap
  static Map<String, String> toMap(PauseInput input) {
    return {'InstanceID': input.InstanceID};
  }
}

/// The Pause action output
final class PauseOutput {
  const PauseOutput();

  /// The factory method fromMap
  factory PauseOutput.fromMap(Map<String, String> m) {
    return const PauseOutput();
  }
}
