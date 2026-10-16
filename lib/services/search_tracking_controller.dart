import 'dart:async';
import '../utils/string_utils.dart';
import 'analytics_service.dart';
import 'creator_data_service.dart';

// Unlike the legacy fuzzy-search normalizer, retain non-Latin characters.
String normalizeAnalyticsQuery(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Query text is local-only and never passed to AnalyticsService or its queue.
class SearchTrackingController {
  SearchTrackingController(this.analytics, this.catalog);
  final AnalyticsService analytics;
  final CreatorDataProvider catalog;
  Timer? _timer;
  String _query = '';
  String? _key, _id;
  SearchSource _source = SearchSource.typed;
  int? _explicit;
  bool _emitted = false;

  bool isLink(String text) {
    try {
      return Uri.tryParse(text)?.queryParameters.keys.any((k) => const {
                'list',
                'custom_list',
                'creator',
                'creator_id'
              }.contains(k)) ??
          false;
    } on FormatException {
      return true;
    }
  }

  void changed(String query) {
    analytics.searchOpened();
    analytics.activity();
    if (isLink(query)) {
      reset();
      return;
    }
    _set(query);
    _timer?.cancel();
    if (_query.trim().isNotEmpty) {
      _timer = Timer(const Duration(seconds: 1), () {
        commit(SearchTrigger.settled);
      });
    }
  }

  void _set(String query,
      {SearchSource source = SearchSource.typed, int? fandomId}) {
    final key =
        '${normalizeAnalyticsQuery(query)}|${catalog.analyticsScope.name}|${catalog.analyticsOriginScope.name}';
    if (_key == key) return;
    _timer?.cancel();
    _key = key;
    _query = query;
    _source = source;
    _explicit = fandomId;
    _emitted = false;
    _id = null;
  }

  String? submit(String query) {
    if (isLink(query)) {
      reset();
      return null;
    }
    if (query.trim().isNotEmpty) analytics.searchOpened();
    _set(query);
    return commit(SearchTrigger.submitted);
  }

  String? result(String query) {
    if (query.trim().isEmpty || isLink(query)) return null;
    _set(query);
    return commit(SearchTrigger.result);
  }

  void select(int fandomId, SearchSource source) {
    final fandom = catalog.fandomById[fandomId];
    if (fandom == null) return;
    analytics.searchOpened();
    _set(fandom.name, source: source, fandomId: fandomId);
    // A selection confirms an ambiguous typed query, but never double-counts
    // an already-recorded canonical/alias query with the same spelling.
    if (!_emitted) {
      _explicit = fandomId;
      _source = source;
    }
    commit(SearchTrigger.selection);
  }

  String? commit(SearchTrigger trigger) {
    _timer?.cancel();
    if (_query.trim().isEmpty || catalog.isLoading) return null;
    if (_emitted) return _id;
    final normalized = normalizeAnalyticsQuery(_query);
    var resolution = SearchResolution.unresolved;
    int? fandomId = _explicit;
    if (fandomId != null) {
      resolution = SearchResolution.explicitSelection;
    } else {
      final canonical = catalog.fandomById.values
          .where((f) => normalizeAnalyticsQuery(f.name) == normalized)
          .toList();
      final aliases = catalog.fandomById.values
          .where((f) => f.alternateNames
              .any((n) => normalizeAnalyticsQuery(n) == normalized))
          .toList();
      if (canonical.length == 1) {
        fandomId = canonical.single.id;
        resolution = SearchResolution.canonical;
      } else if (canonical.length > 1) {
        resolution = SearchResolution.ambiguous;
      } else if (aliases.length == 1) {
        fandomId = aliases.single.id;
        resolution = SearchResolution.alias;
      } else if (aliases.length > 1) {
        resolution = SearchResolution.ambiguous;
      } else if (catalog.allCreators
          .any((c) => normalizeAnalyticsQuery(c.name) == normalized)) {
        resolution = SearchResolution.creator;
      } else if (catalog.allCreators.any((c) =>
          c.searchOptimizedBooths.contains(optimizedBoothFormat(_query)))) {
        resolution = SearchResolution.booth;
      }
    }
    _id = analyticsId();
    _emitted = true;
    analytics.search(
        id: _id!,
        source: _source,
        trigger: trigger,
        resolution: resolution,
        fandomId: fandomId,
        results: catalog.searchCreators(_query).length,
        catalogResults: catalog.searchAllCreators(_query).length,
        scope: catalog.analyticsScope,
        originScope: catalog.analyticsOriginScope);
    return _id;
  }

  void reset() {
    _timer?.cancel();
    _query = '';
    _key = null;
    _id = null;
    _explicit = null;
    _emitted = false;
  }

  void dispose() {
    _timer?.cancel();
  }
}
