import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/map_screen.dart';
import 'services/analytics_service.dart';
import 'services/favorites_service.dart';
import 'services/creator_data_service.dart';
import 'services/recommendation_service.dart';
import 'services/search_tracking_controller.dart';
import 'design_system/cf_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final disableRecommendations = _recommendationsDisabled(Uri.base);
  final analytics = AnalyticsService.production()..start();
  final creatorDataProvider = CreatorDataProvider(analytics: analytics)
    ..initialize();
  final favoritesService =
      FavoritesService(creatorDataProvider, analytics: analytics)..initialize();
  final recommendationService = RecommendationService(
    disabled: disableRecommendations,
  )..initialize();

  runApp(CFMapApp(
    creatorDataProvider: creatorDataProvider,
    favoritesService: favoritesService,
    recommendationService: recommendationService,
    analytics: analytics,
  ));
}

bool _recommendationsDisabled(Uri uri) {
  final value = uri.queryParameters['disable_recommendations']?.toLowerCase();
  return value == '1' || value == 'true';
}

class CFMapApp extends StatelessWidget {
  final AnalyticsService? analytics;
  final CreatorDataProvider creatorDataProvider;
  final FavoritesService favoritesService;
  final RecommendationService recommendationService;
  const CFMapApp({
    super.key,
    required this.creatorDataProvider,
    required this.favoritesService,
    required this.recommendationService,
    this.analytics,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AnalyticsService>(
            create: (_) => analytics ?? AnalyticsService(enabled: false),
            dispose: (_, service) {
              service.dispose();
            }),
        Provider<SearchTrackingController>(
            create: (context) => SearchTrackingController(
                context.read<AnalyticsService>(), creatorDataProvider),
            dispose: (_, service) => service.dispose()),
        ChangeNotifierProvider(
          create: (context) => creatorDataProvider,
        ),
        ChangeNotifierProvider(
          create: (context) => favoritesService,
        ),
        ChangeNotifierProvider(
          create: (context) => recommendationService,
        ),
      ],
      child: MaterialApp(
        title: 'CF23 Booth Map',
        theme: buildCfTheme(Brightness.light),
        darkTheme: buildCfTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: const MapScreen(),
        builder: (context, child) => NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollUpdateNotification &&
                  notification.dragDetails != null) {
                context.read<AnalyticsService>().activity();
              }
              return false;
            },
            child: child!),
      ),
    );
  }
}
