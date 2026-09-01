import 'package:cf_map_flutter/models/creator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../design_system/cf_theme.dart';
import 'creator_avatar.dart';
import 'creator_fandom_pills.dart';
import 'sample_works_gallery.dart';

class CreatorTile extends StatefulWidget {
  const CreatorTile({
    super.key,
    required this.creator,
    required this.onCreatorSelected,
    this.fandoms = const [],
  });

  final Creator creator;
  final Function(Creator) onCreatorSelected;
  final List<String> fandoms;

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
        margin: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(
          color: _isHovered
              ? context.cf.cyan.withValues(alpha: 0.10)
              : Colors.transparent,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                mouseCursor: SystemMouseCursors.click,
                onTap: () => widget.onCreatorSelected(widget.creator),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      mouseCursor: SystemMouseCursors.click,
                      minVerticalPadding: 4,
                      visualDensity: const VisualDensity(vertical: -1),
                      leading: CreatorAvatar(creator: widget.creator),
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
                      title: Text(
                        widget.creator.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${widget.creator.boothsDisplay}  /  ${widget.creator.dayDisplay}',
                        style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.2),
                      ),
                    ),
                    if (widget.fandoms.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
                        child: CreatorFandomSummary(
                          key: ValueKey('creator-fandoms-${widget.creator.id}'),
                          fandoms: widget.fandoms,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ],
        ),
      ),
    );
  }
}
