/// Numeric runs sort by value without converting to bounded integers. This
/// keeps episode 2 before episode 10, including arbitrarily long digit runs.
int compareNetworkNames(String left, String right) {
  final a = left.toLowerCase(), b = right.toLowerCase();
  var i = 0, j = 0;
  bool digit(int code) => code >= 48 && code <= 57;
  while (i < a.length && j < b.length) {
    final x = a.codeUnitAt(i), y = b.codeUnitAt(j);
    if (digit(x) && digit(y)) {
      var endA = i, endB = j;
      while (endA < a.length && digit(a.codeUnitAt(endA))) {
        endA++;
      }
      while (endB < b.length && digit(b.codeUnitAt(endB))) {
        endB++;
      }
      var valueA = i, valueB = j;
      while (valueA < endA - 1 && a.codeUnitAt(valueA) == 48) {
        valueA++;
      }
      while (valueB < endB - 1 && b.codeUnitAt(valueB) == 48) {
        valueB++;
      }
      final length = (endA - valueA).compareTo(endB - valueB);
      if (length != 0) return length;
      final number =
          a.substring(valueA, endA).compareTo(b.substring(valueB, endB));
      if (number != 0) return number;
      // Deterministic tie for 2 / 02 without changing numeric ordering.
      final padding = (endA - i).compareTo(endB - j);
      if (padding != 0) return padding;
      i = endA;
      j = endB;
    } else {
      if (x != y) return x.compareTo(y);
      i++;
      j++;
    }
  }
  final length = (a.length - i).compareTo(b.length - j);
  return length != 0 ? length : left.compareTo(right);
}
