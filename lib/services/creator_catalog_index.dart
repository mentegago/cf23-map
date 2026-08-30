import 'dart:math';

import 'package:collection/collection.dart';

import '../models/creator.dart';
import '../models/fandom.dart';
import '../utils/fuzzy_score.dart';
import '../utils/string_utils.dart';

/// Immutable, query-oriented indexes derived from one catalog snapshot.
class CreatorCatalogIndex {
  final List<Creator> creators;
  final Map<int, Creator> creatorById;
  final Map<String, List<Creator>> creatorsByBooth;
  final Map<int, Fandom> fandomById;
  final Map<String, int> fandomIdBySearchName;
  final Map<int, List<Creator>> creatorsByFandomId;
  final Map<int, int> fandomPopularity;
  final List<Fandom> fandoms;
  final Map<String, List<Creator>> _searchCache = {};
  final Map<String, List<String>> _suggestionCache = {};

  CreatorCatalogIndex._({
    required this.creators,
    required this.creatorById,
    required this.creatorsByBooth,
    required this.fandomById,
    required this.fandomIdBySearchName,
    required this.creatorsByFandomId,
    required this.fandomPopularity,
    required this.fandoms,
  });

  factory CreatorCatalogIndex.build(
    List<Creator> creators,
    Map<int, Fandom> allFandoms,
  ) {
    final creatorById = <int, Creator>{};
    final creatorsByBooth = <String, List<Creator>>{};
    final creatorsByFandomId = <int, List<Creator>>{};
    final fandomPopularity = <int, int>{};
    final usedFandoms = <int, Fandom>{};

    for (final creator in creators) {
      creatorById[creator.id] = creator;
      for (final booth in creator.booths) {
        creatorsByBooth.putIfAbsent(booth, () => []).add(creator);
      }
      final searchableFandomIds = <int>{};
      for (final fandom in creator.fandoms) {
        int? currentId = fandom.id;
        while (currentId != null && searchableFandomIds.add(currentId)) {
          currentId = allFandoms[currentId]?.parentId;
        }
      }
      for (final fandomId in searchableFandomIds) {
        final fandom = allFandoms[fandomId];
        if (fandom == null) continue;
        usedFandoms[fandomId] = fandom;
        creatorsByFandomId.putIfAbsent(fandomId, () => []).add(creator);
        fandomPopularity[fandomId] = (fandomPopularity[fandomId] ?? 0) + 1;
      }
    }

    final fandoms = usedFandoms.values.sortedBy((fandom) => fandom.name);
    return CreatorCatalogIndex._(
      creators: creators,
      creatorById: creatorById,
      creatorsByBooth: creatorsByBooth,
      fandomById: Map.unmodifiable(allFandoms),
      fandomIdBySearchName: {
        for (final fandom in allFandoms.values) fandom.searchName: fandom.id,
      },
      creatorsByFandomId: creatorsByFandomId,
      fandomPopularity: fandomPopularity,
      fandoms: fandoms,
    );
  }

  int? fandomIdForName(String name) =>
      fandomIdBySearchName[optimizeStringFormat(name)];

  List<String> popularFandomNames({int limit = 20}) {
    final ranked = fandomPopularity.entries.toList()
      ..sort((a, b) {
        final popularity = b.value.compareTo(a.value);
        if (popularity != 0) return popularity;
        return fandomById[a.key]!
            .name
            .toLowerCase()
            .compareTo(fandomById[b.key]!.name.toLowerCase());
      });
    return ranked
        .take(limit)
        .map((entry) => fandomById[entry.key]!.name)
        .toList(growable: false);
  }

  List<String> fandomSuggestions(String query, {int limit = 20}) {
    final cacheKey = '$limit:${query.trim().toLowerCase()}';
    return _suggestionCache.putIfAbsent(
      cacheKey,
      () => _fandomSuggestionsUncached(query, limit: limit),
    );
  }

  List<String> _fandomSuggestionsUncached(String query, {required int limit}) {
    if (query.trim().isEmpty) return popularFandomNames(limit: limit);

    final trimmedQuery = query.trim().toLowerCase();
    final optimizedQuery = optimizeStringFormat(trimmedQuery);
    if (optimizedQuery.isEmpty) return const [];
    final maxPopularity = fandomPopularity.values.fold<int>(1, max);
    final matches = <_FandomMatch>[];

    for (final fandom in fandoms) {
      final match = _scoreFandom(
        fandom,
        trimmedQuery: trimmedQuery,
        optimizedQuery: optimizedQuery,
      );
      if (match == null || match.score < 0.7) continue;
      final popularity = fandomPopularity[fandom.id] ?? 0;
      matches.add(match.withPopularity(popularity, maxPopularity));
    }
    matches.sort(_compareFandomMatches);
    return matches
        .take(limit)
        .map((match) => match.fandom.name)
        .toList(growable: false);
  }

