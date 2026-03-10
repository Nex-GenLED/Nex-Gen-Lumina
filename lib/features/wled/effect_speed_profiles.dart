/// Per-effect speed profiles for non-linear slider mapping.
///
/// Each effect has a tuned speed range and curve type so the slider
/// gives precise control across the effect's usable speed range.
library;

import 'dart:math' as math;

// ---------------------------------------------------------------------------
// Curve type enum
// ---------------------------------------------------------------------------

/// How the slider position maps to raw WLED speed values.
enum SpeedCurveType {
  /// Even distribution across the range.
  linear,

  /// ~70 % of slider travel covers the lower half of the raw range.
  /// Best for effects that become chaotic at higher speeds.
  logarithmic,

  /// Smooth deceleration toward the top — cubic ease-out.
  easeOut,
}

// ---------------------------------------------------------------------------
// Speed profile data class
// ---------------------------------------------------------------------------

/// Defines the usable speed range and slider curve for a single WLED effect.
class EffectSpeedProfile {
  /// WLED effect ID this profile applies to.
  final int effectId;

  /// Minimum raw speed value (floor).
  final int rawMin;

  /// Maximum raw speed value (hard ceiling, only reachable in extended mode).
  final int rawMax;

  /// Default speed on first load.
  final int rawDefault;

  /// Soft ceiling — slider maps to this unless extended range is active.
  final int rawRecommendedMax;

  /// Curve type that determines how slider position maps to raw speed.
  final SpeedCurveType curveType;

  /// Human-readable hint shown near the slider (e.g. "Slow drift").
  final String label;

  const EffectSpeedProfile({
    required this.effectId,
    required this.rawMin,
    required this.rawMax,
    required this.rawDefault,
    required this.rawRecommendedMax,
    required this.curveType,
    this.label = '',
  });

  // -------------------------------------------------------------------------
  // Slider ↔ raw speed mapping
  // -------------------------------------------------------------------------

  /// Convert a normalised slider position (0.0–1.0) to a raw WLED speed value.
  ///
  /// When [extended] is true the ceiling is [rawMax] instead of
  /// [rawRecommendedMax].
  int mapSliderToRaw(double sliderPosition, {bool extended = false}) {
    final ceiling = extended ? rawMax : rawRecommendedMax;
    final range = (ceiling - rawMin).toDouble();
    final t = sliderPosition.clamp(0.0, 1.0);

    final double mapped;
    switch (curveType) {
      case SpeedCurveType.logarithmic:
        // log(1 + t*9) / log(10) — gives ~70 % of travel in the lower half.
        mapped = math.log(1 + t * 9) / math.log(10);
      case SpeedCurveType.easeOut:
        // Cubic ease-out: 1 - (1 - t)^3
        mapped = 1 - math.pow(1 - t, 3).toDouble();
      case SpeedCurveType.linear:
        mapped = t;
    }

    return (rawMin + range * mapped).round().clamp(rawMin, ceiling);
  }

  /// Convert a raw WLED speed value back to a normalised slider position
  /// (0.0–1.0). Used when loading a saved pattern so the slider visually
  /// matches the stored speed.
  ///
  /// Returns a pair of (sliderPosition, needsExtended) where needsExtended
  /// is true if the raw value exceeds [rawRecommendedMax].
  ({double position, bool needsExtended}) mapRawToSlider(int rawSpeed) {
    final bool needsExtended = rawSpeed > rawRecommendedMax;
    final ceiling = needsExtended ? rawMax : rawRecommendedMax;
    final range = (ceiling - rawMin).toDouble();
    if (range <= 0) return (position: 0.0, needsExtended: false);

    // Normalised value in 0..1 within the chosen range.
    final normalised = ((rawSpeed - rawMin) / range).clamp(0.0, 1.0);

    final double sliderPos;
    switch (curveType) {
      case SpeedCurveType.logarithmic:
        // Inverse of log(1 + t*9)/log(10):  t = (10^normalised - 1) / 9
        sliderPos = (math.pow(10, normalised) - 1) / 9;
      case SpeedCurveType.easeOut:
        // Inverse of 1 - (1-t)^3:  t = 1 - (1 - normalised)^(1/3)
        sliderPos = 1 - math.pow(1 - normalised, 1.0 / 3.0).toDouble();
      case SpeedCurveType.linear:
        sliderPos = normalised;
    }

    return (
      position: sliderPos.clamp(0.0, 1.0),
      needsExtended: needsExtended,
    );
  }

  // -------------------------------------------------------------------------
  // Contextual speed labels
  // -------------------------------------------------------------------------

  /// Returns a human-readable label for the current slider position.
  /// [extended] should be true when the slider is in extended-range mode.
  String speedLabel(double sliderPosition, {bool extended = false}) {
    if (extended && sliderPosition > 0.95) return 'Maximum';
    if (sliderPosition <= 0.20) return 'Very Slow';
    if (sliderPosition <= 0.40) return 'Slow';
    if (sliderPosition <= 0.60) return 'Medium';
    if (sliderPosition <= 0.80) return 'Fast';
    return 'Very Fast';
  }
}

// ---------------------------------------------------------------------------
// Default / fallback profile
// ---------------------------------------------------------------------------

/// Fallback profile used for any effect without a specific entry.
/// Full 0-255 range, linear curve.
const _defaultProfile = EffectSpeedProfile(
  effectId: -1,
  rawMin: 0,
  rawMax: 255,
  rawDefault: 128,
  rawRecommendedMax: 200,
  curveType: SpeedCurveType.linear,
  label: 'General',
);

