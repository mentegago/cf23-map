import 'string_utils.dart';

List<String> orderCreatorFandoms({
  required Iterable<String> fandoms,
  required Iterable<String> xList,
  Iterable<String> interestOrder = const [],
  bool originalFirst = false,
}) {
  final unique = <String, String>{};
  for (final fandom in fandoms) {
    final normalized = optimizeStringFormat(fandom);
    if (normalized.isNotEmpty) unique.putIfAbsent(normalized, () => fandom);
  }

  final interestRanks = _ranksFor(interestOrder);
  final xListRanks = _ranksFor(xList);
  final ordered = unique.entries.toList()
    ..sort((a, b) {
      if (originalFirst) {
        final aOriginal = a.key == 'original';
        final bOriginal = b.key == 'original';
        if (aOriginal != bOriginal) return aOriginal ? -1 : 1;
      }

      final interestComparison = _compareRanks(
        interestRanks[a.key],
        interestRanks[b.key],
      );
      if (interestComparison != 0) return interestComparison;

      final xListComparison = _compareRanks(
        xListRanks[a.key],
        xListRanks[b.key],
      );
      if (xListComparison != 0) return xListComparison;

      return a.value.toLowerCase().compareTo(b.value.toLowerCase());
    });

  return List.unmodifiable(ordered.map((entry) => entry.value));
}

Map<String, int> _ranksFor(Iterable<String> fandoms) {
  final ranks = <String, int>{};
  for (final fandom in fandoms) {
    final normalized = optimizeStringFormat(fandom);
    if (normalized.isNotEmpty) {
      ranks.putIfAbsent(normalized, () => ranks.length);
    }
  }
  return ranks;
}

int _compareRanks(int? a, int? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return a.compareTo(b);
}
