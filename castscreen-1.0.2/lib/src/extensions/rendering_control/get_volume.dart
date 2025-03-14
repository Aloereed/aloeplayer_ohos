// ignore_for_file: non_constant_identifier_names

part of 'extension.dart';

/// The GetVolume action input
final class GetVolumeInput {
  /// The input argument InstanceID
  final String InstanceID;

  /// The input argument Channel
  final String Channel;

  const GetVolumeInput(
      {this.InstanceID = _defaultInstanceID, this.Channel = _defaultChannel});

  /// The static method toMap
  static Map<String, String> toMap(GetVolumeInput input) {
    return {'InstanceID': input.InstanceID, 'Channel': input.Channel};
  }
}

/// The GetVolume action output
final class GetVolumeOutput {
  /// The output argument CurrentVolume
  final String CurrentVolume;

  const GetVolumeOutput(this.CurrentVolume);

  /// The factory method fromMap
  factory GetVolumeOutput.fromMap(Map<String, String> m) {
    return GetVolumeOutput(m['CurrentVolume'] ?? '0');
  }
}
