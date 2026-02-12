import 'package:nexgen_command/features/wled/effect_database.dart';

// ---------------------------------------------------------------------------
// Output model
// ---------------------------------------------------------------------------

/// Result of context-aware brightness calculation.
class BrightnessRecommendation {
  /// Recommended brightness in the 0.0–1.0 range.
  final double brightness;

  /// Human-readable explanation for debugging / UI transparency.
  final String reasoning;

  const BrightnessRecommendation({
    required this.brightness,
    required this.reasoning,
  });

  /// Convert to WLED brightness value (0–255).
  int get wledBrightness => (brightness * 255).round().clamp(0, 255);
}

// ---------------------------------------------------------------------------
// Calculator
// ---------------------------------------------------------------------------

/// Calculates context-aware brightness defaults using sky darkness,
/// user preferences, and content energy level.
///
/// Uses the existing [currentSkyDarknessProvider] value (0.0 = full day,
/// 1.0 = full night) from `lib/utils/sky_darkness_provider.dart`.
class BrightnessContextCalculator {
  BrightnessContextCalculator._();

  /// Calculate recommended brightness for the current context.
  ///
  /// Parameters:
  /// - [skyDarkness]: 0.0 (full day) → 1.0 (full night). Read from
  ///   `currentSkyDarknessProvider`.
  /// - [userVibeLevel]: 0.0 (subtle/classy) → 1.0 (bold/energetic). From
  ///   `UserModel.vibeLevel`. Pass `null` for neutral (0.5).
  /// - [quietHoursStart] / [quietHoursEnd]: minutes from midnight (0–1439).
  ///   From `UserModel.quietHoursStartMinutes`.
  /// - [hoaCompliance]: caps max brightness when enabled.
  /// - [contentEnergy]: energy level of the requested concept/mood.
  /// - [currentTime]: defaults to `DateTime.now()`.
  static BrightnessRecommendation calculate({
    required double skyDarkness,
    double? userVibeLevel,
    int? quietHoursStart,
    int? quietHoursEnd,
    bool hoaCompliance = false,
    EnergyLevel? contentEnergy,
    DateTime? currentTime,
  }) {
    final now = currentTime ?? DateTime.now();
    final reasons = <String>[];

    // ----- 1. Base brightness from sky darkness curve -----
    double base = _baseBrightness(skyDarkness);
    reasons.add('sky ${(skyDarkness * 100).round()}% → base ${(base * 100).round()}%');

    // ----- 2. Vibe level modifier -----
    final vibe = userVibeLevel ?? 0.5;
    // Linear map: 0.0 → 0.80, 0.5 → 1.00, 1.0 → 1.15
    final vibeMul = 0.80 + vibe * 0.35;
    base *= vibeMul;
    if ((vibeMul - 1.0).abs() > 0.01) {
      reasons.add('vibe ${vibe < 0.4 ? "subtle" : vibe > 0.6 ? "bold" : "balanced"}');
    }

    // ----- 3. Content energy modifier -----
    if (contentEnergy != null) {
      final energyMul = _energyMultiplier(contentEnergy);
      base *= energyMul;
      if ((energyMul - 1.0).abs() > 0.01) {
        reasons.add('energy ${contentEnergy.name}');
      }
    }

    // ----- 4. Quiet hours dampening -----
    if (isInQuietHours(
      startMinutes: quietHoursStart,
      endMinutes: quietHoursEnd,
      currentTime: now,
    )) {
      base *= 0.50;
      reasons.add('quiet hours');
    }

    // ----- 5. HOA compliance cap -----
    if (hoaCompliance && base > 0.75) {
      base = 0.75;
      reasons.add('HOA cap');
    }

    // Final clamp
    base = base.clamp(0.05, 1.0);

    return BrightnessRecommendation(
      brightness: base,
      reasoning: reasons.join(', '),
    );
  }

  // -------------------------------------------------------------------------
  // Quiet hours helper
  // -------------------------------------------------------------------------

  /// Whether [currentTime] falls within the quiet-hours window.
  ///
  /// Handles overnight ranges (e.g. start=1320 [10pm], end=420 [7am]).
  static bool isInQuietHours({
    required int? startMinutes,
    required int? endMinutes,
    DateTime? currentTime,
  }) {
    if (startMinutes == null || endMinutes == null) return false;

    final now = currentTime ?? DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;

    if (startMinutes <= endMinutes) {
      // Same-day range (e.g. 8am–10pm)
      return nowMinutes >= startMinutes && nowMinutes < endMinutes;
    } else {
      // Overnight range (e.g. 10pm–7am)
      return nowMinutes >= startMinutes || nowMinutes < endMinutes;
    }
  }

  // -------------------------------------------------------------------------
  // Internal helpers
  // -------------------------------------------------------------------------

  /// Piecewise-linear base brightness from sky darkness.
  ///
  /// | sky  | base | note                |
  /// |------|------|---------------------|
  /// | 0.0  | 0.60 | full daylight       |
  /// | 0.3  | 0.75 | twilight            |
  /// | 0.5  | 0.85 | dusk                |
  /// | 0.7  | 0.90 | evening (peak)      |
  /// | 1.0  | 0.85 | full night (comfort)|
  static double _baseBrightness(double sky) {
    if (sky <= 0.0) return 0.60;
    if (sky <= 0.3) return _lerp(0.60, 0.75, sky / 0.3);
    if (sky <= 0.5) return _lerp(0.75, 0.85, (sky - 0.3) / 0.2);
    if (sky <= 0.7) return _lerp(0.85, 0.90, (sky - 0.5) / 0.2);
    if (sky <= 1.0) return _lerp(0.90, 0.85, (sky - 0.7) / 0.3);
    return 0.85;
  }

  /// Energy level → brightness multiplier.
  static double _energyMultiplier(EnergyLevel energy) {
    switch (energy) {
      case EnergyLevel.veryLow:
        return 0.70;
      case EnergyLevel.low:
        return 0.85;
      case EnergyLevel.medium:
        return 1.00;
      case EnergyLevel.high:
        return 1.10;
      case EnergyLevel.veryHigh:
        return 1.15;
      case EnergyLevel.dynamic:
        return 1.00;
    }
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}
