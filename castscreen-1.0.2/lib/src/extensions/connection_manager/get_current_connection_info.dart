// ignore_for_file: non_constant_identifier_names

part of 'extension.dart';

// The GetCurrentConnectionInfo action input
final class GetCurrentConnectionInfoInput {
  /// The input argument ConnectionID
  final String ConnectionID;

  const GetCurrentConnectionInfoInput(this.ConnectionID);

  /// The static method toMap
  static Map<String, String> toMap(GetCurrentConnectionInfoInput input) {
    return {'ConnectionID': input.ConnectionID};
  }
}

// The GetCurrentConnectionInfo action output
final class GetCurrentConnectionInfoOutput {
  /// The output argument RcsID
  final String RcsID;

  /// The output argument AVTransportID
  final String AVTransportID;

  /// The output argument ProtocolInfo
  final String ProtocolInfo;

  /// The output argument PeerConnectionManager
  final String PeerConnectionManager;

  /// The output argument PeerConnectionID
  final String PeerConnectionID;

  /// The output argument Status
  final String Status;

  /// The output argument Direction
  final String Direction;

  const GetCurrentConnectionInfoOutput(
    this.RcsID,
    this.AVTransportID,
    this.ProtocolInfo,
    this.PeerConnectionManager,
    this.PeerConnectionID,
    this.Direction,
    this.Status,
  );

  /// The factory method fromXml
  factory GetCurrentConnectionInfoOutput.fromMap(Map<String, String> m) {
    return GetCurrentConnectionInfoOutput(
      m['RcsID'] ?? '',
      m['AVTransportID'] ?? '',
      m['ProtocolInfo'] ?? '',
      m['PeerConnectionManager'] ?? '',
      m['PeerConnectionID'] ?? '',
      m['Direction'] ?? '',
      m['Status'] ?? '',
    );
  }
}
