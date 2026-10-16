import '../models/creator.dart';
import '../utils/int_encoding.dart';
import 'analytics_service.dart';
import 'creator_data_service.dart';

/// Resolves only supported link fields. No supplied text enters analytics.
bool applyDeepLink(String text, CreatorDataProvider catalog,
    AnalyticsService analytics, void Function(Creator) select,
    {bool initial = false}) {
  Map<String, String>? params;
  try {
    params = Uri.tryParse(text)?.queryParameters;
  } on FormatException {
    analytics.failure(Operation.deeplink, FailureCode.invalidInput);
    return true;
  }
  if (params == null) return false;
  final types = ['list', 'custom_list', 'creator_id', 'creator'];
  final present = types.where(params.containsKey).toList();
  if (present.isEmpty) return false;
  final type = present.first;
  var success = false;
  var count = 0;
  try {
    final value = params[type]!;
    if (type == 'list' || type == 'custom_list') {
      final ids = type == 'list'
          ? IntEncoding.stringCodeToInts(value)
          : value.split(',').map(int.parse).toList();
      if (ids.isNotEmpty &&
          ids.every((id) => catalog.getCreatorById(id) != null)) {
        catalog.setCreatorCustomList(ids.toSet().toList(),
            shouldRefreshOnReturn: initial);
        count = ids.toSet().length;
        success = true;
      }
    } else {
      Creator? creator;
      if (type == 'creator_id') {
        creator = catalog.getCreatorById(int.parse(value));
      } else {
        final query = value.trim().toLowerCase();
        if (query.isNotEmpty) {
          final exact =
              catalog.allCreators.where((c) => c.name.toLowerCase() == query);
          final matches = exact.isNotEmpty
              ? exact
              : catalog.allCreators
                  .where((c) => c.name.toLowerCase().contains(query));
          if (matches.isNotEmpty) creator = matches.first;
        }
      }
      if (creator != null) {
        select(creator);
        success = true;
        count = 1;
      }
    }
  } catch (_) {/* invalid input is reported using a bounded code below */}
  analytics.deeplink(type, success, count: count, initial: initial);
  if (!success) analytics.failure(Operation.deeplink, FailureCode.invalidInput);
  return true;
}
