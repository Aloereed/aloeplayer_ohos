import '../models/server_config.dart';
import 'file_service.dart';

/// A connection test must perform a real directory read: SMB server roots are
/// virtual and are not authenticated until their first network operation.
Future<int> probeNetworkConnection(ServerConfig config,
    {FileService? source}) async {
  final service = source ?? FileServiceFactory.createService(config.type);
  var failed = false;
  try {
    if (!await service.connect(config)) throw StateError('无法连接服务器');
    return (await service.listFiles(
            config.type == ServerType.smb ? '/' : config.initialPath))
        .length;
  } catch (_) {
    failed = true;
    rethrow;
  } finally {
    try {
      await service.disconnect();
    } catch (_) {
      if (!failed) rethrow;
    }
  }
}
