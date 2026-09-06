import 'dart:io';
import 'package:path/path.dart' as path;
import '../models/catalog_item.dart';

/// Reads local sidecars only. A scan never modifies media or their metadata.
class CatalogScanner {
  static const extensions = {
    '.mp4',
    '.mkv',
    '.avi',
    '.mov',
    '.flv',
    '.wmv',
    '.webm',
    '.m4v',
    '.ts',
    '.mpg',
    '.mpeg',
    '.m2ts',
    '.rmvb',
    '.3gp',
    '.mp3',
    '.wav',
    '.aac',
    '.flac',
    '.m4a',
    '.ogg',
    '.opus',
    '.wma',
    '.aiff',
    '.ape',
  };
  final Map<String, List<File>> _directories = {};
  final Map<String, NfoMetadata> _metadata = {};

  bool accepts(File file) {
    final name = file.path.endsWith('.lnk')
        ? path.withoutExtension(file.path)
        : file.path;
    return extensions.contains(path.extension(name).toLowerCase());
  }

  Future<List<File>> _files(Directory directory) async =>
      _directories[directory.path] ??= await directory
          .list(followLinks: false)
          .where((e) => e is File)
          .cast<File>()
          .toList();

  File? _find(List<File> files, Iterable<String> names) {
    final byName = {
      for (final file in files) path.basename(file.path).toLowerCase(): file
    };
    for (final name in names) {
      final file = byName[name.toLowerCase()];
      if (file != null) return file;
    }
    return null;
  }

  Future<NfoMetadata> _read(File? file) async {
    if (file == null) return const NfoMetadata();
    if (_metadata.containsKey(file.path)) return _metadata[file.path]!;
    var value = const NfoMetadata();
    try {
      if (await file.length() <= 1024 * 1024) {
        value = NfoMetadata.parse(await file.readAsString());
      }
    } catch (_) {/* Malformed sidecars must not hide playable media. */}
    _metadata[file.path] = value;
    return value;
  }

  Future<CatalogItem> read(File file, Directory root) async {
    final stat = await file.stat();
    final name = file.path.endsWith('.lnk')
        ? path.basenameWithoutExtension(file.path)
        : path.basename(file.path);
    final stem = path.basenameWithoutExtension(name);
    final cleanStem =
        stem.replaceFirst(RegExp(r'^(?:\[[^\]]+\]\s*)+'), '').trim();
    final files = await _files(file.parent);
    final episodeMatch = RegExp(
                r'(?:^|[ ._\-])S(\d{1,2})[ ._\-]*E(\d{1,3})(?:\D|$)',
                caseSensitive: false)
            .firstMatch(cleanStem) ??
        RegExp(r'(?:^|[ ._\-])(\d{1,2})x(\d{1,3})(?:\D|$)',
                caseSensitive: false)
            .firstMatch(cleanStem);
    final animeMatch = RegExp(
                r'^(.+?)\s+-\s+(\d{1,3})(?:v\d+)?(?=\s*(?:\[|\(|$))',
                caseSensitive: false)
            .firstMatch(cleanStem) ??
        RegExp(r'^(.+?)\s+\[(\d{1,3})(?:v\d+)?\](?=\[|\s|$)',
                caseSensitive: false)
            .firstMatch(cleanStem);
    final nfo = _find(files, [
      '$stem.nfo',
      if (episodeMatch == null && animeMatch == null) 'movie.nfo'
    ]);
    final metadata = await _read(nfo);
    File? showNfo;
    File? showPoster;
    var directory = file.parent;
    // Season directories may inherit tvshow.nfo / artwork from their show.
    for (var depth = 0; depth < 3; depth++) {
      if (!path.equals(directory.path, root.path) &&
          !path.isWithin(root.path, directory.path)) {
        break;
      }
      final siblings = await _files(directory);
      showNfo = _find(siblings, ['tvshow.nfo']);
      if (showNfo != null) {
        showPoster = _find(siblings, [
          'poster.jpg',
          'poster.png',
          'poster.webp',
          'folder.jpg',
          'folder.png'
        ]);
        break;
      }
      if (path.equals(directory.path, root.path)) break;
      directory = directory.parent;
    }
    final show = await _read(showNfo);
    var inferredShow = episodeMatch == null
        ? animeMatch?.group(1)?.trim()
        : cleanStem
            .substring(0, episodeMatch.start)
            .replaceAll(RegExp(r'[._]+'), ' ')
            .trim();
    if (inferredShow != null && inferredShow.isEmpty) {
      var folder = file.parent;
      if (RegExp(r'^(?:season[ ._-]*\d+|s\d+|第.+季|specials)$',
              caseSensitive: false)
          .hasMatch(path.basename(folder.path))) {
        folder = folder.parent;
      }
      if (path.isWithin(root.path, folder.path)) {
        inferredShow = path.basename(folder.path);
      }
    }
    final series = metadata.showTitle ??
        show.title ??
        (inferredShow == null || inferredShow.isEmpty ? null : inferredShow);
    final poster = _find(files, [
          for (final extension in ['jpg', 'png', 'webp', 'jpeg'])
            '$stem-poster.$extension',
          for (final extension in ['jpg', 'png', 'webp', 'jpeg'])
            '$stem.$extension',
          'poster.jpg',
          'poster.png',
          'poster.webp',
          'folder.jpg',
          'folder.png',
          'cover.jpg',
          'cover.png',
        ]) ??
        showPoster;
    final revisions = <String>[
      '${stat.size}',
      '${stat.modified.millisecondsSinceEpoch}',
      'catalog-v3'
    ];
    for (final sidecar in [nfo, showNfo, poster]) {
      if (sidecar == null) {
        revisions.add('-');
        continue;
      }
      final value = await sidecar.stat();
      revisions.add(
          '${sidecar.path}:${value.size}:${value.modified.millisecondsSinceEpoch}');
    }
    final yearMatch = RegExp(r'(?:^|[ ._(\-])((?:19|20)\d{2})(?:$|[ ._)\-])')
        .firstMatch(stem);
    return CatalogItem(
        filePath: file.path,
        title: metadata.title ?? stem,
        revision: revisions.join(':'),
        series: series,
        plot: metadata.plot ?? show.plot,
        poster: poster?.path,
        year: metadata.year ??
            show.year ??
            int.tryParse(yearMatch?.group(1) ?? ''),
        season: metadata.season ??
            int.tryParse(episodeMatch?.group(1) ?? '') ??
            (animeMatch == null ? null : 1),
        episode: metadata.episode ??
            int.tryParse(episodeMatch?.group(2) ?? animeMatch?.group(2) ?? ''));
  }
}
