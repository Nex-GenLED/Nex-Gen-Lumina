import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/app_text_styles.dart';

class AppSpacing {
  // Spacing values
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;

  // Edge insets shortcuts
  static const EdgeInsets paddingXs = EdgeInsets.all(xs);
  static const EdgeInsets paddingSm = EdgeInsets.all(sm);
  static const EdgeInsets paddingMd = EdgeInsets.all(md);
  static const EdgeInsets paddingLg = EdgeInsets.all(lg);
  static const EdgeInsets paddingXl = EdgeInsets.all(xl);

  // Horizontal padding
  static const EdgeInsets horizontalXs = EdgeInsets.symmetric(horizontal: xs);
  static const EdgeInsets horizontalSm = EdgeInsets.symmetric(horizontal: sm);
  static const EdgeInsets horizontalMd = EdgeInsets.symmetric(horizontal: md);
  static const EdgeInsets horizontalLg = EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets horizontalXl = EdgeInsets.symmetric(horizontal: xl);

  // Vertical padding
  static const EdgeInsets verticalXs = EdgeInsets.symmetric(vertical: xs);
  static const EdgeInsets verticalSm = EdgeInsets.symmetric(vertical: sm);
  static const EdgeInsets verticalMd = EdgeInsets.symmetric(vertical: md);
  static const EdgeInsets verticalLg = EdgeInsets.symmetric(vertical: lg);
  static const EdgeInsets verticalXl = EdgeInsets.symmetric(vertical: xl);
}

/// Border radius constants for consistent rounded corners
class AppRadius {
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
}

// =============================================================================
// THEMES
// =============================================================================

/// Light theme with modern, neutral aesthetic
ThemeData get lightTheme => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.light(
    primary: LightModeColors.lightPrimary,
    onPrimary: LightModeColors.lightOnPrimary,
    primaryContainer: LightModeColors.lightPrimaryContainer,
    onPrimaryContainer: LightModeColors.lightOnPrimaryContainer,
    secondary: LightModeColors.lightSecondary,
    onSecondary: LightModeColors.lightOnSecondary,
    tertiary: LightModeColors.lightTertiary,
    onTertiary: LightModeColors.lightOnTertiary,
    error: LightModeColors.lightError,
    onError: LightModeColors.lightOnError,
    errorContainer: LightModeColors.lightErrorContainer,
    onErrorContainer: LightModeColors.lightOnErrorContainer,
    surface: LightModeColors.lightSurface,
    onSurface: LightModeColors.lightOnSurface,
    surfaceContainerHighest: LightModeColors.lightSurfaceVariant,
    onSurfaceVariant: LightModeColors.lightOnSurfaceVariant,
    outline: LightModeColors.lightOutline,
    shadow: LightModeColors.lightShadow,
    inversePrimary: LightModeColors.lightInversePrimary,
  ),
  brightness: Brightness.light,
  scaffoldBackgroundColor: LightModeColors.lightBackground,
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.transparent,
    foregroundColor: LightModeColors.lightOnSurface,
    elevation: 0,
    scrolledUnderElevation: 0,
  ),
  cardTheme: CardThemeData(
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(
        color: LightModeColors.lightOutline.withOpacity(0.2),
        width: 1,
      ),
    ),
  ),
  textTheme: _buildPremiumTextTheme(),
);

