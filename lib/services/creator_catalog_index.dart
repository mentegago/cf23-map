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
    final fandomIdBySearchName = <String, int>{
      for (final fandom in allFandoms.values)
        if (fandom.searchName.isNotEmpty) fandom.searchName: fandom.id,
    };
    for (final fandom in allFandoms.values) {
      for (final label in fandom.searchLabels) {
        fandomIdBySearchName.putIfAbsent(label.optimized, () => fandom.id);
      }
    }
    return CreatorCatalogIndex._(
      creators: creators,
      creatorById: creatorById,
      creatorsByBooth: creatorsByBooth,
      fandomById: Map.unmodifiable(allFandoms),
      fandomIdBySearchName: fandomIdBySearchName,
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

  List<String> matchingFandomNames(String query, {int limit = 20}) {
    if (query.trim().isEmpty) return const [];
    return fandomSuggestions(query, limit: limit);
  }

  /// Includes only catalog-represented fandoms, parent first, then by depth.
  List<String> fandomNamesForId(int rootId) => _expandFandoms([rootId]);

  List<String> _expandFandoms(Iterable<int> rootIds) {
    final expanded = <String>[];
    final seen = <int>{};
    for (final rootId in rootIds) {
      final descendants = fandoms
          .where((fandom) => _isDescendantOf(fandom.id, rootId))
          .toList()
        ..sort((a, b) {
          final depth =
              _fandomDepth(a.id, rootId).compareTo(_fandomDepth(b.id, rootId));
          if (depth != 0) return depth;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      for (final fandom in descendants) {
        if (seen.add(fandom.id)) expanded.add(fandom.name);
      }
    }
    return expanded;
  }

  bool _isDescendantOf(int fandomId, int rootId) {
    var currentId = fandomId;
    while (true) {
      if (currentId == rootId) return true;
      final parentId = fandomById[currentId]?.parentId;
      if (parentId == null) return false;
      currentId = parentId;
    }
  }

  int _fandomDepth(int fandomId, int rootId) {
    var currentId = fandomId;
    var depth = 0;
    while (currentId != rootId) {
      final parentId = fandomById[currentId]?.parentId;
      if (parentId == null) return 999;
      currentId = parentId;
      depth++;
    }
    return depth;
  }

  List<String> _fandomSuggestionsUncached(String query, {required int limit}) {
    if (query.trim().isEmpty) return popularFandomNames(limit: limit);

    final trimmedQuery = query.trim().toLowerCase();
    final optimizedQuery = optimizeStringFormat(trimmedQuery);
    if (optimizedQuery.isEmpty) return const [];
    final matches = <_FandomMatch>[];

    for (final fandom in fandoms) {
      final match = _scoreFandom(
        fandom,
        trimmedQuery: trimmedQuery,
        optimizedQuery: optimizedQuery,
      );
      if (match == null || match.score < 0.7) continue;
      matches.add(match);
    }
    matches.sort(_compareFandomMatches);
    // Limit direct matches, but retain their descendants so every included
    // branch can be selected from the chip list.
    return _expandFandoms(matches.take(limit).map((match) => match.fandom.id));
  }

  /// Scores each fandom once, then fans that score out through the inverted
  /// fandom-ID index. This avoids repeating the same fuzzy comparison for
  /// every creator that references a popular fandom.
  List<Creator> search(String query, {int? fandomId}) {
    if (fandomId != null) {
      final matches = [...?creatorsByFandomId[fandomId]]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return matches;
    }
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
        scores[creator.id] = _CreatorMatch(
          creator,
          score,
          stringScore,
          fromCanonical: true,
          tier: optimizedBoothQuery.isNotEmpty && score == 2
              ? -1
              : _textMatchTier(optimizedQuery, creator.name.toLowerCase()),
        );
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
        if (current == null || _fandomBeatsCurrent(current, fandomMatch)) {
          scores[creator.id] = _CreatorMatch(
            creator,
            fandomMatch.score,
            fandomMatch.stringScore,
            fromCanonical: fandomMatch.fromCanonical,
            tier: fandomMatch.tier,
          );
        }
      }
    }

    final matches = scores.values.toList()
      ..sort((a, b) {
        final quality =
            _compareQuality(a.tier, a.fromCanonical, b.tier, b.fromCanonical);
        if (quality != 0) return quality;
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
    _FandomMatch? best;
    for (var i = 0; i < fandom.searchLabels.length; i++) {
      final match = _scoreSearchLabel(
        fandom.searchLabels[i],
        trimmedQuery: trimmedQuery,
        optimizedQuery: optimizedQuery,
      );
      if (match == null || match.score < 0.7) continue;
      final candidate = _FandomMatch(fandom, match.score, match.stringScore,
          fromCanonical: i == 0, tier: match.tier);
      if (best == null || _compareFandomMatches(candidate, best) < 0) {
        best = candidate;
      }
    }
    return best;
  }
}

bool _fandomBeatsCurrent(_CreatorMatch current, _FandomMatch fandom) {
  final quality = _compareQuality(
      fandom.tier, fandom.fromCanonical, current.tier, current.fromCanonical);
  if (quality != 0) return quality < 0;
  if (fandom.score != current.score) return fandom.score > current.score;
  return fandom.stringScore > current.stringScore;
}

// Exact, word prefix, acronym, then general subsequence. Canonical spelling
// only breaks ties within a match tier; an exact alias beats a loose name.
int _compareQuality(int aTier, bool aCanonical, int bTier, bool bCanonical) {
  final tier = aTier.compareTo(bTier);
  if (tier != 0) return tier;
  return aCanonical == bCanonical ? 0 : (aCanonical ? -1 : 1);
}

List<String> _words(String value) =>
    RegExp(r'[a-z0-9]+').allMatches(value).map((m) => m.group(0)!).toList();

int _textMatchTier(String query, String target) {
  if (query == optimizeStringFormat(target)) return 0;
  final words = _words(target);
  if (query.isNotEmpty && words.any((word) => word.startsWith(query))) return 1;
  return 3;
}

({double score, double stringScore, int tier})? _scoreSearchLabel(
  FandomSearchLabel label, {
  required String trimmedQuery,
  required String optimizedQuery,
}) {
  if (optimizedQuery.isEmpty) return null;
  final coverage = optimizedQuery.length / label.optimized.length;
  if (optimizedQuery == label.optimized) {
    return (score: 1.0, stringScore: coverage, tier: 0);
  }

  final queryWords = _words(trimmedQuery);
  final targetWords = _words(label.target);
  var prefix = label.optimized.startsWith(optimizedQuery);
  for (var start = 0;
      start + queryWords.length <= targetWords.length;
      start++) {
    if (queryWords.isNotEmpty &&
        List.generate(queryWords.length,
                (i) => targetWords[start + i].startsWith(queryWords[i]))
            .every((matches) => matches)) {
      prefix = true;
      break;
    }
  }
  if (prefix) return (score: 1.0, stringScore: coverage, tier: 1);

  final initials = targetWords.map((word) => word[0]).join();
  if (optimizedQuery.length >= 2 && initials.startsWith(optimizedQuery)) {
    return (score: 0.85, stringScore: coverage, tier: 2);
  }
  // Very short strings must have a meaningful boundary/alias match.
  if (optimizedQuery.length <= 3) return null;
  final forward = fuzzyScore(optimizedQuery, label.target);
  return forward.matched
      ? (score: forward.score, stringScore: coverage, tier: 3)
      : null;
}

class _CreatorMatch {
  final Creator creator;
  final double score;
  final double stringScore;
  final bool fromCanonical;
  final int tier;

  const _CreatorMatch(
    this.creator,
    this.score,
    this.stringScore, {
    this.fromCanonical = true,
    this.tier = 3,
  });
}

class _FandomMatch {
  final Fandom fandom;
  final double score;
  final double stringScore;
  final bool fromCanonical;
  final int tier;

  const _FandomMatch(
    this.fandom,
    this.score,
    this.stringScore, {
    this.fromCanonical = false,
    this.tier = 3,
  });
}

int _compareFandomMatches(_FandomMatch a, _FandomMatch b) {
  final quality =
      _compareQuality(a.tier, a.fromCanonical, b.tier, b.fromCanonical);
  if (quality != 0) return quality;
  final score = b.score.compareTo(a.score);
  if (score != 0) return score;
  final stringScore = b.stringScore.compareTo(a.stringScore);
  if (stringScore != 0) return stringScore;
  return a.fandom.name.toLowerCase().compareTo(b.fandom.name.toLowerCase());
}
