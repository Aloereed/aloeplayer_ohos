import 'dart:async';

class PlaybackReport {
  final int positionMs;
  final bool stopped, playing;
  final int? observedMs;
  const PlaybackReport(this.positionMs, this.stopped, this.playing,
      {this.observedMs});
}

/// One in-flight report and one latest pending state per playback session.
/// Slow servers cannot build an unbounded backlog of obsolete positions.
class PlaybackReportQueue {
  final Future<void> Function(PlaybackReport) send;
  PlaybackReportQueue(this.send);
  PlaybackReport? _pending;
  Completer<void>? _drained;
  bool _terminal = false;

  Future<void> get drained => _drained?.future ?? Future.value();

  Future<void> add(PlaybackReport report) {
    if (_terminal) return drained;
    _terminal = report.stopped;
    _pending = report;
    final running = _drained;
    if (running != null) return running.future;
    final completion = _drained = Completer<void>();
    unawaited(_run(completion));
    return completion.future;
  }

  Future<void> _run(Completer<void> completion) async {
    Object? failure;
    StackTrace? trace;
    while (_pending != null) {
      final report = _pending!;
      _pending = null;
      try {
        await send(report);
        failure = null;
      } catch (error, stack) {
        failure = error;
        trace = stack;
      }
    }
    _drained = null;
    if (failure == null) {
      completion.complete();
    } else {
      completion.completeError(failure, trace);
    }
  }
}
