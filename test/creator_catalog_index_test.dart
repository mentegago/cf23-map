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

  test('search pills rank by match, empty pills rank by popularity', () {
    final blueArchive = Fandom(
      id: 34,
      name: 'Blue Archive',
      kind: 'franchise',
      parentId: null,
    );
    final bluey = Fandom(
      id: 90,
      name: 'Bluey',
      kind: 'franchise',
      parentId: null,
    );
    Creator creator(int id, Fandom fandom) => Creator(
          id: id,
          name: 'Artist $id',
          spaces: [CreatorSpace(code: 'A-$id')],
          attendanceDayIds: const ['day-1'],
          fandoms: [fandom],
        );
    final index = CreatorCatalogIndex.build(
      [
        creator(1, blueArchive),
        creator(2, blueArchive),
        creator(3, blueArchive),
        creator(4, bluey),
      ],
      {34: blueArchive, 90: bluey},
    );

    expect(index.fandomSuggestions('').first, 'Blue Archive');
    expect(index.popularFandomNames().first, 'Blue Archive');
    expect(index.fandomSuggestions('blue').first, 'Bluey');
  });

  test('alternate names match the canonical fandom for search and pills', () {
    final original = Fandom(
      id: 1,
      name: 'Original',
      kind: 'generic_tag',
      parentId: null,
      alternateNames: const [
        'OC',
        'Oc charater',
        'Original Characters',
        'Original Bara Art',
        'Dan Karya Original.',
        'Dan',
      ],
    );
    final dandadan = Fandom(
      id: 88,
      name: 'Dandadan',
      kind: 'franchise',
      parentId: null,
    );
    final blueArchive = Fandom(
      id: 34,
      name: 'Blue Archive',
      kind: 'franchise',
      parentId: null,
    );
    final marvel = Fandom(
      id: 41,
      name: 'Marvel',
      kind: 'franchise',
      parentId: null,
    );
    final dc = Fandom(
      id: 28,
      name: 'DC',
      kind: 'franchise',
      parentId: null,
      alternateNames: const ['Marvel'],
    );
    Creator creator(int id, String name, Fandom fandom) => Creator(
          id: id,
          name: name,
          spaces: [CreatorSpace(code: 'A-$id')],
          attendanceDayIds: const ['day-1'],
          fandoms: [fandom],
        );
    final index = CreatorCatalogIndex.build(
      [
        creator(1, 'OC Artist', original),
        creator(2, 'Marvel Artist', marvel),
        creator(3, 'DC Artist', dc),
        creator(4, 'BA Artist', blueArchive),
        creator(5, 'BA Artist Two', blueArchive),
        creator(6, 'Original Two', original),
        creator(7, 'Original Three', original),
        creator(8, 'West Booth', dandadan),
      ],
      {1: original, 41: marvel, 28: dc, 34: blueArchive, 88: dandadan},
    );

    expect(index.fandomSuggestions('Oc charater').first, 'Original');
    expect(index.fandomSuggestions('OC').first, 'Original');
    expect(index.fandomSuggestions('Dan').first, 'Dandadan');
    expect(index.search('Dan').first.id, 8);
    expect(index.fandomSuggestions('BA').first, 'Blue Archive');
    expect(index.fandomSuggestions('BA'), isNot(contains('Original')));
    expect(
      index.search('Oc charater').map((creator) => creator.id),
      unorderedEquals([1, 6, 7]),
    );
    expect(index.fandomIdForName('Oc charater'), 1);
    expect(index.fandomIdForName('OC'), 1);
    expect(index.fandomIdForName('Marvel'), 41);
  });
}
