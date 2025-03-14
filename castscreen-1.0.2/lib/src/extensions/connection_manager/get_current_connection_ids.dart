// ignore_for_file: non_constant_identifier_names

part of 'extension.dart';

/// The GetCurrentConnectionIDs action input
final class GetCurrentConnectionIDsInput {
  const GetCurrentConnectionIDsInput();

  /// The static method toMap
  static Map<String, String> toMap(GetCurrentConnectionIDsInput input) {
    return {};
  }
}

/// The GetCurrentConnectionIDs action output
final class GetCurrentConnectionIDsOutput {
  /// The output argument ConnectionIDs
  final String ConnectionIDs;

  const GetCurrentConnectionIDsOutput(this.ConnectionIDs);

  /// The factory method fromMap
  factory GetCurrentConnectionIDsOutput.fromMap(Map<String, String> m) {
    return GetCurrentConnectionIDsOutput(m['ConnectionIDs'] ?? '');
  }
}