/// Dark theme with good contrast and readability
ThemeData get darkTheme => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.dark(
    primary: DarkModeColors.darkPrimary,
    onPrimary: DarkModeColors.darkOnPrimary,
    primaryContainer: DarkModeColors.darkPrimaryContainer,
    onPrimaryContainer: DarkModeColors.darkOnPrimaryContainer,
    secondary: DarkModeColors.darkSecondary,
    onSecondary: DarkModeColors.darkOnSecondary,
    tertiary: DarkModeColors.darkTertiary,
    onTertiary: DarkModeColors.darkOnTertiary,
    error: DarkModeColors.darkError,
    onError: DarkModeColors.darkOnError,
    errorContainer: DarkModeColors.darkErrorContainer,
    onErrorContainer: DarkModeColors.darkOnErrorContainer,
    surface: DarkModeColors.darkSurface,
    onSurface: DarkModeColors.darkOnSurface,
    surfaceContainerHighest: DarkModeColors.darkSurfaceVariant,
    onSurfaceVariant: DarkModeColors.darkOnSurfaceVariant,
    outline: DarkModeColors.darkOutline,
    shadow: DarkModeColors.darkShadow,
    inversePrimary: DarkModeColors.darkInversePrimary,
  ),
  brightness: Brightness.dark,
  scaffoldBackgroundColor: DarkModeColors.darkSurface,
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.transparent,
    foregroundColor: DarkModeColors.darkOnSurface,
    elevation: 0,
    scrolledUnderElevation: 0,
  ),
  cardTheme: CardThemeData(
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(
        color: DarkModeColors.darkOutline.withOpacity(0.2),
        width: 1,
      ),
    ),
  ),
  textTheme: _buildPremiumTextTheme(),
);

