import 'package:dio/dio.dart';
import 'media_server_client.dart';

enum MediaServerShelf { libraries, resume, nextUp, latest, favorites }

extension MediaServerCatalog on MediaServerClient {
  String get _user => Uri.encodeComponent(connection.userId);

  /// New Jellyfin routes with a legacy fallback for older installations.
  /// Authentication, transport and server failures must never trigger retries.
  Future<Response<dynamic>> catalogRequest(String modern, String legacy,
      {String method = 'GET',
      Map<String, dynamic> query = const {},
      CancelToken? cancelToken}) async {
    Future<Response<dynamic>> send(String route) => dio.request<dynamic>(route,
        options: Options(method: method),
        cancelToken: cancelToken,
        queryParameters: {'UserId': connection.userId, ...query});
    if (connection.kind != 'Jellyfin' || modern == legacy) return send(legacy);
    try {
      return await send(modern);
    } on DioException catch (error) {
      if (error.response?.statusCode != 404 &&
          error.response?.statusCode != 405) rethrow;
      return send(legacy);
    }
  }

  MediaServerPage _page(dynamic data, int start, int limit) {
    final rows = data is List ? data : data['Items'] as List? ?? [];
    final count = data is Map ? data['TotalRecordCount'] : null;
    return MediaServerPage(
        items: rows
            .map<MediaServerItem>((row) =>
                MediaServerItem.fromJson(Map<String, dynamic>.from(row as Map)))
            .toList(),
        start: start,
        limit: limit,
        total: count is num && count.isFinite && count >= 0
            ? count.toInt()
            : null);
  }

  Future<MediaServerPage> shelf(MediaServerShelf shelf,
      {int start = 0, int limit = 20, CancelToken? cancelToken}) async {
    if (start < 0 || limit < 1 || limit > 200)
      throw ArgumentError('Invalid page');
    String modern, legacy;
    final query = <String, dynamic>{
      'StartIndex': start,
      'Limit': limit,
      'Fields': 'Overview,MediaSourceCount',
      'EnableUserData': true
    };
    switch (shelf) {
      case MediaServerShelf.libraries:
        modern = 'UserViews';
        legacy = 'Users/$_user/Views';
      case MediaServerShelf.resume:
        modern = 'UserItems/Resume';
        legacy = 'Users/$_user/Items/Resume';
        query['MediaTypes'] = 'Video';
      case MediaServerShelf.nextUp:
        modern = legacy = 'Shows/NextUp';
      case MediaServerShelf.latest:
        modern = 'Items';
        legacy = 'Users/$_user/Items';
        query.addAll({
          'Recursive': true,
          'IncludeItemTypes': 'Movie,Episode,Audio',
          'SortBy': 'DateCreated,SortName',
          'SortOrder': 'Descending'
        });
      case MediaServerShelf.favorites:
        modern = 'Items';
        legacy = 'Users/$_user/Items';
        query.addAll({
          'Recursive': true,
          'IsFavorite': true,
          'SortBy': 'SortName',
          'SortOrder': 'Ascending'
        });
    }
    final response = await catalogRequest(modern, legacy,
        query: query, cancelToken: cancelToken);
    final result = _page(response.data, start, limit);
    // Views has no pagination contract; it returns all permitted libraries.
    return shelf == MediaServerShelf.libraries
        ? MediaServerPage(
            items: result.items,
            start: 0,
            limit: result.items.length,
            total: result.items.length)
        : result;
  }

  Future<MediaServerItem> details(String id, {CancelToken? cancelToken}) async {
    final key = Uri.encodeComponent(id);
    final response = await catalogRequest(
        'Items/$key', 'Users/$_user/Items/$key',
        cancelToken: cancelToken);
    return MediaServerItem.fromJson(
        Map<String, dynamic>.from(response.data as Map));
  }

  Future<MediaServerPage> seasons(String seriesId,
      {CancelToken? cancelToken}) async {
    final route = 'Shows/${Uri.encodeComponent(seriesId)}/Seasons';
    final result = await catalogRequest(route, route,
        cancelToken: cancelToken,
        query: {'Fields': 'Overview', 'IsMissing': false});
    final parsed = _page(result.data, 0, 200);
    return MediaServerPage(
        items: parsed.items,
        start: 0,
        limit: parsed.items.length,
        total: parsed.items.length);
  }

  Future<MediaServerPage> episodes(String seriesId,
      {String? seasonId,
      int start = 0,
      int limit = 100,
      CancelToken? cancelToken}) async {
    if (start < 0 || limit < 1 || limit > 200)
      throw ArgumentError('Invalid episode page');
    final route = 'Shows/${Uri.encodeComponent(seriesId)}/Episodes';
    final result =
        await catalogRequest(route, route, cancelToken: cancelToken, query: {
      'Fields': 'Overview',
      'StartIndex': start,
      'Limit': limit,
      'IsMissing': false,
      if (seasonId != null) 'SeasonId': seasonId
    });
    return _page(result.data, start, limit);
  }

  Future<void> setFavorite(String id, bool value) async {
    final key = Uri.encodeComponent(id);
    await catalogRequest(
        'UserFavoriteItems/$key', 'Users/$_user/FavoriteItems/$key',
        method: value ? 'POST' : 'DELETE');
  }

  Future<void> setPlayed(String id, bool value) async {
    // Stable on both implementations; current Jellyfin still supports this route.
    final route = 'Users/$_user/PlayedItems/${Uri.encodeComponent(id)}';
    await catalogRequest(route, route, method: value ? 'POST' : 'DELETE');
  }
}
