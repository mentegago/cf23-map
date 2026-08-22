import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/creator.dart';
import '../models/recommendation.dart';
import '../utils/string_utils.dart';
import 'recommendation_engine.dart';

class RecommendationService extends ChangeNotifier {
  static const String _storageKey = 'cf23_recommendation_profile_v1';
  static const Duration _saveDelay = Duration(milliseconds: 500);

  final bool disabled;

  RecommendationProfile _profile = RecommendationProfile();
  final RecommendationEngine _engine = const RecommendationEngine();
  final Set<int> _sessionExposureIds = {};
  List<RecommendationResult>? _cachedRecommendations;
  ({
    int creators,
    int favorites,
    int coldStart,
    int limit,
    int revision
  })? _cachedRequestKey;
  ({
    int creators,
    int favorites,
    int coldStart,
    int limit,
    int revision
  })? _desiredRequestKey;
  _RecommendationRequest? _pendingRequest;
  bool _refreshRunning = false;
  int _generation = 0;
  int _sessionRevision = 0;
  Timer? _saveTimer;
  bool _initialized = false;
  bool _disposed = false;

  RecommendationService({this.disabled = false});

  RecommendationProfile get profile => _profile;
  bool get isInitialized => _initialized;

  Future<void> initialize() async {
    if (disabled) {
      _initialized = true;
      return;
    }
    await _loadProfile();
    _initialized = true;
    notifyListeners();
  }

  List<RecommendationResult> recommendationsFor({
    required List<Creator> creators,
    required Set<int> favoriteIds,
    List<String> coldStartFandoms = const [],
    int limit = 10,
  }) {
    if (disabled || !_initialized) return const [];

    final creatorSignature = Object.hash(
      identityHashCode(creators),
      creators.length,
    );
    final sortedFavorites = favoriteIds.toList()..sort();
    final favoriteSignature = Object.hashAll(sortedFavorites);
    final requestKey = (
      creators: creatorSignature,
      favorites: favoriteSignature,
      coldStart: Object.hashAll(coldStartFandoms),
      limit: limit,
      revision: _sessionRevision,
    );

    if (_cachedRequestKey != requestKey && _desiredRequestKey != requestKey) {
      _cachedRecommendations = null;
      _cachedRequestKey = null;
      _desiredRequestKey = requestKey;
      _generation++;
      _pendingRequest = _RecommendationRequest(
        key: requestKey,
        generation: _generation,
        creators: creators,
        favoriteIds: Set<int>.of(favoriteIds),
        coldStartFandoms: List<String>.of(coldStartFandoms),
        limit: limit,
      );
      if (!_refreshRunning) {
        Timer.run(_processPendingRefresh);
      }
    }

    return _cachedRequestKey == requestKey
        ? _cachedRecommendations ?? const []
        : const [];
  }

  void startNewRecommendationSession() {
    if (disabled) return;
    _sessionRevision++;
    _generation++;
    _cachedRecommendations = null;
    _cachedRequestKey = null;
    _desiredRequestKey = null;
    _pendingRequest = null;
    notifyListeners();
  }

  Future<void> _processPendingRefresh() async {
    if (disabled || _refreshRunning || _disposed) return;
    final request = _pendingRequest;
    if (request == null) return;

    _pendingRequest = null;
    _refreshRunning = true;
    final profileSnapshot = RecommendationProfile.fromJson(_profile.toJson());
    final exposureSnapshot = Set<int>.of(_sessionExposureIds);
    final results = await _engine.recommendAsync(
      creators: request.creators,
      profile: profileSnapshot,
      favoriteIds: request.favoriteIds,
      sessionExposureIds: exposureSnapshot,
      coldStartFandoms: request.coldStartFandoms,
      limit: request.limit,
      isCancelled: () => _disposed || request.generation != _generation,
    );
    _refreshRunning = false;

    if (!_disposed &&
        request.generation == _generation &&
        request.key == _desiredRequestKey) {
      _cachedRecommendations = results;
      _cachedRequestKey = request.key;
      notifyListeners();
    }

    if (_pendingRequest != null && !_disposed) {
      Timer.run(_processPendingRefresh);
    }
  }

  void recordCreatorOpened(
    Creator creator,
    CreatorSelectionSource source,
  ) {
    if (disabled) return;
    _sessionExposureIds.add(creator.id);
    if (source == CreatorSelectionSource.mapTap ||
        source == CreatorSelectionSource.randomButton) {
      return;
    }

    final now = DateTime.now();
    final interaction = _interactionFor(creator.id, now);
    if (interaction.deliberateOpenCount > 0 &&
        now.difference(interaction.lastUpdated) < const Duration(minutes: 30)) {
      return;
    }
    final (openStrength, consideration) = switch (source) {
      CreatorSelectionSource.deepLink => (2.5, 0.30),
      CreatorSelectionSource.searchResult => (2.0, 0.20),
      CreatorSelectionSource.allCreators => (1.5, 0.10),
      CreatorSelectionSource.customList => (1.0, 0.10),
      CreatorSelectionSource.recommendation => (0.5, 0.10),
      CreatorSelectionSource.favorites => (0.5, 1.00),
      CreatorSelectionSource.mapTap || CreatorSelectionSource.randomButton => (
          0.0,
          0.0
        ),
    };

    interaction.openStrength =
        (interaction.openStrength + openStrength).clamp(0.0, 6.0);
    interaction.deliberateOpenCount =
        (interaction.deliberateOpenCount + 1).clamp(0, 5);
    interaction.consideration = interaction.consideration < consideration
        ? consideration
        : interaction.consideration;
    interaction.lastUpdated = now;
    _scheduleSave();
  }

