import 'dart:math';

import '../models/booth_proximity.dart';
import '../models/creator.dart';
import '../models/recommendation.dart';
import '../utils/string_utils.dart';

class RecommendationEngine {
  static const double _fandomWeight = 0.75;
  static const double _itineraryWeight = 0.05;
  static const double _fandomItineraryWeight = 0.15;
  static const double _explorationWeight = 0.05;
  static const double _walkingDistanceScale = 8;
  static final Expando<_FandomCatalog> _fandomCatalogs =
      Expando<_FandomCatalog>();

  final BoothProximityData boothProximity;

  const RecommendationEngine({
    this.boothProximity = BoothProximityData.empty,
  });

  List<String> rankedInterestedFandoms({
    required List<Creator> creators,
    required RecommendationProfile profile,
    required Set<int> favoriteIds,
    DateTime? now,
  }) {
    if (creators.isEmpty) return const [];

    final catalog = _fandomCatalog(creators);
    final interestVector = _buildInterestVector(
      creatorsById: {for (final creator in creators) creator.id: creator},
      profile: profile,
      favoriteIds: favoriteIds,
      now: now ?? DateTime.now(),
    );
    final ranked = interestVector.entries
        .where((entry) => catalog.displayByNormalized.containsKey(entry.key))
        .toList()
      ..sort((a, b) {
        final strength = b.value.compareTo(a.value);
        if (strength != 0) return strength;
        final popularity = (catalog.documentFrequency[b.key] ?? 0)
            .compareTo(catalog.documentFrequency[a.key] ?? 0);
        if (popularity != 0) return popularity;
        return a.key.compareTo(b.key);
      });
    return ranked
        .map((entry) => catalog.displayByNormalized[entry.key]!)
        .toList();
  }

  Future<List<RecommendationResult>> recommendAsync({
    required List<Creator> creators,
    required RecommendationProfile profile,
    required Set<int> favoriteIds,
    required Set<int> sessionExposureIds,
    DateTime? now,
    int limit = 10,
    bool Function()? isCancelled,
  }) async {
    if (creators.isEmpty || limit <= 0) return [];

    final budget = _AsyncBudget();
    final currentTime = now ?? DateTime.now();
    final creatorsById = {for (final creator in creators) creator.id: creator};
    final fandomCatalog = await _fandomCatalogAsync(
      creators,
      budget: budget,
      isCancelled: isCancelled,
    );
    if (fandomCatalog == null) return [];

    final interestVector = _buildInterestVector(
      creatorsById: creatorsById,
      profile: profile,
      favoriteIds: favoriteIds,
      now: currentTime,
    );
    await budget.checkpoint(force: true);
    if (isCancelled?.call() ?? false) return [];

    final anchors = _buildItineraryAnchors(
      creatorsById: creatorsById,
      profile: profile,
      favoriteIds: favoriteIds,
    );
    if (interestVector.isEmpty && anchors.isEmpty) return [];
    if (isCancelled?.call() ?? false) return [];

    final candidates = <RecommendationResult>[];
    for (var index = 0; index < creators.length; index++) {
      if (isCancelled?.call() ?? false) return [];
      final creator = creators[index];
      if (creator.id == -1 || favoriteIds.contains(creator.id)) continue;

      final fandom = _fandomAffinity(
        creator,
        interestVector,
        fandomCatalog,
        creators.length,
      );
      final itinerary = _itineraryAffinity(creator, anchors);
      final exploration = _stableExplorationValue(creator.id);

      var score = _fandomWeight * fandom.affinity +
          _itineraryWeight * itinerary.affinity +
          _fandomItineraryWeight * fandom.affinity * itinerary.affinity +
          _explorationWeight * exploration;

      final interaction = profile.creatorInteractions[creator.id];
      if (sessionExposureIds.contains(creator.id)) {
        score *= 0.65;
      } else if (interaction != null) {
        final age = currentTime.difference(interaction.lastUpdated);
        if (age < const Duration(days: 1)) {
          score *= 0.65;
        } else if (age < const Duration(days: 7)) {
          score *= 0.85;
        }
      }

      candidates.add(
        RecommendationResult(
          creator: creator,
          score: score,
          fandomAffinity: fandom.affinity,
          itineraryAffinity: itinerary.affinity,
          matchingFandoms: fandom.matchingFandoms,
          nearbyPlannedCreatorIds: itinerary.nearbyCreatorIds,
        ),
      );
      if (index % 16 == 0) await budget.checkpoint();
    }

    return _selectDiverseAsync(
      candidates,
      limit,
      budget: budget,
      normalizedFandoms: fandomCatalog.setsByCreatorId,
      isCancelled: isCancelled,
    );
  }