  /// Scores each fandom once, then fans that score out through the inverted
  /// fandom-ID index. This avoids repeating the same fuzzy comparison for
  /// every creator that references a popular fandom.
  List<Creator> search(String query) {
    final cacheKey = query.trim().toLowerCase();
    return _searchCache.putIfAbsent(cacheKey, () => _searchUncached(query));
  }

  List<Creator> _searchUncached(String query) {
    if (query.trim().isEmpty) return creators;

    final trimmedQuery = query.trim().toLowerCase();
    final optimizedQuery = optimizeStringFormat(trimmedQuery);
    final optimizedBoothQuery = optimizedBoothFormat(trimmedQuery);
    final scores = <int, _CreatorMatch>{};

    for (final creator in creators) {
      var score = -1.0;
      var stringScore = -1.0;
      if (optimizedBoothQuery.isNotEmpty &&
          creator.searchOptimizedBooths
              .any((booth) => booth.startsWith(optimizedBoothQuery))) {
        score = 2;
        stringScore = 2;
      }

      final nameScore = fuzzyScore(optimizedQuery, creator.name.toLowerCase());
      final nameStringScore = creator.name.isEmpty
          ? 0.0
          : optimizedQuery.length / creator.name.length;
      if (nameScore.matched && nameStringScore > stringScore) {
        score = max(score, nameScore.score);
        stringScore = nameStringScore;
      }
      if (score >= 0.7) {
        scores[creator.id] = _CreatorMatch(creator, score, stringScore);
      }
    }

    for (final fandom in fandoms) {
      final fandomMatch = _scoreFandom(
        fandom,
        trimmedQuery: trimmedQuery,
        optimizedQuery: optimizedQuery,
      );
      if (fandomMatch == null || fandomMatch.score < 0.7) continue;
      for (final creator in creatorsByFandomId[fandom.id] ?? const []) {
        final current = scores[creator.id];
        if (current == null || fandomMatch.stringScore > current.stringScore) {
          scores[creator.id] = _CreatorMatch(
            creator,
            max(current?.score ?? -1, fandomMatch.score),
            fandomMatch.stringScore,
          );
        }
      }
    }

    final matches = scores.values.toList()
      ..sort((a, b) {
        final score = b.score.compareTo(a.score);
        if (score != 0) return score;
        final stringScore = b.stringScore.compareTo(a.stringScore);
        if (stringScore != 0) return stringScore;
        return a.creator.name
            .toLowerCase()
            .compareTo(b.creator.name.toLowerCase());
      });
    return matches.map((match) => match.creator).toList(growable: false);
  }

  _FandomMatch? _scoreFandom(
    Fandom fandom, {
    required String trimmedQuery,
    required String optimizedQuery,
  }) {
    var score = -1.0;
    var stringScore = -1.0;
    final forward = fuzzyScore(optimizedQuery, fandom.name.toLowerCase());
    final forwardStringScore =
        fandom.name.isEmpty ? 0.0 : optimizedQuery.length / fandom.name.length;
    if (forward.matched) {
      score = forward.score;
      stringScore = forwardStringScore;
    }

    if (fandom.searchName.isNotEmpty && trimmedQuery.isNotEmpty) {
      final reverse = fuzzyScore(fandom.searchName, trimmedQuery);
      final reverseStringScore = fandom.searchName.length / trimmedQuery.length;
      if (reverse.matched && reverseStringScore > stringScore) {
        score = max(score, reverse.score);
        stringScore = reverseStringScore;
      }
    }
    return score < 0 ? null : _FandomMatch(fandom, score, stringScore);
  }
}

class _CreatorMatch {
  final Creator creator;
  final double score;
  final double stringScore;

  const _CreatorMatch(this.creator, this.score, this.stringScore);
}

class _FandomMatch {
  final Fandom fandom;
  final double score;
  final double stringScore;
  final int popularity;
  final double combinedScore;

  const _FandomMatch(
    this.fandom,
    this.score,
    this.stringScore, {
    this.popularity = 0,
    this.combinedScore = 0,
  });

  _FandomMatch withPopularity(int popularity, int maxPopularity) =>
      _FandomMatch(
        fandom,
        score,
        stringScore,
        popularity: popularity,
        combinedScore: score * 0.5 + popularity / maxPopularity * 0.5,
      );
}

int _compareFandomMatches(_FandomMatch a, _FandomMatch b) {
  final combined = b.combinedScore.compareTo(a.combinedScore);
  if (combined != 0) return combined;
  final score = b.score.compareTo(a.score);
  if (score != 0) return score;
  final popularity = b.popularity.compareTo(a.popularity);
  if (popularity != 0) return popularity;
  return a.fandom.name.toLowerCase().compareTo(b.fandom.name.toLowerCase());
}
