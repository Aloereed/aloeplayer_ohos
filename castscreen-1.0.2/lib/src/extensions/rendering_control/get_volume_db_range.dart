// ignore_for_file: non_constant_identifier_names

part of 'extension.dart';

/// The GetVolumeDBRange action input
final class GetVolumeDBRangeInput {
  /// The input argument InstanceID
  final String InstanceID;

  /// The input argument Channel
  final String Channel;

  const GetVolumeDBRangeInput(
      {this.InstanceID = _defaultInstanceID, this.Channel = _defaultChannel});

  /// The static method toMap
  static Map<String, String> toMap(GetVolumeDBRangeInput input) {
    return {'InstanceID': input.InstanceID, 'Channel': input.Channel};
  }
}

/// The GetVolumeDBRange action output
final class GetVolumeDBRangeOutput {
  /// The output argument MinValue
  /// <allowedValueRange>
  ///     <minimum>-32768</minimum>
  ///     <maximum>32767</maximum>
  /// </allowedValueRange>
  final String MinValue;

  /// The output argument MaxValue
  /// <allowedValueRange>
  ///     <minimum>-32768</minimum>
  ///     <maximum>32767</maximum>
  /// </allowedValueRange>
  final String MaxValue;

  const GetVolumeDBRangeOutput(this.MinValue, this.MaxValue);

  /// The factory method fromMap
  factory GetVolumeDBRangeOutput.fromMap(Map<String, String> m) {
    return GetVolumeDBRangeOutput(m['MinValue'] ?? '0', m['MaxValue'] ?? '0');
  }
}
