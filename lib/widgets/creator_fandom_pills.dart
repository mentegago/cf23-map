import 'package:flutter/material.dart';

class CreatorFandomSummary extends StatelessWidget {
  final List<String> fandoms;
  final int maxVisible;

  const CreatorFandomSummary({
    super.key,
    required this.fandoms,
    this.maxVisible = 4,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
      height: 1.25,
    );
    final visibleFandoms = fandoms.take(maxVisible).toList(growable: false);
    final hiddenFandoms = fandoms.skip(maxVisible).toList(growable: false);

    return Wrap(
      spacing: 7,
      runSpacing: 3,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var index = 0; index < visibleFandoms.length; index++) ...[
          if (index > 0)
            Container(
              width: 3,
              height: 3,
              decoration: BoxDecoration(
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
            ),
          Text(visibleFandoms[index], style: textStyle),
        ],
        if (hiddenFandoms.isNotEmpty) ...[
          Container(
            width: 3,
            height: 3,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
              shape: BoxShape.circle,
            ),
          ),
          Text(
            '+${hiddenFandoms.length} more',
            style: textStyle?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ],
    );
  }
}
