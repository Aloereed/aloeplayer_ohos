import 'dart:async';
import 'package:flutter/foundation.dart';

/// App-wide timer follows the active playback owner, including background audio.
class PlaybackSleepTimer extends ChangeNotifier {
  static final instance = PlaybackSleepTimer();
  Object? _owner;
  Future<void> Function()? _pause;
  Timer? _timer;
  DateTime? deadline;
  bool endOfItem = false;
  Duration get remaining => deadline == null ? Duration.zero : deadline!.difference(DateTime.now());
  bool get active => deadline != null || endOfItem;

  void attach(Object owner, Future<void> Function() pause) {
    _owner = owner;
    _pause = pause;
  }
  void detach(Object owner) {
    if (_owner == owner) { cancel(); _owner = null; _pause = null; }
  }
  void start(Duration duration) {
    cancel();
    deadline = DateTime.now().add(duration);
    _timer = Timer(duration, _expire);
    notifyListeners();
  }
  void afterCurrentItem() { cancel(); endOfItem = true; notifyListeners(); }
  bool consumeEnd(Object owner) {
    if (_owner != owner || !endOfItem) return false;
    _expire();
    return true;
  }
  void _expire() {
    final pause = _pause;
    cancel();
    if (pause != null) unawaited(pause().catchError((_) {}));
  }
  void cancel() { _timer?.cancel(); _timer = null; deadline = null; endOfItem = false; notifyListeners(); }
  @override
  void dispose() { _timer?.cancel(); super.dispose(); }
}
