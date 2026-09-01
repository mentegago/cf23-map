import 'package:cf_map_flutter/widgets/mobile/mobile_sheet_detent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('creator detail sheet extents are ordered', () {
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

  test('search collapsed extent follows its header and safe area', () {
    expect(
      MobileSearchSheetLayout.collapsedExtent(
        availableHeight: 844,
        bottomSafeArea: 34,
      ),
      closeTo(0.197, 0.001),
    );
    expect(
      MobileSearchSheetLayout.collapsedExtent(
        availableHeight: 844,
        bottomSafeArea: 0,
      ),
      closeTo(0.16, 0.001),
    );
    expect(
      MobileSearchSheetLayout.effectiveBottomSafeArea(0),
      0,
    );
    expect(
      MobileSearchSheetLayout.effectiveBottomSafeArea(
        0,
        useGestureNavigationFallback: true,
      ),
      MobileSearchSheetLayout.iosGestureNavigationFallback,
    );
    expect(
      MobileSearchSheetLayout.collapsedHeaderBottomInset(
        bottomSafeArea: 24,
        expansionProgress: 0,
      ),
      24,
    );
    expect(
      MobileSearchSheetLayout.collapsedHeaderBottomInset(
        bottomSafeArea: 24,
        expansionProgress: 1,
      ),
      0,
    );
  });
}
