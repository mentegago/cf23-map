import 'package:flutter/material.dart';
import '../models/creator.dart';
import '../design_system/cf_theme.dart';

class CreatorAvatar extends StatelessWidget {
  final Creator creator;
  final double radius;

  const CreatorAvatar({
    super.key,
    required this.creator,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    final section = _getBoothSection(creator);
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        color: _getSectionColor(section),
        border: Border.all(color: const Color(0xFF191522), width: 1.5),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(3),
          bottomLeft: Radius.circular(3),
          bottomRight: Radius.circular(12),
        ),
        boxShadow: [
          BoxShadow(color: context.cf.hardShadow, offset: const Offset(2, 2)),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        section,
        style: const TextStyle(
          color: Color(0xFF191522),
          fontWeight: FontWeight.w900,
          letterSpacing: -0.5,
        ),
      ),
    );
  }

  String _getBoothSection(Creator creator) {
    if (creator.booths.isEmpty) return '?';
    final firstBooth = creator.booths.first;
    final hyphen = firstBooth.indexOf('-');
    if (hyphen > 0) {
      return firstBooth.substring(0, hyphen).toUpperCase();
    }
    return firstBooth.isNotEmpty
        ? firstBooth.substring(0, 1).toUpperCase()
        : '?';
  }

  Color _getSectionColor(String section) {
    const List<Color> palette = [
      Color(0xFFFF87B8),
      Color(0xFF70E2EE),
      Color(0xFFFFD84D),
      Color(0xFFA996FF),
      Color(0xFFFF9D7C),
      Color(0xFF7DE0A3),
      Color(0xFFFF9BD0),
      Color(0xFF8CB8F5),
    ];
    final idx = section.codeUnitAt(0) % palette.length;
    return palette[idx];
  }
}
