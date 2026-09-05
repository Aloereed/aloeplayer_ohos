import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class PlaybackPreferences {
  final double subtitleDelay;
  final double audioDelay;
  final String subtitleLanguage;
  final String audioLanguage;
  final String? subtitleTrack;
  final String? audioTrack;
  const PlaybackPreferences({this.subtitleDelay = 0, this.audioDelay = 0, this.subtitleLanguage = '', this.audioLanguage = '', this.subtitleTrack, this.audioTrack});
  Map<String, dynamic> toJson() => {'subtitleDelay': subtitleDelay, 'audioDelay': audioDelay, 'subtitleLanguage': subtitleLanguage, 'audioLanguage': audioLanguage, 'subtitleTrack': subtitleTrack, 'audioTrack': audioTrack};
  factory PlaybackPreferences.fromJson(Map<String, dynamic> json) => PlaybackPreferences(
    subtitleDelay: (json['subtitleDelay'] as num?)?.toDouble() ?? 0, audioDelay: (json['audioDelay'] as num?)?.toDouble() ?? 0,
    subtitleLanguage: json['subtitleLanguage'] as String? ?? '', audioLanguage: json['audioLanguage'] as String? ?? '',
    subtitleTrack: json['subtitleTrack'] as String?, audioTrack: json['audioTrack'] as String?);
}
class MediaBookmark {
  final String name;
  final int positionMs;
  final int? endMs;
  const MediaBookmark(this.name, this.positionMs, {this.endMs});
  Map<String, dynamic> toJson() => {'name': name, 'positionMs': positionMs, 'endMs': endMs};
  factory MediaBookmark.fromJson(Map<String, dynamic> json) => MediaBookmark(json['name'] as String, json['positionMs'] as int, endMs: json['endMs'] as int?);
}
class PlaybackToolsStore {
  static Future<PlaybackPreferences> preferences(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('playback.preferences.$id');
    if (raw == null) return const PlaybackPreferences();
    try { return PlaybackPreferences.fromJson(jsonDecode(raw) as Map<String, dynamic>); } catch (_) { return const PlaybackPreferences(); }
  }
  static Future<void> savePreferences(String id, PlaybackPreferences value) async =>
      (await SharedPreferences.getInstance()).setString('playback.preferences.$id', jsonEncode(value.toJson()));
  static Future<List<MediaBookmark>> bookmarks(String id) async {
    final raw = (await SharedPreferences.getInstance()).getString('playback.bookmarks.$id');
    if (raw == null) return [];
    try { return (jsonDecode(raw) as List).map((e) => MediaBookmark.fromJson(e as Map<String, dynamic>)).toList(); } catch (_) { return []; }
  }
  static Future<void> saveBookmarks(String id, List<MediaBookmark> values) async =>
      (await SharedPreferences.getInstance()).setString('playback.bookmarks.$id', jsonEncode(values.map((e) => e.toJson()).toList()));
}
