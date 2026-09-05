import 'package:xml/xml.dart';

class NfoMetadata {
  final String? title;
  final String? showTitle;
  final String? plot;
  final int? year;
  final int? season;
  final int? episode;
  const NfoMetadata({this.title, this.showTitle, this.plot, this.year, this.season, this.episode});
  static NfoMetadata parse(String input) {
    final root = XmlDocument.parse(input).rootElement;
    String? field(String key) {
      final value = root.getElement(key)?.innerText.trim();
      return value == null || value.isEmpty ? null : value;
    }
    return NfoMetadata(title: field('title'), showTitle: field('showtitle'), plot: field('plot'), year: int.tryParse(field('year') ?? ''),
      season: int.tryParse(field('season') ?? ''), episode: int.tryParse(field('episode') ?? ''));
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
  const CatalogItem({required this.filePath, required this.title, required this.revision, this.series, this.plot, this.poster, this.year, this.season, this.episode});
  Map<String, Object?> toMap() => {'filePath': filePath, 'title': title, 'series': series, 'plot': plot, 'poster': poster, 'year': year, 'season': season, 'episode': episode, 'revision': revision};
  factory CatalogItem.fromMap(Map<String, Object?> map) => CatalogItem(filePath: map['filePath'] as String, title: map['title'] as String, revision: map['revision'] as String,
    series: map['series'] as String?, plot: map['plot'] as String?, poster: map['poster'] as String?, year: map['year'] as int?, season: map['season'] as int?, episode: map['episode'] as int?);
}
