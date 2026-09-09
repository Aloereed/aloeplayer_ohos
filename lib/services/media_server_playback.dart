import 'package:dio/dio.dart';
import 'dart:io';
import 'package:uuid/uuid.dart';
import '../models/playback_media.dart';
import 'cast_media_relay.dart';

enum MediaServerPlayMode { auto, original, transcode }

class MediaServerPlaybackOptions {
  final String? sourceId;
  final int? audioIndex, subtitleIndex;
  final int maxBitrate;
  final MediaServerPlayMode mode;
  const MediaServerPlaybackOptions(
      {this.sourceId,
      this.audioIndex,
      this.subtitleIndex,
      this.maxBitrate = 120000000,
      this.mode = MediaServerPlayMode.auto});
}

class MediaServerStream {
  final Map<String, dynamic> data;
  MediaServerStream(this.data);
  int get index => (data['Index'] as num).toInt();
  String get type => data['Type'] as String? ?? '';
  bool get external => data['IsExternal'] == true;
  String get label =>
      data['DisplayTitle'] as String? ??
      [data['Title'], data['Language'], data['Codec']]
          .whereType<String>()
          .join(' · ');
}

class MediaServerSource {
  final Map<String, dynamic> data;
  MediaServerSource(this.data);
  String get id => data['Id'] as String? ?? '';
  String get label =>
      data['Name'] as String? ?? '${data['Container'] ?? '媒体源'} · $id';
  List<MediaServerStream> get streams => (data['MediaStreams'] as List? ?? [])
      .whereType<Map>()
      .where((m) => m['Index'] is num)
      .map((m) => MediaServerStream(Map<String, dynamic>.from(m)))
      .toList();
  int? get defaultAudio => (data['DefaultAudioStreamIndex'] as num?)?.toInt();
  int? get defaultSubtitle =>
      (data['DefaultSubtitleStreamIndex'] as num?)?.toInt();
}

/// Build a concrete MPV profile and pin stream indices to their source.
Map<String, dynamic> playbackRequest(
    String userId, MediaServerPlaybackOptions options,
    {required bool playing}) {
  if (options.maxBitrate < 128000 || options.maxBitrate > 1000000000) {
    throw ArgumentError('Invalid streaming bitrate');
  }
  return {
    'UserId': userId, 'IsPlayback': playing, 'AutoOpenLiveStream': playing,
    'EnableDirectPlay': options.mode != MediaServerPlayMode.transcode,
    'EnableDirectStream': options.mode != MediaServerPlayMode.transcode,
    'EnableTranscoding': options.mode != MediaServerPlayMode.original,
    'AllowVideoStreamCopy': options.mode != MediaServerPlayMode.transcode,
    'AllowAudioStreamCopy': true,
    'MaxStreamingBitrate': options.maxBitrate,
    // Keep the stream timeline at zero; MPV applies resume/seek itself.
    'StartTimeTicks': 0,
    if (options.sourceId != null) 'MediaSourceId': options.sourceId,
    if (options.audioIndex != null) 'AudioStreamIndex': options.audioIndex,
    if (options.subtitleIndex != null)
      'SubtitleStreamIndex': options.subtitleIndex,
    'DeviceProfile': {
      'Name': 'AloePlayer MPV',
      'MaxStreamingBitrate': options.maxBitrate,
      'DirectPlayProfiles': [
        {
          'Type': 'Video',
          'VideoCodec':
              'h264,hevc,mpeg4,mpeg2video,mpeg1video,vp8,vp9,av1,vc1,wmv3',
          'AudioCodec':
              'aac,ac3,eac3,dts,flac,mp3,mp2,opus,vorbis,alac,pcm_s16le,pcm_s24le,truehd'
        },
        {
          'Type': 'Audio',
          'AudioCodec':
              'aac,ac3,eac3,dts,flac,mp3,mp2,opus,vorbis,alac,pcm_s16le,pcm_s24le,truehd'
        },
      ],
      'TranscodingProfiles': [
        {
          'Type': 'Video',
          'Container': 'ts',
          'Protocol': 'hls',
          'Context': 'Streaming',
          'VideoCodec': 'h264',
          'AudioCodec': 'aac',
          'MaxAudioChannels': '2',
          'MinSegments': 2,
          'SegmentLength': 4,
          'BreakOnNonKeyFrames': false
        },
        {
          'Type': 'Audio',
          'Container': 'mp3',
          'Protocol': 'http',
          'Context': 'Streaming',
          'AudioCodec': 'mp3'
        },
      ],
      'SubtitleProfiles': [
        for (final format in ['srt', 'ass', 'ssa', 'subrip', 'vtt'])
          {'Format': format, 'Method': 'External'},
        for (final format in ['pgssub', 'dvdsub', 'dvbsub'])
          {'Format': format, 'Method': 'Embed'},
      ],
    },
  };
}

