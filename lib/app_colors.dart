import 'package:flutter/material.dart';

// =============================================================================
// COLORS
// =============================================================================

/// Modern, neutral color palette for light mode
/// Uses soft grays and blues instead of purple for a contemporary look
class LightModeColors {
  // Primary: Soft blue-gray for a modern, professional look
  static const lightPrimary = Color(0xFF5B7C99);
  static const lightOnPrimary = Color(0xFFFFFFFF);
  static const lightPrimaryContainer = Color(0xFFD8E6F3);
  static const lightOnPrimaryContainer = Color(0xFF1A3A52);

  // Secondary: Complementary gray-blue
  static const lightSecondary = Color(0xFF5C6B7A);
  static const lightOnSecondary = Color(0xFFFFFFFF);

  // Tertiary: Subtle accent color
  static const lightTertiary = Color(0xFF6B7C8C);
  static const lightOnTertiary = Color(0xFFFFFFFF);

  // Error colors
  static const lightError = Color(0xFFBA1A1A);
  static const lightOnError = Color(0xFFFFFFFF);
  static const lightErrorContainer = Color(0xFFFFDAD6);
  static const lightOnErrorContainer = Color(0xFF410002);

  // Surface and background: High contrast for readability
  static const lightSurface = Color(0xFFFBFCFD);
  static const lightOnSurface = Color(0xFF1A1C1E);
  static const lightBackground = Color(0xFFF7F9FA);
  static const lightSurfaceVariant = Color(0xFFE2E8F0);
  static const lightOnSurfaceVariant = Color(0xFF44474E);

  // Outline and shadow
  static const lightOutline = Color(0xFF74777F);
  static const lightShadow = Color(0xFF000000);
  static const lightInversePrimary = Color(0xFFACC7E3);
}

/// Dark mode colors with good contrast
class DarkModeColors {
  // Primary: Lighter blue for dark background
  static const darkPrimary = Color(0xFFACC7E3);
  static const darkOnPrimary = Color(0xFF1A3A52);
  static const darkPrimaryContainer = Color(0xFF3D5A73);
  static const darkOnPrimaryContainer = Color(0xFFD8E6F3);

  // Secondary
  static const darkSecondary = Color(0xFFBCC7D6);
  static const darkOnSecondary = Color(0xFF2E3842);

  // Tertiary
  static const darkTertiary = Color(0xFFB8C8D8);
  static const darkOnTertiary = Color(0xFF344451);

  // Error colors
  static const darkError = Color(0xFFFFB4AB);
  static const darkOnError = Color(0xFF690005);
  static const darkErrorContainer = Color(0xFF93000A);
  static const darkOnErrorContainer = Color(0xFFFFDAD6);

  // Surface and background: True dark mode
  static const darkSurface = Color(0xFF1A1C1E);
  static const darkOnSurface = Color(0xFFE2E8F0);
  static const darkSurfaceVariant = Color(0xFF44474E);
  static const darkOnSurfaceVariant = Color(0xFFC4C7CF);

  // Outline and shadow
  static const darkOutline = Color(0xFF8E9099);
  static const darkShadow = Color(0xFF000000);
  static const darkInversePrimary = Color(0xFF5B7C99);
}

/// Neon accents used across the app
class AppNeon {
  static const cyan = Color(0xFF00FFFF);
  static const magenta = Color(0xFFFF00FF);
}

/// Nex-Gen Premium palette (Dark-first)
class NexGenPalette {
  // Base
  static const matteBlack = Color(0xFF050505);
  static const gunmetal = Color(0xFF1A1A1A); // Solid gunmetal
  static const gunmetal90 = Color(0xE61A1A1A); // 90% opacity
  static const gunmetal50 = Color(0x801A1A1A); // 50% opacity for charts/bg
  // Brand background deep tone
  static const midnightBlue = Color(0xFF0D1B2A);
  static const deepNavy = Color(0xFF0D1B2A); // Alias for midnightBlue
  // Tracks / gauges
  static const trackDark = Color(0xFF222222);
  // Accents
  static const cyan = Color(0xFF00F0FF); // Nex-Gen Cyan
  static const blue = Color(0xFF007BFF); // Accent Blue for gradients
  static const violet = Color(0xFF7000FF); // Electric Violet
  static const magenta = Color(0xFFFF00FF); // Electric Magenta for Media Mode
  static const amber = Color(0xFFFFAB00); // Amber for warnings
  static const primary = cyan; // Alias for cyan
  static const secondary = violet; // Alias for violet
    // Special accents
    static const gold = Color(0xFFFFD54F); // Subtle gold for featured borders
  // Text
  static const textHigh = Color(0xFFFFFFFF);
  static const textMedium = Color(0xFFB0B0B0);
  static const textPrimary = textHigh; // Alias for textHigh
  static const textSecondary = textMedium; // Alias for textMedium
  // Lines
  static const line = Color(0xFF2A2A2A);
  // Card backgrounds
  static const cardBackground = gunmetal90; // Alias for gunmetal90

  /// Returns dark or light text color based on average luminance of [colors].
  /// Use on any card whose background is derived from theme/pattern colors.
  static Color contrastTextFor(List<Color> colors) {
    if (colors.isEmpty) return textHigh;
    final avg = colors.map((c) => c.computeLuminance()).reduce((a, b) => a + b) / colors.length;
    return avg > 0.45 ? const Color(0xFF1A1A1A) : textHigh;
  }

  /// Secondary (dimmed) variant of [contrastTextFor].
  static Color contrastSecondaryFor(List<Color> colors) {
    if (colors.isEmpty) return textSecondary;
    final avg = colors.map((c) => c.computeLuminance()).reduce((a, b) => a + b) / colors.length;
    return avg > 0.45 ? const Color(0xFF5A5A5A) : textSecondary;
  }
}

/// Reusable gradients and tokens for brand moments (e.g., Login)
class BrandGradients {
  const BrandGradients._();

  /// Background atmosphere: black to midnight blue
  static const LinearGradient atmosphere = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Colors.black, NexGenPalette.midnightBlue],
  );

  /// Primary action gradient: cyan to blue
  static const LinearGradient primaryCta = LinearGradient(
    colors: [NexGenPalette.cyan, NexGenPalette.blue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