  List<RecommendationResult> recommend({
    required List<Creator> creators,
    required RecommendationProfile profile,
    required Set<int> favoriteIds,
    required Set<int> sessionExposureIds,
    DateTime? now,
    int limit = 10,
  }) {
    if (creators.isEmpty || limit <= 0) return [];

    final currentTime = now ?? DateTime.now();
    final creatorsById = {for (final creator in creators) creator.id: creator};
    final fandomCatalog = _fandomCatalog(creators);
    final interestVector = _buildInterestVector(
      creatorsById: creatorsById,
      profile: profile,
      favoriteIds: favoriteIds,
      now: currentTime,
    );
    final anchors = _buildItineraryAnchors(
      creatorsById: creatorsById,
      profile: profile,
      favoriteIds: favoriteIds,
    );
    if (interestVector.isEmpty && anchors.isEmpty) return [];

    final candidates = <RecommendationResult>[];
    for (final creator in creators) {
      if (creator.id == -1 || favoriteIds.contains(creator.id)) continue;

      final fandom = _fandomAffinity(
        creator,
        interestVector,
        fandomCatalog,
        creators.length,
      );
      final itinerary = _itineraryAffinity(creator, anchors);
      final exploration = _stableExplorationValue(creator.id);

      var score = _fandomWeight * fandom.affinity +
          _itineraryWeight * itinerary.affinity +
          _fandomItineraryWeight * fandom.affinity * itinerary.affinity +
          _explorationWeight * exploration;

      final interaction = profile.creatorInteractions[creator.id];
      if (sessionExposureIds.contains(creator.id)) {
        score *= 0.65;
      } else if (interaction != null) {
        final age = currentTime.difference(interaction.lastUpdated);
        if (age < const Duration(days: 1)) {
          score *= 0.65;
        } else if (age < const Duration(days: 7)) {
          score *= 0.85;
        }
      }

      candidates.add(
        RecommendationResult(
          creator: creator,
          score: score,
          fandomAffinity: fandom.affinity,
          itineraryAffinity: itinerary.affinity,
          matchingFandoms: fandom.matchingFandoms,
          nearbyPlannedCreatorIds: itinerary.nearbyCreatorIds,
        ),
      );
    }

    return _selectDiverse(
      candidates,
      limit,
      normalizedFandoms: fandomCatalog.setsByCreatorId,
    );
  }

