import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'analytics_platform_stub.dart'
    if (dart.library.js_interop) 'analytics_platform_web.dart' as platform;
import 'analytics_delivery.dart';
import 'version_service.dart';

enum AnalyticsEvent {
  searchPerformed,
  searchOpened,
  searchCleared,
  searchClosed,
  creatorOpened,
  creatorClosed,
  bookmarkChanged,
  mapInteracted,
  boothSelected,
  listScopeChanged,
  sheetStateChanged,
  creatorAction,
  galleryAction,
  favoritesAction,
  deeplinkProcessed,
  updateAction,
  appReady,
  operationFailed,
  activeMinute,
}

enum SearchSource { typed, suggestion, creatorFandomChip }

enum SearchTrigger { settled, submitted, selection, result }

enum SearchResolution {
  canonical,
  alias,
  explicitSelection,
  creator,
  booth,
  ambiguous,
  unresolved
}

enum ListScope { fullCatalog, sharedList, searchResultList }

enum SelectionSource {
  map,
  searchResult,
  list,
  recommendation,
  random,
  deeplink
}

enum CreatorAction { externalLink, catalog, circleCut, share, sourceCode }

enum GalleryAction { open, imageChanged, close }

enum FavoritesAction { share, copyBooths, bulkAdd }

enum UpdateAction { shown, dismissed, refresh }

enum Operation {
  clipboard,
  linkLaunch,
  favoritesPersistence,
  catalogLoad,
  mapLoad,
  deeplink
}

enum FailureCode {
  unavailable,
  invalidInput,
  notFound,
  storage,
  network,
  launchRejected
}

String analyticsName(Enum value) => value.name
    .replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');
