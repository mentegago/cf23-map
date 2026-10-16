import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:cf_map_flutter/models/creator.dart';
import 'package:cf_map_flutter/models/fandom.dart';
import 'package:cf_map_flutter/services/analytics_service.dart';
import 'package:cf_map_flutter/services/creator_data_service.dart';
import 'package:cf_map_flutter/services/search_tracking_controller.dart';
import 'analytics_test.dart' show RecordingAnalyticsSink;

class TestCatalog extends CreatorDataProvider {
  TestCatalog() : super(enableRemoteUpdates: false);
  @override
  bool get isLoading => false;
  @override
  Map<int, Fandom> get fandomById => {
        5: Fandom(id: 5, name: '東方', kind: 'work', parentId: null),
        1: Fandom(
            id: 1,
            name: 'Blue Archive',
            kind: 'work',
            parentId: null,
            alternateNames: ['BA']),
        2: Fandom(id: 2, name: 'No Sellers', kind: 'work', parentId: null),
        3: Fandom(
            id: 3,
            name: 'Other',
            kind: 'work',
            parentId: null,
            alternateNames: ['collision']),
        4: Fandom(
            id: 4,
            name: 'Another',
            kind: 'work',
            parentId: null,
            alternateNames: ['collision']),
      };
  @override
  List<Creator> get allCreators => [
        Creator(
            id: 10,
            name: 'Circle',
            spaces: [const CreatorSpace(code: 'A-01')],
            attendanceDates: [])
      ];
  @override
  Creator? getCreatorById(int id) =>
      allCreators.where((c) => c.id == id).firstOrNull;
  @override
  List<Creator> searchCreators(String query) =>
      analyticsScope == ListScope.fullCatalog ? searchAllCreators(query) : [];
  @override
  List<Creator> searchAllCreators(String query) =>
      query.toLowerCase() == 'blue archive' ? allCreators : [];
}

void main() {
  testWidgets(
      'settled typing, submit and result emit once; edits start a new attempt',
      (tester) async {
    final sink = RecordingAnalyticsSink();
    final catalog = TestCatalog();
    final tracking = SearchTrackingController(
        AnalyticsService(enabled: true, sink: sink), catalog);
    tracking.changed('Blue');
    await tester.pump(const Duration(milliseconds: 500));
    tracking.changed('Blue Archive');
    await tester.pump(const Duration(milliseconds: 999));
    expect(sink.named('search_performed'), isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    final id = tracking.submit('Blue Archive');
    expect(tracking.result('Blue Archive'), id);
    expect(sink.named('search_performed'), hasLength(1));
    tracking.changed('No Sellers');
    await tester.pump(const Duration(seconds: 1));
    expect(sink.named('search_performed'), hasLength(2));
    final data = sink.named('search_performed').last['data'] as Map;
    expect(data['fandom_id'], 2);
    expect(data['catalog_result_count'], 0);
    tracking.dispose();
    catalog.dispose();
  });
  test(
      'aliases, collisions, unknown text, links and scope are classified without retaining queries',
      () {
    final sink = RecordingAnalyticsSink();
    final catalog = TestCatalog();
    final tracking = SearchTrackingController(
        AnalyticsService(enabled: true, sink: sink), catalog);
    tracking.submit('BA');
    tracking.submit('collision');
    tracking.submit('private arbitrary text');
    tracking.submit('Circle');
    tracking.submit('https://example.org/?list=abc');
    expect(
        sink
            .named('search_performed')
            .map((e) => (e['data'] as Map)['resolution']),
        ['alias', 'ambiguous', 'unresolved', 'creator']);
    expect(jsonEncode(sink.events), isNot(contains('private arbitrary text')));
    expect(jsonEncode(sink.events), isNot(contains('query')));
    tracking.select(1, SearchSource.suggestion);
    catalog.analyticsScope = ListScope.sharedList;
    tracking.submit('Blue Archive');
    expect(
        (sink.named('search_performed').last['data']
            as Map)['catalog_result_count'],
        1);
    expect((sink.named('search_performed').last['data'] as Map)['result_count'],
        0);
    tracking.dispose();
    catalog.dispose();
  });

  test(
      'non-Latin registry names resolve without collapsing into empty ASCII keys',
      () {
    final sink = RecordingAnalyticsSink();
    final catalog = TestCatalog();
    final tracking = SearchTrackingController(
        AnalyticsService(enabled: true, sink: sink), catalog);
    tracking.submit('東方');
    tracking.submit('別の名前');
    final searches = sink.named('search_performed');
    expect((searches.first['data'] as Map)['fandom_id'], 5);
    expect((searches.last['data'] as Map)['resolution'], 'unresolved');
    expect(jsonEncode(sink.events), isNot(contains('別の名前')));
    tracking.dispose();
    catalog.dispose();
  });
}