  Map<String, double> _buildInterestVector({
    required Map<int, Creator> creatorsById,
    required RecommendationProfile profile,
    required Set<int> favoriteIds,
    required DateTime now,
  }) {
    final vector = <String, double>{};

    for (final entry in profile.explicitFandomSignals.entries) {
      final value = _decay(
        entry.value.strength,
        entry.value.lastUpdated,
        const Duration(days: 60),
        now,
      );
      if (value > 0.01) vector[entry.key] = value;
    }

    for (final entry in profile.creatorInteractions.entries) {
      final creator = creatorsById[entry.key];
      if (creator == null || creator.fandoms.isEmpty) continue;

      final interaction = entry.value;
      final behaviorStrength = min(interaction.openStrength, 6) +
          min(interaction.sampleWorkViews, 3) * 4 +
          min(interaction.externalLinkClicks, 2) * 5 +
          min(interaction.shares, 2) * 4;
      final decayedBehavior = _decay(
        behaviorStrength.toDouble(),
        interaction.lastUpdated,
        const Duration(days: 30),
        now,
      );
      final totalStrength =
          decayedBehavior + (favoriteIds.contains(entry.key) ? 10 : 0);
      if (totalStrength <= 0.01) continue;

      final divisor = sqrt(creator.fandoms.length);
      for (final fandom in creator.fandoms) {
        final key = _normalizeFandom(fandom);
        if (key.isEmpty) continue;
        vector[key] = (vector[key] ?? 0) + totalStrength / divisor;
      }
    }

    for (final favoriteId in favoriteIds) {
      if (profile.creatorInteractions.containsKey(favoriteId)) continue;
      final creator = creatorsById[favoriteId];
      if (creator == null || creator.fandoms.isEmpty) continue;
      final divisor = sqrt(creator.fandoms.length);
      for (final fandom in creator.fandoms) {
        final key = _normalizeFandom(fandom);
        if (key.isNotEmpty) {
          vector[key] = (vector[key] ?? 0) + 10 / divisor;
        }
      }
    }

    final maximum = vector.values.fold<double>(0, max);
    if (maximum > 0) {
      vector.updateAll((_, value) => value / maximum);
    }
    return vector;
  }

  _FandomCatalog _fandomCatalog(List<Creator> creators) {
    final cached = _fandomCatalogs[creators];
    if (cached != null) return cached;

    final frequency = <String, int>{};
    final entriesByCreatorId = <int, List<_NormalizedFandom>>{};
    final setsByCreatorId = <int, Set<String>>{};
    final displayByNormalized = <String, String>{};
    for (final creator in creators) {
      final entries = _normalizedFandoms(creator);
      final uniqueFandoms = entries.map((entry) => entry.normalized).toSet();
      for (final fandom in uniqueFandoms) {
        frequency[fandom] = (frequency[fandom] ?? 0) + 1;
      }
      for (final entry in entries) {
        displayByNormalized.putIfAbsent(entry.normalized, () => entry.display);
      }
      entriesByCreatorId[creator.id] = entries;
      setsByCreatorId[creator.id] = uniqueFandoms;
    }
    final catalog = _FandomCatalog(
      documentFrequency: frequency,
      entriesByCreatorId: entriesByCreatorId,
      setsByCreatorId: setsByCreatorId,
      displayByNormalized: displayByNormalized,
    );
    _fandomCatalogs[creators] = catalog;
    return catalog;
  }

  Future<_FandomCatalog?> _fandomCatalogAsync(
    List<Creator> creators, {
    required _AsyncBudget budget,
    bool Function()? isCancelled,
  }) async {
    final cached = _fandomCatalogs[creators];
    if (cached != null) return cached;

    final frequency = <String, int>{};
    final entriesByCreatorId = <int, List<_NormalizedFandom>>{};
    final setsByCreatorId = <int, Set<String>>{};
    final displayByNormalized = <String, String>{};
    for (var index = 0; index < creators.length; index++) {
      if (isCancelled?.call() ?? false) return null;
      final creator = creators[index];
      final entries = _normalizedFandoms(creator);
      final uniqueFandoms = entries.map((entry) => entry.normalized).toSet();
      for (final fandom in uniqueFandoms) {
        frequency[fandom] = (frequency[fandom] ?? 0) + 1;
      }
      for (final entry in entries) {
        displayByNormalized.putIfAbsent(entry.normalized, () => entry.display);
      }
      entriesByCreatorId[creator.id] = entries;
      setsByCreatorId[creator.id] = uniqueFandoms;
      if (index % 32 == 0) await budget.checkpoint();
    }
    final catalog = _FandomCatalog(
      documentFrequency: frequency,
      entriesByCreatorId: entriesByCreatorId,
      setsByCreatorId: setsByCreatorId,
      displayByNormalized: displayByNormalized,
    );
    _fandomCatalogs[creators] = catalog;
    return catalog;
  }

