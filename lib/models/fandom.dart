import '../utils/string_utils.dart';

class FandomSearchLabel {
  final String target;
  final String optimized;

  const FandomSearchLabel({required this.target, required this.optimized});
}

class Fandom {
  final int id;
  final String name;
  final String kind;
  final int? parentId;
  final List<String> alternateNames;
  final String searchName;
  final List<FandomSearchLabel> searchLabels;

  Fandom({
    required this.id,
    required this.name,
    required this.kind,
    required this.parentId,
    this.alternateNames = const [],
  })  : searchName = optimizeStringFormat(name),
        searchLabels = _searchLabelsFor(name, alternateNames);

  factory Fandom.fromJson(Map<String, dynamic> json) {
    return Fandom(
      id: (json['id'] as num).toInt(),
      name: json['name'].toString(),
      kind: json['kind']?.toString() ?? 'unknown',
      parentId: (json['parentId'] as num?)?.toInt(),
      alternateNames: _alternateNamesFrom(json['alternateNames']),
    );
  }
}

List<String> _alternateNamesFrom(Object? value) {
  if (value is! List) return const [];
  return [
    for (final name in value)
      if (name != null && name.toString().trim().isNotEmpty) name.toString(),
  ];
}

List<FandomSearchLabel> _searchLabelsFor(
  String name,
  List<String> alternateNames,
) {
  final labels = <FandomSearchLabel>[];
  final seen = <String>{};
  for (final raw in [name, ...alternateNames]) {
    final optimized = optimizeStringFormat(raw);
    if (optimized.isEmpty || !seen.add(optimized)) continue;
    labels.add(FandomSearchLabel(
      target: raw.toLowerCase(),
      optimized: optimized,
    ));
  }
  return List.unmodifiable(labels);
}
