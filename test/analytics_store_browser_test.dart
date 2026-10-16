@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:cf_map_flutter/services/analytics_store_web.dart';

void main() {
  test('IndexedDB survives new instances and atomically leases across senders',
      () async {
    final first = IndexedAnalyticsStore();
    final second = IndexedAnalyticsStore();
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = 'browser-$now';
    await first.put(
        id,
        {
          'payload': {
            'data': {'client_event_id': id, 'occurred_at_ms': now}
          }
        },
        now);
    expect((await second.pending(now)).any((e) => e['id'] == id), true);
    expect(await first.acquire('first', now), true);
    expect(await second.acquire('second', now), false);
    await first.release('first');
    expect(await second.acquire('second', now), true);
    await second.remove(id);
    await second.release('second');
    expect((await first.pending(now)).any((e) => e['id'] == id), false);
  });
}