  List<_NormalizedFandom> _normalizedFandoms(Creator creator) {
    return creator.fandoms
        .map(
          (fandom) => _NormalizedFandom(
            display: fandom,
            normalized: _normalizeFandom(fandom),
          ),
        )
        .where((fandom) => fandom.normalized.isNotEmpty)
        .toList();
  }

  ({double affinity, List<String> matchingFandoms}) _fandomAffinity(
    Creator creator,
    Map<String, double> interestVector,
    _FandomCatalog catalog,
    int creatorCount,
  ) {
    final matches = <({String fandom, double value})>[];
    for (final fandom in catalog.entriesByCreatorId[creator.id] ?? const []) {
      final interest = interestVector[fandom.normalized];
      if (interest == null || interest <= 0) continue;

      final frequency = catalog.documentFrequency[fandom.normalized] ?? 1;
      final specificity =
          (log((creatorCount + 1) / (frequency + 1)) / 4).clamp(0.35, 1.0);
      matches.add((fandom: fandom.display, value: interest * specificity));
    }
    matches.sort((a, b) => b.value.compareTo(a.value));

    var affinity = 0.0;
    if (matches.isNotEmpty) affinity += matches[0].value;
    if (matches.length > 1) affinity += matches[1].value * 0.4;
    if (matches.length > 2) affinity += matches[2].value * 0.2;

    return (
      affinity: (affinity / 1.6).clamp(0.0, 1.0),
      matchingFandoms: matches.take(3).map((match) => match.fandom).toList(),
    );
  }

  List<({Creator creator, double strength})> _buildItineraryAnchors({
    required Map<int, Creator> creatorsById,
    required RecommendationProfile profile,
    required Set<int> favoriteIds,
  }) {
    final anchors = <({Creator creator, double strength})>[];
    for (final creator in creatorsById.values) {
      final interaction = profile.creatorInteractions[creator.id];
      final strength = favoriteIds.contains(creator.id)
          ? 1.0
          : interaction?.consideration ?? 0;
      if (strength >= 0.2 && creator.booths.isNotEmpty) {
        anchors.add((creator: creator, strength: strength.clamp(0.0, 1.0)));
      }
    }
    anchors.sort((a, b) => b.strength.compareTo(a.strength));
    return anchors.take(20).toList();
  }

  ({double affinity, List<int> nearbyCreatorIds}) _itineraryAffinity(
    Creator candidate,
    List<({Creator creator, double strength})> anchors,
  ) {
    if (candidate.booths.isEmpty || anchors.isEmpty) {
      return (affinity: 0, nearbyCreatorIds: const []);
    }

    var bestAffinity = 0.0;
    final nearby = <int>[];
    for (final anchor in anchors) {
      if (anchor.creator.id == candidate.id) continue;
      final proximity = _boothProximity(candidate, anchor.creator);
      if (proximity <= 0) continue;
      final affinity = anchor.strength * proximity;
      if (affinity > bestAffinity) {
        bestAffinity = affinity;
        nearby
          ..clear()
          ..add(anchor.creator.id);
      } else if (bestAffinity > 0 && affinity >= bestAffinity * 0.8) {
        nearby.add(anchor.creator.id);
      }
    }

    return (
      affinity: bestAffinity.clamp(0.0, 1.0),
      nearbyCreatorIds: nearby.take(3).toList(),
    );
  }

  double _boothProximity(Creator first, Creator second) {
    var best = 0.0;
    for (final firstBooth in first.booths) {
      for (final secondBooth in second.booths) {
        final distance =
            boothProximity.distanceBetween(firstBooth, secondBooth);
        if (distance == null) continue;
        final proximity = exp(-distance / _walkingDistanceScale);
        best = max(best, proximity);
      }
    }
    return best;
  }

