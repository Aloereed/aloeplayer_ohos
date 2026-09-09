import 'member_access.dart';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/playback_media.dart';
import 'credential_store.dart';
import 'media_server_playback.dart';

class MediaServerConnection {
  final String id, name, url, userId, username, token, kind;
  const MediaServerConnection(
      {required this.id,
      required this.name,
      required this.url,
      required this.userId,
      required this.username,
      required this.token,
      required this.kind});
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'userId': userId,
        'username': username,
        'kind': kind
      };
  static String normalizeUrl(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('请输入完整的 http:// 或 https:// 服务器地址');
    }
    return uri.toString().replaceFirst(RegExp(r'/+$'), '');
  }
}

class MediaServerStore {
  static final _serial = MemberAccess.sourceWrites;
  static Future<List<MediaServerConnection>> load() => _serial.run(_load);
  static Future<List<MediaServerConnection>> _load() async {
    final raw = (await SharedPreferences.getInstance())
            .getString('media-server.connections') ??
        '[]';
    final result = <MediaServerConnection>[];
    for (final row in jsonDecode(raw) as List) {
      result.add(MediaServerConnection(
          id: row['id'],
          name: row['name'],
          url: row['url'],
          userId: row['userId'],
          username: row['username'],
          kind: row['kind'],
          token:
              await CredentialStore.read('media-server.${row['id']}') ?? ''));
    }
    return result;
  }

  static Future<void> save(MediaServerConnection connection) =>
      _serial.run(() async {
        final all = await _load();
        await MemberAccess.instance
            .requireNewSource(kind: connection.kind, existingId: connection.id);
        all.removeWhere((c) => c.id == connection.id);
        await CredentialStore.write(
            'media-server.${connection.id}', connection.token);
        all.add(connection);
        await (await SharedPreferences.getInstance()).setString(
            'media-server.connections',
            jsonEncode(all.map((c) => c.toJson()).toList()));
      });
  static Future<void> remove(String id) => _serial.run(() async {
        final all = await _load();
        all.removeWhere((c) => c.id == id);
        await (await SharedPreferences.getInstance()).setString(
            'media-server.connections',
            jsonEncode(all.map((c) => c.toJson()).toList()));
        await CredentialStore.delete('media-server.$id');
      });
}

class MediaServerItem {
  final String id, name, type;
  final String? overview;
  final int resumeMs;
  final bool isFolder;
  final Map<String, dynamic> metadata;
  const MediaServerItem(
      {required this.id,
      required this.name,
      required this.type,
      this.overview,
      this.resumeMs = 0,
      this.metadata = const {},
      this.isFolder = false});
  int get durationMs =>
      ((metadata['RunTimeTicks'] as num? ?? 0) / 10000).round();
  bool get favorite => metadata['UserData']?['IsFavorite'] == true;
  bool get played => metadata['UserData']?['Played'] == true;
  String? get seriesId => metadata['SeriesId'] as String?;
  int? get index => (metadata['IndexNumber'] as num?)?.toInt();
  int? get seasonIndex => (metadata['ParentIndexNumber'] as num?)?.toInt();
  bool get playable => [
        'Movie',
        'Episode',
        'Video',
        'MusicVideo',
        'Audio',
        'TvChannel'
      ].contains(type);
  factory MediaServerItem.fromJson(Map<String, dynamic> data) =>
      MediaServerItem(
          id: data['Id'] as String,
          name: data['Name'] as String? ?? '',
          type: data['Type'] as String? ?? '',
          overview: data['Overview'] as String?,
          metadata: Map<String, dynamic>.unmodifiable(data),
          resumeMs: ((data['UserData']?['PlaybackPositionTicks'] as num? ?? 0) /
                  10000)
              .round(),
          isFolder: data['IsFolder'] as bool? ??
              [
                'CollectionFolder',
                'Folder',
                'Series',
                'Season',
                'MusicAlbum',
                'BoxSet',
                'Playlist'
              ].contains(data['Type']));
}

class MediaServerPage {
  final List<MediaServerItem> items;
  final int start;
  final int? total;
  final int limit;
  const MediaServerPage(
      {required this.items,
      required this.start,
      required this.limit,
      this.total});
  int get nextStart => start + items.length;
  bool get hasMore =>
      items.isNotEmpty &&
      (total != null ? nextStart < total! : items.length >= limit);
}

class MediaServerClient {
  final MediaServerConnection connection;
  final Dio dio;
  final Map<String, MediaServerPlaybackSession> _sessions = {};
  Future<void> _reports = Future.value();
  MediaServerClient(this.connection, {Dio? client}) : dio = client ?? Dio() {
    dio.options = BaseOptions(
        baseUrl: '${connection.url}/',
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: headers);
  }
  Map<String, String> get headers => {
        'X-Emby-Authorization':
            'MediaBrowser Client="AloePlayer", Device="HarmonyOS", DeviceId="${connection.id}", Version="4.0.1"',
        if (connection.token.isNotEmpty) 'X-Emby-Token': connection.token,
      };
  static Future<MediaServerConnection> login(
      {required String url,
      required String username,
      required String password,
      required String kind,
      String? id}) async {
    final provisional = MediaServerConnection(
        id: id ?? const Uuid().v4(),
        name: '$kind · $username',
        url: MediaServerConnection.normalizeUrl(url),
        userId: '',
        username: username,
        token: '',
        kind: kind);
    final client = MediaServerClient(provisional);
    try {
      final result = await client.dio.post<Map<String, dynamic>>(
          'Users/AuthenticateByName',
          data: {'Username': username, 'Pw': password});
      final data = result.data!;
      return MediaServerConnection(
          id: provisional.id,
          name: provisional.name,
          url: provisional.url,
          userId: data['User']['Id'] as String,
          username: username,
          token: data['AccessToken'] as String,
          kind: kind);
    } finally {
      client.dio.close();
    }
  }

