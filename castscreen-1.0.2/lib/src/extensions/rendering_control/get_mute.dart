// ignore_for_file: non_constant_identifier_names

part of 'extension.dart';

/// The GetMute action input
final class GetMuteInput {
  /// The input argument InstanceID
  final String InstanceID;

  /// The input argument Channel
  /// <allowedValueList>
  ///   <allowedValue>Master</allowedValue>
  ///   <allowedValue>LF</allowedValue>
  ///   <allowedValue>RF</allowedValue>
  /// </allowedValueList>
  final String Channel;

  const GetMuteInput(
      {this.InstanceID = _defaultInstanceID, this.Channel = _defaultChannel});

  /// The static method toMap
  static Map<String, String> toMap(GetMuteInput input) {
    return {'InstanceID': input.InstanceID, 'Channel': input.Channel};
  }
}

/// The GetMute action output
final class GetMuteOutput {
  /// The output argument CurrentMute
  final bool CurrentMute;

  const GetMuteOutput(this.CurrentMute);

  /// The factory method fromMap
  factory GetMuteOutput.fromMap(Map<String, String> m) {
    return GetMuteOutput((m['CurrentMute'] ?? 'false') == 'true');
  }
}
