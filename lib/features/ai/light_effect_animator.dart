import 'dart:math' as math;
import 'package:flutter/material.dart';

/// The effect types available for the compact LED preview strip.
///
/// These are simplified categories that map to groups of WLED effect IDs.
/// Use [effectTypeFromWledId] to convert a raw WLED effect ID.
enum EffectType {
  solid,
  chase,
  fade,
  twinkle,
  sparkle,
  rainbow,
  gradient,
  breathe,
}

/// Map a raw WLED effect ID to the preview [EffectType].
EffectType effectTypeFromWledId(int effectId) {
  // Solid
  if (effectId == 0) return EffectType.solid;

  // Breathe / pulse
  if (effectId == 2 || effectId == 25) return EffectType.breathe;

  // Chase / running / theater
  if (const {3, 4, 14, 15, 28, 29, 33, 34, 47, 48, 64, 87, 111, 112, 115}
      .contains(effectId)) {
    return EffectType.chase;
  }

  // Rainbow / color cycling
  if (const {9, 10, 102}.contains(effectId)) return EffectType.rainbow;

  // Gradient / blends
  if (const {46, 89, 101}.contains(effectId)) return EffectType.gradient;

  // Twinkle
  if (const {49, 50, 74, 108, 109, 117, 118}.contains(effectId)) {
    return EffectType.twinkle;
  }

  // Sparkle
  if (const {52, 65, 66, 78, 80}.contains(effectId)) {
    return EffectType.sparkle;
  }

  // Fade / dissolve
  if (const {1, 13, 38}.contains(effectId)) return EffectType.fade;

  // Default animated effects → chase
  return EffectType.chase;
}

/// Pure-function effect engine.
///
/// Given base [colors], an [effect] type, the desired [pixelCount], and the
/// current animation [phase] (0.0–1.0 looping), returns a `List<Color>` of
/// length [pixelCount] representing the current frame.
///
/// [speed] and [brightness] are both normalized 0.0–1.0.
class LightEffectAnimator {
  const LightEffectAnimator._();

  /// Compute one frame of the effect animation.
  static List<Color> computeFrame({
    required List<Color> colors,
    required EffectType effect,
    required int pixelCount,
    required double phase,
    double speed = 0.5,
    double brightness = 1.0,
  }) {
    if (colors.isEmpty || pixelCount <= 0) {
      return List.filled(pixelCount.clamp(0, 300), Colors.black);
    }

    switch (effect) {
      case EffectType.solid:
        return _solid(colors, pixelCount, phase, brightness);
      case EffectType.chase:
        return _chase(colors, pixelCount, phase, brightness);
      case EffectType.fade:
        return _fade(colors, pixelCount, phase, brightness);
      case EffectType.twinkle:
        return _twinkle(colors, pixelCount, phase, brightness);
      case EffectType.sparkle:
        return _sparkle(colors, pixelCount, phase, brightness);
      case EffectType.rainbow:
        return _rainbow(colors, pixelCount, phase, brightness);
      case EffectType.gradient:
        return _gradient(colors, pixelCount, phase, brightness);
      case EffectType.breathe:
        return _breathe(colors, pixelCount, phase, brightness);
    }
  }

  /// Returns the recommended animation duration for an effect type.
  static Duration durationForEffect(EffectType effect, double speed) {
    // Speed 0.0 → slowest, 1.0 → fastest
    // Base durations per effect, then scaled by speed
    final double baseMs;
    switch (effect) {
      case EffectType.solid:
        baseMs = 3000; // gentle glow pulse
      case EffectType.breathe:
        baseMs = 3000;
      case EffectType.fade:
        baseMs = 4000;
      case EffectType.chase:
        baseMs = 2500;
      case EffectType.rainbow:
        baseMs = 4000;
      case EffectType.gradient:
        baseMs = 5000;
      case EffectType.twinkle:
        baseMs = 3500;
      case EffectType.sparkle:
        baseMs = 2000;
    }

    // Speed 0 → 1.6x slower, speed 1 → 0.4x faster
    final multiplier = 1.6 - speed * 1.2;
    return Duration(milliseconds: (baseMs * multiplier).round());
  }

  // -------------------------------------------------------------------------
  // Effect implementations
  // -------------------------------------------------------------------------

  /// Static colors with a subtle breathing glow pulse.
  static List<Color> _solid(
      List<Color> colors, int count, double phase, double bri) {
    // Very gentle pulse: 90%–100% brightness
    final pulse = 0.90 + 0.10 * ((math.sin(phase * math.pi * 2) + 1) / 2);
    final effectiveBri = bri * pulse;

    return List.generate(count, (i) {
      final base = colors[i % colors.length];
      return _applyBrightness(base, effectiveBri);
    });
  }

  /// Colors shift smoothly left-to-right (or right-to-left).
  static List<Color> _chase(
      List<Color> colors, int count, double phase, double bri) {
    // Chase head moves across the strip
    final headPos = phase * count;
    final trailLength = (count * 0.45).clamp(3.0, count * 0.6);

    return List.generate(count, (i) {
      double dist = (i - headPos) % count;
      if (dist < 0) dist += count;

      if (dist < trailLength) {
        final fade = math.cos(dist / trailLength * math.pi / 2);
        final base = colors[i % colors.length];
        return _applyBrightness(base, bri * fade);
      }

      return Colors.black;
    });
  }

