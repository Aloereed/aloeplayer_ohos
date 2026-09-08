import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/network_sort.dart';

void main() {
  test(
      'episode names sort naturally with Unicode, padding and multiple numeric runs',
      () {
    final names = ['第10集.mkv', '第2集.mkv', '第1集.mkv']..sort(compareNetworkNames);
    expect(names, ['第1集.mkv', '第2集.mkv', '第10集.mkv']);
    expect(['S10E1', 'S2E10', 'S2E2', 'S2E02']..sort(compareNetworkNames),
        ['S2E2', 'S2E02', 'S2E10', 'S10E1']);
    expect(compareNetworkNames('a${'9' * 50}', 'a1${'0' * 50}'), lessThan(0));
    expect(compareNetworkNames('EP2', 'ep10'), lessThan(0));
  });
  test(
      'natural comparator is deterministic and transitive with punctuation and ties',
      () {
    final names = [
      '',
      '0',
      '00',
      '1',
      '01',
      '2',
      'a',
      'A',
      'a2',
      'a02',
      'a10',
      '中文1',
      '中文2',
      '中文10',
      'a#1',
      'a%2'
    ];
    for (final a in names) {
      expect(compareNetworkNames(a, a), 0);
      for (final b in names) {
        expect(compareNetworkNames(a, b).sign, -compareNetworkNames(b, a).sign);
      }
    }
    final sorted = names.toList()..sort(compareNetworkNames);
    for (var i = 0; i < sorted.length; i++) {
      for (var j = i + 1; j < sorted.length; j++) {
        expect(compareNetworkNames(sorted[i], sorted[j]), lessThan(0));
      }
    }
  });
}
