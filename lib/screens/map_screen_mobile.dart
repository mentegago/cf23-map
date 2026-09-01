import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/creator.dart';
import '../models/map_cell.dart';
import '../services/creator_data_service.dart';
import '../widgets/fab_button.dart';
import '../widgets/map_viewer.dart';
import '../widgets/mobile/creator_detail_sheet.dart';
import '../widgets/mobile/expandable_search.dart';
import '../widgets/mobile/mobile_sheet_detent.dart';
import '../widgets/version_notification.dart';
import '../design_system/cf_design_system.dart';

class MapScreenMobileView extends StatefulWidget {
  final List<MergedCell> mergedCells;
  final int rows;
  final int cols;
  final Future<void> Function() onClearSelection;
  final void Function(Creator, {required String source, String searchQuery})
      onCreatorSelected;
  final void Function(String?) onBoothTap;

  const MapScreenMobileView({
    super.key,
    required this.mergedCells,
    required this.rows,
    required this.cols,
    required this.onClearSelection,
    required this.onCreatorSelected,
    required this.onBoothTap,
  });

  @override
  State<MapScreenMobileView> createState() => _MapScreenMobileViewState();
}

class _MapScreenMobileViewState extends State<MapScreenMobileView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _detailAnimationController;
  late final Animation<Offset> _detailSlideAnimation;
  final GlobalKey<ExpandableSearchState> _expandableSearchKey =
      GlobalKey<ExpandableSearchState>();
  final DraggableScrollableController _detailSheetController =
      DraggableScrollableController();
  Creator? _visibleCreator;
  int? _lastCreatorId;
  bool _isAnimatingOut = false;
  bool _isPresentingDetail = false;
  bool _isDetailVisible = false;
  bool _isMainSheetVisible = true;
  MobileSearchSheetDetent _rememberedMainDetent =
      MobileSearchSheetDetent.collapsed;

  @override
  void initState() {
    super.initState();
    _detailAnimationController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    _detailSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _detailAnimationController,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );
  }

  @override
  void dispose() {
    _detailAnimationController.dispose();
    _detailSheetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final creators = context.select((CreatorDataProvider p) => p.creators);
    final selectedCreator =
        context.select((CreatorDataProvider p) => p.selectedCreator);
    final isCreatorCustomListMode =
        context.select((CreatorDataProvider p) => p.isCreatorCustomListMode);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncVisibleCreator(selectedCreator);
    });

    return Stack(
      children: [
        MapViewer(
          mergedCells: widget.mergedCells,
          rows: widget.rows,
          cols: widget.cols,
          onBoothTap: widget.onBoothTap,
        ),
        const FABButton(isDesktop: false),
        if (isCreatorCustomListMode)
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: CfPanel(
              accent: context.cf.pink,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CfKicker('Curated route'),
                  const SizedBox(height: 8),
                  Text(
                    "You're viewing a curated creator list",
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Only the creators selected by the list owner are shown on the map. Tap the search box above to see the creator list.",
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
        const VersionNotification(isDesktop: false),
        if (creators != null)
          Visibility(
            visible: _isMainSheetVisible,
            maintainState: true,
            maintainAnimation: true,
            maintainSize: true,
            child: ExpandableSearch(
              key: _expandableSearchKey,
              creators: creators,
              onCreatorSelected: widget.onCreatorSelected,
              selectedCreator: selectedCreator,
            ),
          ),
        if (_visibleCreator != null && _isDetailVisible)
          SlideTransition(
            position: _detailSlideAnimation,
            child: CreatorDetailSheet(
              creator: _visibleCreator!,
              controller: _detailSheetController,
              onClose: _dismissDetail,
              onRequestSearch: _handleRequestSearch,
            ),
          ),
      ],
    );
  }

  void _handleRequestSearch(String query) {
    _rememberedMainDetent = MobileSearchSheetDetent.expanded;
    _expandableSearchKey.currentState?.performSearch(query);
    _dismissDetail();
  }

  void _syncVisibleCreator(Creator? selected) {
    if (!mounted || _isAnimatingOut) return;
    final selectedId = selected?.id;

    if (selected != null) {
      final isNewSelection =
          selectedId != _lastCreatorId || !identical(selected, _visibleCreator);
      if (isNewSelection) {
        setState(() {
          _visibleCreator = selected;
          _lastCreatorId = selectedId;
        });
      }
      if (!_isDetailVisible && !_isPresentingDetail) {
        _presentDetail();
      }
    } else {
      if (_visibleCreator != null && !_isDetailVisible) {
        setState(() {
          _visibleCreator = null;
          _lastCreatorId = null;
        });
      }
    }
  }

  void _presentDetail() {
    _isPresentingDetail = true;
    final mainSheet = _expandableSearchKey.currentState;
    _rememberedMainDetent =
        mainSheet?.currentDetent ?? MobileSearchSheetDetent.collapsed;

    if (_rememberedMainDetent == MobileSearchSheetDetent.expanded) {
      mainSheet?.resizeBehindDetail();
    }

    setState(() {
      _isMainSheetVisible = false;
      _isDetailVisible = true;
    });
    _detailAnimationController.forward(from: 0);
    _isPresentingDetail = false;
  }

  void _dismissDetail() {
    if (_visibleCreator == null) {
      widget.onClearSelection();
      return;
    }
    if (_isAnimatingOut) return;

    _isAnimatingOut = true;
    _finishDismissingDetail();
  }

  Future<void> _finishDismissingDetail() async {
    final mainSheet = _expandableSearchKey.currentState;
    final detailExtent = _detailSheetController.isAttached
        ? _detailSheetController.size
        : MobileSheetDetent.partiallyExpanded.extent;

    if (detailExtent < MobileSheetDetent.partiallyExpanded.extent - 0.01) {
      mainSheet?.jumpToDetent(MobileSearchSheetDetent.collapsed);
    }

    if (!mounted) return;
    setState(() {
      _isMainSheetVisible = true;
    });

    await Future.wait([
      _detailAnimationController.reverse(),
      if (mainSheet != null) mainSheet.animateToDetent(_rememberedMainDetent),
    ]);

    if (!mounted) return;
    setState(() {
      _visibleCreator = null;
      _lastCreatorId = null;
      _isDetailVisible = false;
    });
    await widget.onClearSelection();
    if (mounted) {
      _isAnimatingOut = false;
    }
  }
}
