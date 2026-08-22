enum MobileSheetDetent {
  collapsed(0.28),
  partiallyExpanded(0.56),
  expanded(0.94);

  const MobileSheetDetent(this.extent);

  final double extent;

  static MobileSheetDetent nearest(double extent) {
    return values.reduce(
      (current, candidate) =>
          (candidate.extent - extent).abs() < (current.extent - extent).abs()
              ? candidate
              : current,
    );
  }
}

enum MobileSearchSheetDetent { collapsed, expanded }

abstract final class MobileSearchSheetLayout {
  static const double headerHeight = 132;
  static const double minimumBottomSafeArea = 24;
  static const double minimumCollapsedExtent = 0.16;
  static const double maximumCollapsedExtent = 0.24;

  static double effectiveBottomSafeArea(double reportedBottomSafeArea) {
    return reportedBottomSafeArea < minimumBottomSafeArea
        ? minimumBottomSafeArea
        : reportedBottomSafeArea;
  }

  static double collapsedExtent({
    required double availableHeight,
    required double bottomSafeArea,
  }) {
    final effectiveSafeArea = effectiveBottomSafeArea(bottomSafeArea);
    return ((headerHeight + effectiveSafeArea) / availableHeight)
        .clamp(minimumCollapsedExtent, maximumCollapsedExtent)
        .toDouble();
  }
}

const mobileSheetAnimationDuration = Duration(milliseconds: 320);
