// ignore_for_file: non_constant_identifier_names

part of 'extension.dart';

/// The GetVolumeDB action input
final class GetVolumeDBInput {
  /// The input argument InstanceID
  final String InstanceID;

  /// The input argument Channel
  final String Channel;

  const GetVolumeDBInput(
      {this.InstanceID = _defaultInstanceID, this.Channel = _defaultChannel});

  /// The static method toMap
  static Map<String, String> toMap(GetVolumeDBInput input) {
    return {'InstanceID': input.InstanceID, 'Channel': input.Channel};
  }
}

/// The GetVolumeDB action output
final class GetVolumeDBOutput {
  /// The output argument CurrentVolume
  final String CurrentVolume;

  const GetVolumeDBOutput(this.CurrentVolume);

  /// The factory method fromMap
  factory GetVolumeDBOutput.fromMap(Map<String, String> m) {
    return GetVolumeDBOutput(m['CurrentVolume'] ?? '0');
  }
}
