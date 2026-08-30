import 'dart:convert';
import 'dart:io';

import 'package:cf_map_flutter/models/creator.dart';
import 'package:cf_map_flutter/models/fandom.dart';
import 'package:cf_map_flutter/services/creator_catalog_index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bundled v1 catalog resolves every creator fandom ID', () async {
    final catalog = json.decode(
      await File('data/catalog-initial.json').readAsString(),
    ) as Map<String, dynamic>;
    final registry = json.decode(
      await File('data/fandoms-initial.json').readAsString(),
    ) as Map<String, dynamic>;
    final version = json.decode(
      await File('data/last-updated-initial.json').readAsString(),
    ) as Map<String, dynamic>;

    expect(catalog['schemaVersion'], '1.0.0');
    expect(registry['schemaVersion'], '1.0.0');
    expect(version['creator_data_version'], isPositive);

    final fandoms = (registry['fandoms'] as List)
        .cast<Map<String, dynamic>>()
        .map(Fandom.fromJson)
        .toList();
    final fandomById = {for (final fandom in fandoms) fandom.id: fandom};
    final unknownIds = <int>{};
    for (final exhibitor in (catalog['exhibitors'] as List).cast<Map>()) {
      for (final id in (exhibitor['fandomIds'] as List).cast<num>()) {
        if (!fandomById.containsKey(id.toInt())) unknownIds.add(id.toInt());
      }
    }
    expect(unknownIds, isEmpty);
  });

  test('fandom search scores a fandom once and resolves creators by ID', () {
    final blueArchive = Fandom(
      id: 34,
      name: 'Blue Archive',
      kind: 'franchise',
      parentId: null,
    );
    final hololive = Fandom(
      id: 10,
      name: 'Hololive',
      kind: 'publisher_umbrella',
      parentId: null,
    );
    final hoyoverse = Fandom(
      id: 9,
      name: 'HoYoverse',
      kind: 'publisher_umbrella',
      parentId: null,
    );
    final genshin = Fandom(
      id: 2,
      name: 'Genshin Impact',
      kind: 'franchise',
      parentId: 9,
    );
    Creator creator(int id, String name, Fandom fandom) => Creator(
          id: id,
          name: name,
          spaces: [CreatorSpace(code: 'A-$id')],
          attendanceDayIds: const ['day-1', 'day-2'],
          fandoms: [fandom],
        );
    final creators = [
      creator(1, 'First Artist', blueArchive),
      creator(2, 'Second Artist', blueArchive),
      creator(3, 'Third Artist', hololive),
      creator(4, 'Fourth Artist', genshin),
    ];
    final index = CreatorCatalogIndex.build(
      creators,
      {34: blueArchive, 10: hololive, 9: hoyoverse, 2: genshin},
    );

    expect(index.fandomIdForName('blue-archive'), 34);
    expect(index.search('BA').map((creator) => creator.id), [1, 2]);
    expect(index.fandomSuggestions('blue').first, 'Blue Archive');
    expect(index.creatorsByFandomId[34], hasLength(2));
    expect(index.search('HoYoverse').map((creator) => creator.id), [4]);
  });
}
