/// libsmb2 stat fields are Unix seconds + nanoseconds, already converted from
/// SMB's wire-format Windows FILETIME by the native library.
DateTime smbStatTime(int seconds, int nanoseconds) {
  final milliseconds = seconds * 1000 + nanoseconds ~/ 1000000;
  if (seconds < 0 || milliseconds > 8640000000000000) return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
}