// ---------------------------------------------------------------------------
// Per-effect profile registry
// ---------------------------------------------------------------------------

/// Lookup a speed profile for the given WLED [effectId].
/// Falls back to a sensible default if no specific profile exists.
EffectSpeedProfile getSpeedProfile(int effectId) {
  return _profilesById[effectId] ?? _defaultProfile;
}

/// Map keyed by effect ID for O(1) lookup. Built lazily from [_allProfiles].
final Map<int, EffectSpeedProfile> _profilesById = {
  for (final p in _allProfiles) p.effectId: p,
};

/// All per-effect speed profiles.
///
/// Organised by WLED category for readability. Curve type and range chosen
/// based on how the effect behaves visually:
///   - Ambient / slow effects → lower ceilings, logarithmic curves
///   - Energetic effects → higher ceilings but still logarithmic for precision
///   - Sweep / wipe effects → ease-out for smooth top-end deceleration
const List<EffectSpeedProfile> _allProfiles = [
  // ─── Basic effects ─────────────────────────────────────────────────────
  // 0: Solid — no speed control (static), but include a profile in case
  EffectSpeedProfile(effectId: 0, rawMin: 0, rawMax: 255, rawDefault: 128, rawRecommendedMax: 200, curveType: SpeedCurveType.linear, label: 'Static'),
  // 1: Blink
  EffectSpeedProfile(effectId: 1, rawMin: 10, rawMax: 220, rawDefault: 80, rawRecommendedMax: 160, curveType: SpeedCurveType.logarithmic, label: 'Blink rate'),
  // 2: Breathe
  EffectSpeedProfile(effectId: 2, rawMin: 5, rawMax: 160, rawDefault: 40, rawRecommendedMax: 100, curveType: SpeedCurveType.logarithmic, label: 'Breathing pace'),
  // 5: Random Colors
  EffectSpeedProfile(effectId: 5, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Change rate'),
  // 7: Dynamic
  EffectSpeedProfile(effectId: 7, rawMin: 10, rawMax: 210, rawDefault: 70, rawRecommendedMax: 150, curveType: SpeedCurveType.logarithmic, label: 'Motion'),
  // 8: Colorloop
  EffectSpeedProfile(effectId: 8, rawMin: 5, rawMax: 180, rawDefault: 40, rawRecommendedMax: 110, curveType: SpeedCurveType.logarithmic, label: 'Cycle speed'),
  // 12: Fade
  EffectSpeedProfile(effectId: 12, rawMin: 5, rawMax: 160, rawDefault: 40, rawRecommendedMax: 100, curveType: SpeedCurveType.logarithmic, label: 'Fade pace'),
  // 18: Dissolve
  EffectSpeedProfile(effectId: 18, rawMin: 10, rawMax: 180, rawDefault: 50, rawRecommendedMax: 120, curveType: SpeedCurveType.logarithmic, label: 'Dissolve rate'),
  // 19: Dissolve Rnd
  EffectSpeedProfile(effectId: 19, rawMin: 10, rawMax: 180, rawDefault: 50, rawRecommendedMax: 120, curveType: SpeedCurveType.logarithmic, label: 'Dissolve rate'),
  // 26: Blink Rainbow
  EffectSpeedProfile(effectId: 26, rawMin: 10, rawMax: 220, rawDefault: 80, rawRecommendedMax: 160, curveType: SpeedCurveType.logarithmic, label: 'Blink rate'),
  // 34: Colorful
  EffectSpeedProfile(effectId: 34, rawMin: 5, rawMax: 180, rawDefault: 50, rawRecommendedMax: 120, curveType: SpeedCurveType.logarithmic, label: 'Shift rate'),
  // 35: Traffic Light
  EffectSpeedProfile(effectId: 35, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Change rate'),
  // 46: Gradient
  EffectSpeedProfile(effectId: 46, rawMin: 5, rawMax: 160, rawDefault: 35, rawRecommendedMax: 100, curveType: SpeedCurveType.logarithmic, label: 'Shift speed'),
  // 47: Loading
  EffectSpeedProfile(effectId: 47, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.easeOut, label: 'Loading pace'),
  // 56: Tri Fade
  EffectSpeedProfile(effectId: 56, rawMin: 5, rawMax: 160, rawDefault: 40, rawRecommendedMax: 100, curveType: SpeedCurveType.logarithmic, label: 'Fade pace'),
  // 62: Oscillate
  EffectSpeedProfile(effectId: 62, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Oscillation'),
  // 65: Palette
  EffectSpeedProfile(effectId: 65, rawMin: 5, rawMax: 180, rawDefault: 45, rawRecommendedMax: 110, curveType: SpeedCurveType.logarithmic, label: 'Palette cycle'),
  // 68: Bpm
  EffectSpeedProfile(effectId: 68, rawMin: 10, rawMax: 220, rawDefault: 80, rawRecommendedMax: 160, curveType: SpeedCurveType.logarithmic, label: 'BPM'),
  // 83: Solid Pattern — static, no speed
  EffectSpeedProfile(effectId: 83, rawMin: 0, rawMax: 255, rawDefault: 128, rawRecommendedMax: 200, curveType: SpeedCurveType.linear, label: 'Static'),
  // 84: Solid Pattern Tri — static
  EffectSpeedProfile(effectId: 84, rawMin: 0, rawMax: 255, rawDefault: 128, rawRecommendedMax: 200, curveType: SpeedCurveType.linear, label: 'Static'),
  // 85: Spots — static
  EffectSpeedProfile(effectId: 85, rawMin: 0, rawMax: 255, rawDefault: 128, rawRecommendedMax: 200, curveType: SpeedCurveType.linear, label: 'Static'),
  // 86: Spots Fade
  EffectSpeedProfile(effectId: 86, rawMin: 5, rawMax: 160, rawDefault: 40, rawRecommendedMax: 100, curveType: SpeedCurveType.logarithmic, label: 'Fade pace'),
  // 98: Percent
  EffectSpeedProfile(effectId: 98, rawMin: 0, rawMax: 255, rawDefault: 128, rawRecommendedMax: 200, curveType: SpeedCurveType.linear, label: 'Fill'),
  // 100: Heartbeat
  EffectSpeedProfile(effectId: 100, rawMin: 5, rawMax: 170, rawDefault: 45, rawRecommendedMax: 110, curveType: SpeedCurveType.logarithmic, label: 'Heart rate'),
  // 108: Sine
  EffectSpeedProfile(effectId: 108, rawMin: 5, rawMax: 180, rawDefault: 45, rawRecommendedMax: 110, curveType: SpeedCurveType.logarithmic, label: 'Wave speed'),
  // 113: Washing Machine
  EffectSpeedProfile(effectId: 113, rawMin: 10, rawMax: 210, rawDefault: 60, rawRecommendedMax: 150, curveType: SpeedCurveType.logarithmic, label: 'Wash cycle'),
  // 117: Dynamic Smooth
  EffectSpeedProfile(effectId: 117, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Motion'),
  // 128: Pixels
  EffectSpeedProfile(effectId: 128, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Pixel rate'),

  // ─── Wipe effects ──────────────────────────────────────────────────────
  // 3: Wipe
  EffectSpeedProfile(effectId: 3, rawMin: 10, rawMax: 200, rawDefault: 50, rawRecommendedMax: 140, curveType: SpeedCurveType.easeOut, label: 'Wipe speed'),
  // 4: Wipe Random
  EffectSpeedProfile(effectId: 4, rawMin: 10, rawMax: 200, rawDefault: 50, rawRecommendedMax: 140, curveType: SpeedCurveType.easeOut, label: 'Wipe speed'),
  // 6: Sweep
  EffectSpeedProfile(effectId: 6, rawMin: 10, rawMax: 200, rawDefault: 50, rawRecommendedMax: 140, curveType: SpeedCurveType.easeOut, label: 'Sweep speed'),
  // 36: Sweep Random
  EffectSpeedProfile(effectId: 36, rawMin: 10, rawMax: 200, rawDefault: 50, rawRecommendedMax: 140, curveType: SpeedCurveType.easeOut, label: 'Sweep speed'),
  // 55: Tri Wipe
  EffectSpeedProfile(effectId: 55, rawMin: 10, rawMax: 200, rawDefault: 50, rawRecommendedMax: 140, curveType: SpeedCurveType.easeOut, label: 'Wipe speed'),

  // ─── Chase effects ─────────────────────────────────────────────────────
  // 13: Theater
  EffectSpeedProfile(effectId: 13, rawMin: 10, rawMax: 210, rawDefault: 55, rawRecommendedMax: 150, curveType: SpeedCurveType.logarithmic, label: 'Chase speed'),
  // 14: Theater Rainbow
  EffectSpeedProfile(effectId: 14, rawMin: 10, rawMax: 210, rawDefault: 55, rawRecommendedMax: 150, curveType: SpeedCurveType.logarithmic, label: 'Chase speed'),
  // 15: Running
  EffectSpeedProfile(effectId: 15, rawMin: 10, rawMax: 210, rawDefault: 55, rawRecommendedMax: 150, curveType: SpeedCurveType.logarithmic, label: 'Run speed'),
  // 16: Saw
  EffectSpeedProfile(effectId: 16, rawMin: 10, rawMax: 200, rawDefault: 55, rawRecommendedMax: 150, curveType: SpeedCurveType.logarithmic, label: 'Saw speed'),
  // 27: Android
  EffectSpeedProfile(effectId: 27, rawMin: 10, rawMax: 200, rawDefault: 55, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Chase speed'),
  // 28: Chase
  EffectSpeedProfile(effectId: 28, rawMin: 10, rawMax: 220, rawDefault: 60, rawRecommendedMax: 160, curveType: SpeedCurveType.logarithmic, label: 'Chase speed'),
  // 29: Chase Random
  EffectSpeedProfile(effectId: 29, rawMin: 10, rawMax: 220, rawDefault: 60, rawRecommendedMax: 160, curveType: SpeedCurveType.logarithmic, label: 'Chase speed'),
  // 30: Chase Rainbow
  EffectSpeedProfile(effectId: 30, rawMin: 10, rawMax: 220, rawDefault: 60, rawRecommendedMax: 160, curveType: SpeedCurveType.logarithmic, label: 'Chase speed'),
  // 31: Chase Flash
  EffectSpeedProfile(effectId: 31, rawMin: 10, rawMax: 220, rawDefault: 60, rawRecommendedMax: 160, curveType: SpeedCurveType.logarithmic, label: 'Chase speed'),
  // 32: Chase Flash Rnd
  EffectSpeedProfile(effectId: 32, rawMin: 10, rawMax: 220, rawDefault: 60, rawRecommendedMax: 160, curveType: SpeedCurveType.logarithmic, label: 'Chase speed'),
  // 37: Chase 2
  EffectSpeedProfile(effectId: 37, rawMin: 10, rawMax: 220, rawDefault: 60, rawRecommendedMax: 160, curveType: SpeedCurveType.logarithmic, label: 'Chase speed'),
  // 50: Two Dots
  EffectSpeedProfile(effectId: 50, rawMin: 10, rawMax: 200, rawDefault: 55, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Chase speed'),
  // 52: Running Dual
  EffectSpeedProfile(effectId: 52, rawMin: 10, rawMax: 210, rawDefault: 55, rawRecommendedMax: 150, curveType: SpeedCurveType.logarithmic, label: 'Run speed'),
  // 54: Chase 3
  EffectSpeedProfile(effectId: 54, rawMin: 10, rawMax: 220, rawDefault: 60, rawRecommendedMax: 160, curveType: SpeedCurveType.logarithmic, label: 'Chase speed'),
  // 64: Juggle
  EffectSpeedProfile(effectId: 64, rawMin: 10, rawMax: 210, rawDefault: 55, rawRecommendedMax: 150, curveType: SpeedCurveType.logarithmic, label: 'Juggle speed'),
  // 78: Railway
  EffectSpeedProfile(effectId: 78, rawMin: 10, rawMax: 200, rawDefault: 55, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Rail speed'),
  // 92: Sinelon
  EffectSpeedProfile(effectId: 92, rawMin: 10, rawMax: 200, rawDefault: 55, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Sweep speed'),
  // 93: Sinelon Dual
  EffectSpeedProfile(effectId: 93, rawMin: 10, rawMax: 200, rawDefault: 55, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Sweep speed'),
  // 94: Sinelon Rainbow
  EffectSpeedProfile(effectId: 94, rawMin: 10, rawMax: 200, rawDefault: 55, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Sweep speed'),
  // 111: Chunchun
  EffectSpeedProfile(effectId: 111, rawMin: 10, rawMax: 200, rawDefault: 55, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Chase speed'),

  // ─── Scanner effects ───────────────────────────────────────────────────
  // 10: Scan
  EffectSpeedProfile(effectId: 10, rawMin: 10, rawMax: 190, rawDefault: 45, rawRecommendedMax: 130, curveType: SpeedCurveType.logarithmic, label: 'Scan speed'),
  // 11: Scan Dual
  EffectSpeedProfile(effectId: 11, rawMin: 10, rawMax: 190, rawDefault: 45, rawRecommendedMax: 130, curveType: SpeedCurveType.logarithmic, label: 'Scan speed'),
  // 40: Scanner
  EffectSpeedProfile(effectId: 40, rawMin: 10, rawMax: 190, rawDefault: 45, rawRecommendedMax: 130, curveType: SpeedCurveType.logarithmic, label: 'Scan speed'),
  // 41: Lighthouse
  EffectSpeedProfile(effectId: 41, rawMin: 10, rawMax: 190, rawDefault: 45, rawRecommendedMax: 130, curveType: SpeedCurveType.logarithmic, label: 'Rotation'),
  // 58: ICU
  EffectSpeedProfile(effectId: 58, rawMin: 10, rawMax: 190, rawDefault: 50, rawRecommendedMax: 130, curveType: SpeedCurveType.logarithmic, label: 'Scan speed'),
  // 60: Scanner Dual
  EffectSpeedProfile(effectId: 60, rawMin: 10, rawMax: 190, rawDefault: 45, rawRecommendedMax: 130, curveType: SpeedCurveType.logarithmic, label: 'Scan speed'),

  // ─── Sparkle / Twinkle effects ─────────────────────────────────────────
  // 17: Twinkle
  EffectSpeedProfile(effectId: 17, rawMin: 5, rawMax: 170, rawDefault: 40, rawRecommendedMax: 110, curveType: SpeedCurveType.logarithmic, label: 'Twinkle rate'),
  // 20: Sparkle
  EffectSpeedProfile(effectId: 20, rawMin: 5, rawMax: 180, rawDefault: 45, rawRecommendedMax: 120, curveType: SpeedCurveType.logarithmic, label: 'Sparkle rate'),
  // 21: Sparkle Dark
  EffectSpeedProfile(effectId: 21, rawMin: 5, rawMax: 180, rawDefault: 45, rawRecommendedMax: 120, curveType: SpeedCurveType.logarithmic, label: 'Sparkle rate'),
  // 22: Sparkle+
  EffectSpeedProfile(effectId: 22, rawMin: 5, rawMax: 180, rawDefault: 45, rawRecommendedMax: 120, curveType: SpeedCurveType.logarithmic, label: 'Sparkle rate'),
  // 49: Fairy
  EffectSpeedProfile(effectId: 49, rawMin: 5, rawMax: 160, rawDefault: 35, rawRecommendedMax: 100, curveType: SpeedCurveType.logarithmic, label: 'Fairy shimmer'),
  // 51: Fairytwinkle
  EffectSpeedProfile(effectId: 51, rawMin: 5, rawMax: 160, rawDefault: 35, rawRecommendedMax: 100, curveType: SpeedCurveType.logarithmic, label: 'Fairy shimmer'),
  // 74: Colortwinkles
  EffectSpeedProfile(effectId: 74, rawMin: 5, rawMax: 160, rawDefault: 35, rawRecommendedMax: 100, curveType: SpeedCurveType.logarithmic, label: 'Twinkle rate'),
  // 80: Twinklefox
  EffectSpeedProfile(effectId: 80, rawMin: 5, rawMax: 160, rawDefault: 35, rawRecommendedMax: 100, curveType: SpeedCurveType.logarithmic, label: 'Twinkle rate'),
  // 81: Twinklecat
  EffectSpeedProfile(effectId: 81, rawMin: 5, rawMax: 160, rawDefault: 35, rawRecommendedMax: 100, curveType: SpeedCurveType.logarithmic, label: 'Twinkle rate'),
  // 87: Glitter
  EffectSpeedProfile(effectId: 87, rawMin: 5, rawMax: 170, rawDefault: 40, rawRecommendedMax: 110, curveType: SpeedCurveType.logarithmic, label: 'Glitter rate'),
  // 103: Solid Glitter
  EffectSpeedProfile(effectId: 103, rawMin: 5, rawMax: 170, rawDefault: 40, rawRecommendedMax: 110, curveType: SpeedCurveType.logarithmic, label: 'Glitter rate'),
  // 106: Twinkleup
  EffectSpeedProfile(effectId: 106, rawMin: 5, rawMax: 160, rawDefault: 35, rawRecommendedMax: 100, curveType: SpeedCurveType.logarithmic, label: 'Twinkle rate'),

  // ─── Meteor effects ────────────────────────────────────────────────────
  // 59: Multi Comet
  EffectSpeedProfile(effectId: 59, rawMin: 5, rawMax: 180, rawDefault: 40, rawRecommendedMax: 120, curveType: SpeedCurveType.logarithmic, label: 'Comet speed'),
  // 76: Meteor
  EffectSpeedProfile(effectId: 76, rawMin: 5, rawMax: 180, rawDefault: 40, rawRecommendedMax: 120, curveType: SpeedCurveType.logarithmic, label: 'Meteor speed'),
  // 77: Meteor Smooth
  EffectSpeedProfile(effectId: 77, rawMin: 5, rawMax: 180, rawDefault: 40, rawRecommendedMax: 120, curveType: SpeedCurveType.logarithmic, label: 'Meteor speed'),

  // ─── Fire effects ──────────────────────────────────────────────────────
  // 45: Fire Flicker
  EffectSpeedProfile(effectId: 45, rawMin: 5, rawMax: 150, rawDefault: 30, rawRecommendedMax: 90, curveType: SpeedCurveType.logarithmic, label: 'Flicker rate'),
  // 66: Fire 2012
  EffectSpeedProfile(effectId: 66, rawMin: 5, rawMax: 160, rawDefault: 35, rawRecommendedMax: 100, curveType: SpeedCurveType.logarithmic, label: 'Flame speed'),
  // 88: Candle
  EffectSpeedProfile(effectId: 88, rawMin: 5, rawMax: 140, rawDefault: 25, rawRecommendedMax: 80, curveType: SpeedCurveType.logarithmic, label: 'Flicker rate'),
  // 102: Candle Multi
  EffectSpeedProfile(effectId: 102, rawMin: 5, rawMax: 140, rawDefault: 25, rawRecommendedMax: 80, curveType: SpeedCurveType.logarithmic, label: 'Flicker rate'),

  // ─── Fireworks effects ─────────────────────────────────────────────────
  // 42: Fireworks
  EffectSpeedProfile(effectId: 42, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Launch rate'),
  // 89: Fireworks Starburst
  EffectSpeedProfile(effectId: 89, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Burst rate'),
  // 90: Fireworks 1D
  EffectSpeedProfile(effectId: 90, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Launch rate'),

  // ─── Ripple effects ────────────────────────────────────────────────────
  // 79: Ripple
  EffectSpeedProfile(effectId: 79, rawMin: 5, rawMax: 170, rawDefault: 35, rawRecommendedMax: 110, curveType: SpeedCurveType.logarithmic, label: 'Ripple speed'),
  // 99: Ripple Rainbow
  EffectSpeedProfile(effectId: 99, rawMin: 5, rawMax: 170, rawDefault: 35, rawRecommendedMax: 110, curveType: SpeedCurveType.logarithmic, label: 'Ripple speed'),

  // ─── Rainbow effects ───────────────────────────────────────────────────
  // 9: Rainbow
  EffectSpeedProfile(effectId: 9, rawMin: 5, rawMax: 180, rawDefault: 40, rawRecommendedMax: 110, curveType: SpeedCurveType.logarithmic, label: 'Cycle speed'),
  // 33: Rainbow Runner
  EffectSpeedProfile(effectId: 33, rawMin: 10, rawMax: 200, rawDefault: 55, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Run speed'),
  // 63: Pride 2015
  EffectSpeedProfile(effectId: 63, rawMin: 5, rawMax: 170, rawDefault: 40, rawRecommendedMax: 110, curveType: SpeedCurveType.logarithmic, label: 'Wave speed'),

  // ─── Strobe effects ────────────────────────────────────────────────────
  // 23: Strobe
  EffectSpeedProfile(effectId: 23, rawMin: 10, rawMax: 230, rawDefault: 80, rawRecommendedMax: 170, curveType: SpeedCurveType.logarithmic, label: 'Strobe rate'),
  // 24: Strobe Rainbow
  EffectSpeedProfile(effectId: 24, rawMin: 10, rawMax: 230, rawDefault: 80, rawRecommendedMax: 170, curveType: SpeedCurveType.logarithmic, label: 'Strobe rate'),
  // 25: Strobe Mega
  EffectSpeedProfile(effectId: 25, rawMin: 10, rawMax: 240, rawDefault: 90, rawRecommendedMax: 180, curveType: SpeedCurveType.logarithmic, label: 'Strobe rate'),
  // 57: Lightning
  EffectSpeedProfile(effectId: 57, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Flash rate'),

  // ─── Ambient effects ───────────────────────────────────────────────────
  // 38: Aurora
  EffectSpeedProfile(effectId: 38, rawMin: 5, rawMax: 150, rawDefault: 30, rawRecommendedMax: 90, curveType: SpeedCurveType.logarithmic, label: 'Aurora drift'),
  // 39: Stream
  EffectSpeedProfile(effectId: 39, rawMin: 5, rawMax: 160, rawDefault: 30, rawRecommendedMax: 100, curveType: SpeedCurveType.easeOut, label: 'Flow speed'),
  // 43: Rain
  EffectSpeedProfile(effectId: 43, rawMin: 5, rawMax: 170, rawDefault: 35, rawRecommendedMax: 110, curveType: SpeedCurveType.logarithmic, label: 'Rain rate'),
  // 61: Stream 2
  EffectSpeedProfile(effectId: 61, rawMin: 5, rawMax: 160, rawDefault: 30, rawRecommendedMax: 100, curveType: SpeedCurveType.easeOut, label: 'Flow speed'),
  // 67: Colorwaves
  EffectSpeedProfile(effectId: 67, rawMin: 5, rawMax: 160, rawDefault: 30, rawRecommendedMax: 100, curveType: SpeedCurveType.easeOut, label: 'Wave speed'),
  // 75: Lake
  EffectSpeedProfile(effectId: 75, rawMin: 5, rawMax: 150, rawDefault: 25, rawRecommendedMax: 90, curveType: SpeedCurveType.logarithmic, label: 'Shimmer'),
  // 96: Drip
  EffectSpeedProfile(effectId: 96, rawMin: 5, rawMax: 170, rawDefault: 35, rawRecommendedMax: 110, curveType: SpeedCurveType.logarithmic, label: 'Drip rate'),
  // 97: Plasma
  EffectSpeedProfile(effectId: 97, rawMin: 5, rawMax: 160, rawDefault: 30, rawRecommendedMax: 100, curveType: SpeedCurveType.easeOut, label: 'Plasma flow'),
  // 101: Pacifica
  EffectSpeedProfile(effectId: 101, rawMin: 5, rawMax: 150, rawDefault: 25, rawRecommendedMax: 90, curveType: SpeedCurveType.logarithmic, label: 'Ocean drift'),
  // 104: Sunrise
  EffectSpeedProfile(effectId: 104, rawMin: 5, rawMax: 140, rawDefault: 20, rawRecommendedMax: 80, curveType: SpeedCurveType.logarithmic, label: 'Rise speed'),
  // 105: Phased
  EffectSpeedProfile(effectId: 105, rawMin: 5, rawMax: 160, rawDefault: 30, rawRecommendedMax: 100, curveType: SpeedCurveType.logarithmic, label: 'Phase speed'),
  // 110: Flow
  EffectSpeedProfile(effectId: 110, rawMin: 5, rawMax: 160, rawDefault: 30, rawRecommendedMax: 100, curveType: SpeedCurveType.easeOut, label: 'Flow speed'),
  // 112: Dancing Shadows
  EffectSpeedProfile(effectId: 112, rawMin: 5, rawMax: 160, rawDefault: 35, rawRecommendedMax: 100, curveType: SpeedCurveType.logarithmic, label: 'Shadow pace'),
  // 115: Blends
  EffectSpeedProfile(effectId: 115, rawMin: 5, rawMax: 160, rawDefault: 30, rawRecommendedMax: 100, curveType: SpeedCurveType.easeOut, label: 'Blend speed'),
  // 116: TV Simulator
  EffectSpeedProfile(effectId: 116, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Flicker rate'),

  // ─── Noise effects ─────────────────────────────────────────────────────
  // 69: Fill Noise
  EffectSpeedProfile(effectId: 69, rawMin: 5, rawMax: 160, rawDefault: 30, rawRecommendedMax: 100, curveType: SpeedCurveType.logarithmic, label: 'Noise speed'),
  // 70: Noise 1
  EffectSpeedProfile(effectId: 70, rawMin: 5, rawMax: 160, rawDefault: 30, rawRecommendedMax: 100, curveType: SpeedCurveType.logarithmic, label: 'Noise speed'),
  // 71: Noise 2
  EffectSpeedProfile(effectId: 71, rawMin: 5, rawMax: 160, rawDefault: 30, rawRecommendedMax: 100, curveType: SpeedCurveType.logarithmic, label: 'Noise speed'),
  // 72: Noise 3
  EffectSpeedProfile(effectId: 72, rawMin: 5, rawMax: 160, rawDefault: 30, rawRecommendedMax: 100, curveType: SpeedCurveType.logarithmic, label: 'Noise speed'),
  // 73: Noise 4
  EffectSpeedProfile(effectId: 73, rawMin: 5, rawMax: 160, rawDefault: 30, rawRecommendedMax: 100, curveType: SpeedCurveType.logarithmic, label: 'Noise speed'),
  // 107: Noise Pal
  EffectSpeedProfile(effectId: 107, rawMin: 5, rawMax: 160, rawDefault: 30, rawRecommendedMax: 100, curveType: SpeedCurveType.logarithmic, label: 'Noise speed'),
  // 109: Phased Noise
  EffectSpeedProfile(effectId: 109, rawMin: 5, rawMax: 160, rawDefault: 30, rawRecommendedMax: 100, curveType: SpeedCurveType.logarithmic, label: 'Noise speed'),

  // ─── Game effects ──────────────────────────────────────────────────────
  // 44: Tetrix
  EffectSpeedProfile(effectId: 44, rawMin: 10, rawMax: 210, rawDefault: 60, rawRecommendedMax: 150, curveType: SpeedCurveType.logarithmic, label: 'Drop speed'),
  // 91: Bouncing Balls
  EffectSpeedProfile(effectId: 91, rawMin: 10, rawMax: 200, rawDefault: 55, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Bounce speed'),
  // 95: Popcorn
  EffectSpeedProfile(effectId: 95, rawMin: 10, rawMax: 200, rawDefault: 55, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Pop rate'),

  // ─── Holiday effects ───────────────────────────────────────────────────
  // 82: Halloween Eyes
  EffectSpeedProfile(effectId: 82, rawMin: 5, rawMax: 170, rawDefault: 40, rawRecommendedMax: 110, curveType: SpeedCurveType.logarithmic, label: 'Blink rate'),

  // ─── Audio-reactive effects ────────────────────────────────────────────
  // Audio effects generally respond to sound; speed controls reactivity.
  // TODO: Tune these during QA — audio responsiveness varies by microphone.
  EffectSpeedProfile(effectId: 129, rawMin: 10, rawMax: 220, rawDefault: 80, rawRecommendedMax: 170, curveType: SpeedCurveType.logarithmic, label: 'Reactivity'),
  EffectSpeedProfile(effectId: 130, rawMin: 10, rawMax: 220, rawDefault: 80, rawRecommendedMax: 170, curveType: SpeedCurveType.logarithmic, label: 'Reactivity'),
  EffectSpeedProfile(effectId: 131, rawMin: 10, rawMax: 220, rawDefault: 80, rawRecommendedMax: 170, curveType: SpeedCurveType.logarithmic, label: 'Reactivity'),
  EffectSpeedProfile(effectId: 132, rawMin: 10, rawMax: 220, rawDefault: 80, rawRecommendedMax: 170, curveType: SpeedCurveType.logarithmic, label: 'Reactivity'),
  EffectSpeedProfile(effectId: 133, rawMin: 10, rawMax: 220, rawDefault: 80, rawRecommendedMax: 170, curveType: SpeedCurveType.logarithmic, label: 'Reactivity'),
  EffectSpeedProfile(effectId: 134, rawMin: 10, rawMax: 220, rawDefault: 80, rawRecommendedMax: 170, curveType: SpeedCurveType.logarithmic, label: 'Reactivity'),
  EffectSpeedProfile(effectId: 135, rawMin: 10, rawMax: 220, rawDefault: 80, rawRecommendedMax: 170, curveType: SpeedCurveType.logarithmic, label: 'Reactivity'),
  EffectSpeedProfile(effectId: 136, rawMin: 10, rawMax: 220, rawDefault: 80, rawRecommendedMax: 170, curveType: SpeedCurveType.logarithmic, label: 'Reactivity'),
  EffectSpeedProfile(effectId: 137, rawMin: 10, rawMax: 220, rawDefault: 80, rawRecommendedMax: 170, curveType: SpeedCurveType.logarithmic, label: 'Reactivity'),
  EffectSpeedProfile(effectId: 138, rawMin: 10, rawMax: 220, rawDefault: 80, rawRecommendedMax: 170, curveType: SpeedCurveType.logarithmic, label: 'Reactivity'),
  EffectSpeedProfile(effectId: 139, rawMin: 10, rawMax: 220, rawDefault: 80, rawRecommendedMax: 170, curveType: SpeedCurveType.logarithmic, label: 'Reactivity'),
  EffectSpeedProfile(effectId: 140, rawMin: 10, rawMax: 220, rawDefault: 80, rawRecommendedMax: 170, curveType: SpeedCurveType.logarithmic, label: 'Reactivity'),
  EffectSpeedProfile(effectId: 141, rawMin: 10, rawMax: 220, rawDefault: 80, rawRecommendedMax: 170, curveType: SpeedCurveType.logarithmic, label: 'Reactivity'),
  EffectSpeedProfile(effectId: 143, rawMin: 10, rawMax: 220, rawDefault: 80, rawRecommendedMax: 170, curveType: SpeedCurveType.logarithmic, label: 'Reactivity'),
  EffectSpeedProfile(effectId: 144, rawMin: 10, rawMax: 220, rawDefault: 80, rawRecommendedMax: 170, curveType: SpeedCurveType.logarithmic, label: 'Reactivity'),
  EffectSpeedProfile(effectId: 145, rawMin: 10, rawMax: 220, rawDefault: 80, rawRecommendedMax: 170, curveType: SpeedCurveType.logarithmic, label: 'Reactivity'),
  EffectSpeedProfile(effectId: 147, rawMin: 10, rawMax: 220, rawDefault: 80, rawRecommendedMax: 170, curveType: SpeedCurveType.logarithmic, label: 'Reactivity'),
  EffectSpeedProfile(effectId: 148, rawMin: 10, rawMax: 220, rawDefault: 80, rawRecommendedMax: 170, curveType: SpeedCurveType.logarithmic, label: 'Reactivity'),
  EffectSpeedProfile(effectId: 155, rawMin: 10, rawMax: 220, rawDefault: 80, rawRecommendedMax: 170, curveType: SpeedCurveType.logarithmic, label: 'Reactivity'),
  EffectSpeedProfile(effectId: 156, rawMin: 10, rawMax: 220, rawDefault: 80, rawRecommendedMax: 170, curveType: SpeedCurveType.logarithmic, label: 'Reactivity'),
  EffectSpeedProfile(effectId: 157, rawMin: 10, rawMax: 220, rawDefault: 80, rawRecommendedMax: 170, curveType: SpeedCurveType.logarithmic, label: 'Reactivity'),
  EffectSpeedProfile(effectId: 158, rawMin: 10, rawMax: 220, rawDefault: 80, rawRecommendedMax: 170, curveType: SpeedCurveType.logarithmic, label: 'Reactivity'),
  EffectSpeedProfile(effectId: 159, rawMin: 10, rawMax: 220, rawDefault: 80, rawRecommendedMax: 170, curveType: SpeedCurveType.logarithmic, label: 'Reactivity'),
  EffectSpeedProfile(effectId: 160, rawMin: 10, rawMax: 220, rawDefault: 80, rawRecommendedMax: 170, curveType: SpeedCurveType.logarithmic, label: 'Reactivity'),
  EffectSpeedProfile(effectId: 163, rawMin: 10, rawMax: 220, rawDefault: 80, rawRecommendedMax: 170, curveType: SpeedCurveType.logarithmic, label: 'Reactivity'),
  EffectSpeedProfile(effectId: 165, rawMin: 10, rawMax: 220, rawDefault: 80, rawRecommendedMax: 170, curveType: SpeedCurveType.logarithmic, label: 'Reactivity'),
  EffectSpeedProfile(effectId: 175, rawMin: 10, rawMax: 220, rawDefault: 80, rawRecommendedMax: 170, curveType: SpeedCurveType.logarithmic, label: 'Reactivity'),
  EffectSpeedProfile(effectId: 185, rawMin: 10, rawMax: 220, rawDefault: 80, rawRecommendedMax: 170, curveType: SpeedCurveType.logarithmic, label: 'Reactivity'),

  // ─── 2D effects ────────────────────────────────────────────────────────
  // TODO: 2D effects need per-effect QA tuning on actual matrix hardware.
  // Using moderate defaults for now.
  EffectSpeedProfile(effectId: 118, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Motion'),
  EffectSpeedProfile(effectId: 119, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Motion'),
  EffectSpeedProfile(effectId: 120, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Motion'),
  EffectSpeedProfile(effectId: 121, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Motion'),
  EffectSpeedProfile(effectId: 122, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Scroll speed'),
  EffectSpeedProfile(effectId: 123, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Drift speed'),
  EffectSpeedProfile(effectId: 124, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Wave speed'),
  EffectSpeedProfile(effectId: 125, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Motion'),
  EffectSpeedProfile(effectId: 126, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Motion'),
  EffectSpeedProfile(effectId: 127, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Wave speed'),
  EffectSpeedProfile(effectId: 146, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Noise speed'),
  EffectSpeedProfile(effectId: 149, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Fire speed'),
  EffectSpeedProfile(effectId: 150, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Swirl speed'),
  EffectSpeedProfile(effectId: 152, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Helix speed'),
  EffectSpeedProfile(effectId: 153, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Rain speed'),
  EffectSpeedProfile(effectId: 154, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Motion'),
  EffectSpeedProfile(effectId: 162, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Pulse speed'),
  EffectSpeedProfile(effectId: 164, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Drift speed'),
  EffectSpeedProfile(effectId: 166, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Radiation'),
  EffectSpeedProfile(effectId: 167, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Burst rate'),
  EffectSpeedProfile(effectId: 168, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Motion'),
  EffectSpeedProfile(effectId: 172, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Generation'),
  EffectSpeedProfile(effectId: 173, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Motion'),
  EffectSpeedProfile(effectId: 174, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Aurora drift'),
  EffectSpeedProfile(effectId: 176, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Motion'),
  EffectSpeedProfile(effectId: 177, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Motion'),
  EffectSpeedProfile(effectId: 178, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Motion'),
  EffectSpeedProfile(effectId: 179, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.easeOut, label: 'Flow speed'),
  EffectSpeedProfile(effectId: 180, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Motion'),
  EffectSpeedProfile(effectId: 181, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Motion'),
  EffectSpeedProfile(effectId: 182, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Helix speed'),
  EffectSpeedProfile(effectId: 183, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Motion'),
  EffectSpeedProfile(effectId: 184, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Wave speed'),
  EffectSpeedProfile(effectId: 186, rawMin: 10, rawMax: 200, rawDefault: 60, rawRecommendedMax: 140, curveType: SpeedCurveType.logarithmic, label: 'Motion'),
];
