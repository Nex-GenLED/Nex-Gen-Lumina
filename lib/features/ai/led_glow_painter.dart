import 'package:flutter/material.dart';

/// CustomPainter that renders a row of LED dots with a colored glow bloom.
///
/// Supports two layout modes:
/// - **Linear** (default): equally-spaced dots along a horizontal line.
/// - **Arc**: dots follow a gentle upward curve to mimic a roofline shape.
///
/// Each LED is drawn in three layers for a premium "lit bulb" look:
///   1. Outer bloom halo (large, blurred, low opacity)
///   2. Filled LED body (crisp circle)
///   3. Hot-center highlight (small, bright, white-shifted)
class LedGlowPainter extends CustomPainter {
  /// One color per LED. Length determines pixel count.
  final List<Color> ledColors;

  /// Diameter of each LED dot.
  final double ledSize;

  /// If true, LEDs follow a gentle upward arc instead of a straight line.
  final bool arcLayout;

  /// Curvature factor for arc mode (0.0 = flat, 1.0 = very curved).
  /// Typically 0.15–0.35 looks like a residential roofline.
  final double arcCurvature;

  /// Overall brightness multiplier (0.0–1.0).
  final double brightness;

  LedGlowPainter({
    required this.ledColors,
    this.ledSize = 6.0,
    this.arcLayout = false,
    this.arcCurvature = 0.2,
    this.brightness = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (ledColors.isEmpty) return;

    final count = ledColors.length;
    final radius = ledSize / 2;

    // Horizontal padding so the outermost glow doesn't clip
    final hPad = ledSize + 4;
    final usableWidth = size.width - hPad * 2;

    // Vertical center line (arc bows upward from here)
    final centerY = size.height / 2 + radius;

    for (int i = 0; i < count; i++) {
      final t = count > 1 ? i / (count - 1) : 0.5;
      final x = hPad + t * usableWidth;

      // Arc offset: parabola peaking at center, zero at edges
      double y = centerY;
      if (arcLayout) {
        final arcOffset = 4.0 * arcCurvature * size.height * t * (1 - t);
        y = centerY - arcOffset;
      }

      final pos = Offset(x, y);
      final color = ledColors[i];

      // Skip fully black / off LEDs
      final lum = color.computeLuminance();
      if (lum < 0.005 && brightness < 0.02) continue;

      _drawLed(canvas, pos, color, radius);
    }
  }

  void _drawLed(Canvas canvas, Offset pos, Color color, double radius) {
    final effectiveBri = brightness.clamp(0.0, 1.0);

    // --- Layer 1: Outer glow bloom ---
    final bloomRadius = radius * 3.2;
    final bloomPaint = Paint()
      ..color = color.withValues(alpha: 0.30 * effectiveBri)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 2.5);
    canvas.drawCircle(pos, bloomRadius, bloomPaint);

    // --- Layer 2: LED body ---
    final bodyPaint = Paint()
      ..color = color.withValues(alpha: effectiveBri)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pos, radius, bodyPaint);

    // --- Layer 3: Hot center highlight ---
    final highlightColor = Color.lerp(color, Colors.white, 0.50)!;
    final highlightPaint = Paint()
      ..color = highlightColor.withValues(alpha: 0.70 * effectiveBri)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pos, radius * 0.35, highlightPaint);
  }

  @override
  bool shouldRepaint(LedGlowPainter oldDelegate) {
    return oldDelegate.brightness != brightness ||
        oldDelegate.ledSize != ledSize ||
        oldDelegate.arcLayout != arcLayout ||
        oldDelegate.arcCurvature != arcCurvature ||
        !_colorsEqual(oldDelegate.ledColors, ledColors);
  }

  static bool _colorsEqual(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