  List<RecommendationResult> _selectDiverse(
    List<RecommendationResult> candidates,
    int limit, {
    required Map<int, Set<String>> normalizedFandoms,
  }) {
    final remaining = List<RecommendationResult>.from(candidates);
    final selected = <RecommendationResult>[];

    while (remaining.isNotEmpty && selected.length < limit) {
      RecommendationResult? best;
      var bestAdjustedScore = double.negativeInfinity;
      for (final candidate in remaining) {
        var maximumOverlap = 0.0;
        for (final existing in selected) {
          maximumOverlap = max(
            maximumOverlap,
            _fandomOverlap(
              normalizedFandoms[candidate.creator.id]!,
              normalizedFandoms[existing.creator.id]!,
            ),
          );
        }
        final adjustedScore = candidate.score - maximumOverlap * 0.08;
        if (adjustedScore > bestAdjustedScore ||
            (adjustedScore == bestAdjustedScore &&
                (best == null || candidate.creator.id < best.creator.id))) {
          best = candidate;
          bestAdjustedScore = adjustedScore;
        }
      }
      selected.add(best!);
      remaining.remove(best);
    }
    return selected;
  }

  Future<List<RecommendationResult>> _selectDiverseAsync(
    List<RecommendationResult> candidates,
    int limit, {
    required _AsyncBudget budget,
    required Map<int, Set<String>> normalizedFandoms,
    bool Function()? isCancelled,
  }) async {
    final remaining = List<RecommendationResult>.from(candidates);
    final selected = <RecommendationResult>[];
    var scanned = 0;

    while (remaining.isNotEmpty && selected.length < limit) {
      RecommendationResult? best;
      var bestAdjustedScore = double.negativeInfinity;
      for (final candidate in remaining) {
        if (isCancelled?.call() ?? false) return [];
        var maximumOverlap = 0.0;
        for (final existing in selected) {
          maximumOverlap = max(
            maximumOverlap,
            _fandomOverlap(
              normalizedFandoms[candidate.creator.id]!,
              normalizedFandoms[existing.creator.id]!,
            ),
          );
        }
        final adjustedScore = candidate.score - maximumOverlap * 0.08;
        if (adjustedScore > bestAdjustedScore ||
            (adjustedScore == bestAdjustedScore &&
                (best == null || candidate.creator.id < best.creator.id))) {
          best = candidate;
          bestAdjustedScore = adjustedScore;
        }
        scanned++;
        if (scanned % 32 == 0) await budget.checkpoint();
      }
      selected.add(best!);
      remaining.remove(best);
    }
    return selected;
  }

  double _fandomOverlap(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    return a.intersection(b).length / a.union(b).length;
  }

  double _stableExplorationValue(int creatorId) {
    final value = (creatorId * 1103515245 + 12345) & 0x7fffffff;
    return value / 0x7fffffff;
  }

  double _decay(
    double value,
    DateTime lastUpdated,
    Duration halfLife,
    DateTime now,
  ) {
    if (lastUpdated.millisecondsSinceEpoch <= 0 || !now.isAfter(lastUpdated)) {
      return value;
    }
    final elapsed = now.difference(lastUpdated).inMilliseconds;
    final periods = elapsed / halfLife.inMilliseconds;
    return value * pow(0.5, periods);
  }

  String _normalizeFandom(String fandom) => optimizeStringFormat(fandom);
}

class _FandomCatalog {
  final Map<String, int> documentFrequency;
  final Map<int, List<_NormalizedFandom>> entriesByCreatorId;
  final Map<int, Set<String>> setsByCreatorId;
  final Map<String, String> displayByNormalized;

  const _FandomCatalog({
    required this.documentFrequency,
    required this.entriesByCreatorId,
    required this.setsByCreatorId,
    required this.displayByNormalized,
  });
}

class _NormalizedFandom {
  final String display;
  final String normalized;

  const _NormalizedFandom({
    required this.display,
    required this.normalized,
  });
}

class _AsyncBudget {
  Stopwatch _stopwatch = Stopwatch()..start();

  Future<void> checkpoint({bool force = false}) async {
    if (!force && _stopwatch.elapsedMicroseconds < 3000) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
    _stopwatch = Stopwatch()..start();
  }
}
