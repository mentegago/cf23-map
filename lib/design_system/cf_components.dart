import 'package:flutter/material.dart';

import 'cf_theme.dart';

class CfPanel extends StatelessWidget {
  const CfPanel({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.accent,
    this.shadow = true,
    this.borderRadius = 14,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? accent;
  final bool shadow;
  final double borderRadius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cf = context.cf;
    final radius = BorderRadius.only(
      topLeft: Radius.circular(borderRadius),
      topRight: const Radius.circular(4),
      bottomLeft: const Radius.circular(4),
      bottomRight: Radius.circular(borderRadius),
    );
    final panel = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: cf.paperRaised,
        borderRadius: radius,
        border: Border.all(color: cf.ink, width: 1.4),
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: accent ?? cf.hardShadow,
                  offset: const Offset(3, 3),
                  blurRadius: 0,
                ),
              ]
            : null,
      ),
      child: child,
    );

    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: onTap == null
          ? panel
          : Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: radius,
                child: panel,
              ),
            ),
    );
  }
}

class CfKicker extends StatelessWidget {
  const CfKicker(this.label, {super.key, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cf = context.cf;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 16, height: 4, color: color ?? cf.pink),
        const SizedBox(width: 7),
        Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
                color: cf.muted,
              ),
        ),
      ],
    );
  }
}

class CfTag extends StatelessWidget {
  const CfTag({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.onTap,
    this.foregroundColor,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final fill = color ?? Theme.of(context).colorScheme.secondaryContainer;
    final foreground = foregroundColor ?? context.cfForegroundOn(fill);
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: foreground),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
    final decoration = BoxDecoration(
      color: fill,
      border: Border.all(color: foreground, width: 1.1),
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(3),
        topRight: Radius.circular(10),
        bottomLeft: Radius.circular(10),
        bottomRight: Radius.circular(3),
      ),
    );

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: decoration,
        child: InkWell(
          onTap: onTap,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(3),
            topRight: Radius.circular(10),
            bottomLeft: Radius.circular(10),
            bottomRight: Radius.circular(3),
          ),
          child: content,
        ),
      ),
    );
  }
}

class CfActionButton extends StatelessWidget {
  const CfActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.color,
    this.compact = false,
    this.onLongPress,
    this.foregroundColor,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;
  final bool compact;
  final VoidCallback? onLongPress;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final cf = context.cf;
    final fill = color ?? cf.yellow;
    final foreground = foregroundColor ?? context.cfForegroundOn(fill);
    return Opacity(
      opacity: onPressed == null ? 0.45 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: cf.hardShadow,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(9),
            topRight: Radius.circular(3),
            bottomLeft: Radius.circular(3),
            bottomRight: Radius.circular(9),
          ),
        ),
        padding: const EdgeInsets.only(right: 3, bottom: 3),
        child: Material(
          color: fill,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: foreground, width: 1.2),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(9),
              topRight: Radius.circular(3),
              bottomLeft: Radius.circular(3),
              bottomRight: Radius.circular(9),
            ),
          ),
          child: InkWell(
            onTap: onPressed,
            onLongPress: onLongPress,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 10 : 13,
                vertical: compact ? 8 : 10,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: foreground),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CfIconControl extends StatelessWidget {
  const CfIconControl({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
    this.size = 40,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cf = context.cf;
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: color ?? cf.paperRaised,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: cf.ink, width: 1.2),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(12),
            topRight: Radius.circular(4),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(12),
          ),
        ),
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: 20, color: cf.ink),
          ),
        ),
      ),
    );
  }
}

class CfSheetGrip extends StatelessWidget {
  const CfSheetGrip({super.key});

  @override
  Widget build(BuildContext context) {
    final cf = context.cf;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 14, height: 5, color: cf.pink),
          Container(width: 14, height: 5, color: cf.yellow),
          Container(width: 14, height: 5, color: cf.cyan),
        ],
      ),
    );
  }
}