Future<Map<String, dynamic>> requestPlaybackInfo(
    Dio dio, String itemId, String userId, MediaServerPlaybackOptions options,
    {required bool playing, CancelToken? cancelToken}) async {
  final response = await dio.post<Map<String, dynamic>>(
      'Items/${Uri.encodeComponent(itemId)}/PlaybackInfo',
      cancelToken: cancelToken,
      queryParameters: {'UserId': userId},
      data: playbackRequest(userId, options, playing: playing));
  final result = response.data ?? {};
  if (result['ErrorCode'] != null)
    throw StateError('服务器无法提供所选播放模式：${result['ErrorCode']}');
  return result;
}

/// Server URLs may include their proxy prefix, omit it, or use relative paths.
Uri resolveMediaServerUrl(String baseUrl, String address) {
  final base = Uri.parse('$baseUrl/');
  final target = Uri.parse(address);
  Uri result;
  if (target.hasScheme || target.hasAuthority) {
    result = base.resolveUri(target);
  } else if (target.path.startsWith(base.path) && base.path != '/') {
    result = base.resolveUri(target);
  } else {
    result = base.resolve(address.replaceFirst(RegExp(r'^/+'), ''));
  }
  if (!['http', 'https'].contains(result.scheme) ||
      result.host.isEmpty ||
      result.userInfo.isNotEmpty) {
    throw StateError('服务器返回了不支持的媒体地址');
  }
  if (result.origin == base.origin) {
    final query = Map<String, String>.from(result.queryParameters);
    query.removeWhere((key, _) => key.toLowerCase() == 'api_key');
    result = result.replace(
        query: query.isEmpty ? '' : Uri(queryParameters: query).query);
  }
  return result;
}

class MediaServerPlaybackSession {
  final Dio dio;
  final String itemId, sessionId, sourceId, deviceId, playMethod;
  final String? liveStreamId;
  final int? audioIndex, subtitleIndex;
  final bool canSeek;
  late final PlaybackMedia media;
  CastMediaRelay? _relay;
  bool started = false, closed = false;
  MediaServerPlaybackSession(
      {required this.dio,
      required this.itemId,
      required this.sessionId,
      required this.sourceId,
      required this.deviceId,
      required this.playMethod,
      this.liveStreamId,
      this.audioIndex,
      this.subtitleIndex,
      required this.canSeek});

  Future<void> close() async {
    if (closed) return;
    closed = true;
    await _relay?.close();
    final calls = <Future<dynamic>>[];
    final options = Options(
        receiveTimeout: const Duration(seconds: 3),
        sendTimeout: const Duration(seconds: 3));
    if (liveStreamId != null)
      calls.add(dio.post('LiveStreams/Close',
          queryParameters: {'LiveStreamId': liveStreamId}, options: options));
    if (playMethod != 'DirectPlay')
      calls.add(dio.delete('Videos/ActiveEncodings',
          queryParameters: {'DeviceId': deviceId, 'PlaySessionId': sessionId},
          options: options));
    await Future.wait(calls.map((call) async {
      try {
        await call.timeout(const Duration(seconds: 4));
      } catch (_) {}
    }));
  }
}

