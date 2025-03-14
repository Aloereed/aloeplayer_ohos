// ignore_for_file: non_constant_identifier_names

library castscreen.extensions.av_transport;

import 'package:castscreen/src/core/lib.dart';

part 'next.dart';
part 'pause.dart';
part 'play.dart';
part 'previous.dart';
part 'set_av_transport_uri.dart';
part 'stop.dart';

const _defaultInstanceID = '1';
const _defaultSpeed = '1';

/// The action extension to implements AVTransport SCPD Service
extension AVTransportActionsExtension on Device {
  /// Pause cast screen
  Future<PauseOutput> pause(PauseInput input) => avTransportService!.invoke(
        'Pause',
        input,
        PauseInput.toMap,
        PauseOutput.fromMap,
      );

  /// Play cast screen
  Future<PlayOutput> play(PlayInput input) => avTransportService!.invoke(
        'Play',
        input,
        PlayInput.toMap,
        PlayOutput.fromMap,
      );

  /// Previous cast screen
  Future<PreviousOutput> previous(PreviousInput input) =>
      avTransportService!.invoke(
        'Previous',
        input,
        PreviousInput.toMap,
        PreviousOutput.fromMap,
      );

  /// Set a video stream url cast screen
  Future<SetAVTransportURIOutput> setAVTransportURI(
          SetAVTransportURIInput input) =>
      avTransportService!.invoke(
        'SetAVTransportURI',
        input,
        SetAVTransportURIInput.toMap,
        SetAVTransportURIOutput.fromMap,
      );

  /// Stop cast screen
  Future<StopOutput> stop(StopInput input) => avTransportService!.invoke(
        'Stop',
        input,
        StopInput.toMap,
        StopOutput.fromMap,
      );
}
