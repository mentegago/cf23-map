import 'dart:async';
import 'dart:convert';

import 'package:cf_map_flutter/services/map_data_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> snapshot(int version, {String booth = 'A-01'}) => {
      'version': version,
      'layout': {
        'schemaVersion': 2,
        'bounds': {'width': 500, 'height': 300},
        'features': [
          {
            'uid': 'booth',
            'id': booth,
            'kind': 'booth',
            'geometry': {
              'type': 'rect',
              'x': 10,
              'y': 20,
              'width': 30,
              'height': 40
            },
          }
        ],
      },
      'proximity': {
        'schema_version': 1,
        'map_sha256': 'map-$version',
        'booths': [booth],
        'neighbors': [[]],
      },
    };

class _Bundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final bundled = snapshot(1);
    final value = switch (key) {
      'data/map-version.json' => {'version': 1},
      'data/map.json' => bundled['layout'],
      'data/booth-proximity.json' => bundled['proximity'],
      _ => throw StateError(key),
    };
    return ByteData.sublistView(utf8.encode(jsonEncode(value)));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('bundled map stays visible until the complete remote snapshot arrives',
      () async {
    final download = Completer<http.Response>();
    final applied = Completer<void>();
    final service = MapDataService(
        bundle: _Bundle(),
        client: MockClient((request) async {
          if (request.url.path == '/manifest.json') {
            return http.Response(
                jsonEncode({
                  'map': {'version': 2, 'path': 'maps/next.json'}
                }),
                200);
          }
          return download.future;
        }));
    addTearDown(service.dispose);
    service.addListener(() {
      if (service.version == 2 && !applied.isCompleted) applied.complete();
    });
    await service.initialize();
    final original = service.layout;
    expect(service.version, 1);
    expect(service.proximity!.mapSha256, 'map-1');
    // A second check must share the in-flight download rather than start another.
    await service.checkForUpdates();
    expect(identical(service.layout, original), isTrue);
    download
        .complete(http.Response(jsonEncode(snapshot(2, booth: 'B-02')), 200));
    await applied.future;
    expect(service.layout!.features.single.content, 'B-02');
    expect(service.proximity!.mapSha256, 'map-2');
    // Wait for persistence after the visible update.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final offline =
        MapDataService(bundle: _Bundle(), enableRemoteUpdates: false);
    addTearDown(offline.dispose);
    await offline.initialize();
    expect(offline.version, 2);
    expect(offline.layout!.features.single.content, 'B-02');
  });

  test('ignores corrupt cache and cached data older than the bundle', () async {
    for (final raw in ['invalid json', jsonEncode(snapshot(0))]) {
      SharedPreferences.setMockInitialValues({'map_snapshot_v1': raw});
      final service =
          MapDataService(bundle: _Bundle(), enableRemoteUpdates: false);
      await service.initialize();
      expect(service.version, 1);
      service.dispose();
    }
  });

  test('offline, malformed and mismatched publications retain the usable map',
      () async {
    var body = 'not json';
    var status = 200;
    final firstCheck = Completer<void>();
    final service = MapDataService(
        bundle: _Bundle(),
        client: MockClient((request) async {
          if (request.url.path == '/manifest.json') {
            if (!firstCheck.isCompleted) firstCheck.complete();
            return http.Response(
                jsonEncode({
                  'map': {'version': 2, 'path': 'maps/next.json'}
                }),
                200);
          }
          return http.Response(body, status);
        }));
    addTearDown(service.dispose);
    await service.initialize();
    await firstCheck.future;
    // Finish the automatic check before exercising explicit retries.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final original = service.layout;
    for (final invalid in [
      snapshot(3),
      {...snapshot(2), 'proximity': {}},
      {
        ...snapshot(2),
        'layout': {'schemaVersion': 99}
      },
    ]) {
      body = jsonEncode(invalid);
      await service.checkForUpdates();
      expect(identical(service.layout, original), isTrue);
      expect(service.version, 1);
    }
    status = 503;
    await service.checkForUpdates();
    expect(identical(service.layout, original), isTrue);
    status = 200;
    body = jsonEncode(snapshot(2));
    await service.checkForUpdates();
    expect(service.version, 2);
  });

  test('unchanged versions do not download a snapshot', () async {
    var requests = 0;
    final checked = Completer<void>();
    final service = MapDataService(
        bundle: _Bundle(),
        client: MockClient((request) async {
          requests++;
          expect(request.url.path, '/manifest.json');
          checked.complete();
          return http.Response(
              jsonEncode({
                'map': {'version': 1, 'path': 'maps/current.json'}
              }),
              200);
        }));
    addTearDown(service.dispose);
    await service.initialize();
    await checked.future;
    expect(requests, 1);
  });
}
