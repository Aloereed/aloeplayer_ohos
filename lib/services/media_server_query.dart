enum MediaServerTypeFilter { all, movies, series, episodes, audio }

enum MediaServerWatchFilter { all, unwatched, watched }

enum MediaServerSort { name, added, premiere, rating, duration }

class MediaServerQuery {
  final MediaServerTypeFilter type;
  final MediaServerWatchFilter watched;
  final MediaServerSort sort;
  final bool favorites, descending;
  const MediaServerQuery(
      {this.type = MediaServerTypeFilter.all,
      this.watched = MediaServerWatchFilter.all,
      this.sort = MediaServerSort.name,
      this.favorites = false,
      this.descending = false});

  bool get filtered =>
      type != MediaServerTypeFilter.all ||
      watched != MediaServerWatchFilter.all ||
      favorites;
  bool get changed => filtered || sort != MediaServerSort.name || descending;
  bool matches(
      {required String itemType,
      required bool played,
      required bool favorite}) {
    final expected = switch (type) {
      MediaServerTypeFilter.all => null,
      MediaServerTypeFilter.movies => 'Movie',
      MediaServerTypeFilter.series => 'Series',
      MediaServerTypeFilter.episodes => 'Episode',
      MediaServerTypeFilter.audio => 'Audio',
    };
    if (expected != null && itemType != expected) return false;
    if (watched != MediaServerWatchFilter.all &&
        played != (watched == MediaServerWatchFilter.watched)) return false;
    return !favorites || favorite;
  }

  String get summary => [
        if (type != MediaServerTypeFilter.all) typeLabel(type),
        if (watched != MediaServerWatchFilter.all) watchLabel(watched),
        if (favorites) '收藏',
        '${sortLabel(sort)}${descending ? '↓' : '↑'}',
      ].join(' · ');

  Map<String, dynamic> get parameters => {
        if (filtered) 'Recursive': true,
        if (type != MediaServerTypeFilter.all)
          'IncludeItemTypes': switch (type) {
            MediaServerTypeFilter.movies => 'Movie',
            MediaServerTypeFilter.series => 'Series',
            MediaServerTypeFilter.episodes => 'Episode',
            MediaServerTypeFilter.audio => 'Audio',
            MediaServerTypeFilter.all => '',
          }
        else if (watched != MediaServerWatchFilter.all)
          'IncludeItemTypes': 'Movie,Episode,Video,MusicVideo,Audio',
        if (watched != MediaServerWatchFilter.all)
          'IsPlayed': watched == MediaServerWatchFilter.watched,
        if (favorites) 'IsFavorite': true,
        'SortBy': switch (sort) {
          MediaServerSort.name => 'SortName',
          MediaServerSort.added => 'DateCreated,SortName',
          MediaServerSort.premiere => 'PremiereDate,SortName',
          MediaServerSort.rating => 'CommunityRating,SortName',
          MediaServerSort.duration => 'Runtime,SortName',
        },
        'SortOrder': descending ? 'Descending' : 'Ascending',
      };
  static String typeLabel(MediaServerTypeFilter value) =>
      const ['全部类型', '电影', '剧集系列', '单集', '音频'][value.index];
  static String watchLabel(MediaServerWatchFilter value) =>
      const ['全部观看状态', '未看', '已看'][value.index];
  static String sortLabel(MediaServerSort value) =>
      const ['名称', '添加时间', '首映时间', '评分', '时长'][value.index];
}
