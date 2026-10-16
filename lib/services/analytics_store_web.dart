import 'package:idb_shim/idb.dart';
import 'catalog_idb_factory.dart';
import 'analytics_delivery.dart';

/// Lease reads/writes share a read-write transaction: atomic across tabs.
class IndexedAnalyticsStore implements AnalyticsStore {
  Future<Database>? _db;
  Future<Database> get database => _db ??= catalogIdbFactory()!
          .open('cf23-analytics', version: 1, onUpgradeNeeded: (event) {
        event.database.createObjectStore('events', keyPath: 'id');
        event.database.createObjectStore('leases');
      });
  @override
  Future<void> put(String id, Map<String, dynamic> event, int now) async {
    final db = await database;
    final tx = db.transaction('events', idbModeReadWrite);
    final store = tx.objectStore('events');
    await store.put({'id': id, 'created': now, 'event': event});
    final records = (await store.getAll())
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList()
      ..sort(analyticsRecordOrder);
    var remaining = records.length;
    for (final record in records) {
      if (now - (record['created'] as int) > 259200000 || remaining > 2000) {
        await store.delete(record['id']);
        remaining--;
      }
    }
    await tx.completed;
  }

  @override
  Future<List<Map<String, dynamic>>> pending(int now) async {
    final tx = (await database).transaction('events', idbModeReadWrite);
    final store = tx.objectStore('events');
    final result = <Map<String, dynamic>>[];
    for (final raw in await store.getAll()) {
      final record = Map<String, dynamic>.from(raw as Map);
      if (now - (record['created'] as int) > 259200000) {
        await store.delete(record['id']);
      } else {
        result.add(record);
      }
    }
    await tx.completed;
    result.sort(analyticsRecordOrder);
    return result;
  }

  @override
  Future<void> remove(String id) async {
    final tx = (await database).transaction('events', idbModeReadWrite);
    await tx.objectStore('events').delete(id);
    await tx.completed;
  }

  @override
  Future<bool> acquire(String owner, int now) async {
    final tx = (await database).transaction('leases', idbModeReadWrite);
    final store = tx.objectStore('leases');
    final lease = await store.getObject('sender') as Map?;
    final allowed = lease == null ||
        lease['owner'] == owner ||
        (lease['until'] as int) <= now;
    if (allowed) {
      await store.put({'owner': owner, 'until': now + 15000}, 'sender');
    }
    await tx.completed;
    return allowed;
  }

  @override
  Future<void> release(String owner) async {
    final tx = (await database).transaction('leases', idbModeReadWrite);
    final store = tx.objectStore('leases');
    final lease = await store.getObject('sender') as Map?;
    if (lease?['owner'] == owner) await store.delete('sender');
    await tx.completed;
  }
}
