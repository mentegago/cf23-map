import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'analytics_delivery.dart';
import 'analytics_store_web.dart';

AnalyticsStore createStore() => IndexedAnalyticsStore();
bool isVisible() => web.document.visibilityState == 'visible';
Map<String, Object> metadata() => {
      'language': web.window.navigator.language,
      'screen': '${web.window.screen.width}x${web.window.screen.height}'
    };
Stream<void> reconnects() {
  late StreamController<void> controller;
  final listener = ((web.Event _) {
    controller.add(null);
  }).toJS;
  controller = StreamController<void>(onListen: () {
    web.window.addEventListener('online', listener);
  }, onCancel: () {
    web.window.removeEventListener('online', listener);
  });
  return controller.stream;
}
