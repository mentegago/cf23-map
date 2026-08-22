import 'package:cf_map_flutter/models/creator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import 'creator_avatar.dart';
import 'creator_fandom_pills.dart';
import 'sample_works_gallery.dart';

class CreatorTile extends StatefulWidget {
  const CreatorTile({
    super.key,
    required this.creator,
    required this.onCreatorSelected,
    this.recommendationFandoms = const [],
  });

  final Creator creator;
  final Function(Creator) onCreatorSelected;
  final List<String> recommendationFandoms;

  @override
  State<CreatorTile> createState() => _CreatorTileState();
}

class _CreatorTileState extends State<CreatorTile> {
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

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onHover: _handleHover,
      onExit: _handleExit,
      child: Container(
        color: _isHovered
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6)
            : Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: CreatorAvatar(creator: widget.creator),
              trailing: widget.creator.sampleworksImages.isNotEmpty
                  ? IconButton(
                      icon: widget.creator.sampleworksImages.length > 1
                          ? const Icon(Icons.photo_library)
                          : const Icon(Icons.photo),
                      onPressed: () {
                        showSampleWorksGallery(
                          context: context,
                          imageUrls: widget.creator.sampleworksImages,
                          creator: widget.creator,
                        );
                      },
                    )
                  : null,
              title: Text(
                widget.creator.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${widget.creator.boothsDisplay} • ${widget.creator.dayDisplay}',
                style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
              onTap: () => widget.onCreatorSelected(widget.creator),
            ),
            if (widget.recommendationFandoms.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 0, 10),
                child: CreatorFandomPills(
                  key: ValueKey('creator-fandoms-${widget.creator.id}'),
                  fandoms: widget.recommendationFandoms,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
