// ignore_for_file: non_constant_identifier_names

part of 'extension.dart';

/// The Play action input
final class PlayInput {
  /// The input argument InstanceID
  final String InstanceID;

  /// The input argument Speed
  final String Speed;

  const PlayInput(
      {this.InstanceID = _defaultInstanceID, this.Speed = _defaultSpeed});

  /// The static method toMap
  static Map<String, String> toMap(PlayInput input) {
    return {'InstanceID': input.InstanceID, 'Speed': input.Speed};
  }
}

/// The Play action output
final class PlayOutput {
  const PlayOutput();

  /// The factory method fromMap
  factory PlayOutput.fromMap(Map<String, String> m) {
    return const PlayOutput();
  }
}
