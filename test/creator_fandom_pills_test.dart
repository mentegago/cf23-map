import 'package:cf_map_flutter/models/creator.dart';
import 'package:cf_map_flutter/models/fandom.dart';
import 'package:cf_map_flutter/widgets/creator_tile.dart';
import 'package:cf_map_flutter/widgets/creator_fandom_pills.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows every fandom as compact wrapping metadata',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 240,
            child: CreatorFandomSummary(
              fandoms: ['Blue Archive', 'Hololive', 'Touhou'],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Blue Archive'), findsOneWidget);
    expect(find.text('Hololive'), findsOneWidget);

    expect(find.text('Touhou'), findsOneWidget);
    expect(find.byType(Wrap), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recommended fandoms use a full-width row below creator details',
      (tester) async {
    var selectedCount = 0;
    final creator = Creator(
      id: 1,
      name: 'Artist Strong',
      spaces: const [
        CreatorSpace(code: 'L-49a'),
        CreatorSpace(code: 'L-49b'),
      ],
      attendanceDates: const ['2026-10-31', '2026-11-01'],
      fandoms: [
        Fandom(
            id: 1, name: 'Dance with Death', kind: 'franchise', parentId: null),
        Fandom(
            id: 2,
            name: 'A Space for the Unbound',
            kind: 'franchise',
            parentId: null),
        Fandom(id: 3, name: 'Alien Stage', kind: 'franchise', parentId: null),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            child: CreatorTile(
              creator: creator,
              onCreatorSelected: (_) => selectedCount++,
              fandoms: creator.fandomNames,
            ),
          ),
        ),
      ),
    );

    final summary = tester.getSize(find.byType(CreatorFandomSummary));
    expect(summary.width, 302);
    final tileHeight = tester.getSize(find.byType(ListTile)).height;
    expect(tileHeight, greaterThanOrEqualTo(48));
    final boothBottom =
        tester.getBottomLeft(find.textContaining('L-49a, L-49b')).dy;
    final fandomTop = tester.getTopLeft(find.text('Dance with Death')).dy;
    expect(fandomTop - boothBottom, lessThanOrEqualTo(10));
    await tester.tap(find.text('Dance with Death'));
    await tester.pump();
    expect(selectedCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('limits metadata and summarizes hidden fandoms', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CreatorFandomSummary(
            fandoms: ['One', 'Two', 'Three', 'Four', 'Five', 'Six'],
          ),
        ),
      ),
    );

    expect(find.text('One'), findsOneWidget);
    expect(find.text('Four'), findsOneWidget);
    expect(find.text('Five'), findsNothing);
    expect(find.text('Six'), findsNothing);
    expect(find.text('+2 more'), findsOneWidget);
  });
}
