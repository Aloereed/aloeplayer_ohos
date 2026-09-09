import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'media_server_client.dart';

/// Owns query generations so late requests cannot overwrite a newer location.
class MediaServerBrowserController extends ChangeNotifier {
  final MediaServerClient client;
  MediaServerBrowserController(this.client);
  List<MediaServerItem> items = [];
  final List<MediaServerItem> parents = [];
  String search = '';
  bool busy = false, hasMore = false;
  int? total;
  Object? error;
  int _nextStart = 0, _generation = 0;
  bool _disposed = false;
  CancelToken? _cancel;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load({bool more = false}) async {
    if (_disposed || (more && (busy || !hasMore))) return;
    _cancel?.cancel('Query replaced');
    final cancel = _cancel = CancelToken();
    final generation = ++_generation;
    final start = more ? _nextStart : 0;
    if (!more) {
      items = [];
      total = null;
      hasMore = false;
      _nextStart = 0;
    }
    busy = true;
    error = null;
    _notify();
    try {
      final result = await client.itemPage(
          parent: parents.lastOrNull?.id,
          search: search,
          start: start,
          cancelToken: cancel);
      if (_disposed || generation != _generation) return;
      final previousCount = more ? items.length : 0;
      final seen = <String>{};
      items = [...(more ? items : <MediaServerItem>[]), ...result.items]
          .where((item) => seen.add(item.id))
          .toList();
      _nextStart = result.nextStart;
      total = result.total;
      hasMore = result.hasMore && (!more || items.length > previousCount);
    } catch (failure) {
      if (!_disposed &&
          generation == _generation &&
          !(failure is DioException && CancelToken.isCancel(failure))) {
        error = failure;
      }
    } finally {
      if (!_disposed && generation == _generation) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> query(String value) {
    search = value.trim();
    return load();
  }

  Future<void> enter(MediaServerItem folder) {
    parents.add(folder);
    search = '';
    return load();
  }

  Future<void> back() async {
    if (parents.isNotEmpty) {
      parents.removeLast();
      search = '';
      await load();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _cancel?.cancel('Browser closed');
    unawaited(client.close());
    super.dispose();
  }
}