  void recordFandomInterest(String fandom) {
    if (disabled) return;
    final key = optimizeStringFormat(fandom);
    if (key.isEmpty) return;

    final now = DateTime.now();
    final signal = _profile.explicitFandomSignals.putIfAbsent(
      key,
      () => FandomSignal(strength: 0, lastUpdated: now),
    );
    signal.strength = (signal.strength + 5).clamp(0.0, 20.0);
    signal.lastUpdated = now;
    _scheduleSave();
  }

  void recordSampleWorksViewed(Creator creator) {
    if (disabled) return;
    final now = DateTime.now();
    final interaction = _interactionFor(creator.id, now);
    interaction.sampleWorkViews = (interaction.sampleWorkViews + 1).clamp(0, 3);
    interaction.consideration =
        interaction.consideration < 0.5 ? 0.5 : interaction.consideration;
    interaction.lastUpdated = now;
    _scheduleSave();
  }

  void recordExternalLinkOpened(Creator creator) {
    if (disabled) return;
    final now = DateTime.now();
    final interaction = _interactionFor(creator.id, now);
    interaction.externalLinkClicks =
        (interaction.externalLinkClicks + 1).clamp(0, 2);
    interaction.consideration =
        interaction.consideration < 0.6 ? 0.6 : interaction.consideration;
    interaction.lastUpdated = now;
    _scheduleSave();
  }

  void recordCreatorShared(Creator creator) {
    if (disabled) return;
    final now = DateTime.now();
    final interaction = _interactionFor(creator.id, now);
    interaction.shares = (interaction.shares + 1).clamp(0, 2);
    interaction.consideration =
        interaction.consideration < 0.7 ? 0.7 : interaction.consideration;
    interaction.lastUpdated = now;
    _scheduleSave();
  }

  void recordFavoriteChanged(Creator creator, bool favorite) {
    if (disabled) return;
    final now = DateTime.now();
    final interaction = _interactionFor(creator.id, now);
    interaction.favorite = favorite;
    interaction.consideration =
        favorite ? 1.0 : _considerationWithoutFavorite(interaction);
    interaction.lastUpdated = now;
    _scheduleSave();
  }

  Future<void> clearProfile() async {
    if (disabled) return;
    _profile = RecommendationProfile();
    _sessionExposureIds.clear();
    _cachedRecommendations = null;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_storageKey);
    notifyListeners();
  }

  CreatorInteraction _interactionFor(int creatorId, DateTime now) {
    return _profile.creatorInteractions.putIfAbsent(
      creatorId,
      () => CreatorInteraction(lastUpdated: now),
    );
  }

  double _considerationWithoutFavorite(CreatorInteraction interaction) {
    if (interaction.shares > 0) return 0.7;
    if (interaction.externalLinkClicks > 0) return 0.6;
    if (interaction.sampleWorkViews > 0) return 0.5;
    if (interaction.deliberateOpenCount >= 2) return 0.25;
    if (interaction.deliberateOpenCount == 1) return 0.1;
    return 0;
  }

  Future<void> _loadProfile() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_storageKey);
      if (raw == null) return;
      _profile = RecommendationProfile.fromJson(
        json.decode(raw) as Map<String, dynamic>,
      );
    } catch (error) {
      if (kDebugMode) {
        print('Could not load recommendation profile: $error');
      }
      _profile = RecommendationProfile();
    }
  }

  void _scheduleSave() {
    if (disabled) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, _saveProfile);
  }

  Future<void> _saveProfile() async {
    if (disabled) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_storageKey, json.encode(_profile.toJson()));
    } catch (error) {
      if (kDebugMode) {
        print('Could not save recommendation profile: $error');
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _saveTimer?.cancel();
    super.dispose();
  }
}

class _RecommendationRequest {
  final ({
    int creators,
    int favorites,
    int coldStart,
    int limit,
    int revision,
  }) key;
  final int generation;
  final List<Creator> creators;
  final Set<int> favoriteIds;
  final List<String> coldStartFandoms;
  final int limit;

  const _RecommendationRequest({
    required this.key,
    required this.generation,
    required this.creators,
    required this.favoriteIds,
    required this.coldStartFandoms,
    required this.limit,
  });
}
