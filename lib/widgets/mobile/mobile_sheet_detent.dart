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

const mobileSheetAnimationDuration = Duration(milliseconds: 320);
