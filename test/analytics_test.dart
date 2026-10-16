import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cf_map_flutter/services/analytics_service.dart';
import 'package:cf_map_flutter/services/analytics_delivery.dart';

class RecordingAnalyticsSink implements AnalyticsSink {
  final events = <Map<String, dynamic>>[];
  @override
  void add(Map<String, dynamic> event) => events.add(event);
  @override
  Future<void> flush() async {}
  @override
  Future<void> dispose() async {}
  List<Map> named(String name) => events
      .map((e) => e['payload'] as Map)
      .where((p) => p['name'] == name)
      .toList();
}

void main() {
  test(
      'disabled collection sends nothing; startup sends one canonical pageview',
      () {
    final sink = RecordingAnalyticsSink();
    final disabled = AnalyticsService(enabled: false, sink: sink)
      ..start()
      ..activity();
    disabled.creatorOpened(1, SelectionSource.map);
    expect(sink.events, isEmpty);
    AnalyticsService(enabled: true, sink: sink)
      ..start()
      ..start();
    expect(sink.events, hasLength(1));
    expect(
        sink.events.single['payload'], {'url': '/', 'title': 'CF23 Booth Map'});
  });
  test(
      'activity uses visible UTC minute boundaries, stable run IDs and increasing sequences',
      () {
    var now = DateTime.utc(2026, 10, 31, 4);
    var visible = true;
    final sink = RecordingAnalyticsSink();
    final service = AnalyticsService(
        enabled: true,
        sink: sink,
        clock: () => now,
        visible: () => visible,
        runId: 'test');
    service.activity();
    service.activity();
    visible = false;
    now = now.add(const Duration(minutes: 1));
    service.activity();
    visible = true;
    service.activity();
    final events = sink.named('active_minute');
    expect(events, hasLength(2));
    expect(events.map((p) => (p['data'] as Map)['sequence']), [1, 2]);
    expect(
        events.map((p) => (p['data'] as Map)['app_run_id']).toSet(), {'test'});
    expect(events.map((p) => (p['data'] as Map)['client_event_id']).toSet(),
        hasLength(2));
  });
  test('creator lifetimes deduplicate and distinguish replacement', () {
    var now = DateTime.utc(2026);
    final sink = RecordingAnalyticsSink();
    final a = AnalyticsService(enabled: true, sink: sink, clock: () => now);
    a.creatorOpened(1, SelectionSource.map);
    a.creatorOpened(1, SelectionSource.map);
    now = now.add(const Duration(seconds: 2));
    a.creatorOpened(2, SelectionSource.random);
    a.creatorClosed();
    expect(sink.named('creator_opened'), hasLength(2));
    final close = sink.named('creator_closed').first['data'] as Map;
    expect(close['duration_ms'], 2000);
    expect(close['reason'], 'replaced');
  });
  test('invalid search attribution is rejected', () {
    final a = AnalyticsService(enabled: true, sink: RecordingAnalyticsSink());
    expect(
        () => a.search(
            id: 'id',
            source: SearchSource.typed,
            trigger: SearchTrigger.settled,
            resolution: SearchResolution.unresolved,
            fandomId: 2,
            results: 0,
            catalogResults: 0,
            scope: ListScope.fullCatalog),
        throwsArgumentError);
  });
  test(
      'retry retains ID/time, reuses native cache token, and drops permanent errors',
      () async {
    var attempts = 0;
    final requests = <http.Request>[];
    final store = MemoryAnalyticsStore();
    final delivery = AnalyticsDelivery(
        endpoint: Uri.parse('https://example.invalid/api/send'),
        website: 'website',
        hostname: 'example.invalid',
        metadata: () => {'language': 'en', 'screen': '800x600'},
        store: store,
        autoFlush: false,
        client: MockClient((r) async {
          requests.add(r);
          attempts++;
          if (attempts == 1) return http.Response('failure', 503);
          if (attempts == 2) {
            return http.Response('{"cache":"native-token"}', 200);
          }
          return http.Response('invalid', 400);
        }));
    delivery.add({
      'type': 'event',
      'payload': {
        'url': '/',
        'name': 'search_performed',
        'data': {'client_event_id': 'stable', 'occurred_at_ms': 123}
      }
    });
    await delivery.flush();
    expect(store.records, hasLength(1));
    await delivery.flush();
    expect(store.records, isEmpty);
    expect(jsonDecode(requests[0].body), jsonDecode(requests[1].body));
    delivery.add({
      'type': 'event',
      'payload': {
        'url': '/',
        'name': 'active_minute',
        'data': {'client_event_id': 'other'}
      }
    });
    await delivery.flush();
    expect(store.records, isEmpty);
    expect(requests.last.headers['x-umami-cache'], 'native-token');
    expect(requests.first.headers.containsKey('user-agent'), false);
    await delivery.dispose();
  });
  test('memory fallback queue enforces expiry, capacity, and leases', () async {
    final store = MemoryAnalyticsStore();
    for (var i = 0; i < 2001; i++) {
      await store.put('$i', {}, i);
    }
    expect(store.records, hasLength(2000));
    expect(store.records.containsKey('0'), false);
    expect(await store.acquire('a', 0), true);
    expect(await store.acquire('b', 1), false);
    await store.release('b');
    expect(await store.acquire('b', 2), false);
    expect(await store.acquire('b', 15001), true);
    expect(await store.pending(259202001), isEmpty);
  });
  test('storage failure falls back without blocking delivery', () async {
    final delivery = AnalyticsDelivery(
        endpoint: Uri.parse('https://example.invalid/api/send'),
        website: 'w',
        hostname: 'h',
        metadata: () => {},
        store: BrokenStore(),
        autoFlush: false,
        client: MockClient((_) async => http.Response('{}', 200)));
    delivery.add({
      'type': 'event',
      'payload': {
        'url': '/',
        'data': {'client_event_id': '1'}
      }
    });
    await delivery.flush();
    expect(delivery.store, isA<MemoryAnalyticsStore>());
    await delivery.dispose();
  });
  test(
      'same-millisecond events preserve within-run sequence rather than random ID order',
      () async {
    final store = MemoryAnalyticsStore();
    Map<String, dynamic> event(int seq) => {
          'payload': {
            'data': {'app_run_id': 'run', 'sequence': seq}
          }
        };
    await store.put('a', event(2), 100);
    await store.put('z', event(1), 100);
    expect((await store.pending(100)).map((r) => r['id']), ['z', 'a']);
    await store.put(
        'm',
        {
          'payload': {
            'data': {'app_run_id': 'other', 'sequence': 1}
          }
        },
        100);
    expect((await store.pending(100)).map((r) => r['id']), ['m', 'z', 'a']);
  });
}

class BrokenStore extends MemoryAnalyticsStore {
  @override
  Future<void> put(String id, Map<String, dynamic> event, int now) async {
    throw StateError('unavailable');
  }
}
