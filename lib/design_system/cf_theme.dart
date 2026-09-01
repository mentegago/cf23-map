import 'package:flutter/material.dart';

@immutable
class CfTheme extends ThemeExtension<CfTheme> {
  const CfTheme({
    required this.ink,
    required this.paper,
    required this.paperRaised,
    required this.pink,
    required this.cyan,
    required this.yellow,
    required this.violet,
    required this.muted,
    required this.hardShadow,
  });

  final Color ink;
  final Color paper;
  final Color paperRaised;
  final Color pink;
  final Color cyan;
  final Color yellow;
  final Color violet;
  final Color muted;
  final Color hardShadow;

  static const light = CfTheme(
    ink: Color(0xFF191522),
    paper: Color(0xFFFFF8ED),
    paperRaised: Color(0xFFFFFEFA),
    pink: Color(0xFFFF3D8D),
    cyan: Color(0xFF00C8E0),
    yellow: Color(0xFFFFD84D),
    violet: Color(0xFF7657FF),
    muted: Color(0xFF70697A),
    hardShadow: Color(0xFF191522),
  );

  static const dark = CfTheme(
    ink: Color(0xFFFFF6E8),
    paper: Color(0xFF15111E),
    paperRaised: Color(0xFF211A2B),
    pink: Color(0xFFFF5CA2),
    cyan: Color(0xFF26DDF0),
    yellow: Color(0xFFFFDC60),
    violet: Color(0xFF9A83FF),
    muted: Color(0xFFB8ACBF),
    hardShadow: Color(0xFF050308),
  );

  @override
  CfTheme copyWith({
    Color? ink,
    Color? paper,
    Color? paperRaised,
    Color? pink,
    Color? cyan,
    Color? yellow,
    Color? violet,
    Color? muted,
    Color? hardShadow,
  }) {
    return CfTheme(
      ink: ink ?? this.ink,
      paper: paper ?? this.paper,
      paperRaised: paperRaised ?? this.paperRaised,
      pink: pink ?? this.pink,
      cyan: cyan ?? this.cyan,
      yellow: yellow ?? this.yellow,
      violet: violet ?? this.violet,
      muted: muted ?? this.muted,
      hardShadow: hardShadow ?? this.hardShadow,
    );
  }

  @override
  CfTheme lerp(ThemeExtension<CfTheme>? other, double t) {
    if (other is! CfTheme) return this;
    return CfTheme(
      ink: Color.lerp(ink, other.ink, t)!,
      paper: Color.lerp(paper, other.paper, t)!,
      paperRaised: Color.lerp(paperRaised, other.paperRaised, t)!,
      pink: Color.lerp(pink, other.pink, t)!,
      cyan: Color.lerp(cyan, other.cyan, t)!,
      yellow: Color.lerp(yellow, other.yellow, t)!,
      violet: Color.lerp(violet, other.violet, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      hardShadow: Color.lerp(hardShadow, other.hardShadow, t)!,
    );
  }
}

extension CfThemeContext on BuildContext {
  CfTheme get cf =>
      Theme.of(this).extension<CfTheme>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? CfTheme.dark
          : CfTheme.light);

  Color cfForegroundOn(Color fill) {
    final composite = Color.alphaBlend(fill, cf.paperRaised);
    return composite.computeLuminance() > 0.42
        ? const Color(0xFF191522)
        : const Color(0xFFFFFEFA);
  }
}

ThemeData buildCfTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final cf = dark ? CfTheme.dark : CfTheme.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: cf.pink,
    onPrimary: dark ? const Color(0xFF22000E) : Colors.white,
    primaryContainer: dark ? const Color(0xFF582039) : const Color(0xFFFFD9E8),
    onPrimaryContainer:
        dark ? const Color(0xFFFFD9E8) : const Color(0xFF4C0927),
    secondary: cf.cyan,
    onSecondary: const Color(0xFF002E34),
    secondaryContainer:
        dark ? const Color(0xFF10434B) : const Color(0xFFC9F7FC),
    onSecondaryContainer:
        dark ? const Color(0xFFC9F7FC) : const Color(0xFF00363D),
    tertiary: cf.violet,
    onTertiary: Colors.white,
    tertiaryContainer: dark ? const Color(0xFF3B306C) : const Color(0xFFE6E0FF),
    onTertiaryContainer:
        dark ? const Color(0xFFE9E4FF) : const Color(0xFF25145D),
    error: dark ? const Color(0xFFFF7A78) : const Color(0xFFC7253E),
    onError: Colors.white,
    errorContainer: dark ? const Color(0xFF5C1D28) : const Color(0xFFFFDADF),
    onErrorContainer: dark ? const Color(0xFFFFDADF) : const Color(0xFF5D0717),
    surface: cf.paperRaised,
    onSurface: cf.ink,
    surfaceContainerLowest: cf.paper,
    surfaceContainerLow:
        dark ? const Color(0xFF1B1624) : const Color(0xFFFFF3E2),
    surfaceContainer: dark ? const Color(0xFF251D30) : const Color(0xFFFFEBCF),
    surfaceContainerHigh:
        dark ? const Color(0xFF30263B) : const Color(0xFFF6DECB),
    surfaceContainerHighest:
        dark ? const Color(0xFF3B2E47) : const Color(0xFFEED2C1),
    onSurfaceVariant: cf.muted,
    outline: dark ? const Color(0xFF766981) : const Color(0xFF554C60),
    outlineVariant: dark ? const Color(0xFF44384E) : const Color(0xFFD7C8BD),
    shadow: cf.hardShadow,
    scrim: Colors.black,
    inverseSurface: cf.ink,
    onInverseSurface: cf.paper,
    inversePrimary: cf.pink,
  );

  final base = ThemeData(
    brightness: brightness,
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: cf.paper,
    fontFamily: 'Roboto',
    extensions: [cf],
  );

  final display = base.textTheme.titleLarge?.copyWith(
    fontWeight: FontWeight.w900,
    letterSpacing: -0.5,
    fontVariations: const [
      FontVariation('wdth', 82),
      FontVariation('wght', 900)
    ],
  );

  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      headlineSmall: display?.copyWith(fontSize: 26),
      titleLarge: display,
      titleMedium: display?.copyWith(fontSize: 17, letterSpacing: 0),
      titleSmall: display?.copyWith(fontSize: 14, letterSpacing: 0.2),
      labelLarge:
          base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: cf.paper,
      foregroundColor: cf.ink,
      elevation: 0,
      shadowColor: Colors.transparent,
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    iconTheme: IconThemeData(color: cf.ink),
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      border: InputBorder.none,
      hintStyle: TextStyle(color: cf.muted),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.secondaryContainer,
      selectedColor: cf.yellow,
      side: BorderSide(color: cf.ink, width: 1.2),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(12),
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(4),
        ),
      ),
      labelStyle: TextStyle(color: cf.ink, fontWeight: FontWeight.w700),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: cf.paperRaised,
      modalBackgroundColor: cf.paperRaised,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: cf.ink,
      contentTextStyle: TextStyle(color: cf.paper),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: cf.pink, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
    ),
  );
}
