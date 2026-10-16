import '../services/deep_link_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cf_map_flutter/services/analytics_service.dart';
import '../services/map_parser.dart';
import '../services/creator_data_service.dart';
import '../utils/browser_navigation.dart';
import '../widgets/mobile/creator_selector_sheet.dart';
import '../models/map_cell.dart';
import '../models/creator.dart';
import '../models/recommendation.dart';
import '../services/recommendation_service.dart';
import '../services/search_tracking_controller.dart';
import 'map_screen_desktop.dart';
import 'map_screen_mobile.dart';
import 'dart:async';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _startup = Stopwatch()..start();
  MapLayout? _mapLayout;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMapData();
  }

  Future<void> _loadMapData() async {
    try {
      final startTime = DateTime.now();

      final layout = await MapParser.loadMapLayout();
      if (!mounted) return;

      print(
          'Map data loaded in ${DateTime.now().difference(startTime).inMilliseconds}ms');
      print('Loaded ${layout.features.length} map features');

      setState(() {
        _mapLayout = layout;
        _isLoading = false;
      });

      // Handle query parameter if booth is specified in URL
      _handleQueryParameters();
    } catch (e) {
      if (!mounted) return;
      context
          .read<AnalyticsService>()
          .failure(Operation.mapLoad, FailureCode.unavailable);
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _handleCreatorSelected(Creator creator,
      {required String source, String searchQuery = ''}) {
    context.read<RecommendationService>().recordCreatorOpened(
          creator,
          creatorSelectionSourceFromString(
            source,
            searchQuery: searchQuery,
          ),
        );

    final creatorProvider = context.read<CreatorDataProvider>();
    final tracking = context.read<SearchTrackingController>();
    final searchId = source == 'list' ? tracking.result(searchQuery) : null;
    if (source != 'list') tracking.reset();
    final selection = switch (source) {
      'map' => SelectionSource.map,
      'recommendation' => SelectionSource.recommendation,
      'deeplink' || 'deeplink_search_bar' => SelectionSource.deeplink,
      _ =>
        searchId == null ? SelectionSource.list : SelectionSource.searchResult,
    };
    final results = searchId == null
        ? <Creator>[]
        : creatorProvider.searchCreators(searchQuery);
    creatorProvider.setSelectedCreator(creator,
        source: selection,
        searchId: searchId,
        position: searchId == null
            ? null
            : results.indexWhere((c) => c.id == creator.id) + 1);
    context.read<AnalyticsService>().searchClosed(reason: 'creator_selected');
    _updateQueryParametersIfNeeded(creator.id);
  }

  Future<void> _clearSelection() async {
    final creatorProvider = context.read<CreatorDataProvider>();
    if (creatorProvider.selectedCreator != null) {
      creatorProvider.setSelectedCreator(null);
    }
    _updateQueryParametersIfNeeded(null);
  }

  void _handleBoothTap(String? boothId) {
    if (boothId == null) {
      context.read<AnalyticsService>().boothSelected(0);
      return;
    }

    final creatorProvider = context.read<CreatorDataProvider>();
    final boothToCreators = creatorProvider.boothToCreators;
    if (boothToCreators == null) return;

    final creators = boothToCreators[boothId];
    context.read<AnalyticsService>().boothSelected(creators?.length ?? 0);
    if (creators == null || creators.isEmpty) return;

    if (creators.length == 1) {
      _handleCreatorSelected(creators.first, source: 'map');
    } else {
      showModalBottomSheet(
        context: context,
        builder: (context) => CreatorSelectorSheet(
          boothId: boothId,
          creators: creators,
          onCreatorSelected: (creator) =>
              _handleCreatorSelected(creator, source: 'map'),
        ),
      );
    }
  }

  void _updateQueryParametersIfNeeded(int? creatorId) {
    if (kIsWeb) {
      final uri = Uri.parse(browserCurrentUrl());
      final creatorParam = uri.queryParameters['creator'];
      final creatorIdParam =
          int.tryParse(uri.queryParameters['creator_id'] ?? '');

      if (creatorParam != null || creatorIdParam != null) {
        browserPushState(creatorId != null ? '/?creator_id=$creatorId' : '/');
      }
    }
  }

  void _handleQueryParameters() {
    context.read<CreatorDataProvider>().onCreatorDataServiceInitialized(() {
      if (!mounted) return;
      final catalog = context.read<CreatorDataProvider>();
      context
          .read<AnalyticsService>()
          .ready(_startup.elapsedMilliseconds, catalog.catalogSource);
      applyDeepLink(
          browserCurrentUrl(),
          context.read<CreatorDataProvider>(),
          context.read<AnalyticsService>(),
          (creator) => _handleCreatorSelected(creator, source: 'deeplink'),
          initial: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.select(
        (CreatorDataProvider creatorProvider) => creatorProvider.isLoading);
    final error = context
        .select((CreatorDataProvider creatorProvider) => creatorProvider.error);

    return Scaffold(
        body: Stack(
      children: [
        _isLoading || isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null || error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error, color: Colors.red, size: 48),
                          const SizedBox(height: 16),
                          Text('Error loading map: ${_error ?? error}'),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _isLoading = true;
                                _error = null;
                              });
                              _loadMapData();
                            },
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _isDesktop
                    ? _buildDesktopLayout(context)
                    : _buildMobileLayout(context),
        // Clean snackbar listener
        _StatusSnackbarListener(),
      ],
    ));
  }

  bool get _isDesktop {
    final screenWidth = MediaQuery.of(context).size.width;
    return screenWidth > 768; // Breakpoint for desktop layout
  }

  Widget _buildDesktopLayout(BuildContext context) {
    return MapScreenDesktopView(
      mapLayout: _mapLayout!,
      onCreatorSelected: _handleCreatorSelected,
      onClearSelection: _clearSelection,
      onBoothTap: _handleBoothTap,
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return MapScreenMobileView(
      mapLayout: _mapLayout!,
      onClearSelection: _clearSelection,
      onCreatorSelected: _handleCreatorSelected,
      onBoothTap: _handleBoothTap,
    );
  }
}

class _StatusSnackbarListener extends StatefulWidget {
  @override
  _StatusSnackbarListenerState createState() => _StatusSnackbarListenerState();
}

class _StatusSnackbarListenerState extends State<_StatusSnackbarListener> {
  CreatorDataStatus? _previousStatus;

  @override
  Widget build(BuildContext context) {
    return Consumer<CreatorDataProvider>(
      builder: (context, provider, child) {
        // Only show snackbar when status actually changes
        if (_previousStatus != provider.status) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              if (provider.status == CreatorDataStatus.updated) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Creator booth list updated'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            }
          });
          _previousStatus = provider.status;
        }
        return const SizedBox.shrink();
      },
    );
  }
}
