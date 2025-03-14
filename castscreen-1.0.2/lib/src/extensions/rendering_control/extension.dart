// ignore_for_file: non_constant_identifier_names

library castscreen.extensions.renderingcontrol;

import 'package:castscreen/src/core/lib.dart';

part 'get_mute.dart';
part 'get_volume_db_range.dart';
part 'get_volume_db.dart';
part 'get_volume.dart';
part 'set_mute.dart';
part 'set_volume.dart';

const _defaultInstanceID = '1';
const _defaultChannel = 'Master';

/// The action extension to implements RenderingControl SCPD Service
extension RenderingControlActionsExtension on Device {
  /// Get mute
  Future<GetMuteOutput> getMute(GetMuteInput input) =>
      renderingControlService!.invoke(
        'GetMute',
        input,
        GetMuteInput.toMap,
        GetMuteOutput.fromMap,
      );

  /// Get volume db range
  Future<GetVolumeDBRangeOutput> getVolumeDBRange(
          GetVolumeDBRangeInput input) =>
      renderingControlService!.invoke(
        'GetVolumeDBRange',
        input,
        GetVolumeDBRangeInput.toMap,
        GetVolumeDBRangeOutput.fromMap,
      );

  /// Get volume db
  Future<GetVolumeDBOutput> getVolumeDB(GetVolumeDBInput input) =>
      renderingControlService!.invoke(
        'GetVolumeDB',
        input,
        GetVolumeDBInput.toMap,
        GetVolumeDBOutput.fromMap,
      );

  /// Get volume
  Future<GetVolumeOutput> getVolume(GetVolumeInput input) =>
      renderingControlService!.invoke(
        'GetVolume',
        input,
        GetVolumeInput.toMap,
        GetVolumeOutput.fromMap,
      );

  /// Set mute
  Future<SetMuteOutput> setMute(SetMuteInput input) =>
      renderingControlService!.invoke(
        'SetMute',
        input,
        SetMuteInput.toMap,
        SetMuteOutput.fromMap,
      );

  /// Set volume
  Future<SetVolumeOutput> setVolume(SetVolumeInput input) =>
      renderingControlService!.invoke(
        'SetVolume',
        input,
        SetVolumeInput.toMap,
        SetVolumeOutput.fromMap,
      );
}
