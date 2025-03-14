// ignore_for_file: non_constant_identifier_names

part of 'extension.dart';

/// The SetAVTransportURI action input
final class SetAVTransportURIInput {
  /// The input argument InstanceID
  final String InstanceID;

  /// The input argument CurrentURI
  final String CurrentURI;

  /// The input argument CurrentURIMetaData
  final String CurrentURIMetaData;

  const SetAVTransportURIInput(this.CurrentURI,
      {this.InstanceID = _defaultInstanceID, this.CurrentURIMetaData = ''});

  /// The static method toMap
  static Map<String, String> toMap(SetAVTransportURIInput input) {
    return {
      'InstanceID': input.InstanceID,
      'CurrentURI': input.CurrentURI,
      'CurrentURIMetaData': input.CurrentURIMetaData
    };
  }
}

/// The AVTransportURI action output
final class SetAVTransportURIOutput {
  const SetAVTransportURIOutput();

  /// The factory method fromMap
  factory SetAVTransportURIOutput.fromMap(Map<String, String> m) {
    return const SetAVTransportURIOutput();
  }
}
