import 'dart:io';

/// Respect short Retry-After values. Long server cooldowns remain visible to
/// the caller instead of sleeping indefinitely or retrying earlier than asked.
Duration? webDavRetryDelay(String? retryAfter, int attempt, {DateTime? now}) {
  var milliseconds = 350 * (attempt + 1);
  if (retryAfter != null) {
    final seconds = int.tryParse(retryAfter.trim());
    if (seconds != null) {
      if (seconds < 0 || seconds > 2) return null;
      milliseconds = seconds * 1000;
    } else {
      try {
        milliseconds = HttpDate.parse(retryAfter)
            .difference(now ?? DateTime.now())
            .inMilliseconds;
      } catch (_) {/* An invalid header uses the bounded default delay. */}
    }
  }
  if (milliseconds > 2000) return null;
  return Duration(milliseconds: milliseconds < 0 ? 0 : milliseconds);
}
