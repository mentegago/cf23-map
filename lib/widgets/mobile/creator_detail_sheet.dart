import 'package:flutter/material.dart';
import '../../models/creator.dart';
import '../creator_detail_content.dart';
import 'mobile_sheet_detent.dart';

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
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.2),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ListView(
            controller: scrollController,
            children: [
              // Handle bar
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Content
              CreatorDetailContent(
                creator: creator,
                showFavoriteButton: true,
                showShareButton: true,
                showCloseButton: true,
                onClose: onClose,
                onRequestSearch: onRequestSearch,
              ),
            ],
          ),
        );
      },
    );
  }
}
