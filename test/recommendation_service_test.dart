import 'dart:async';

import 'package:cf_map_flutter/models/creator.dart';
import 'package:cf_map_flutter/models/recommendation.dart';
import 'package:cf_map_flutter/services/recommendation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Creator testCreator(int id) => Creator(
      id: id,
      userId: 'user-$id',
      name: 'Creator $id',
      booths: ['A-$id'],
      day: 'BOTH',
      fandoms: const ['Blue Archive'],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('map and random opens remain exposure-only', () async {
    final service = RecommendationService();
    await service.initialize();

    service.recordCreatorOpened(
      testCreator(1),
      CreatorSelectionSource.mapTap,
    );
    service.recordCreatorOpened(
      testCreator(2),
      CreatorSelectionSource.randomButton,
    );

    expect(service.profile.creatorInteractions, isEmpty);
  });

  test('direct creator deeplink contributes to the local profile', () async {
    final service = RecommendationService();
    await service.initialize();

    service.recordCreatorOpened(
      testCreator(1),
      CreatorSelectionSource.deepLink,
    );

    final interaction = service.profile.creatorInteractions[1];
    expect(interaction, isNotNull);
    expect(interaction!.openStrength, 2.5);
    expect(interaction.consideration, 0.3);

    service.recordCreatorOpened(
      testCreator(1),
      CreatorSelectionSource.deepLink,
    );
    expect(interaction.openStrength, 2.5);
  });

  test('meaningful engagement after map exposure is retained', () async {
    final service = RecommendationService();
    await service.initialize();
    final creator = testCreator(1);

    service.recordCreatorOpened(creator, CreatorSelectionSource.mapTap);
    service.recordSampleWorksViewed(creator);

    final interaction = service.profile.creatorInteractions[1];
    expect(interaction, isNotNull);
    expect(interaction!.sampleWorkViews, 1);
    expect(interaction.consideration, 0.5);
  });

  test('no profile data keeps the alphabetical-list fallback', () async {
    final service = RecommendationService(
      refreshDelay: const Duration(milliseconds: 20),
    );
    await service.initialize();
    final creators = [testCreator(1), testCreator(2), testCreator(3)];

    expect(
      service.recommendationsFor(
        creators: creators,
        favoriteIds: const {},
      ),
      isEmpty,
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(
      service.recommendationsFor(
        creators: creators,
        favoriteIds: const {},
      ),
      isEmpty,
    );
  });

  test('home fandoms put interests first and fill from popular fandoms',
      () async {
    final service = RecommendationService();
    await service.initialize();
    final creators = [
      testCreator(1),
      Creator(
        id: 2,
        userId: 'user-2',
        name: 'Creator 2',
        booths: const ['A-2'],
        day: 'BOTH',
        fandoms: const ['Hololive'],
      ),
    ];
    service.recordFandomInterest('Blue Archive');
    final popular = [
      'Hololive',
      'Blue Archive',
      ...List.generate(25, (index) => 'Popular $index'),
    ];

    final suggestions = service.homeFandomSuggestionsFor(
      creators: creators,
      favoriteIds: const {},
      popularFandoms: popular,
    );

    expect(suggestions, hasLength(20));
    expect(suggestions.first, 'Blue Archive');
    expect(
        suggestions.where((fandom) => fandom == 'Blue Archive'), hasLength(1));
    expect(suggestions[1], 'Hololive');
    service.dispose();
  });

  test('profile changes batch and refresh in the background', () async {
    final service = RecommendationService(
      refreshDelay: const Duration(milliseconds: 80),
    );
    await service.initialize();
    final creators = [testCreator(1), testCreator(2), testCreator(3)];
    expect(
      service.recommendationsFor(
        creators: creators,
        favoriteIds: const {},
      ),
      isEmpty,
    );

    var notifications = 0;
    final completer = Completer<void>();
    service.addListener(() {
      notifications++;
      if (!completer.isCompleted) completer.complete();
    });

    service.recordFandomInterest('Blue Archive');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    service.recordFandomInterest('Hololive');

    final immediate = service.recommendationsFor(
      creators: creators,
      favoriteIds: const {},
    );
    expect(immediate, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(notifications, 0);

    await completer.future.timeout(const Duration(seconds: 5));
    final published = service.recommendationsFor(
      creators: creators,
      favoriteIds: const {},
    );
    expect(published, isNotEmpty);

    service.recordFandomInterest('Touhou');
    expect(
      service.recommendationsFor(
          creators: creators,
          favoriteIds: const {}).map((result) => result.creator.id),
      published.map((result) => result.creator.id),
    );
    service.dispose();
  });

  test('disabled service skips profiling and recommendation work', () async {
    final service = RecommendationService(disabled: true);
    await service.initialize();
    final creator = testCreator(1);

    service.recordCreatorOpened(creator, CreatorSelectionSource.deepLink);
    service.recordFandomInterest('Blue Archive');
    service.recordSampleWorksViewed(creator);
    service.recordExternalLinkOpened(creator);
    service.recordCreatorShared(creator);
    service.recordFavoriteChanged(creator, true);

    expect(service.isInitialized, isTrue);
    expect(service.profile.creatorInteractions, isEmpty);
    expect(service.profile.explicitFandomSignals, isEmpty);
    expect(
      service.recommendationsFor(
        creators: [creator],
        favoriteIds: const {},
      ),
      isEmpty,
    );
  });
}