  Future<List<MediaServerItem>> items(
          {String? parent, String search = '', int start = 0}) async =>
      (await itemPage(parent: parent, search: search, start: start)).items;

  Future<MediaServerPage> itemPage(
      {String? parent,
      String search = '',
      int start = 0,
      int limit = 100,
      CancelToken? cancelToken}) async {
    if (start < 0 || limit < 1 || limit > 200)
      throw ArgumentError('Invalid media page bounds');
    final response = await dio.get<Map<String, dynamic>>(
        connection.kind == 'Jellyfin'
            ? 'Items'
            : 'Users/${Uri.encodeComponent(connection.userId)}/Items',
        cancelToken: cancelToken,
        queryParameters: {
          'UserId': connection.userId,
          if (parent != null) 'ParentId': parent,
          if (search.isNotEmpty) 'SearchTerm': search,
          if (search.isNotEmpty) 'Recursive': true,
          'StartIndex': start,
          'Limit': limit,
          'EnableTotalRecordCount': true,
          'Fields': 'Overview,MediaSourceCount',
          'SortBy': 'SortName',
          'SortOrder': 'Ascending',
        });
    final rows = response.data?['Items'] as List? ?? [];
    final total = response.data?['TotalRecordCount'];
    return MediaServerPage(
        items: rows
            .map((row) => MediaServerItem.fromJson(row as Map<String, dynamic>))
            .toList(),
        start: start,
        limit: limit,
        total: total is num && total.isFinite && total >= 0
            ? total.toInt()
            : null);
  }

  String imageUrl(String id) =>
      '${connection.url}/Items/${Uri.encodeComponent(id)}/Images/Primary?maxWidth=360&quality=80';
  Future<List<MediaServerSource>> playbackSources(MediaServerItem item,
      {CancelToken? cancelToken}) async {
    final response = await requestPlaybackInfo(
        dio, item.id, connection.userId, const MediaServerPlaybackOptions(),
        playing: false, cancelToken: cancelToken);
    return (response['MediaSources'] as List? ?? [])
        .whereType<Map>()
        .map((m) => MediaServerSource(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<PlaybackMedia> playback(MediaServerItem item,
      {CancelToken? cancelToken,
      MediaServerPlaybackOptions options =
          const MediaServerPlaybackOptions()}) async {
    final session = await prepareServerPlayback(
        dio: dio,
        baseUrl: connection.url,
        userId: connection.userId,
        deviceId: connection.id,
        headers: headers,
        itemId: item.id,
        itemType: item.type,
        title: item.name,
        resumeMs: item.resumeMs,
        options: options,
        cancelToken: cancelToken);
    _sessions[session.media.url] = session;
    return session.media;
  }

  Future<MediaServerItem> item(String id) async {
    final result = await dio
        .get<Map<String, dynamic>>('Users/${connection.userId}/Items/$id');
    return MediaServerItem.fromJson(result.data!);
  }

  Future<void> report(
      PlaybackMedia media, int positionMs, bool stopped, bool playing) {
    final session = _sessions[media.url];
    if (session == null || session.closed) return Future.value();
    _reports = _reports.catchError((_) {}).then((_) async {
      if (session.closed) return;
      final payload = {
        'ItemId': session.itemId,
        'PositionTicks': positionMs.clamp(0, 900719925474) * 10000,
        'PlaySessionId': session.sessionId,
        'MediaSourceId': session.sourceId,
        if (session.liveStreamId != null) 'LiveStreamId': session.liveStreamId,
        if (session.audioIndex != null) 'AudioStreamIndex': session.audioIndex,
        if (session.subtitleIndex != null)
          'SubtitleStreamIndex': session.subtitleIndex,
        'PlayMethod': session.playMethod,
        'IsPaused': !playing,
        'CanSeek': session.canSeek,
      };
      try {
        if (!session.started) {
          await dio.post('Sessions/Playing', data: payload);
          session.started = true;
        }
        await dio.post(
            stopped ? 'Sessions/Playing/Stopped' : 'Sessions/Playing/Progress',
            data: payload);
      } finally {
        if (stopped) {
          await session.close();
          _sessions.remove(media.url);
        }
      }
    });
    return _reports;
  }

  Future<void> close() async {
    try {
      await _reports.timeout(const Duration(seconds: 5));
    } catch (_) {}
    await Future.wait(
        _sessions.values.toList().map((session) => session.close()));
    _sessions.clear();
    dio.close(force: true);
  }
}
