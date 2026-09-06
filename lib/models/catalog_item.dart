import 'package:xml/xml.dart';
import 'package:path/path.dart' as path;

class NfoMetadata {
  final String? title;
  final String? showTitle;
  final String? plot;
  final int? year;
  final int? season;
  final int? episode;
  const NfoMetadata(
      {this.title,
      this.showTitle,
      this.plot,
      this.year,
      this.season,
      this.episode});
  static NfoMetadata parse(String input) {
    final root = XmlDocument.parse(input).rootElement;
    String? field(String key) {
      final value = root.getElement(key)?.innerText.trim();
      return value == null || value.isEmpty ? null : value;
    }

    return NfoMetadata(
        title: field('title'),
        showTitle: field('showtitle'),
        plot: field('plot'),
        year: int.tryParse(field('year') ?? ''),
        season: int.tryParse(field('season') ?? ''),
        episode: int.tryParse(field('episode') ?? ''));
  }
}

class CatalogItem {
  final String filePath;
  final String title;
  final String? series;
  final String? plot;
  final String? poster;
  final int? year;
  final int? season;
  final int? episode;
  final String revision;
  String get mediaName => filePath.endsWith('.lnk')
      ? path.basenameWithoutExtension(filePath)
      : path.basename(filePath);
  bool get isAudio => const {
        '.mp3',
        '.wav',
        '.aac',
        '.flac',
        '.m4a',
        '.ogg',
        '.opus',
        '.wma',
        '.aiff',
        '.ape'
      }.contains(path.extension(mediaName).toLowerCase());
  int get modifiedMs =>
      int.tryParse(revision.split(':').elementAtOrNull(1) ?? '') ?? 0;
  String get episodeLabel =>
      episode == null ? title : 'S${season ?? 1} · E$episode';
  const CatalogItem(
      {required this.filePath,
      required this.title,
      required this.revision,
      this.series,
      this.plot,
      this.poster,
      this.year,
      this.season,
      this.episode});
  Map<String, Object?> toMap() => {
        'filePath': filePath,
        'title': title,
        'series': series,
        'plot': plot,
        'poster': poster,
        'year': year,
        'season': season,
        'episode': episode,
        'revision': revision
      };
  factory CatalogItem.fromMap(Map<String, Object?> map) => CatalogItem(
      filePath: map['filePath'] as String,
      title: map['title'] as String,
      revision: map['revision'] as String,
      series: map['series'] as String?,
      plot: map['plot'] as String?,
      poster: map['poster'] as String?,
      year: map['year'] as int?,
      season: map['season'] as int?,
      episode: map['episode'] as int?);
}

/// One poster per series; keep separate copies of a show in separate folders.
class CatalogCollection {
  final String id;
  final List<CatalogItem> items;
  CatalogCollection(this.id, Iterable<CatalogItem> entries)
      : items = List.of(entries)..sort(compareCatalogEpisodes);
  CatalogItem get first => items.first;
  bool get isSeries => !first.isAudio && first.series != null;
  String get title => isSeries ? first.series! : first.title;
  String get kind => first.isAudio
      ? '音频'
      : isSeries
          ? '剧集'
          : '电影';
  String? get poster =>
      items.map((e) => e.poster).whereType<String>().firstOrNull;
  String? get plot => items.map((e) => e.plot).whereType<String>().firstOrNull;
  int? get year => items.map((e) => e.year).whereType<int>().firstOrNull;
  int get modifiedMs => items.fold(
      0, (value, item) => value > item.modifiedMs ? value : item.modifiedMs);
  bool matches(String query) {
    final words = query.toLowerCase().trim().split(RegExp(r'\s+'));
    final text =
        '$title ${items.map((e) => '${e.title} ${e.year ?? ''} ${e.mediaName}').join(' ')}'
            .toLowerCase();
    return words.every(text.contains);
  }

  static List<CatalogCollection> group(Iterable<CatalogItem> items) {
    final groups = <String, List<CatalogItem>>{};
    for (final item in items) {
      var directory = path.dirname(item.filePath);
      if (RegExp(r'^(?:season[ ._-]*\d+|s\d+|第.+季|specials)$',
              caseSensitive: false)
          .hasMatch(path.basename(directory))) {
        directory = path.dirname(directory);
      }
      final key = item.series == null || item.isAudio
          ? item.filePath
          : '$directory\u0000${item.series}';
      groups.putIfAbsent(key, () => []).add(item);
    }
    return groups.entries
        .map((e) => CatalogCollection(e.key, e.value))
        .toList();
  }
}

int compareCatalogEpisodes(CatalogItem a, CatalogItem b) {
  final season = (a.season ?? 1).compareTo(b.season ?? 1);
  if (season != 0) return season;
  final episode = (a.episode ?? 0).compareTo(b.episode ?? 0);
  if (episode != 0) return episode;
  return compareCatalogTitles(a.mediaName, b.mediaName);
}

int compareCatalogTitles(String a, String b) {
  final parts = RegExp(r'\d+|\D+');
  final left = parts.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final right = parts.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < left.length && i < right.length; i++) {
    final ln = int.tryParse(left[i]), rn = int.tryParse(right[i]);
    final order = ln != null && rn != null
        ? ln.compareTo(rn)
        : left[i].compareTo(right[i]);
    if (order != 0) return order;
  }
  return left.length.compareTo(right.length);
}
