import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

abstract class AnalyticsSink {
  void add(Map<String, dynamic> event);
  Future<void> flush();
  Future<void> dispose();
}

abstract class AnalyticsStore {
  Future<void> put(String id, Map<String, dynamic> event, int now);
  Future<List<Map<String, dynamic>>> pending(int now);
  Future<void> remove(String id);
  Future<bool> acquire(String owner, int now);
  Future<void> release(String owner);
}

int analyticsRecordOrder(Map<String, dynamic> a, Map<String, dynamic> b) {
  final time = (a['created'] as int).compareTo(b['created'] as int);
  if (time != 0) return time;
  final left = (a['event'] as Map)['payload'] as Map;
  final right = (b['event'] as Map)['payload'] as Map;
  final ld = left['data'] as Map?;
  final rd = right['data'] as Map?;
  if (ld == null && rd != null) return -1;
  if (rd == null && ld != null) return 1;
  final run = ((ld?['app_run_id'] as String?) ?? '')
      .compareTo((rd?['app_run_id'] as String?) ?? '');
  if (run != 0) return run;
  if (ld?['sequence'] is int && rd?['sequence'] is int) {
    final sequence = (ld!['sequence'] as int).compareTo(rd!['sequence'] as int);
    if (sequence != 0) return sequence;
  }
  return (a['id'] as String).compareTo(b['id'] as String);
}

class MemoryAnalyticsStore implements AnalyticsStore {
  final Map<String, Map<String, dynamic>> records = {};
  String? _owner;
  int _until = 0;
  @override
  Future<void> put(String id, Map<String, dynamic> event, int now) async {
    records[id] = {'id': id, 'created': now, 'event': event};
    while (records.length > 2000) {
      records.remove(records.keys.first);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> pending(int now) async {
    records
        .removeWhere((_, value) => now - (value['created'] as int) > 259200000);
    return records.values.toList()..sort(analyticsRecordOrder);
  }

  @override
  Future<void> remove(String id) async {
    records.remove(id);
  }

  @override
  Future<bool> acquire(String owner, int now) async {
    if (_owner != null && _owner != owner && _until > now) return false;
    _owner = owner;
    _until = now + 15000;
    return true;
  }

  @override
  Future<void> release(String owner) async {
    if (_owner == owner) _owner = null;
  }
}

class AnalyticsDelivery implements AnalyticsSink {
  AnalyticsDelivery(
      {required this.endpoint,
      required this.website,
      required this.hostname,
      required this.metadata,
      required this.store,
      http.Client? client,
      this.reconnect,
      DateTime Function()? clock,
      this.autoFlush = true})
      : client = client ?? http.Client(),
        clock = clock ?? DateTime.now {
    _subscription = reconnect?.listen((_) {
      _notBefore = null;
      _schedule(Duration.zero);
    });
    if (autoFlush) _schedule(Duration.zero);
  }
  final Uri endpoint;
  final String website, hostname;
  final Map<String, Object> Function() metadata;
  AnalyticsStore store;
  final http.Client client;
  final Stream<void>? reconnect;
  final DateTime Function() clock;
  final bool autoFlush;
  final _fallback = MemoryAnalyticsStore();
  final _owner =
      '${DateTime.now().microsecondsSinceEpoch}-${Random().nextDouble()}';
  Future<void> _writes = Future.value();
  Future<void>? _flushing;
  StreamSubscription<void>? _subscription;
  Timer? _retry;
  String? _cache;
  int _attempts = 0;
  bool _disposed = false;
  int _generation = 0;
  int? _notBefore;
  int get _now => clock().millisecondsSinceEpoch;
  void _diagnostic(String message) {
    debugPrint('Analytics: $message');
  }

  @override
  void add(Map<String, dynamic> event) {
    if (_disposed) return;
    final immutable = jsonDecode(jsonEncode(event)) as Map<String, dynamic>;
    final data = (immutable['payload'] as Map)['data'] as Map?;
    final id = data?['client_event_id'] as String? ?? 'page-$_owner-$_now';
    final created = _now;
    _generation++;
    _writes = _writes.then((_) async {
      try {
        await store.put(id, immutable, created);
      } catch (_) {
        _diagnostic('persistent storage unavailable; using memory');
        store = _fallback;
        await store.put(id, immutable, created);
      }
    }).catchError((Object _) {
      _diagnostic('queue write failed');
    });
    if (autoFlush) unawaited(_writes.then((_) => flush()));
  }

  void _schedule(Duration delay) {
    if (_disposed || !autoFlush) return;
    _retry?.cancel();
    _retry = Timer(delay, () {
      unawaited(flush());
    });
  }

  @override
  Future<void> flush() {
    if (_disposed) return Future.value();
    if (_notBefore != null && _now < _notBefore!) {
      _schedule(Duration(milliseconds: _notBefore! - _now));
      return Future.value();
    }
    return _flushing ??= _drain().catchError((Object _) {
      _diagnostic('queue unavailable');
      _schedule(const Duration(seconds: 5));
    }).whenComplete(() {
      _flushing = null;
    });
  }

  Future<void> _drain() async {
    await _writes;
    if (!await store.acquire(_owner, _now)) {
      _schedule(const Duration(seconds: 5));
      return;
    }
    try {
      while (!_disposed) {
        final generation = _generation;
        await _writes;
        final records = await store.pending(_now);
        if (records.isEmpty) {
          if (generation != _generation) continue;
          _attempts = 0;
          return;
        }
        if (!await store.acquire(_owner, _now)) return;
        final record = records.first;
        final event = Map<String, dynamic>.from(record['event'] as Map);
        final payload = Map<String, dynamic>.from(event['payload'] as Map);
        event['payload'] = {
          'website': website,
          'hostname': hostname,
          'referrer': '',
          ...metadata(),
          ...payload
        };
        bool retry = false;
        try {
          final response = await client
              .post(endpoint,
                  headers: {
                    'Content-Type': 'application/json',
                    if (_cache != null) 'x-umami-cache': _cache!
                  },
                  body: jsonEncode(event))
              .timeout(const Duration(seconds: 5));
          if (response.statusCode >= 200 && response.statusCode < 300) {
            try {
              final body = jsonDecode(response.body);
              if (body is Map && body['cache'] is String) {
                _cache = body['cache'];
              }
            } catch (_) {}
          } else if ((response.statusCode == 401 ||
                  response.statusCode == 403) &&
              _cache != null) {
            _cache = null;
            retry = true;
          } else if (response.statusCode == 429 || response.statusCode >= 500) {
            retry = true;
          } else {
            _diagnostic('dropped invalid event (${response.statusCode})');
            if (response.statusCode == 401 || response.statusCode == 403) {
              _cache = null;
            }
          }
        } catch (_) {
          retry = true;
        }
        if (retry) {
          final seconds = min(60, pow(2, min(_attempts++, 6)).toInt());
          final delay = Duration(
              milliseconds: min(
                  60000,
                  (seconds * 1000 * (0.75 + Random().nextDouble() * .5))
                      .round()));
          // Explicit/manual test flushing is immediate; production new events
          // must not bypass an existing retry backoff.
          if (autoFlush) _notBefore = _now + delay.inMilliseconds;
          _schedule(delay);
          return;
        }
        await store.remove(record['id'] as String);
        _notBefore = null;
        _attempts = 0;
      }
    } finally {
      await store.release(_owner);
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _retry?.cancel();
    await _subscription?.cancel();
    await _writes;
    if (_flushing != null) await _flushing;
    client.close();
  }
}
