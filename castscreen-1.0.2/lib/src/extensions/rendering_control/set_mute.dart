// ignore_for_file: non_constant_identifier_names

part of 'extension.dart';

/// The SetMute action input
final class SetMuteInput {
  /// The input argument InstanceID
  final String InstanceID;

  /// The input argument Channel
  final String Channel;

  /// The input argument DesiredMute
  final bool DesiredMute;

  const SetMuteInput(this.DesiredMute,
      {this.InstanceID = _defaultInstanceID, this.Channel = _defaultChannel});

  /// The static method toMap
  static Map<String, String> toMap(SetMuteInput input) {
    return {
      'InstanceID': input.InstanceID,
      'Channel': input.Channel,
      'DesiredMute': '${input.DesiredMute}'
    };
  }
}

/// The SetMute action output
final class SetMuteOutput {
  const SetMuteOutput();

  /// The factory method fromMap
  factory SetMuteOutput.fromMap(Map<String, String> m) {
    return const SetMuteOutput();
  }
}
