import 'dart:async';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/creator.dart';
import '../utils/int_encoding.dart';
import '../utils/url_encoding.dart';
import 'creator_data_service.dart';
import 'analytics_service.dart';

class FavoritesService extends ChangeNotifier {
  static const String _favoritesIdsKey = 'favorite_creator_ids';
  static SharedPreferences? _prefs;

  // Local state for fast synchronous access
  final Set<int> _favoriteIds = <int>{};

  // Debounce timer for storage updates
  Timer? _storageUpdateTimer;
  static const Duration _debounceDelay = Duration(milliseconds: 500);

  CreatorDataProvider creatorDataProvider;

  FavoritesService(this.creatorDataProvider, {this.analytics});
  final AnalyticsService? analytics;

  List<Creator> get favorites {
    final favoriteCreators = <Creator>[];
    for (final id in _favoriteIds) {
      final creator = creatorDataProvider.getCreatorById(id);
      if (creator != null) {
        favoriteCreators.add(creator);
      }
    }

    return favoriteCreators
        .sorted((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  // Synchronous methods for fast access
  void addFavorite(int creatorId, {String? operationId}) {
    if (creatorId < 0 ||
        creatorDataProvider.getCreatorById(creatorId) == null) {
      return;
    }
    if (_favoriteIds.add(creatorId)) {
      analytics?.bookmark(creatorId, true,
          bulk: operationId != null, operationId: operationId);
      notifyListeners();
      _scheduleStorageUpdate();
    }
  }

  void removeFavorite(int creatorId) {
    if (_favoriteIds.remove(creatorId)) {
      analytics?.bookmark(creatorId, false);
      notifyListeners();
      _scheduleStorageUpdate();
    }
  }

  bool isFavorited(int creatorId) {
    return _favoriteIds.contains(creatorId);
  }

  ({int added, int skipped, int failed}) addAllFavorites(
      Iterable<int> creatorIds) {
    final ids = creatorIds.toList();
    final operationId = analyticsId();
    var added = 0, skipped = 0, failed = 0;
    for (final id in ids) {
      if (id < 0 || creatorDataProvider.getCreatorById(id) == null) {
        failed++;
        continue;
      }
      if (isFavorited(id)) {
        skipped++;
        continue;
      }
      addFavorite(id, operationId: operationId);
      added++;
    }
    analytics?.favorites(FavoritesAction.bulkAdd,
        success: failed == 0,
        operationId: operationId,
        requested: ids.length,
        added: added,
        skipped: skipped,
        failed: failed);
    return (added: added, skipped: skipped, failed: failed);
  }

  String get favoriteIdsCode {
    return IntEncoding.intsToStringCode(_favoriteIds.toList());
  }

  List<int> favoriteIdsFromCode(String code) {
    return IntEncoding.stringCodeToInts(code);
  }

  String getBoothCodeList() {
    final allBooths = <String>[];
    for (final creator in favorites) {
      allBooths.addAll(creator.booths);
    }
    return allBooths.join(',');
  }

  /// Get the shareable URL for favorites
  String getShareableUrl() {
    final listCode = IntEncoding.intsToStringCode(
        favorites.map((creator) => creator.id).toList());
    return UrlEncoding.toUrl({'list': listCode});
  }

  // Debounced storage update
  void _scheduleStorageUpdate() {
    _storageUpdateTimer?.cancel();
    _storageUpdateTimer = Timer(_debounceDelay, () {
      _updateStorage();
    });
  }

  // Asynchronous storage update
  Future<void> _updateStorage() async {
    await _initPrefs();
    if (_prefs == null) {
      analytics?.failure(Operation.favoritesPersistence, FailureCode.storage);
      return;
    }

    try {
      await _prefs!.setStringList(
          _favoritesIdsKey, _favoriteIds.map((id) => id.toString()).toList());
    } catch (e) {
      analytics?.failure(Operation.favoritesPersistence, FailureCode.storage);
      if (kDebugMode) {
        print('Failed to save favorite IDs: $e');
      }
    }
  }

  // Initialize SharedPreferences
  Future<void> _initPrefs() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
    } catch (e) {
      // Handle cases where SharedPreferences is not available (e.g., HTTP, private browsing)
      if (kDebugMode) {
        print('SharedPreferences initialization failed: $e');
      }
      // Create a mock SharedPreferences that doesn't persist
      _prefs = null;
    }
  }

  /// Get favorite creator IDs
  Future<List<int>> _getFavoriteIds() async {
    await _initPrefs();

    if (_prefs == null) {
      return [];
    }

    final idsJson = _prefs!.getStringList(_favoritesIdsKey) ?? const <String>[];
    return idsJson
        .map((idString) => int.tryParse(idString))
        .whereType<int>()
        .toList();
  }

  @override
  void dispose() {
    _storageUpdateTimer?.cancel();
    super.dispose();
  }

  /// Get the number of favorited creators
  int get favoriteCount => _favoriteIds.length;

  /// Check if persistent storage is available
  bool get isStorageAvailable => _prefs != null;

  /// Get storage availability status for debugging
  String get storageStatus {
    if (_prefs == null) {
      return 'Storage not available (HTTP/Private browsing)';
    }
    return 'Storage available';
  }

  /// Initialize and check storage availability
  Future<void> initialize() async {
    await _initPrefs();

    // Load favorites from storage into local state
    final favoriteIds = await _getFavoriteIds();
    _favoriteIds.clear();
    _favoriteIds.addAll(favoriteIds);
    notifyListeners();

    if (kDebugMode) {
      print(
          'FavoritesService: $storageStatus, loaded ${_favoriteIds.length} favorites');
    }
  }
}
