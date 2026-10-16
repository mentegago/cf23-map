import 'analytics_delivery.dart';

AnalyticsStore createStore() => MemoryAnalyticsStore();
bool isVisible() => true;
Map<String, Object> metadata() => {'language': 'en', 'screen': '0x0'};
Stream<void> reconnects() => const Stream.empty();
