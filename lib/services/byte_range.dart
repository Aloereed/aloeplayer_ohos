/// A single HTTP byte range; [end] is inclusive.
class ByteRange {
  final int start;
  final int end;
  const ByteRange(this.start, this.end);
  int get length => end - start + 1;

  static ByteRange? parse(String value, int size) {
    if (size <= 0) return null;
    final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(value.trim());
    if (match == null) return null;
    final first = match[1]!;
    final last = match[2]!;
    if (first.isEmpty) {
      final suffix = int.tryParse(last);
      if (suffix == null || suffix <= 0) return null;
      return ByteRange(suffix >= size ? 0 : size - suffix, size - 1);
    }
    final start = int.tryParse(first);
    final requestedEnd = last.isEmpty ? size - 1 : int.tryParse(last);
    if (start == null || requestedEnd == null || start >= size || requestedEnd < start) return null;
    return ByteRange(start, requestedEnd >= size ? size - 1 : requestedEnd);
  }
}
