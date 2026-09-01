import 'package:cf_map_flutter/widgets/creator_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../design_system/cf_design_system.dart';
import '../models/creator.dart';
import 'sample_works_gallery.dart';

class CreatorTileFeatured extends StatefulWidget {
  const CreatorTileFeatured(
      {super.key, required this.creator, required this.onCreatorSelected});

  final Creator creator;
  final Function(Creator) onCreatorSelected;

  @override
  State<CreatorTileFeatured> createState() => _CreatorTileFeaturedState();
}

class _CreatorTileFeaturedState extends State<CreatorTileFeatured> {
  bool _isHovered = false;

  void _handleHover(PointerEvent event) {
    // Ignore hover events from touch devices
    if (event.kind == PointerDeviceKind.touch) {
      return;
    }

    if (!_isHovered) {
      setState(() {
        _isHovered = true;
      });
    }
  }

  void _handleExit(PointerEvent event) {
    // Ignore exit events from touch devices
    if (event.kind == PointerDeviceKind.touch) {
      return;
    }

    if (_isHovered) {
      setState(() {
        _isHovered = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          onHover: _handleHover,
          onExit: _handleExit,
          child: CfPanel(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            accent: context.cf.cyan,
            padding: EdgeInsets.zero,
            child: Container(
              color: _isHovered
                  ? context.cf.cyan.withValues(alpha: 0.16)
                  : Colors.transparent,
              child: ListTile(
                mouseCursor: SystemMouseCursors.click,
                leading: CreatorAvatar(creator: widget.creator),
                title: Text(
                  widget.creator.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${widget.creator.boothsDisplay}  /  ${widget.creator.dayDisplay}',
                  style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600),
                ),
                trailing: widget.creator.assets.gallery.isNotEmpty
                    ? IconButton(
                        icon: widget.creator.assets.gallery.length > 1
                            ? const Icon(Icons.photo_library)
                            : const Icon(Icons.photo),
                        onPressed: () {
                          showSampleWorksGallery(
                            context: context,
                            imageUrls: widget.creator.assets.gallery,
                            creator: widget.creator,
                          );
                        },
                      )
                    : null,
                onTap: () => widget.onCreatorSelected(widget.creator),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
