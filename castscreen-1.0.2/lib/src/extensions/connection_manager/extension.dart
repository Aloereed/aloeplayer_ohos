// ignore_for_file: non_constant_identifier_names

library castscreen.extensions.connection_manager;

import 'package:castscreen/src/core/lib.dart';

part 'get_current_connection_ids.dart';
part 'get_current_connection_info.dart';
part 'get_protocol_info.dart';

/// The action extension to implements ConnectionManager SCPD Service
extension ConnectionManagerActionsExtension on Device {
  /// Get current connection ids from UPnP device
  Future<GetCurrentConnectionIDsOutput> getCurrentConnectionIDs(
          GetCurrentConnectionIDsInput input) =>
      connectionManagerService!.invoke(
        'GetCurrentConnectionIDs',
        input,
        GetCurrentConnectionIDsInput.toMap,
        GetCurrentConnectionIDsOutput.fromMap,
      );

  /// Get current connection info from UPnP device
  Future<GetCurrentConnectionInfoOutput> getCurrentConnectionInfo(
          GetCurrentConnectionInfoInput input) =>
      connectionManagerService!.invoke(
        'GetCurrentConnectionInfo',
        input,
        GetCurrentConnectionInfoInput.toMap,
        GetCurrentConnectionInfoOutput.fromMap,
      );

  /// Get protocol info from UPnP device
  Future<GetProtocolInfoOutput> getProtocolInfo(GetProtocolInfoInput input) =>
      connectionManagerService!.invoke(
        'GetProtocolInfo',
        input,
        GetProtocolInfoInput.toMap,
        GetProtocolInfoOutput.fromMap,
      );
}
