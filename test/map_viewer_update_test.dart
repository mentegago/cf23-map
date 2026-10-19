import 'package:cf_map_flutter/models/creator.dart';
import 'package:cf_map_flutter/models/map_cell.dart';
import 'package:cf_map_flutter/services/analytics_service.dart';
import 'package:cf_map_flutter/services/creator_data_service.dart';
import 'package:cf_map_flutter/widgets/map_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

MapLayout layout(double x, String booth) => MapLayout(
      features: [
        MapFeature(
            uid: 'booth',
            content: booth,
            kind: 'booth',
            x: x,
            y: 80,
            width: 30,
            height: 40)
      ],
      width: 500,
      height: 300,
      schemaVersion: 2,
    );

void main() {
  for (final desktop in [true, false]) {
    for (final initiallySelected in [true, false]) {
      testWidgets(
          '${desktop ? 'desktop' : 'mobile'} focuses a creator selected ${initiallySelected ? 'before' : 'after'} mounting',
          (tester) async {
        tester.view.physicalSize = Size(desktop ? 1100 : 390, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final creators = CreatorDataProvider(enableRemoteUpdates: false);
        final analytics = AnalyticsService(enabled: false);
        addTearDown(creators.dispose);
        addTearDown(analytics.dispose);
        final creator = Creator(
          id: 1000077,
          name: 'AMAPro.',
          spaces: const [CreatorSpace(code: 'AC-30')],
          attendanceDates: const [],
        );
        if (initiallySelected) creators.setSelectedCreator(creator);
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: creators),
            Provider.value(value: analytics),
          ],
          child: MaterialApp(
            home: Scaffold(body: MapViewer(mapLayout: layout(10, 'AC-30'))),
          ),
        ));
        if (!initiallySelected) creators.setSelectedCreator(creator);
        final viewer =
            tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
        final initialTransform = viewer.transformationController!.value.clone();
        // Focusing waits for layout before starting the camera animation.
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pumpAndSettle();
        final transform = viewer.transformationController!.value;
        expect(transform, isNot(initialTransform));
        final boothCenter =
            MatrixUtils.transformPoint(transform, const Offset(25, 100));
        final viewport = tester.getSize(find.byType(InteractiveViewer));
        expect(boothCenter.dx, closeTo(viewport.width / 2, 0.01));
        expect(
            boothCenter.dy, closeTo(viewport.height / (desktop ? 2 : 3), 0.01));
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('a live update preserves viewport and replaces booth hit targets',
      (tester) async {
    final creators = CreatorDataProvider(enableRemoteUpdates: false);
    final analytics = AnalyticsService(enabled: false);
    addTearDown(creators.dispose);
    addTearDown(analytics.dispose);
    var current = layout(10, 'A-01');
    late StateSetter update;
    String? tapped;
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: creators),
        Provider.value(value: analytics),
      ],
      child: MaterialApp(
          home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
        update = setState;
        return MapViewer(
            mapLayout: current, onBoothTap: (booth) => tapped = booth);
      }))),
    ));
    await tester.pump();
    final viewer =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    final controller = viewer.transformationController!;
    final viewport = Matrix4.identity()
      ..translate(20.0, 30.0)
      ..scale(1.2);
    controller.value = viewport.clone();
    update(() => current = layout(100, 'B-02'));
    await tester.pump();
    await tester.pump();
    expect(controller.value, viewport);
    final origin = tester.getTopLeft(find.byType(InteractiveViewer));
    await tester.tapAt(origin + const Offset(158, 150));
    expect(tapped, 'B-02');
    await tester.tapAt(origin + const Offset(50, 150));
    expect(tapped, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
