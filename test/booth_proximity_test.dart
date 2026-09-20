import 'dart:convert';
import 'dart:io';

import 'package:cf_map_flutter/models/booth_proximity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late BoothProximityData proximity;
  late Map<String, dynamic> rawData;

  setUpAll(() async {
    final raw = await File('data/booth-proximity.json').readAsString();
    rawData = json.decode(raw) as Map<String, dynamic>;
    proximity = BoothProximityData.fromJson(rawData);
  });

  test('generated metadata is present', () {
    expect(proximity.mapSha256, hasLength(64));
    expect(proximity.maxDistance, 32);
    expect(proximity.maxNeighbors, 48);
  });

  test('lookup table stays bounded for runtime memory and parsing cost', () {
    final booths = rawData['booths'] as List<dynamic>;
    final neighbors = rawData['neighbors'] as List<dynamic>;
    final neighborCounts =
        neighbors.map((entries) => (entries as List<dynamic>).length).toList();

    expect(neighbors, hasLength(booths.length));
    expect(neighborCounts.every((count) => count <= 48), isTrue);
    expect(neighborCounts.fold<int>(0, (sum, count) => sum + count),
        lessThanOrEqualTo(booths.length * 48));
  });

  test('same and side-by-side booths have short walking distances', () {
    expect(proximity.distanceBetween('Y-32b', 'Y-32b'), 0);
    expect(proximity.distanceBetween('Y-32b', 'Y-32a'), lessThanOrEqualTo(2));
    expect(proximity.distanceBetween('Y-33a', 'Y-33b'), lessThanOrEqualTo(2));
  });

  test('new semantic map includes creator and corporate booths', () {
    final booths = (rawData['booths'] as List<dynamic>).cast<String>();
    expect(booths.length, greaterThan(3000));
    expect(booths, containsAll(<String>['Y-32a', '1207', '1208']));
  });

  test('booth lookup normalizes sectioned and sectionless IDs', () {
    expect(
      proximity.distanceBetween('Y-032B', 'Y-32a'),
      proximity.distanceBetween('Y-32b', 'Y-032A'),
    );
    expect(
      proximity.distanceBetween('01208', '1209'),
      proximity.distanceBetween('1208', '01209'),
    );
  });
}