  /// All LEDs cross-fade between the provided colors sequentially.
  static List<Color> _fade(
      List<Color> colors, int count, double phase, double bri) {
    if (colors.length < 2) return _solid(colors, count, phase, bri);

    // Which pair of colors are we blending between?
    final scaledPhase = phase * colors.length;
    final fromIdx = scaledPhase.floor() % colors.length;
    final toIdx = (fromIdx + 1) % colors.length;
    final blend = scaledPhase - scaledPhase.floor();

    // Smooth easing
    final easedBlend = _smoothstep(blend);
    final blended = Color.lerp(colors[fromIdx], colors[toIdx], easedBlend)!;
    final adjusted = _applyBrightness(blended, bri);

    return List.filled(count, adjusted);
  }

  /// Random LEDs briefly brighten to white and back.
  static List<Color> _twinkle(
      List<Color> colors, int count, double phase, double bri) {
    // Base: dim version of the colors
    final result = List.generate(count, (i) {
      final base = colors[i % colors.length];
      return _applyBrightness(base, bri * 0.30);
    });

    // Overlay twinkle flashes — use phase-seeded random for determinism
    final sparkleSet = (phase * 12).floor();
    final rng = math.Random(sparkleSet);
    final subPhase = (phase * 12) % 1.0;
    // Smooth triangle wave for fade in/out
    final fadeEnvelope = subPhase < 0.5
        ? subPhase / 0.5
        : (1.0 - subPhase) / 0.5;

    final sparkleCount = (count * 0.15).ceil().clamp(2, 10);
    for (int s = 0; s < sparkleCount; s++) {
      final idx = rng.nextInt(count);
      final base = colors[idx % colors.length];
      final white = Color.lerp(base, Colors.white, 0.70)!;
      result[idx] = _applyBrightness(white, bri * (0.6 + 0.4 * fadeEnvelope));
    }

    return result;
  }

  /// White flashes overlay the base color pattern.
  static List<Color> _sparkle(
      List<Color> colors, int count, double phase, double bri) {
    // Base: full-brightness color pattern
    final result = List.generate(count, (i) {
      final base = colors[i % colors.length];
      return _applyBrightness(base, bri);
    });

    // Rapid white flashes
    final sparkleSet = (phase * 20).floor();
    final rng = math.Random(sparkleSet);
    final subPhase = (phase * 20) % 1.0;
    final flashIntensity = subPhase < 0.3 ? subPhase / 0.3 : 0.0;

    final flashCount = (count * 0.08).ceil().clamp(1, 6);
    for (int s = 0; s < flashCount; s++) {
      final idx = rng.nextInt(count);
      if (flashIntensity > 0.01) {
        result[idx] = Color.lerp(
            result[idx], Colors.white, flashIntensity * 0.9)!;
      }
    }

    return result;
  }

  /// Smooth hue rotation across the strip.
  static List<Color> _rainbow(
      List<Color> colors, int count, double phase, double bri) {
    return List.generate(count, (i) {
      final hue = ((i / count + phase) % 1.0) * 360;
      final hsv = HSVColor.fromAHSV(1.0, hue, 0.9, 1.0);
      return _applyBrightness(hsv.toColor(), bri);
    });
  }

  /// Smooth interpolation between defined color stops, slowly shifting.
  static List<Color> _gradient(
      List<Color> colors, int count, double phase, double bri) {
    if (colors.length < 2) return _solid(colors, count, phase, bri);

    return List.generate(count, (i) {
      // Shift the gradient position over time
      final t = ((i / (count - 1)) + phase) % 1.0;
      final scaledT = t * (colors.length - 1);
      final fromIdx = scaledT.floor().clamp(0, colors.length - 2);
      final blend = scaledT - fromIdx;
      final easedBlend = _smoothstep(blend);
      final color =
          Color.lerp(colors[fromIdx], colors[fromIdx + 1], easedBlend)!;
      return _applyBrightness(color, bri);
    });
  }

  /// All LEDs pulse brightness in unison (sine wave).
  static List<Color> _breathe(
      List<Color> colors, int count, double phase, double bri) {
    // Sine wave: min 25% brightness, max 100%
    final pulse = 0.25 + 0.75 * ((math.sin(phase * math.pi * 2) + 1) / 2);
    final effectiveBri = bri * pulse;

    return List.generate(count, (i) {
      final base = colors[i % colors.length];
      return _applyBrightness(base, effectiveBri);
    });
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  /// Apply a 0.0–1.0 brightness multiplier to a color by lerping toward black.
  static Color _applyBrightness(Color color, double brightness) {
    if (brightness >= 1.0) return color;
    if (brightness <= 0.0) return Colors.black;
    return Color.lerp(Colors.black, color, brightness)!;
  }

  /// Hermite smoothstep for easing (0→0, 0.5→0.5, 1→1 with smooth slopes).
  static double _smoothstep(double t) {
    final ct = t.clamp(0.0, 1.0);
    return ct * ct * (3 - 2 * ct);
  }
}