/// Nex-Gen Premium Dark Theme
ThemeData get nexGenPremiumDarkTheme => ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  colorScheme: const ColorScheme.dark(
    primary: NexGenPalette.cyan,
    onPrimary: Colors.black,
    secondary: NexGenPalette.violet,
    onSecondary: Colors.black,
    surface: NexGenPalette.gunmetal90,
    onSurface: NexGenPalette.textHigh,
    surfaceContainerHighest: NexGenPalette.gunmetal90,
    onSurfaceVariant: NexGenPalette.textMedium,
    error: Color(0xFFFF6B6B),
    onError: Colors.black,
    outline: NexGenPalette.line,
    shadow: Colors.black,
    inversePrimary: NexGenPalette.cyan,
  ),
  scaffoldBackgroundColor: NexGenPalette.matteBlack,
  // Reduce splash effects globally per design spec
  splashFactory: NoSplash.splashFactory,
  highlightColor: Colors.transparent,
  hoverColor: Colors.transparent,
  focusColor: Colors.transparent,
  pageTransitionsTheme: const PageTransitionsTheme(builders: {
    TargetPlatform.android: ZoomPageTransitionsBuilder(),
    TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
    TargetPlatform.macOS: ZoomPageTransitionsBuilder(),
    TargetPlatform.linux: ZoomPageTransitionsBuilder(),
    TargetPlatform.windows: ZoomPageTransitionsBuilder(),
  }),
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.transparent,
    foregroundColor: NexGenPalette.textHigh,
    elevation: 0,
    scrolledUnderElevation: 0,
  ),
  iconTheme: const IconThemeData(color: NexGenPalette.textMedium, size: 22),
  cardTheme: CardThemeData(
    color: NexGenPalette.gunmetal90,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: NexGenPalette.line, width: 1),
    ),
    margin: const EdgeInsets.all(0),
  ),
  sliderTheme: SliderThemeData(
    trackHeight: 6,
    trackShape: const NeonGradientSliderTrackShape(
      inactiveTrackColor: Color(0xFF2A2A2A),
      gradient: LinearGradient(colors: [NexGenPalette.cyan, NexGenPalette.cyan]),
    ),
    thumbColor: NexGenPalette.cyan,
    overlayColor: Colors.transparent, // No overlay per spec
    thumbShape: const NeonGlowThumbShape(radius: 10, glowColor: NexGenPalette.cyan, glowBlur: 18),
    inactiveTrackColor: const Color(0xFF2A2A2A),
  ),
  inputDecorationTheme: const InputDecorationTheme(
    filled: false,
    border: OutlineInputBorder(borderSide: BorderSide(color: NexGenPalette.line, width: 1.5), borderRadius: BorderRadius.all(Radius.circular(16))),
    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: NexGenPalette.line, width: 1.5), borderRadius: BorderRadius.all(Radius.circular(16))),
    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: NexGenPalette.cyan, width: 1.5), borderRadius: BorderRadius.all(Radius.circular(16))),
    labelStyle: TextStyle(color: NexGenPalette.textMedium),
    hintStyle: TextStyle(color: NexGenPalette.textMedium),
    prefixIconColor: NexGenPalette.textMedium,
    suffixIconColor: NexGenPalette.textMedium,
    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  ),
  switchTheme: SwitchThemeData(
    thumbColor: const MaterialStatePropertyAll(NexGenPalette.cyan),
    trackColor: MaterialStateProperty.resolveWith((states) {
      if (states.contains(MaterialState.selected)) return NexGenPalette.cyan.withValues(alpha: 0.25);
      return const Color(0xFF2A2A2A);
    }),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: ButtonStyle(
      backgroundColor: const MaterialStatePropertyAll(NexGenPalette.cyan),
      foregroundColor: const MaterialStatePropertyAll(Colors.black),
      shape: MaterialStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      elevation: const MaterialStatePropertyAll(6),
      shadowColor: MaterialStatePropertyAll(NexGenPalette.cyan.withValues(alpha: 0.4)),
      padding: const MaterialStatePropertyAll(EdgeInsets.symmetric(horizontal: 18, vertical: 14)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: ButtonStyle(
      side: const MaterialStatePropertyAll(BorderSide(color: NexGenPalette.line, width: 1.5)),
      shape: MaterialStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      foregroundColor: const MaterialStatePropertyAll(NexGenPalette.textHigh),
      padding: const MaterialStatePropertyAll(EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: ButtonStyle(
      foregroundColor: const MaterialStatePropertyAll(NexGenPalette.cyan),
      shape: MaterialStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      padding: const MaterialStatePropertyAll(EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
    ),
  ),
  snackBarTheme: const SnackBarThemeData(
    backgroundColor: NexGenPalette.gunmetal90,
    contentTextStyle: TextStyle(color: NexGenPalette.textHigh),
    behavior: SnackBarBehavior.floating,
  ),
  dividerTheme: const DividerThemeData(color: NexGenPalette.line, thickness: 1),
  textTheme: _buildPremiumTextTheme(),
);

/// Premium text theme: Montserrat for headings/labels, Inter for body
TextTheme _buildPremiumTextTheme() => TextTheme(
  displayLarge: GoogleFonts.montserrat(fontSize: FontSizes.displayLarge, fontWeight: FontWeight.w700, letterSpacing: -0.25, color: NexGenPalette.textHigh),
  displayMedium: GoogleFonts.montserrat(fontSize: FontSizes.displayMedium, fontWeight: FontWeight.w700, color: NexGenPalette.textHigh),
  displaySmall: GoogleFonts.montserrat(fontSize: FontSizes.displaySmall, fontWeight: FontWeight.w700, color: NexGenPalette.textHigh),
  headlineLarge: GoogleFonts.montserrat(fontSize: FontSizes.headlineLarge, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: NexGenPalette.textHigh),
  headlineMedium: GoogleFonts.montserrat(fontSize: FontSizes.headlineMedium, fontWeight: FontWeight.w700, color: NexGenPalette.textHigh),
  headlineSmall: GoogleFonts.montserrat(fontSize: FontSizes.headlineSmall, fontWeight: FontWeight.w700, color: NexGenPalette.textHigh),
  titleLarge: GoogleFonts.montserrat(fontSize: FontSizes.titleLarge, fontWeight: FontWeight.w600, color: NexGenPalette.textHigh),
  titleMedium: GoogleFonts.montserrat(fontSize: FontSizes.titleMedium, fontWeight: FontWeight.w600, color: NexGenPalette.textHigh),
  titleSmall: GoogleFonts.montserrat(fontSize: FontSizes.titleSmall, fontWeight: FontWeight.w600, color: NexGenPalette.textHigh),
  labelLarge: GoogleFonts.montserrat(fontSize: FontSizes.labelLarge, fontWeight: FontWeight.w600, letterSpacing: 0.1, color: NexGenPalette.textHigh),
  labelMedium: GoogleFonts.montserrat(fontSize: FontSizes.labelMedium, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: NexGenPalette.textHigh),
  labelSmall: GoogleFonts.montserrat(fontSize: FontSizes.labelSmall, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: NexGenPalette.textHigh),
  bodyLarge: GoogleFonts.inter(fontSize: FontSizes.bodyLarge, fontWeight: FontWeight.w400, letterSpacing: 0.15, color: NexGenPalette.textHigh),
  bodyMedium: GoogleFonts.inter(fontSize: FontSizes.bodyMedium, fontWeight: FontWeight.w400, letterSpacing: 0.25, color: NexGenPalette.textMedium),
  bodySmall: GoogleFonts.inter(fontSize: FontSizes.bodySmall, fontWeight: FontWeight.w400, letterSpacing: 0.4, color: NexGenPalette.textMedium),
);

// =============================================================================
// CUSTOM SLIDER SHAPES (Neon Gradient Track + Glow Thumb)
// =============================================================================

class NeonGradientSliderTrackShape extends SliderTrackShape {
  const NeonGradientSliderTrackShape({required this.inactiveTrackColor, required this.gradient});
  final Color inactiveTrackColor;
  final LinearGradient gradient;

  @override
  Rect getPreferredRect({required RenderBox parentBox, Offset offset = Offset.zero, required SliderThemeData sliderTheme, bool isEnabled = true, bool isDiscrete = false}) {
    final double trackHeight = sliderTheme.trackHeight ?? 4;
    final double trackLeft = offset.dx + 8;
    final double trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final double trackWidth = parentBox.size.width - 16;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }

  @override
  void paint(PaintingContext context, Offset offset, {required RenderBox parentBox, required SliderThemeData sliderTheme, required Animation<double> enableAnimation, required Offset thumbCenter, Offset? secondaryOffset, bool isEnabled = true, bool isDiscrete = false, required TextDirection textDirection}) {
    final Rect trackRect = getPreferredRect(parentBox: parentBox, offset: offset, sliderTheme: sliderTheme);
    final Canvas canvas = context.canvas;

    // Inactive track (full length)
    final RRect baseRRect = RRect.fromRectAndRadius(trackRect, const Radius.circular(99));
    final Paint inactive = Paint()..color = inactiveTrackColor;
    canvas.drawRRect(baseRRect, inactive);

    // Active track with gradient up to thumb
    final Rect activeRect = Rect.fromLTWH(trackRect.left, trackRect.top, (thumbCenter.dx - trackRect.left).clamp(0, trackRect.width), trackRect.height);
    final RRect activeRRect = RRect.fromRectAndRadius(activeRect, const Radius.circular(99));
    final Paint activePaint = Paint()..shader = gradient.createShader(trackRect);
    canvas.save();
    canvas.clipRRect(activeRRect);
    canvas.drawRRect(RRect.fromRectAndRadius(trackRect, const Radius.circular(99)), activePaint);
    canvas.restore();
  }
}

class NeonGlowThumbShape extends SliderComponentShape {
  const NeonGlowThumbShape({this.radius = 10, this.glowBlur = 14, this.glowColor = AppNeon.cyan});
  final double radius;
  final double glowBlur;
  final Color glowColor;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size.fromRadius(radius);

  @override
  void paint(PaintingContext context, Offset center, {required Animation<double> activationAnimation, required Animation<double> enableAnimation, required bool isDiscrete, required TextPainter labelPainter, required RenderBox parentBox, required SliderThemeData sliderTheme, required TextDirection textDirection, required double value, required double textScaleFactor, required Size sizeWithOverflow}) {
    final Canvas canvas = context.canvas;

    // Glow
    final Paint glowPaint = Paint()
      ..color = glowColor.withValues(alpha: 0.55)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowBlur);
    canvas.drawCircle(center, radius + 6, glowPaint);

    // Core thumb
    final Paint thumbPaint = Paint()..color = sliderTheme.thumbColor ?? glowColor;
    canvas.drawCircle(center, radius, thumbPaint);
  }
}
