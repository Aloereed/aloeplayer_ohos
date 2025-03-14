// ignore_for_file: non_constant_identifier_names

part of 'extension.dart';

/// The Previous action input
final class PreviousInput {
  /// The input argument InstanceID
  final String InstanceID;

  const PreviousInput({this.InstanceID = _defaultInstanceID});

  /// The static method toMap
  static Map<String, String> toMap(PreviousInput input) {
    return {'InstanceID': input.InstanceID};
  }
}

/// The Previous action output
final class PreviousOutput {
  const PreviousOutput();

  /// The factory method fromMap
  factory PreviousOutput.fromMap(Map<String, String> m) {
    return const PreviousOutput();
  }
}