String analyticsId() {
  final random = Random.secure();
  return List.generate(
      16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// Only typed methods cross the collection boundary. Never pass search text here.
class AnalyticsService {
  AnalyticsService(
      {required this.enabled,
      this.sink,
      DateTime Function()? clock,
      bool Function()? visible,
      String? runId})
      : clock = clock ?? DateTime.now,
        visible = visible ?? platform.isVisible,
        runId = runId ?? analyticsId();
  factory AnalyticsService.production() {
    const website = String.fromEnvironment('UMAMI_WEBSITE_ID');
    const endpoint = String.fromEnvironment('UMAMI_ENDPOINT');
    const hostname = String.fromEnvironment('UMAMI_HOSTNAME');
    final uri = Uri.tryParse(endpoint);
    final enabled = kReleaseMode &&
        website.isNotEmpty &&
        hostname.isNotEmpty &&
        uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.hasAuthority;
    final delivery = enabled
        ? AnalyticsDelivery(
            endpoint: uri,
            website: website,
            hostname: hostname,
            metadata: platform.metadata,
            store: platform.createStore(),
            reconnect: platform.reconnects())
        : null;
    return AnalyticsService(enabled: enabled, sink: delivery);
  }
  final bool enabled;
  final AnalyticsSink? sink;
  final DateTime Function() clock;
  final bool Function() visible;
  final String runId;
  int? catalogVersion;
  int _sequence = 0;
  int? _activeMinute;
  bool _started = false;
  bool _searchVisible = false;
  int? _creatorId;
  DateTime? _creatorSince;
  void start() {
    if (_started) return;
    _started = true;
    if (enabled) {
      sink?.add({
        'type': 'event',
        'payload': {'url': '/', 'title': 'CF23 Booth Map'}
      });
    }
  }

  void _emit(AnalyticsEvent event,
      [Map<String, Object> properties = const {}]) {
    if (!enabled) return;
    final data = <String, Object>{
      'schema_version': 1,
      'event_edition': 'comic-frontier-23',
      'app_version': VersionService.clientVersion,
      if (catalogVersion != null) 'catalog_version': catalogVersion!,
      'client_event_id': analyticsId(),
      'occurred_at_ms': clock().toUtc().millisecondsSinceEpoch,
      'app_run_id': runId,
      'sequence': ++_sequence,
      ...properties,
    };
    sink?.add({
      'type': 'event',
      'payload': {'url': '/', 'name': analyticsName(event), 'data': data}
    });
  }

  void activity() {
    if (!visible()) return;
    final minute = clock().toUtc().millisecondsSinceEpoch ~/ 60000;
    if (_activeMinute == minute) return;
    _activeMinute = minute;
    _emit(AnalyticsEvent.activeMinute);
  }

  void search(
      {required String id,
      required SearchSource source,
      required SearchTrigger trigger,
      required SearchResolution resolution,
      int? fandomId,
      required int results,
      required int catalogResults,
      required ListScope scope,
      ListScope? originScope}) {
    final resolved = {
      SearchResolution.canonical,
      SearchResolution.alias,
      SearchResolution.explicitSelection
    }.contains(resolution);
    if (resolved != (fandomId != null)) {
      throw ArgumentError('Resolution and fandom ID disagree');
    }
    _emit(AnalyticsEvent.searchPerformed, {
      'search_id': id,
      'source': analyticsName(source),
      'trigger': analyticsName(trigger),
      'resolution': analyticsName(resolution),
      if (fandomId != null) 'fandom_id': fandomId,
      'result_count': results,
      'catalog_result_count': catalogResults,
      'scope': analyticsName(scope),
      if (originScope != null) 'origin_scope': analyticsName(originScope)
    });
    activity();
  }

  void searchOpened() {
    if (_searchVisible) return;
    _searchVisible = true;
    _emit(AnalyticsEvent.searchOpened);
  }

  void searchCleared() {
    _emit(AnalyticsEvent.searchCleared);
    activity();
  }

  void searchClosed({String reason = 'dismissed'}) {
    if (!{'dismissed', 'back', 'creator_selected'}.contains(reason)) {
      throw ArgumentError('Unknown close reason');
    }
    if (!_searchVisible) return;
    _searchVisible = false;
    _emit(AnalyticsEvent.searchClosed, {'reason': reason});
  }

  void creatorOpened(int id, SelectionSource source,
      {String? searchId, int? position}) {
    if (_creatorId == id) return;
    creatorClosed(reason: 'replaced');
    _creatorId = id;
    _creatorSince = clock();
    _emit(AnalyticsEvent.creatorOpened, {
      'creator_id': id,
      'source': analyticsName(source),
      if (searchId != null) 'search_id': searchId,
      if (position != null) 'result_position': position
    });
    activity();
  }

  void creatorClosed({String reason = 'dismissed'}) {
    if (!{'dismissed', 'replaced', 'search_opened'}.contains(reason)) {
      throw ArgumentError('Unknown close reason');
    }
    if (_creatorId == null) return;
    _emit(AnalyticsEvent.creatorClosed, {
      'creator_id': _creatorId!,
      'reason': reason,
      'duration_ms': max(0, clock().difference(_creatorSince!).inMilliseconds)
    });
    _creatorId = null;
    _creatorSince = null;
  }

  void bookmark(int id, bool added, {bool bulk = false, String? operationId}) {
    _emit(AnalyticsEvent.bookmarkChanged, {
      'creator_id': id,
      'action': added ? 'add' : 'remove',
      'source': bulk ? 'bulk' : 'individual',
      if (operationId != null) 'operation_id': operationId
    });
    activity();
  }

  void scopeChanged(ListScope scope, int count, {ListScope? origin}) {
    _emit(AnalyticsEvent.listScopeChanged, {
      'scope': analyticsName(scope),
      'count': count,
      if (origin != null) 'origin_scope': analyticsName(origin)
    });
    activity();
  }

  void mapInteracted({required bool pan, required bool zoom}) {
    if (!pan && !zoom) return;
    _emit(AnalyticsEvent.mapInteracted, {
      'action': pan && zoom
          ? 'both'
          : pan
              ? 'pan'
              : 'zoom'
    });
    activity();
  }

  void boothSelected(int count) {
    _emit(AnalyticsEvent.boothSelected, {
      'count': count,
      'outcome': count == 0
          ? 'empty'
          : count == 1
              ? 'opened'
              : 'chooser'
    });
    activity();
  }

  void sheetState(String state, {required bool user, bool detail = false}) {
    if (!{'collapsed', 'expanded', 'partiallyExpanded'}.contains(state)) {
      throw ArgumentError('Unknown sheet state');
    }
    _emit(AnalyticsEvent.sheetStateChanged, {
      'state': state,
      'sheet': detail ? 'detail' : 'search',
      'source': user ? 'gesture' : 'programmatic'
    });
    if (user) activity();
  }

  void creatorAction(CreatorAction action,
      {int? creatorId, bool success = true, bool? expanded}) {
    _emit(AnalyticsEvent.creatorAction, {
      'action': analyticsName(action),
      'success': success,
      if (creatorId != null) 'creator_id': creatorId,
      if (expanded != null) 'expanded': expanded
    });
    activity();
  }

  void gallery(GalleryAction action, int creatorId, {int? index, int? count}) {
    _emit(AnalyticsEvent.galleryAction, {
      'action': analyticsName(action),
      'creator_id': creatorId,
      if (index != null) 'index': index,
      if (count != null) 'count': count
    });
    activity();
  }

  void favorites(FavoritesAction action,
      {required bool success,
      int? count,
      String? operationId,
      int? requested,
      int? added,
      int? skipped,
      int? failed}) {
    _emit(AnalyticsEvent.favoritesAction, {
      'action': analyticsName(action),
      'success': success,
      if (count != null) 'count': count,
      if (operationId != null) 'operation_id': operationId,
      if (requested != null) 'requested': requested,
      if (added != null) 'added': added,
      if (skipped != null) 'skipped': skipped,
      if (failed != null) 'failed': failed
    });
    activity();
  }

  void deeplink(String type, bool success,
      {int count = 0, bool initial = false}) {
    if (!{'list', 'custom_list', 'creator_id', 'creator'}.contains(type)) {
      throw ArgumentError('Unknown link type');
    }
    _emit(AnalyticsEvent.deeplinkProcessed, {
      'type': type,
      'success': success,
      'count': count,
      'source': initial ? 'initial' : 'pasted'
    });
  }

  void update(UpdateAction action) =>
      _emit(AnalyticsEvent.updateAction, {'action': analyticsName(action)});
  void ready(int durationMs, String source) {
    if (!{'bundled', 'cache'}.contains(source)) {
      throw ArgumentError('Unknown catalog source');
    }
    _emit(
        AnalyticsEvent.appReady, {'duration_ms': durationMs, 'source': source});
  }

  void failure(Operation operation, FailureCode code) => _emit(
      AnalyticsEvent.operationFailed,
      {'operation': analyticsName(operation), 'code': analyticsName(code)});
  Future<void> flushBeforeReload() async {
    try {
      await sink?.flush().timeout(const Duration(milliseconds: 300));
    } catch (_) {/* best effort */}
  }

  Future<void> dispose() async {
    await sink?.dispose();
  }
}
