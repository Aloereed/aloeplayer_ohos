// ignore_for_file: non_constant_identifier_names

part of 'extension.dart';

/// The SetVolume action output
final class SetVolumeInput {
  /// The input argument InstanceID
  final String InstanceID;

  /// The input argument Channel
  final String Channel;

  /// The input argument DesiredVolume
  /// <allowedValueRange>
  ///   <minimum>0</minimum>
  ///   <maximum>100</maximum>
  ///   <step>1</step>
  /// </allowedValueRange>
  final int DesiredVolume;

  const SetVolumeInput(this.DesiredVolume,
      {this.InstanceID = _defaultInstanceID, this.Channel = _defaultChannel});

  /// The static method toMap
  static Map<String, String> toMap(SetVolumeInput input) {
    return {
      'InstanceID': input.InstanceID,
      'Channel': input.Channel,
      'DesiredVolume': '${input.DesiredVolume}'
    };
  }
}

/// The SetVolume action output
final class SetVolumeOutput {
  const SetVolumeOutput();

  /// The factory method fromMap
  factory SetVolumeOutput.fromMap(Map<String, String> m) {
    return const SetVolumeOutput();
  }
}
