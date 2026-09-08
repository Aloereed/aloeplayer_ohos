/// Preserve native errno across the worker boundary. Missing files can map to
/// HTTP 404; permission, authentication and network failures must remain errors.
class SmbOperationError extends StateError {
  final int code;
  SmbOperationError(this.code, super.message);
  bool get isMissing => code == -2 || code == -20; // ENOENT / ENOTDIR
}
