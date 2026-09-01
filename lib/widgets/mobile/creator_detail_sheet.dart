import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../models/creator.dart';
import '../creator_detail_content.dart';
import 'mobile_sheet_detent.dart';
import '../../design_system/cf_design_system.dart';

class CreatorDetailSheet extends StatelessWidget {
  final Creator creator;
  final VoidCallback onClose;
  final Function(String) onRequestSearch;
  final DraggableScrollableController controller;

  const CreatorDetailSheet({
    super.key,
    required this.creator,
    required this.onClose,
    required this.onRequestSearch,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return DraggableScrollableSheet(
      controller: controller,
      initialChildSize: MobileSheetDetent.partiallyExpanded.extent,
      minChildSize: MobileSheetDetent.collapsed.extent,
      maxChildSize: MobileSheetDetent.expanded.extent,
      snap: true,
      snapSizes: [MobileSheetDetent.partiallyExpanded.extent],
      snapAnimationDuration: mobileSheetAnimationDuration,
      shouldCloseOnMinExtent: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(color: context.cf.ink, width: 1.5),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.2),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Stack(
            children: [
              ListView(
                controller: scrollController,
                children: [
                  const Center(child: CfSheetGrip()),
                  CreatorDetailContent(
                    creator: creator,
                    showFavoriteButton: false,
                    showShareButton: false,
                    showCloseButton: false,
                    onRequestSearch: onRequestSearch,
                  ),
                ],
              ),
              AnimatedBuilder(
                animation: scrollController,
                builder: (context, child) {
                  final offset = scrollController.hasClients
                      ? scrollController.offset
                      : 0.0;
                  return Positioned(
                    top: math.max(8, 39 - offset),
                    right: 16,
                    child: child!,
                  );
                },
                child: CreatorDetailActions(
                  creator: creator,
                  showFavoriteButton: true,
                  showShareButton: true,
                  showCloseButton: true,
                  onClose: onClose,
                  onShare: () => shareCreator(context, creator),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
