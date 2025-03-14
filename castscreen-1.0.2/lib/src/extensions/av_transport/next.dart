// ignore_for_file: non_constant_identifier_names

part of 'extension.dart';

/// The Next action input
final class NextInput {
  /// The input argument InstanceID
  final String InstanceID;

  const NextInput({this.InstanceID = _defaultInstanceID});

  /// The static method toMap
  static Map<String, String> toMap(NextInput input) {
    return {'InstanceID': input.InstanceID};
  }
}

/// The Next action output
final class NextOutput {
  const NextOutput();

  /// The factory method fromMap
  factory NextOutput.fromMap(Map<String, String> m) {
    return const NextOutput();
  }
}
