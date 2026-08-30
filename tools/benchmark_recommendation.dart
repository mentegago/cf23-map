import 'dart:convert';
import 'dart:io';

import 'package:cf_map_flutter/models/booth_proximity.dart';
import 'package:cf_map_flutter/models/creator.dart';
import 'package:cf_map_flutter/models/fandom.dart';
import 'package:cf_map_flutter/models/recommendation.dart';
import 'package:cf_map_flutter/services/recommendation_engine.dart';

Future<void> main(List<String> arguments) async {
  final iterations = arguments.isEmpty ? 25 : int.parse(arguments.first);
  final catalog = json.decode(
    await File('data/catalog-initial.json').readAsString(),
  ) as Map<String, dynamic>;
  final registry = json.decode(
    await File('data/fandoms-initial.json').readAsString(),
  ) as Map<String, dynamic>;
  final fandoms = (registry['fandoms'] as List<dynamic>)
      .map((value) => Fandom.fromJson(value as Map<String, dynamic>))
      .toList();
  final fandomById = {for (final fandom in fandoms) fandom.id: fandom};
  final event = catalog['event'] as Map<String, dynamic>;
  final dayLabels = {
    for (final day in event['days'] as List<dynamic>)
      (day as Map<String, dynamic>)['id'].toString(): day['label'].toString(),
  };
  final creators = (catalog['exhibitors'] as List<dynamic>)
      .map((value) => Creator.fromCatalogJson(
            value as Map<String, dynamic>,
            fandomById: fandomById,
            dayLabels: dayLabels,
          ))
      .toList();
  final proximity = BoothProximityData.fromJson(
    json.decode(await File('data/booth-proximity.json').readAsString())
        as Map<String, dynamic>,
  );
  final favorites = creators
      .where((creator) => creator.booths.isNotEmpty)
      .take(20)
      .map((creator) => creator.id)
      .toSet();
  final engine = RecommendationEngine(boothProximity: proximity);
  final profile = RecommendationProfile();

  engine.recommend(
    creators: creators,
    profile: profile,
    favoriteIds: favorites,
    sessionExposureIds: const {},
  );

  final timings = <int>[];
  for (var iteration = 0; iteration < iterations; iteration++) {
    final stopwatch = Stopwatch()..start();
    engine.recommend(
      creators: creators,
      profile: profile,
      favoriteIds: favorites,
      sessionExposureIds: const {},
    );
    stopwatch.stop();
    timings.add(stopwatch.elapsedMicroseconds);
  }

  timings.sort();
  final total = timings.fold<int>(0, (sum, value) => sum + value);
  final averageMilliseconds = total / timings.length / 1000;
  final medianMilliseconds = timings[timings.length ~/ 2] / 1000;
  final maximumMilliseconds = timings.last / 1000;
  stdout.writeln(
    '${creators.length} creators, ${favorites.length} itinerary anchors, '
    '$iterations runs',
  );
  stdout.writeln(
    'core scoring: average ${averageMilliseconds.toStringAsFixed(2)} ms, '
    'median ${medianMilliseconds.toStringAsFixed(2)} ms, '
    'max ${maximumMilliseconds.toStringAsFixed(2)} ms',
  );
}
