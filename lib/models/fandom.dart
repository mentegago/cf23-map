import '../utils/string_utils.dart';

class Fandom {
  final int id;
  final String name;
  final String kind;
  final int? parentId;
  final String searchName;

  Fandom({
    required this.id,
    required this.name,
    required this.kind,
    required this.parentId,
  }) : searchName = optimizeStringFormat(name);

  factory Fandom.fromJson(Map<String, dynamic> json) {
    return Fandom(
      id: (json['id'] as num).toInt(),
      name: json['name'].toString(),
      kind: json['kind']?.toString() ?? 'unknown',
      parentId: (json['parentId'] as num?)?.toInt(),
    );
  }
}
