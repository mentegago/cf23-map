import 'dart:math';

import '../models/creator.dart';
import '../models/recommendation.dart';
import '../utils/string_utils.dart';

class RecommendationEngine {
  static const double _fandomWeight = 0.75;
  static const double _itineraryWeight = 0.05;
  static const double _fandomItineraryWeight = 0.15;
  static const double _explorationWeight = 0.05;
  static const double _boothNumberDistanceScale = 4;
  static final RegExp _boothPattern = RegExp(r'^([A-Z]+)-0*(\d+)$');

  const RecommendationEngine();

  Future<List<RecommendationResult>> recommendAsync({
    required List<Creator> creators,
    required RecommendationProfile profile,
    required Set<int> favoriteIds,
    required Set<int> sessionExposureIds,
    List<String> coldStartFandoms = const [],
    DateTime? now,
    int limit = 10,
    bool Function()? isCancelled,
  }) async {
    if (creators.isEmpty || limit <= 0) return [];

    final budget = _AsyncBudget();
    final currentTime = now ?? DateTime.now();
    final creatorsById = {for (final creator in creators) creator.id: creator};
    final fandomDocumentFrequency = <String, int>{};
    for (var index = 0; index < creators.length; index++) {
      if (isCancelled?.call() ?? false) return [];
      final uniqueFandoms = creators[index]
          .fandoms
          .map(_normalizeFandom)
          .where((fandom) => fandom.isNotEmpty)
          .toSet();
      for (final fandom in uniqueFandoms) {
        fandomDocumentFrequency[fandom] =
            (fandomDocumentFrequency[fandom] ?? 0) + 1;
      }
      if (index % 32 == 0) await budget.checkpoint();
    }

    final interestVector = _buildInterestVector(
      creatorsById: creatorsById,
      profile: profile,
      favoriteIds: favoriteIds,
      coldStartFandoms: coldStartFandoms,
      now: currentTime,
    );
    await budget.checkpoint(force: true);
    if (isCancelled?.call() ?? false) return [];

    final anchors = _buildItineraryAnchors(
      creatorsById: creatorsById,
      profile: profile,
      favoriteIds: favoriteIds,
    );
    if (isCancelled?.call() ?? false) return [];

    final candidates = <RecommendationResult>[];
    for (var index = 0; index < creators.length; index++) {
      if (isCancelled?.call() ?? false) return [];
      final creator = creators[index];
      if (creator.id == -1 || favoriteIds.contains(creator.id)) continue;

      final fandom = _fandomAffinity(
        creator,
        interestVector,
        fandomDocumentFrequency,
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
      isCancelled: isCancelled,
    );
  }

  List<RecommendationResult> recommend({
    required List<Creator> creators,
    required RecommendationProfile profile,
    required Set<int> favoriteIds,
    required Set<int> sessionExposureIds,
    List<String> coldStartFandoms = const [],
    DateTime? now,
    int limit = 10,
  }) {
    if (creators.isEmpty || limit <= 0) return [];

    final currentTime = now ?? DateTime.now();
    final creatorsById = {for (final creator in creators) creator.id: creator};
    final fandomDocumentFrequency = _fandomDocumentFrequency(creators);
    final interestVector = _buildInterestVector(
      creatorsById: creatorsById,
      profile: profile,
      favoriteIds: favoriteIds,
      coldStartFandoms: coldStartFandoms,
      now: currentTime,
    );
    final anchors = _buildItineraryAnchors(
      creatorsById: creatorsById,
      profile: profile,
      favoriteIds: favoriteIds,
    );

    final candidates = <RecommendationResult>[];
    for (final creator in creators) {
      if (creator.id == -1 || favoriteIds.contains(creator.id)) continue;

      final fandom = _fandomAffinity(
        creator,
        interestVector,
        fandomDocumentFrequency,
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

    return _selectDiverse(candidates, limit);
  }

  Map<String, double> _buildInterestVector({
    required Map<int, Creator> creatorsById,
    required RecommendationProfile profile,
    required Set<int> favoriteIds,
    required List<String> coldStartFandoms,
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

    if (vector.isEmpty) {
      for (var index = 0; index < coldStartFandoms.length; index++) {
        final key = _normalizeFandom(coldStartFandoms[index]);
        if (key.isNotEmpty) {
          vector[key] = max(vector[key] ?? 0, 1 - index * 0.03);
        }
      }
    }

    final maximum = vector.values.fold<double>(0, max);
    if (maximum > 0) {
      vector.updateAll((_, value) => value / maximum);
    }
    return vector;
  }

  Map<String, int> _fandomDocumentFrequency(List<Creator> creators) {
    final frequency = <String, int>{};
    for (final creator in creators) {
      final uniqueFandoms = creator.fandoms
          .map(_normalizeFandom)
          .where((fandom) => fandom.isNotEmpty)
          .toSet();
      for (final fandom in uniqueFandoms) {
        frequency[fandom] = (frequency[fandom] ?? 0) + 1;
      }
    }
    return frequency;
  }

  ({double affinity, List<String> matchingFandoms}) _fandomAffinity(
    Creator creator,
    Map<String, double> interestVector,
    Map<String, int> documentFrequency,
    int creatorCount,
  ) {
    final matches = <({String fandom, double value})>[];
    for (final fandom in creator.fandoms) {
      final key = _normalizeFandom(fandom);
      final interest = interestVector[key];
      if (interest == null || interest <= 0) continue;

      final frequency = documentFrequency[key] ?? 1;
      final specificity =
          (log((creatorCount + 1) / (frequency + 1)) / 4).clamp(0.35, 1.0);
      matches.add((fandom: fandom, value: interest * specificity));
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
      final firstLocation = _parseBooth(firstBooth);
      if (firstLocation == null) continue;
      for (final secondBooth in second.booths) {
        final secondLocation = _parseBooth(secondBooth);
        if (secondLocation == null ||
            firstLocation.section != secondLocation.section) {
          continue;
        }

        final numberGap = (firstLocation.number - secondLocation.number).abs();
        final proximity = exp(-numberGap / _boothNumberDistanceScale);
        best = max(best, proximity);
      }
    }
    return best;
  }

  ({String section, int number})? _parseBooth(String booth) {
    final match = _boothPattern.firstMatch(booth.trim().toUpperCase());
    if (match == null) return null;
    final number = int.tryParse(match.group(2)!);
    if (number == null) return null;
    return (section: match.group(1)!, number: number);
  }

  List<RecommendationResult> _selectDiverse(
    List<RecommendationResult> candidates,
    int limit,
  ) {
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
            _fandomOverlap(candidate.creator, existing.creator),
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
            _fandomOverlap(candidate.creator, existing.creator),
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

  double _fandomOverlap(Creator first, Creator second) {
    final a = first.fandoms.map(_normalizeFandom).toSet();
    final b = second.fandoms.map(_normalizeFandom).toSet();
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

class _AsyncBudget {
  Stopwatch _stopwatch = Stopwatch()..start();

  Future<void> checkpoint({bool force = false}) async {
    if (!force && _stopwatch.elapsedMicroseconds < 3000) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
    _stopwatch = Stopwatch()..start();
  }
}