Future<MediaServerPlaybackSession> prepareServerPlayback(
    {required Dio dio,
    required String baseUrl,
    required String userId,
    required String deviceId,
    required Map<String, String> headers,
    required String itemId,
    required String itemType,
    required String title,
    required int resumeMs,
    required MediaServerPlaybackOptions options,
    CancelToken? cancelToken}) async {
  final response = await requestPlaybackInfo(dio, itemId, userId, options,
      playing: true, cancelToken: cancelToken);
  final sources = (response['MediaSources'] as List? ?? [])
      .whereType<Map>()
      .map((m) => MediaServerSource(Map<String, dynamic>.from(m)))
      .toList();
  if (sources.isEmpty) throw StateError('服务器没有可用的媒体源');
  var source = options.sourceId == null
      ? sources.first
      : sources.where((s) => s.id == options.sourceId).firstOrNull;
  if (source == null || source.id.isEmpty) throw StateError('所选媒体版本已不可用，请刷新详情');
  final sessionId = response['PlaySessionId'] as String? ??
      const Uuid().v4().replaceAll('-', '');
  if (source.data['RequiresOpening'] == true &&
      source.data['LiveStreamId'] == null) {
    final opened = await dio.post<Map<String, dynamic>>('LiveStreams/Open',
        cancelToken: cancelToken,
        data: {
          ...playbackRequest(userId, options, playing: true),
          'ItemId': itemId,
          'OpenToken': source.data['OpenToken'],
          'PlaySessionId': sessionId
        });
    final openedSource = opened.data?['MediaSource'];
    if (openedSource is! Map) throw StateError('服务器未能打开直播媒体源');
    source = MediaServerSource(Map<String, dynamic>.from(openedSource));
  }
  final data = source.data;
  final direct = options.mode != MediaServerPlayMode.transcode &&
      data['SupportsDirectPlay'] != false;
  final directStream = !direct &&
      options.mode != MediaServerPlayMode.transcode &&
      data['SupportsDirectStream'] == true &&
      data['DirectStreamUrl'] is String;
  final method = direct
      ? 'DirectPlay'
      : directStream
          ? 'DirectStream'
          : 'Transcode';
  final session = MediaServerPlaybackSession(
      dio: dio,
      itemId: itemId,
      sessionId: sessionId,
      sourceId: source.id,
      deviceId: deviceId,
      playMethod: method,
      liveStreamId: data['LiveStreamId'] as String?,
      audioIndex: options.audioIndex ?? source.defaultAudio,
      subtitleIndex: options.subtitleIndex ?? source.defaultSubtitle,
      canSeek: data['IsInfiniteStream'] != true);
  try {
    String address;
    if (direct) {
      address = Uri(pathSegments: [
        itemType == 'Audio' ? 'Audio' : 'Videos',
        itemId,
        'stream'
      ], queryParameters: {
        'Static': 'true',
        'MediaSourceId': source.id,
        'PlaySessionId': sessionId,
        'DeviceId': deviceId,
        if (session.liveStreamId != null) 'LiveStreamId': session.liveStreamId!
      }).toString();
    } else if (directStream) {
      address = data['DirectStreamUrl'] as String;
    } else {
      if (options.mode == MediaServerPlayMode.original ||
          data['TranscodingUrl'] is! String ||
          (data['TranscodingUrl'] as String).isEmpty)
        throw StateError('服务器无法提供所选模式，请尝试其他码率或媒体版本');
      address = data['TranscodingUrl'] as String;
    }
    final upstream = resolveMediaServerUrl(baseUrl, address);
    final serverOrigin = Uri.parse(baseUrl).origin;
    final resourceHeaders = upstream.origin == serverOrigin
        ? headers
        : <String, String>{
            for (final entry
                in (data['RequiredHttpHeaders'] as Map? ?? {}).entries)
              if (entry.key is String && entry.value is String)
                entry.key as String: entry.value as String
          };
    final relay = await CastMediaRelay.start(upstream.toString(),
        host: '127.0.0.1',
        bindAddress: InternetAddress.loopbackIPv4,
        headers: resourceHeaders);
    session._relay = relay;
    if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
    final subtitles = <String>[];
    String? subtitleTrack;
    final chosenSubtitle = source.streams
        .where((s) => s.type == 'Subtitle' && s.index == session.subtitleIndex)
        .firstOrNull;
    if (session.subtitleIndex == -1) {
      subtitleTrack = 'no';
    } else if (chosenSubtitle != null &&
        ((chosenSubtitle.external &&
                !['Encode', 'Hls']
                    .contains(chosenSubtitle.data['DeliveryMethod'])) ||
            chosenSubtitle.data['DeliveryMethod'] == 'External')) {
      final delivery = chosenSubtitle.data['DeliveryUrl'] as String?;
      final uri = resolveMediaServerUrl(
          baseUrl,
          delivery ??
              'Videos/${Uri.encodeComponent(itemId)}/${Uri.encodeComponent(source.id)}/Subtitles/${chosenSubtitle.index}/Stream.srt');
      subtitles.add(relay.grantRemote(uri,
          headers: uri.origin == serverOrigin ? headers : const {}));
      subtitleTrack = 'external';
    } else if (chosenSubtitle != null && direct) {
      subtitleTrack =
          '${source.streams.where((s) => s.type == 'Subtitle' && !s.external).toList().indexWhere((s) => s.index == chosenSubtitle.index) + 1}';
    }
    final audioOrdinal = source.streams
        .where((s) => s.type == 'Audio')
        .toList()
        .indexWhere((s) => s.index == session.audioIndex);
    session.media = PlaybackMedia(
        id: Uri(scheme: 'aloe-server', host: deviceId, path: '/$itemId')
            .toString(),
        url: relay.url,
        title: title,
        mediaType: itemType == 'Audio' ? 'audio' : 'video',
        subtitles: subtitles,
        startPositionMs: resumeMs,
        preferredAudioTrack:
            audioOrdinal >= 0 ? (direct ? '${audioOrdinal + 1}' : '1') : null,
        preferredSubtitleTrack: subtitleTrack);
    return session;
  } catch (_) {
    await session.close();
    rethrow;
  }
}
