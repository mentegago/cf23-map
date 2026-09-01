import 'package:cf_map_flutter/models/creator.dart';
import 'package:cf_map_flutter/models/fandom.dart';
import 'package:cf_map_flutter/widgets/creator_tile.dart';
import 'package:cf_map_flutter/widgets/creator_fandom_pills.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows every fandom in a horizontal list', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 240,
            child: CreatorFandomPills(
              fandoms: ['Blue Archive', 'Hololive', 'Touhou'],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Blue Archive'), findsOneWidget);
    expect(find.text('Hololive'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(-240, 0));
    await tester.pumpAndSettle();

    expect(find.text('Touhou'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recommended fandoms use a full-width row below creator details',
      (tester) async {
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
              onCreatorSelected: (_) {},
              recommendationFandoms: creator.fandomNames,
            ),
          ),
        ),
      ),
    );

    final pills = tester.getSize(find.byType(CreatorFandomPills));
    expect(pills.width, 374);
    expect(tester.takeException(), isNull);
  });
}
