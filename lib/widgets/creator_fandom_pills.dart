import 'package:flutter/material.dart';

class CreatorFandomPills extends StatelessWidget {
  final List<String> fandoms;

  const CreatorFandomPills({
    super.key,
    required this.fandoms,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: fandoms.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final fandom = fandoms[index];

          return Chip(
            label: Text(
              fandom,
              style: theme.textTheme.labelSmall,
            ),
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            side: BorderSide(
              color: theme.colorScheme.outline.withValues(alpha: 0.2),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4),
          );
        },
      ),
    );
  }
}
