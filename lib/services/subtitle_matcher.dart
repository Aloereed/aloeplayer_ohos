import 'package:path/path.dart' as path;

List<String> matchSubtitles(String mediaName, Iterable<String> candidates, {String preferredLanguage = ''}) {
  String name(String value) => path.basename(Uri.decodeComponent(Uri.tryParse(value)?.path ?? value)).toLowerCase();
  final stem = path.basenameWithoutExtension(name(mediaName));
  final languages = preferredLanguage.toLowerCase().split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).toList();
  final result = candidates.where((candidate) {
    final file = name(candidate);
    final base = path.basenameWithoutExtension(file);
    return {'.srt', '.ass', '.ssa', '.vtt'}.contains(path.extension(file)) && (base == stem || base.startsWith('$stem.'));
  }).toList();
  int score(String candidate) {
    final base = path.basenameWithoutExtension(name(candidate));
    final suffix = base.substring(stem.length).split('.');
    return (languages.any(suffix.contains) ? 200 : 0) + (base == stem ? 100 : 0);
  }
  result.sort((a, b) { final ranked = score(b).compareTo(score(a)); return ranked != 0 ? ranked : name(a).compareTo(name(b)); });
  return result;
}
