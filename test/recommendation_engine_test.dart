import 'package:cf_map_flutter/models/booth_proximity.dart';
import 'package:cf_map_flutter/models/creator.dart';
import 'package:cf_map_flutter/models/recommendation.dart';
import 'package:cf_map_flutter/services/recommendation_engine.dart';
import 'package:flutter_test/flutter_test.dart';

Creator creator(int id, String booth, List<String> fandoms) => Creator(
      id: id,
      userId: 'user-$id',
      name: 'Creator $id',
      booths: [booth],
      day: 'BOTH',
      fandoms: fandoms,
    );

void main() {
  final now = DateTime(2026, 8, 22);

  test('no profile data produces no personalized recommendations', () {
    const engine = RecommendationEngine();
    final results = engine.recommend(
      creators: [
        creator(1, 'A-1', ['Blue Archive']),
        creator(2, 'B-1', ['Hololive']),
      ],
      profile: RecommendationProfile(),
      favoriteIds: {},
      sessionExposureIds: {},
      now: now,
    );

    expect(results, isEmpty);
  });

  test('explicit fandom interest promotes matching creators', () {
    final profile = RecommendationProfile(
      explicitFandomSignals: {
        'bluearchive': FandomSignal(strength: 5, lastUpdated: now),
      },
    );
    const engine = RecommendationEngine();
    final results = engine.recommend(
      creators: [
        creator(1, 'A-1', ['Blue Archive']),
        creator(2, 'B-1', ['Hololive']),
      ],
      profile: profile,
      favoriteIds: {},
      sessionExposureIds: {},
      now: now,
    );

    expect(results.first.creator.id, 1);
    expect(results.first.matchingFandoms, contains('Blue Archive'));
  });

  test('matching fandoms are ordered by their contribution', () {
    final profile = RecommendationProfile(
      explicitFandomSignals: {
        'bluearchive': FandomSignal(strength: 5, lastUpdated: now),
        'hololive': FandomSignal(strength: 2, lastUpdated: now),
      },
    );
    const engine = RecommendationEngine();
    final results = engine.recommend(
      creators: [
        creator(1, 'A-1', ['Hololive', 'Blue Archive']),
      ],
      profile: profile,
      favoriteIds: {},
      sessionExposureIds: {},
      now: now,
    );

    expect(results.single.matchingFandoms, ['Blue Archive', 'Hololive']);
  });

  test('interested fandoms are ranked using the recommendation profile', () {
    final profile = RecommendationProfile(
      explicitFandomSignals: {
        'bluearchive': FandomSignal(strength: 5, lastUpdated: now),
        'hololive': FandomSignal(strength: 2, lastUpdated: now),
      },
    );
    const engine = RecommendationEngine();

    expect(
      engine.rankedInterestedFandoms(
        creators: [
          creator(1, 'A-1', ['Hololive']),
          creator(2, 'A-2', ['Blue Archive']),
          creator(3, 'A-3', ['Touhou']),
        ],
        profile: profile,
        favoriteIds: const {},
        now: now,
      ),
      ['Blue Archive', 'Hololive'],
    );
  });

  test('existing favorites seed fandom interest without prior profile data',
      () {
    const engine = RecommendationEngine();
    final results = engine.recommend(
      creators: [
        creator(1, 'A-1', ['Blue Archive']),
        creator(2, 'B-1', ['Blue Archive']),
        creator(3, 'C-1', ['Hololive']),
      ],
      profile: RecommendationProfile(),
      favoriteIds: {1},
      sessionExposureIds: {},
      now: now,
    );

    expect(results.first.creator.id, 2);
  });

  test('booth proximity uses precomputed walking distance', () {
    final profile = RecommendationProfile(
      creatorInteractions: {
        1: CreatorInteraction(
          favorite: true,
          consideration: 1,
          lastUpdated: now,
        ),
      },
    );
    final proximity = BoothProximityData.fromJson({
      'schema_version': 1,
      'map_sha256': 'test',
      'max_distance': 32,
      'max_neighbors': 48,
      'booths': ['AA-10', 'AA-12', 'AB-10'],
      'neighbors': [
        [
          [1, 4],
        ],
        [
          [0, 4],
        ],
        [],
      ],
    });
    final engine = RecommendationEngine(boothProximity: proximity);
    final results = engine.recommend(
      creators: [
        creator(1, 'AA-10', ['Blue Archive']),
        creator(2, 'AA-10', ['Blue Archive']),
        creator(3, 'AA-12', ['Blue Archive']),
        creator(4, 'AB-10', ['Blue Archive']),
      ],
      profile: profile,
      favoriteIds: {1},
      sessionExposureIds: {},
      now: now,
    );

    final sameNumber = results.singleWhere((result) => result.creator.id == 2);
    final closeNumber = results.singleWhere((result) => result.creator.id == 3);
    final differentSection =
        results.singleWhere((result) => result.creator.id == 4);
    expect(sameNumber.itineraryAffinity, 1);
    expect(
      sameNumber.itineraryAffinity,
      greaterThan(closeNumber.itineraryAffinity),
    );
    expect(closeNumber.itineraryAffinity, greaterThan(0));
    expect(differentSection.itineraryAffinity, 0);
    expect(sameNumber.nearbyPlannedCreatorIds, contains(1));
  });

  test('asynchronous ranking matches synchronous ranking', () async {
    final profile = RecommendationProfile(
      explicitFandomSignals: {
        'bluearchive': FandomSignal(strength: 5, lastUpdated: now),
      },
    );
    const engine = RecommendationEngine();
    final creators = [
      creator(1, 'A-1', ['Blue Archive']),
      creator(2, 'B-1', ['Hololive']),
      creator(3, 'C-1', ['Blue Archive']),
    ];

    final synchronous = engine.recommend(
      creators: creators,
      profile: profile,
      favoriteIds: {},
      sessionExposureIds: {},
      now: now,
    );
    final asynchronous = await engine.recommendAsync(
      creators: creators,
      profile: profile,
      favoriteIds: {},
      sessionExposureIds: {},
      now: now,
    );

    expect(
      asynchronous.map((result) => result.creator.id),
      synchronous.map((result) => result.creator.id),
    );
  });
}
