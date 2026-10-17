import 'package:cf_map_flutter/models/creator.dart';
import 'package:cf_map_flutter/services/creator_catalog_index.dart';
import 'package:cf_map_flutter/utils/int_encoding.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Creator parse(Map<String, dynamic> json) => Creator.fromCatalogJson(
        json,
        fandomById: {},
        dayLabels: {},
      );

  test('manual exhibitors support search, booth lookup and shared list IDs',
      () {
    final creator = parse({
      'id': '1000001',
      'name': 'Example Food',
      'catalogUrl': null,
      'spaces': [
        {'code': 'FOOD-01', 'type': 'food'}
      ],
      'assets': {
        'thumbnail': 'https://cf23-config.nnt.gg/images/food/logo.webp',
        'gallery': ['https://cf23-config.nnt.gg/images/food/menu.webp'],
      },
    });
    final index = CreatorCatalogIndex.build([creator], {});
    expect(creator.catalogUrl, isNull);
    expect(creator.assets.thumbnail,
        'https://cf23-config.nnt.gg/images/food/logo.webp');
    expect(index.search('Example Food'), contains(creator));
    expect(index.creatorsByBooth['FOOD-01'], [creator]);
    expect(index.creatorById[1000001], creator);
    expect(
        IntEncoding.stringCodeToInts(
            IntEncoding.intsToStringCode([123, 1000001, 1999999])),
        [123, 1000001, 1999999]);
  });

  test('legacy catalog entries retain their Comifuro page', () {
    expect(parse({'id': '123', 'name': 'Legacy'}).catalogUrl,
        'https://catalog.comifuro.net/circle/123');
    expect(
        parse({
          'id': '123',
          'name': 'Explicit',
          'catalogUrl': 'https://example.com/exhibitor',
        }).catalogUrl,
        'https://example.com/exhibitor');
  });
}
