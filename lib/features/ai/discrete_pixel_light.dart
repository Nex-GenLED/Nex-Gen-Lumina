import 'package:flutter/material.dart';

/// Static painting utilities for a single discrete LED pixel.
///
/// Each pixel is rendered as three layers:
///   1. **Glow** — soft radial blur behind the circle (simulates light bleed)
///   2. **Body** — filled circle with the assigned color
///   3. **Specular** — small white highlight at top-left (bulb appearance)
///
/// All methods are static for zero allocation overhead in paint loops.
class DiscretePixelLight {
  DiscretePixelLight._();

  /// Paint one LED pixel at [center].
  ///
  /// - [color]: the pixel's assigned color this frame.
  /// - [radius]: circle radius in logical pixels.
  /// - [brightness]: 0.0–1.0 multiplier applied to color and glow.
  /// - [radiusScale]: additional multiplier on radius (for breathe effect).
  /// - [glowSigmaFactor]: sigma = radius * this factor (default 0.8).
  /// - [glowOpacity]: base opacity of the glow layer (default 0.35).
  /// - [specular]: whether to draw the specular highlight.
  /// - [adjacentGap]: distance to nearest neighbor pixel center; when pixels
  ///   are close together, glow sigma is reduced to prevent merging.
  static void paint(
    Canvas canvas,
    Offset center,
    Color color,
    double radius, {
    double brightness = 1.0,
    double radiusScale = 1.0,
    double glowSigmaFactor = 0.8,
    double glowOpacity = 0.35,
    bool specular = true,
    double? adjacentGap,
  }) {
    final r = radius * radiusScale;
    final bri = brightness.clamp(0.0, 1.0);
    if (bri < 0.01) return; // pixel off

    // Adjust glow sigma when pixels are close to prevent merging
    double sigma = r * glowSigmaFactor;
    if (adjacentGap != null && adjacentGap < r * 4) {
      sigma *= (adjacentGap / (r * 4)).clamp(0.3, 1.0);
    }

    // --- Layer 1: Glow ---
    final glowPaint = Paint()
      ..color = color.withValues(alpha: glowOpacity * bri)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);
    canvas.drawCircle(center, r * 2.0, glowPaint);

    // --- Layer 2: Body ---
    final bodyPaint = Paint()
      ..color = _applyBrightness(color, bri)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, r, bodyPaint);

    // --- Layer 3: Specular highlight ---
    if (specular && bri > 0.15) {
      final highlightOffset = Offset(center.dx - r * 0.25, center.dy - r * 0.25);
      final highlightPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.15 * bri)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(highlightOffset, r * 0.30, highlightPaint);
    }
  }

  /// Paint a batch of pixels efficiently.
  ///
  /// Uses [Canvas.saveLayer] for the glow pass to batch blur operations,
  /// then draws bodies and specular highlights in separate passes.
  static void paintBatch(
    Canvas canvas,
    Size canvasSize,
    List<Offset> positions,
    List<Color> colors,
    List<double> brightnesses,
    List<double> radiusScales,
    double baseRadius, {
    double glowSigmaFactor = 0.8,
    double glowOpacity = 0.35,
    bool specular = true,
  }) {
    final count = positions.length;
    if (count == 0) return;

    // Compute average gap between adjacent pixels for glow reduction
    double avgGap = baseRadius * 5; // default: wide enough for full glow
    if (count > 1) {
      double totalDist = 0;
      for (int i = 1; i < count; i++) {
        totalDist += (positions[i] - positions[i - 1]).distance;
      }
      avgGap = totalDist / (count - 1);
    }

    // Glow sigma adjusted for density
    double sigma = baseRadius * glowSigmaFactor;
    if (avgGap < baseRadius * 4) {
      sigma *= (avgGap / (baseRadius * 4)).clamp(0.3, 1.0);
    }

    // --- Pass 1: Glow layer (batched with saveLayer) ---
    canvas.saveLayer(
      Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height),
      Paint(),
    );
    final glowFilter = MaskFilter.blur(BlurStyle.normal, sigma);
    for (int i = 0; i < count; i++) {
      final bri = brightnesses[i].clamp(0.0, 1.0);
      if (bri < 0.01) continue;
      final r = baseRadius * radiusScales[i];
      final glowPaint = Paint()
        ..color = colors[i].withValues(alpha: glowOpacity * bri)
        ..maskFilter = glowFilter;
      canvas.drawCircle(positions[i], r * 2.0, glowPaint);
    }
    canvas.restore();

    // --- Pass 2: Bodies ---
    for (int i = 0; i < count; i++) {
      final bri = brightnesses[i].clamp(0.0, 1.0);
      if (bri < 0.01) continue;
      final r = baseRadius * radiusScales[i];
      final bodyPaint = Paint()
        ..color = _applyBrightness(colors[i], bri)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(positions[i], r, bodyPaint);
    }

    // --- Pass 3: Specular highlights ---
    if (specular) {
      for (int i = 0; i < count; i++) {
        final bri = brightnesses[i].clamp(0.0, 1.0);
        if (bri < 0.15) continue;
        final r = baseRadius * radiusScales[i];
        final off = Offset(
            positions[i].dx - r * 0.25, positions[i].dy - r * 0.25);
        final hlPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.15 * bri)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(off, r * 0.30, hlPaint);
      }
    }
  }

  static Color _applyBrightness(Color color, double brightness) {
    if (brightness >= 1.0) return color;
    if (brightness <= 0.0) return Colors.black;
    return Color.lerp(Colors.black, color, brightness)!;
  }
}
