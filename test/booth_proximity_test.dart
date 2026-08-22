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
    expect(proximity.distanceBetween('L-49a', 'L-49a'), 0);
    expect(proximity.distanceBetween('L-49a', 'L-49b'), 1);
    expect(proximity.distanceBetween('L-49a', 'L-50a'), 2);
    expect(proximity.distanceBetween('AA-10', 'AA-09'), 1);
  });

  test('back-to-back booths are not retained as nearby', () {
    expect(proximity.distanceBetween('L-49a', 'L-12a'), isNull);
  });

  test('booth lookup normalizes leading zeroes and suffix case', () {
    expect(
      proximity.distanceBetween('AA-010', 'AA-09'),
      proximity.distanceBetween('AA-10', 'AA-9'),
    );
    expect(
      proximity.distanceBetween('L-049A', 'L-49b'),
      proximity.distanceBetween('L-49a', 'L-49b'),
    );
  });
}
