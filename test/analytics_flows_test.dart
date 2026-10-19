import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cf_map_flutter/services/analytics_service.dart';
import 'package:cf_map_flutter/services/creator_data_service.dart';
import 'package:cf_map_flutter/services/favorites_service.dart';
import 'package:cf_map_flutter/services/recommendation_service.dart';
import 'package:cf_map_flutter/services/search_tracking_controller.dart';
import 'package:cf_map_flutter/services/deep_link_handler.dart';
import 'package:cf_map_flutter/widgets/desktop/desktop_sidebar.dart';
import 'package:cf_map_flutter/widgets/creator_detail_content.dart';
import 'package:cf_map_flutter/widgets/mobile/expandable_search.dart';
import 'analytics_test.dart' show RecordingAnalyticsSink;
import 'search_tracking_test.dart' show TestCatalog;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'loaded catalog automatically supplies creator and fandom display labels',
      () async {
    SharedPreferences.setMockInitialValues({});
    final sink = RecordingAnalyticsSink();
    final analytics = AnalyticsService(enabled: true, sink: sink);
    final catalog =
        CreatorDataProvider(enableRemoteUpdates: false, analytics: analytics);
    addTearDown(catalog.dispose);
    await catalog.initialize();
    final creator = catalog.allCreators.first;
    final fandom = catalog.fandomById.values.first;
    catalog.setSelectedCreator(creator);
    analytics.search(
        id: analyticsId(),
        source: SearchSource.typed,
        trigger: SearchTrigger.submitted,
        resolution: SearchResolution.canonical,
        fandomId: fandom.id,
        results: 0,
        catalogResults: 0,
        scope: ListScope.fullCatalog);
    expect((sink.named('creator_opened').single['data'] as Map)['creator_name'],
        creator.name);
    expect(
        (sink.named('search_performed').single['data'] as Map)['fandom_name'],
        fandom.name);
    expect(
        (sink.named('creator_opened').single['data'] as Map)['catalog_version'],
        catalog.currentDataVersion);
  });
  test(
      'bookmark membership and bulk summaries exclude restored, duplicate and invalid IDs',
      () async {
    SharedPreferences.setMockInitialValues({
      'favorite_creator_ids': ['10']
    });
    final sink = RecordingAnalyticsSink();
    final analytics = AnalyticsService(enabled: true, sink: sink);
    final catalog = TestCatalog();
    final favorites = FavoritesService(catalog, analytics: analytics);
    await favorites.initialize();
    expect(sink.events, isEmpty);
    favorites.addFavorite(10);
    favorites.addFavorite(-1);
    expect(sink.events, isEmpty);
    favorites.removeFavorite(10);
    favorites.removeFavorite(10);
    final result = favorites.addAllFavorites([10, 10, -1]);
    expect(result, (added: 1, skipped: 1, failed: 1));
    expect(sink.named('bookmark_changed'), hasLength(2));
    final summary = sink.named('favorites_action').single['data'] as Map;
    final add = sink.named('bookmark_changed').last['data'] as Map;
    expect(summary['success'], false);
    expect(summary['operation_id'], add['operation_id']);
    favorites.dispose();
    catalog.dispose();
  });
  test('link imports emit bounded outcomes without leaking supplied text', () {
    final sink = RecordingAnalyticsSink();
    final analytics = AnalyticsService(enabled: true, sink: sink);
    final catalog = TestCatalog();
    var selected = 0;
    expect(
        applyDeepLink('https://private.example/?creator_id=10&source=secret',
            catalog, analytics, (_) => selected++),
        true);
    expect(selected, 1);
    applyDeepLink(
        'https://private.example/?creator_id=999', catalog, analytics, (_) {});
    expect(sink.named('deeplink_processed'), hasLength(2));
    expect(sink.named('operation_failed'), hasLength(1));
    expect(jsonEncode(sink.events), isNot(contains('private.example')));
    expect(jsonEncode(sink.events), isNot(contains('secret')));
    catalog.dispose();
  });
  for (final mobile in [false, true]) {
    testWidgets(
        '${mobile ? 'mobile' : 'desktop'} typing and submission share one search revision',
        (tester) async {
      tester.view.physicalSize = const Size(1100, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final sink = RecordingAnalyticsSink();
      final analytics = AnalyticsService(enabled: true, sink: sink);
      final catalog = TestCatalog();
      final tracking = SearchTrackingController(analytics, catalog);
      final favorites = FavoritesService(catalog, analytics: analytics);
      await favorites.initialize();
      final recommendations = RecommendationService(disabled: true);
      await recommendations.initialize();
      await tester.pumpWidget(MultiProvider(
          providers: [
            Provider<AnalyticsService>.value(value: analytics),
            Provider<SearchTrackingController>.value(value: tracking),
            ChangeNotifierProvider<CreatorDataProvider>.value(value: catalog),
            ChangeNotifierProvider<FavoritesService>.value(value: favorites),
            ChangeNotifierProvider<RecommendationService>.value(
                value: recommendations)
          ],
          child: MaterialApp(
              home: Scaffold(
                  body: mobile
                      ? ExpandableSearch(
                          creators: catalog.allCreators,
                          onCreatorSelected: (_,
                              {required source, searchQuery = ''}) {})
                      : DesktopSidebar(
                          creators: catalog.allCreators,
                          onCreatorSelected: (_,
                              {required source, searchQuery = ''}) {})))));
      await tester.enterText(find.byType(TextField), 'Blue Archive');
      await tester.pump(const Duration(milliseconds: 999));
      expect(sink.named('search_performed'), isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(sink.named('search_performed'), hasLength(1));
      expect(
          (sink.named('search_performed').single['data'] as Map)['fandom_id'],
          1);
      await tester.pumpWidget(const SizedBox());
      tracking.dispose();
      favorites.dispose();
      recommendations.dispose();
      catalog.dispose();
    });
  }
  for (final initiallySelected in [true, false]) {
    testWidgets(
        'desktop shows details for a creator selected ${initiallySelected ? 'before' : 'after'} mounting',
        (tester) async {
      tester.view.physicalSize = const Size(1100, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final analytics = AnalyticsService(enabled: false);
      final catalog = TestCatalog();
      final tracking = SearchTrackingController(analytics, catalog);
      final favorites = FavoritesService(catalog, analytics: analytics);
      await favorites.initialize();
      final recommendations = RecommendationService(disabled: true);
      await recommendations.initialize();
      addTearDown(analytics.dispose);
      addTearDown(catalog.dispose);
      addTearDown(tracking.dispose);
      addTearDown(favorites.dispose);
      addTearDown(recommendations.dispose);
      void selectCreator() => applyDeepLink(
          'https://cf23.nnt.gg/?creator_id=10',
          catalog,
          analytics,
          (creator) => catalog.setSelectedCreator(creator),
          initial: true);
      if (initiallySelected) selectCreator();
      await tester.pumpWidget(MultiProvider(
        providers: [
          Provider.value(value: analytics),
          Provider.value(value: tracking),
          ChangeNotifierProvider<CreatorDataProvider>.value(value: catalog),
          ChangeNotifierProvider.value(value: favorites),
          ChangeNotifierProvider.value(value: recommendations),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer<CreatorDataProvider>(
              builder: (context, provider, _) => DesktopSidebar(
                creators: catalog.allCreators,
                selectedCreator: provider.selectedCreator,
                onCreatorSelected: (_, {required source, searchQuery = ''}) {},
              ),
            ),
          ),
        ),
      ));
      if (!initiallySelected) selectCreator();
      await tester.pumpAndSettle();
      expect(find.byType(CreatorDetailContent), findsOneWidget);
      // Opening search should still return to the directory.
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.byType(CreatorDetailContent), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  test(
      'machine contract covers every enum event, has closed fields and required common metadata',
      () {
    final schema = jsonDecode(File('test/fixtures/analytics_event_schema.json')
        .readAsStringSync()) as Map;
    final variants = schema['oneOf'] as List;
    expect(variants.map((v) => v['properties']['name']['const']).toSet(),
        AnalyticsEvent.values.map(analyticsName).toSet());
    for (final variant in variants) {
      final data = variant['properties']['data'];
      expect(data['additionalProperties'], false);
      expect(
          data['required'],
          containsAll(
              ['client_event_id', 'occurred_at_ms', 'app_run_id', 'sequence']));
      expect((data['properties'] as Map).keys, isNot(contains('query')));
    }
  });
  test(
      'all typed methods produce contract-valid fields, primitive types and enum values',
      () {
    final sink = RecordingAnalyticsSink();
    final a = AnalyticsService(enabled: true, sink: sink)
      ..updateCatalog(29,
          creatorNames: {10: 'Circle'}, fandomNames: {1: 'Blue Archive'});
    a.searchOpened();
    a.searchCleared();
    a.searchClosed();
    a.search(
        id: analyticsId(),
        source: SearchSource.typed,
        trigger: SearchTrigger.settled,
        resolution: SearchResolution.canonical,
        fandomId: 1,
        results: 2,
        catalogResults: 2,
        scope: ListScope.fullCatalog);
    a.creatorOpened(10, SelectionSource.map);
    a.creatorClosed();
    a.bookmark(10, true);
    a.mapInteracted(pan: true, zoom: false);
    a.boothSelected(1);
    a.scopeChanged(ListScope.sharedList, 2);
    a.sheetState('expanded', user: true);
    a.creatorAction(CreatorAction.share, creatorId: 10);
    a.gallery(GalleryAction.open, 10, count: 2);
    a.favorites(FavoritesAction.copyBooths, success: true, count: 2);
    a.deeplink('list', true, count: 2);
    a.update(UpdateAction.shown);
    a.ready(100, 'cache');
    a.failure(Operation.clipboard, FailureCode.unavailable);
    final schema = jsonDecode(File('test/fixtures/analytics_event_schema.json')
        .readAsStringSync()) as Map;
    final variants = schema['oneOf'] as List;
    for (final event in sink.events) {
      final payload = event['payload'] as Map;
      final definition = variants.singleWhere((v) =>
              v['properties']['name']['const'] == payload['name'])['properties']
          ['data'];
      final properties = definition['properties'] as Map;
      final data = payload['data'] as Map;
      expect(data.keys, containsAll(definition['required'] as List));
      for (final entry in data.entries) {
        expect(properties.containsKey(entry.key), true,
            reason: '${payload['name']}.${entry.key}');
        final rule = properties[entry.key] as Map;
        if (rule.containsKey('enum')) {
          expect(rule['enum'], contains(entry.value));
        }
        if (rule.containsKey('const')) expect(entry.value, rule['const']);
        if (rule['type'] == 'integer') expect(entry.value, isA<int>());
        if (rule['type'] == 'boolean') expect(entry.value, isA<bool>());
        if (rule['type'] == 'string') expect(entry.value, isA<String>());
        if (rule.containsKey('pattern')) {
          expect(
              RegExp(rule['pattern'] as String).hasMatch(entry.value as String),
              true);
        }
      }
    }
    expect(sink.events.map((e) => e['payload']['name']).toSet(),
        AnalyticsEvent.values.map(analyticsName).toSet());
  });
}
