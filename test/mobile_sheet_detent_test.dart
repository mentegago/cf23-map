import 'package:cf_map_flutter/widgets/mobile/mobile_sheet_detent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile sheet extents are ordered', () {
    expect(
      MobileSheetDetent.values.map((detent) => detent.extent),
      orderedEquals([0.28, 0.56, 0.94]),
    );
  });

  test('nearest resolves an in-flight extent to a named detent', () {
    expect(
      MobileSheetDetent.nearest(0.31),
      MobileSheetDetent.collapsed,
    );
    expect(
      MobileSheetDetent.nearest(0.61),
      MobileSheetDetent.partiallyExpanded,
    );
    expect(
      MobileSheetDetent.nearest(0.9),
      MobileSheetDetent.expanded,
    );
  });
}
