import 'package:collection/collection.dart';

import '../utils/string_utils.dart';
import 'fandom.dart';

class CreatorSpace {
  final String code;
  final String? type;

  const CreatorSpace({required this.code, this.type});

  factory CreatorSpace.fromJson(Map<String, dynamic> json) => CreatorSpace(
        code: json['code'].toString(),
        type: json['type']?.toString(),
      );
}

class CreatorLink {
  final String type;
  final String url;

  const CreatorLink({required this.type, required this.url});

  String get title => _displayLabel(type);
}

class CreatorAssets {
  final String? thumbnail;
  final List<String> gallery;

  const CreatorAssets({this.thumbnail, this.gallery = const []});

  factory CreatorAssets.fromJson(Map<String, dynamic> json) => CreatorAssets(
        thumbnail: json['thumbnail'] as String?,
        gallery: ((json['gallery'] as List?) ?? const [])
            .map((value) => value.toString())
            .toList(growable: false),
      );
}

class Creator {
  final int id;
  final String name;
  final List<CreatorSpace> spaces;
  final List<String> attendanceDayIds;
  final Map<String, String> dayLabels;
  final String? contentRating;
  final List<String> offerings;
  final CreatorAssets assets;
  final List<CreatorLink> links;
  final List<Fandom> fandoms;

  final List<String> searchOptimizedBooths;

  Creator({
    required this.id,
    required this.name,
    required this.spaces,
    required this.attendanceDayIds,
    this.dayLabels = const {},
    this.contentRating,
    this.offerings = const [],
    this.assets = const CreatorAssets(),
    this.links = const [],
    this.fandoms = const [],
  }) : searchOptimizedBooths = spaces
            .map((space) => optimizedBoothFormat(space.code))
            .toList(growable: false);

  factory Creator.fromCatalogJson(
    Map<String, dynamic> json, {
    required Map<int, Fandom> fandomById,
    required Map<String, String> dayLabels,
  }) {
    final fandoms = ((json['fandomIds'] as List?) ?? const [])
        .whereType<num>()
        .map((value) => fandomById[value.toInt()])
        .nonNulls
        .toSet()
        .sortedBy((fandom) => fandom.name.toLowerCase());

    return Creator(
      id: int.parse(json['id'].toString()),
      name: json['name'].toString(),
      spaces: ((json['spaces'] as List?) ?? const [])
          .whereType<Map>()
          .map((space) => CreatorSpace.fromJson(
                Map<String, dynamic>.from(space),
              ))
          .where((space) => space.code.isNotEmpty)
          .toList(growable: false),
      attendanceDayIds: ((json['attendanceDayIds'] as List?) ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
      dayLabels: dayLabels,
      contentRating: json['contentRating']?.toString(),
      offerings: ((json['offerings'] as List?) ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
      assets: json['assets'] is Map
          ? CreatorAssets.fromJson(
              Map<String, dynamic>.from(json['assets'] as Map),
            )
          : const CreatorAssets(),
      links: ((json['links'] as List?) ?? const [])
          .whereType<Map>()
          .map((link) => CreatorLink(
                type: link['type']?.toString() ?? '',
                url: link['url']?.toString() ?? '',
              ))
          .where((link) => link.url.isNotEmpty)
          .toList(growable: false),
      fandoms: fandoms,
    );
  }

  late final List<int> fandomIds = List.unmodifiable(
    fandoms.map((fandom) => fandom.id),
  );

  late final List<String> fandomNames = List.unmodifiable(
    fandoms.map((fandom) => fandom.name),
  );

  late final List<String> booths = List.unmodifiable(
    spaces.map((space) => space.code),
  );

  String get day {
    if (attendanceDayIds.length > 1) return 'BOTH';
    if (attendanceDayIds.isEmpty) return '';
    final id = attendanceDayIds.single;
    final label = (dayLabels[id] ?? id).toLowerCase();
    if (id == 'day-1' ||
        label.contains('saturday') ||
        label.contains('sabtu')) {
      return 'SAT';
    }
    if (id == 'day-2' || label.contains('sunday') || label.contains('minggu')) {
      return 'SUN';
    }
    return dayLabels[id] ?? id;
  }

  String get dayDisplay {
    if (attendanceDayIds.isEmpty) return '';
    return attendanceDayIds.map((id) => dayLabels[id] ?? id).join(' & ');
  }

  String get boothsDisplay => booths.join(', ');

  late final List<String> offeringNames = List.unmodifiable(
    offerings.map(_displayLabel),
  );

  String get offeringsDisplay => offeringNames.join(', ');
}

String _displayLabel(String value) {
  if (value.isEmpty) return value;
  return value
      .split(RegExp(r'[_-]+'))
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
