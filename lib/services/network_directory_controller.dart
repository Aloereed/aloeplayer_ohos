import 'package:flutter/foundation.dart';
import 'file_service.dart';

/// A directory change commits only after a successful response. Superseded
/// requests cannot replace the current folder or poison its back history.
class NetworkDirectoryController extends ChangeNotifier {
  final FileService source;
  NetworkDirectoryController(this.source);
  String path = '/';
  List<FileItem> files = const [];
  final List<String> history = [];
  String? error;
  String? failedPath;
  bool loading = false;
  int _request = 0;
  bool _disposed = false;

  Future<bool> open(String target, {bool remember = false}) async {
    final request = ++_request;
    loading = true;
    error = null;
    failedPath = target;
    notifyListeners();
    try {
      final result = await source.listFiles(target);
      if (_disposed || request != _request) return false;
      if (remember && target != path) history.add(path);
      path = target;
      files = result;
      failedPath = null;
      return true;
    } catch (failure) {
      if (!_disposed && request == _request) error = failure.toString();
      return false;
    } finally {
      if (!_disposed && request == _request) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> back() async {
    if (history.isEmpty) return false;
    final index = history.length - 1;
    final target = history[index];
    final success = await open(target);
    if (success && history.length > index && history[index] == target) {
      history.removeRange(index, history.length);
      if (!_disposed) notifyListeners();
    }
    return success;
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    super.dispose();
  }
}
