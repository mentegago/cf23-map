import 'dart:convert';
import 'dart:io';

import 'package:cf_map_flutter/design_system/cf_design_system.dart';
import 'package:cf_map_flutter/models/creator.dart';
import 'package:cf_map_flutter/models/fandom.dart';
import 'package:cf_map_flutter/services/analytics_service.dart';
import 'package:cf_map_flutter/services/catalog_snapshot_cache.dart';
import 'package:cf_map_flutter/services/creator_catalog_index.dart';
import 'package:cf_map_flutter/services/creator_data_service.dart';
import 'package:cf_map_flutter/services/favorites_service.dart';
import 'package:cf_map_flutter/services/recommendation_service.dart';
import 'package:cf_map_flutter/services/search_tracking_controller.dart';
import 'package:cf_map_flutter/widgets/desktop/desktop_sidebar.dart';
import 'package:cf_map_flutter/widgets/mobile/expandable_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _fandoms = [
  Fandom(id: 1, name: 'Pretty Cure', kind: 'franchise', parentId: null),
  Fandom(id: 2, name: 'Star Detective Precure', kind: 'work', parentId: 1),
  Fandom(id: 3, name: 'Smile Precure', kind: 'work', parentId: 1),
  Fandom(id: 4, name: 'IVE', kind: 'individual', parentId: null),
  Fandom(id: 5, name: 'Star', kind: 'work', parentId: null),
  Fandom(id: 6, name: 'SPC', kind: 'work', parentId: null),
  Fandom(
      id: 7,
      name: 'AoT',
      kind: 'work',
      parentId: null,
      alternateNames: ['Attack on Titan', 'Shingeki no Kyojin']),
  Fandom(id: 8, name: 'Blue Archive', kind: 'work', parentId: null),
  Fandom(id: 9, name: 'Bizarre', kind: 'work', parentId: null),
  Fandom(id: 10, name: 'Unused Child', kind: 'work', parentId: 1),
  Fandom(id: 11, name: 'Detective Extras', kind: 'work', parentId: 2),
];

final _creators = [
  for (final fandom in _fandoms.where((f) => f.id != 10))
    Creator(
        id: fandom.id,
        name: 'Artist ${fandom.id}',
        spaces: [CreatorSpace(code: 'Q-${fandom.id}')],
        attendanceDates: ['2026-10-31'],
        fandoms: [fandom]),
  Creator(
      id: 12,
      name: 'Pretty Cure Studio',
      spaces: [],
      attendanceDates: [],
      fandoms: [_fandoms[3]]),
];

CreatorCatalogIndex _index() => CreatorCatalogIndex.build(
    _creators, {for (final fandom in _fandoms) fandom.id: fandom});

