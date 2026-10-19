import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/booth_proximity.dart';
import '../models/map_cell.dart';
import 'catalog_snapshot_cache.dart';
import 'map_parser.dart';

/// Keeps the visible map available while a complete replacement downloads.
class MapDataService extends ChangeNotifier {
  static final configBase = Uri.parse('https://cf23-config.nnt.gg/');
  final bool enableRemoteUpdates;
  final CatalogSnapshotCache _cache;
  final http.Client _client;
  final AssetBundle _bundle;
  final Duration updateInterval;
  MapSnapshot? _snapshot;
  Timer? _timer;
  bool _checking = false;
  bool _disposed = false;
  Future<void>? _initializing;

  MapDataService({
    this.enableRemoteUpdates = true,
    this.updateInterval = const Duration(hours: 1),
    CatalogSnapshotCache? cache,
    http.Client? client,
    AssetBundle? bundle,
  })  : _cache = cache ?? CatalogSnapshotCache(namespace: 'map'),
        _client = client ?? http.Client(),
        _bundle = bundle ?? rootBundle;

  MapLayout? get layout => _snapshot?.layout;
  BoothProximityData? get proximity => _snapshot?.proximity;
  int? get version => _snapshot?.version;

  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    try {
      final version =
          jsonDecode(await _bundle.loadString('data/map-version.json'))
              as Map<String, dynamic>;
      MapSnapshot? cached;
      try {
        final raw = await _cache.read();
        if (raw != null) cached = await compute(parseMapSnapshot, raw);
      } catch (error) {
        if (kDebugMode) print('Ignoring invalid cached map: $error');
      }
      final bundledVersion = (version['version'] as num).toInt();
      if (cached != null && cached.version >= bundledVersion) {
        _snapshot = cached;
      } else {
        final documents = await Future.wait([
          _bundle.loadString('data/map.json'),
          _bundle.loadString('data/booth-proximity.json'),
        ]);
        _snapshot = await compute(
            parseMapSnapshot,
            jsonEncode({
              'version': bundledVersion,
              'layout': jsonDecode(documents[0]),
              'proximity': jsonDecode(documents[1]),
            }));
      }
      if (_disposed) return;
      notifyListeners();
      if (enableRemoteUpdates) {
        _timer = Timer.periodic(updateInterval, (_) => checkForUpdates());
        unawaited(checkForUpdates());
      }
    } catch (_) {
      _initializing = null;
      rethrow;
    }
  }

  Future<void> checkForUpdates() async {
    if (!enableRemoteUpdates || _disposed || _checking || _snapshot == null) {
      return;
    }
    _checking = true;
    try {
      final manifest =
          jsonDecode(await _fetch(configBase.resolve('manifest.json')))
              as Map<String, dynamic>;
      final descriptor = manifest['map'];
      if (descriptor == null) return;
      final remoteVersion = (descriptor['version'] as num).toInt();
      if (remoteVersion <= _snapshot!.version) return;
      final uri = configBase.resolve(descriptor['path'] as String);
      if (uri.origin != configBase.origin) {
        throw const FormatException('Map must use the config origin');
      }
      final raw = await _fetch(uri);
      final next = await compute(parseMapSnapshot, raw);
      if (_disposed) return;
      if (next.version != remoteVersion) {
        throw const FormatException('Map version does not match manifest');
      }
      _snapshot = next;
      notifyListeners();
      await _cache.write(raw);
    } catch (error) {
      // Offline, partial deployments, and bad data keep the last usable map.
      if (kDebugMode) print('Could not update map: $error');
    } finally {
      _checking = false;
    }
  }

  Future<String> _fetch(Uri uri) async {
    final response = await _client
        .get(uri.replace(queryParameters: {
          ...uri.queryParameters,
          't': DateTime.now().millisecondsSinceEpoch.toString(),
        }))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError('${uri.path} returned HTTP ${response.statusCode}');
    }
    return utf8.decode(response.bodyBytes);
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _client.close();
    super.dispose();
  }
}

class MapSnapshot {
  final int version;
  final MapLayout layout;
  final BoothProximityData proximity;

  const MapSnapshot(this.version, this.layout, this.proximity);
}

/// Parsing happens off the UI isolate on native platforms.
MapSnapshot parseMapSnapshot(String raw) {
  final document = jsonDecode(raw) as Map<String, dynamic>;
  final version = document['version'];
  if (version is! int || version < 1) {
    throw const FormatException('Invalid map version');
  }
  final source = document['layout'];
  if (source is Map && source['schemaVersion'] != 2) {
    throw const FormatException('Unsupported map schema');
  }
  final layout = MapParser.parseMapLayout(source);
  if (!layout.width.isFinite ||
      !layout.height.isFinite ||
      layout.width <= 0 ||
      layout.height <= 0 ||
      layout.features.isEmpty) {
    throw const FormatException('Invalid map bounds or empty map');
  }
  for (final feature in layout.features) {
    if (![
      feature.x,
      feature.y,
      feature.width,
      feature.height,
      feature.rotation,
      feature.thickness,
      feature.right,
      feature.bottom,
      feature.lineStartX ?? 0,
      feature.lineStartY ?? 0,
      feature.lineEndX ?? 0,
      feature.lineEndY ?? 0,
      feature.fontSize ?? 0,
    ].every((value) => value.isFinite)) {
      throw const FormatException('Invalid map feature geometry');
    }
  }
  final proximity = BoothProximityData.fromJson(
      document['proximity'] as Map<String, dynamic>);
  return MapSnapshot(version, layout, proximity);
}