Future<CreatorDataProvider> _catalog() async {
  SharedPreferences.setMockInitialValues({
    CatalogSnapshotCache.prefsSnapshotKey: jsonEncode({
      'version': 999999999,
      'catalog': {
        'schemaVersion': '1.0.0',
        'event': {'days': []},
        'exhibitors': [
          for (final c in _creators)
            {
              'id': c.id,
              'name': c.name,
              'fandomIds': c.fandomIds,
              'spaces': [
                for (final space in c.spaces) {'code': space.code}
              ],
              'attendanceDates': c.attendanceDates,
            }
        ],
      },
      'fandomRegistry': {
        'schemaVersion': '1.0.0',
        'fandoms': [
          for (final f in _fandoms)
            {
              'id': f.id,
              'name': f.name,
              'parentId': f.parentId,
              'kind': f.kind,
              'alternateNames': f.alternateNames,
            },
        ]
      },
    }),
  });
  final catalog = CreatorDataProvider(enableRemoteUpdates: false);
  await catalog.initialize();
  expect(catalog.error, isNull);
  expect(catalog.catalogSource, 'cache');
  return catalog;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('long queries exclude reverse substring and subsequence fandoms', () {
    final index = _index();
    expect(index.fandomSuggestions('Star Detective Precure'),
        ['Star Detective Precure', 'Detective Extras']);
    expect(index.search('Star Detective Precure').map((c) => c.id),
        unorderedEquals([2, 11]));
    expect(index.search('Star Detective Precure', fandomId: 999), isEmpty);
  });

  test('aliases, word prefixes, acronyms and longer fuzzy queries survive', () {
    final index = _index();
    for (final query in ['Attack on Titan', 'AoT', 'shingeki']) {
      expect(index.fandomSuggestions(query).first, 'AoT');
      expect(index.search(query).map((c) => c.id), contains(7));
    }
    expect(index.fandomSuggestions('BA'), ['Blue Archive']);
    expect(index.fandomSuggestions('blu arc'), ['Blue Archive']);
    expect(index.fandomSuggestions('lue'), isNot(contains('Blue Archive')));
    expect(index.fandomSuggestions('BlArch'), contains('Blue Archive'));
    expect(index.search('Q-02').first.id, 2);
  });

  test('hierarchy chips include represented descendants once, parent first',
      () {
    final index = _index();
    expect(index.fandomSuggestions('Pretty Cure'), [
      'Pretty Cure',
      'Smile Precure',
      'Star Detective Precure',
      'Detective Extras'
    ]);
    final chips = index.fandomSuggestions('Precure');
    expect(chips.toSet().length, chips.length);
    expect(index.fandomNamesForId(2),
        ['Star Detective Precure', 'Detective Extras']);
    expect(chips, isNot(contains('Unused Child')));
    expect(index.matchingFandomNames('Pretty Cure'),
        index.fandomSuggestions('Pretty Cure'));
  });

  test('selected IDs narrow both scopes and edits permanently clear selection',
      () async {
    final catalog = await _catalog();
    addTearDown(catalog.dispose);
    expect(
        catalog.searchCreators('Pretty Cure').map((c) => c.id), contains(12));
    catalog.selectFandomSearch(1);
    expect(catalog.searchCreators('Pretty Cure').map((c) => c.id),
        unorderedEquals([1, 2, 3, 11]));
    catalog.updateSearchQuery('Pretty Cure');
    expect(catalog.selectedFandomIdForQuery('Pretty Cure'), 1);
    catalog.setCreatorCustomList([2, 12]);
    expect(catalog.searchCreators('Pretty Cure').map((c) => c.id), [2]);
    expect(catalog.searchAllCreators('Pretty Cure').map((c) => c.id),
        unorderedEquals([1, 2, 3, 11]));
    expect(catalog.fandomSuggestions('Pretty Cure'),
        ['Pretty Cure', 'Star Detective Precure']);
    catalog.updateSearchQuery('Pretty Cure ');
    catalog.updateSearchQuery('Pretty Cure');
    expect(catalog.selectedFandomIdForQuery('Pretty Cure'), isNull);
    expect(
        catalog.searchCreators('Pretty Cure').map((c) => c.id), contains(12));
  });

  test('bundled catalog reproduces screenshot without unrelated fandoms', () {
    final registry =
        jsonDecode(File('data/fandoms-initial.json').readAsStringSync()) as Map;
    final fandoms = {
      for (final raw in registry['fandoms'] as List)
        (raw['id'] as num).toInt():
            Fandom.fromJson(Map<String, dynamic>.from(raw))
    };
    final catalog =
        jsonDecode(File('data/catalog-initial.json').readAsStringSync()) as Map;
    final creators = [
      for (final raw in catalog['exhibitors'] as List)
        Creator.fromCatalogJson(Map<String, dynamic>.from(raw),
            fandomById: fandoms, dayLabels: const {})
    ];
    final index = CreatorCatalogIndex.build(creators, fandoms);
    expect(index.fandomSuggestions('Star Detective Precure'),
        ['Star Detective Precure']);
    expect(index.search('Star Detective Precure'), isNotEmpty);
    expect(
        index
            .search('Star Detective Precure')
            .every((c) => c.fandomNames.contains('Star Detective Precure')),
        isTrue);
    expect(index.fandomSuggestions('AOT').first, 'Attack on Titan');
    expect(index.search('AOT').map((c) => c.id).toSet(),
        containsAll(index.search('Attack on Titan').map((c) => c.id)));
  });

  for (final mobile in [false, true]) {
    testWidgets(
        '${mobile ? 'mobile' : 'desktop'} chip selection, narrowing, cursor and edits',
        (tester) async {
      tester.view.physicalSize = const Size(1100, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final catalog = (await tester.runAsync(_catalog))!;
      final analytics = AnalyticsService(enabled: false);
      final tracking = SearchTrackingController(analytics, catalog);
      final favorites = FavoritesService(catalog);
      await favorites.initialize();
      final recommendations = RecommendationService(disabled: true);
      await recommendations.initialize();
      await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: catalog),
            Provider.value(value: analytics),
            Provider.value(value: tracking),
            ChangeNotifierProvider.value(value: favorites),
            ChangeNotifierProvider.value(value: recommendations),
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
      final field = find.byType(TextField);
      await tester.tap(field);
      await tester.enterText(field, 'Pretty Cure');
      await tester.pumpAndSettle();
      Finder chip(String label) => find.byWidgetPredicate(
          (widget) => widget is CfTag && widget.label == label);
      expect(chip('Star Detective Precure'), findsOneWidget);
      await tester.tap(chip('Pretty Cure'));
      await tester.pumpAndSettle();
      expect(catalog.selectedFandomIdForQuery('Pretty Cure'), 1);
      expect(find.text('4 results'), findsOneWidget);
      await tester.ensureVisible(chip('Star Detective Precure'));
      await tester.tap(chip('Star Detective Precure'));
      await tester.pumpAndSettle();
      expect(catalog.selectedFandomIdForQuery('Star Detective Precure'), 2);
      expect(chip('Detective Extras'), findsOneWidget);
      expect(find.text('2 results'), findsOneWidget);
      final controller = tester.widget<TextField>(field).controller!;
      controller.selection = const TextSelection.collapsed(offset: 3);
      await tester.pump();
      expect(catalog.selectedFandomIdForQuery(controller.text), 2);
      await tester.enterText(field, 'Pretty Cure');
      await tester.pumpAndSettle();
      expect(catalog.selectedFandomIdForQuery('Pretty Cure'), isNull);
      expect(find.text('5 results'), findsOneWidget);
      await tester.enterText(field, '');
      await tester.pumpAndSettle();
      expect(catalog.selectedFandomIdForQuery('Pretty Cure'), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      tracking.dispose();
      favorites.dispose();
      recommendations.dispose();
      catalog.dispose();
      analytics.dispose();
    });
  }
}
