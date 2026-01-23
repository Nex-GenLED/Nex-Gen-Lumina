import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:nexgen_command/features/ar/ar_preview_providers.dart';
import 'package:nexgen_command/models/roofline_mask.dart';

/// CustomPainter that renders LED light effects along the roofline.
///
/// Supports multiple effect types:
/// - Solid: Single color glow across the roofline
/// - Breathe: Pulsing opacity animation
/// - Chase: Moving color segment with trail
/// - Rainbow: Cycling hue gradient
/// - Twinkle: Random sparkle points
/// - Wave: Oscillating color pattern
class RooflineLightPainter extends CustomPainter {
  final List<Color> colors;
  final double animationPhase; // 0.0 to 1.0
  final int effectId;
  final int speed;
  final int intensity;
  final RooflineMask? mask;
  final bool isOn;
  final int brightness;
  final int ledCount; // Virtual LED count for simulation

  RooflineLightPainter({
    required this.colors,
    this.animationPhase = 0.0,
    this.effectId = 0,
    this.speed = 128,
    this.intensity = 128,
    this.mask,
    this.isOn = true,
    this.brightness = 255,
    this.ledCount = 120,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!isOn || colors.isEmpty || brightness == 0) return;

    final effectiveColors = colors.isEmpty ? [Colors.white] : colors;
    final category = categorizeEffect(effectId);
    final brightnessFactor = brightness / 255.0;

    // Check if we have custom roofline points
    if (mask != null && mask!.hasCustomPoints && mask!.points.length >= 2) {
      // Use custom roofline path
      final canvasPoints = mask!.points
          .map((p) => Offset(p.dx * size.width, p.dy * size.height))
          .toList();

      _paintAlongPath(canvas, size, canvasPoints, effectiveColors, brightnessFactor, category);
      return;
    }

    // Fall back to rectangle-based rendering
    final maskHeight = mask?.maskHeight ?? 0.25;
    final rooflineRect = Rect.fromLTWH(
      0,
      0,
      size.width,
      size.height * maskHeight,
    );

    switch (category) {
      case EffectCategory.solid:
        _paintSolid(canvas, rooflineRect, effectiveColors, brightnessFactor);
        break;
      case EffectCategory.breathe:
        _paintBreathe(canvas, rooflineRect, effectiveColors, brightnessFactor);
        break;
      case EffectCategory.chase:
        _paintChase(canvas, rooflineRect, effectiveColors, brightnessFactor);
        break;
      case EffectCategory.rainbow:
        _paintRainbow(canvas, rooflineRect, brightnessFactor);
        break;
      case EffectCategory.twinkle:
        _paintTwinkle(canvas, rooflineRect, effectiveColors, brightnessFactor);
        break;
      case EffectCategory.wave:
        _paintWave(canvas, rooflineRect, effectiveColors, brightnessFactor);
        break;
      case EffectCategory.fire:
        _paintFire(canvas, rooflineRect, brightnessFactor);
        break;
    }
  }

  /// Paint light effects along a custom roofline path
  void _paintAlongPath(
    Canvas canvas,
    Size size,
    List<Offset> points,
    List<Color> colors,
    double brightness,
    EffectCategory category,
  ) {
    // Create the roofline path
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    // Calculate total path length for LED distribution
    double totalLength = 0;
    for (int i = 1; i < points.length; i++) {
      totalLength += (points[i] - points[i - 1]).distance;
    }

    // Get positions along the path for each virtual LED
    final ledPositions = _getLedPositionsAlongPath(points, totalLength);

    switch (category) {
      case EffectCategory.solid:
        _paintSolidPath(canvas, path, ledPositions, colors, brightness);
        break;
      case EffectCategory.breathe:
        _paintBreathePath(canvas, path, ledPositions, colors, brightness);
        break;
      case EffectCategory.chase:
        _paintChasePath(canvas, ledPositions, colors, brightness);
        break;
      case EffectCategory.rainbow:
        _paintRainbowPath(canvas, ledPositions, brightness);
        break;
      case EffectCategory.twinkle:
        _paintTwinklePath(canvas, ledPositions, colors, brightness);
        break;
      case EffectCategory.wave:
        _paintWavePath(canvas, ledPositions, colors, brightness);
        break;
      case EffectCategory.fire:
        _paintFirePath(canvas, ledPositions, brightness);
        break;
    }
  }

  /// Calculate LED positions distributed along the path
  List<Offset> _getLedPositionsAlongPath(List<Offset> points, double totalLength) {
    final positions = <Offset>[];
    final segmentLength = totalLength / ledCount;

    double accumulatedLength = 0;
    int segmentIndex = 0;

    for (int i = 0; i < ledCount; i++) {
      final targetLength = i * segmentLength;

      // Find the segment containing this position
      while (segmentIndex < points.length - 1) {
        final segStart = points[segmentIndex];
        final segEnd = points[segmentIndex + 1];
        final segLen = (segEnd - segStart).distance;

        if (accumulatedLength + segLen >= targetLength) {
          // Position is in this segment
          final progressInSegment = (targetLength - accumulatedLength) / segLen;
          final pos = Offset(
            segStart.dx + (segEnd.dx - segStart.dx) * progressInSegment,
            segStart.dy + (segEnd.dy - segStart.dy) * progressInSegment,
          );
          positions.add(pos);
          break;
        }

        accumulatedLength += segLen;
        segmentIndex++;
      }

      // Handle edge case where we've reached the end
      if (positions.length <= i) {
        positions.add(points.last);
      }
    }

    return positions;
  }

  /// Paint solid color along the roofline path
  void _paintSolidPath(Canvas canvas, Path path, List<Offset> positions, List<Color> colors, double brightness) {
    // Draw glow along the path
    final glowPaint = Paint()
      ..color = colors.first.withValues(alpha: 0.4 * brightness)
      ..strokeWidth = 30
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.screen
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);
    canvas.drawPath(path, glowPaint);

    // Draw main light line
    final mainPaint = Paint()
      ..color = colors.first.withValues(alpha: 0.7 * brightness)
      ..strokeWidth = 12
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.screen
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawPath(path, mainPaint);

    // Draw LED points for texture
    for (int i = 0; i < positions.length; i++) {
      final colorIndex = (i * colors.length ~/ positions.length) % colors.length;
      final color = colors[colorIndex];
      final ledPaint = Paint()
        ..color = color.withValues(alpha: 0.9 * brightness)
        ..blendMode = BlendMode.screen
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(positions[i], 4, ledPaint);
    }
  }

  /// Paint breathing effect along path
  void _paintBreathePath(Canvas canvas, Path path, List<Offset> positions, List<Color> colors, double brightness) {
    final breathePhase = math.sin(animationPhase * math.pi * 2);
    final breatheIntensity = 0.3 + (breathePhase + 1) / 2 * 0.7;
    final effectiveBrightness = brightness * breatheIntensity;

    final glowPaint = Paint()
      ..color = colors.first.withValues(alpha: 0.5 * effectiveBrightness)
      ..strokeWidth = 25 + breathePhase * 10
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.screen
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 12 + breathePhase * 5);
    canvas.drawPath(path, glowPaint);
  }

  /// Paint chase effect along path
  void _paintChasePath(Canvas canvas, List<Offset> positions, List<Color> colors, double brightness) {
    // Longer chase segment for smoother visual flow
    final chaseLength = ledCount ~/ 3;
    final chaseStart = (animationPhase * ledCount).floor();

    for (int i = 0; i < positions.length; i++) {
      int distance = (i - chaseStart) % ledCount;
      if (distance < 0) distance += ledCount;

      if (distance < chaseLength) {
        final trailFade = 1.0 - (distance / chaseLength);
        final colorIndex = (i * colors.length ~/ positions.length) % colors.length;
        final color = colors[colorIndex];

        final ledPaint = Paint()
          ..color = color.withValues(alpha: 0.9 * brightness * trailFade)
          ..blendMode = BlendMode.screen
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8 * trailFade);
        canvas.drawCircle(positions[i], 8 + 6 * trailFade, ledPaint);
      }
    }
  }

  /// Paint rainbow effect along path
  void _paintRainbowPath(Canvas canvas, List<Offset> positions, double brightness) {
    for (int i = 0; i < positions.length; i++) {
      final hue = ((i / positions.length + animationPhase) % 1.0) * 360;
      final color = HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();

      final ledPaint = Paint()
        ..color = color.withValues(alpha: 0.8 * brightness)
        ..blendMode = BlendMode.screen
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(positions[i], 8, ledPaint);
    }
  }

  /// Paint twinkle effect along path
  void _paintTwinklePath(Canvas canvas, List<Offset> positions, List<Color> colors, double brightness) {
    // Slower sparkle change rate for smoother, less chaotic animation
    final random = math.Random((animationPhase * 500).floor());

    // Base glow
    for (final pos in positions) {
      final basePaint = Paint()
        ..color = colors.first.withValues(alpha: 0.2 * brightness)
        ..blendMode = BlendMode.screen
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(pos, 4, basePaint);
    }

    // Reduced sparkle count for more elegant effect
    final sparkleCount = (intensity / 50).ceil().clamp(2, 8);
    for (int i = 0; i < sparkleCount; i++) {
      final posIndex = random.nextInt(positions.length);
      final pos = positions[posIndex];
      final sparkleOpacity = 0.5 + random.nextDouble() * 0.5;
      final sparkleSize = 6.0 + random.nextDouble() * 8.0;
      final colorIndex = random.nextInt(colors.length);

      final sparklePaint = Paint()
        ..color = colors[colorIndex].withValues(alpha: sparkleOpacity * brightness)
        ..blendMode = BlendMode.screen
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(pos, sparkleSize, sparklePaint);
    }
  }

  /// Paint wave effect along path
  void _paintWavePath(Canvas canvas, List<Offset> positions, List<Color> colors, double brightness) {
    for (int i = 0; i < positions.length; i++) {
      // Reduced wave frequency for smoother, more elegant motion
      final waveValue = math.sin((i / positions.length + animationPhase) * math.pi * 2.5);
      final ledBrightness = 0.3 + (waveValue + 1) / 2 * 0.7;
      final colorIndex = (i * colors.length ~/ positions.length) % colors.length;
      final color = colors[colorIndex];

      final ledPaint = Paint()
        ..color = color.withValues(alpha: 0.8 * brightness * ledBrightness)
        ..blendMode = BlendMode.screen
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 + 4 * ledBrightness);
      canvas.drawCircle(positions[i], 5 + 4 * ledBrightness, ledPaint);
    }
  }

  /// Paint fire effect along path
  void _paintFirePath(Canvas canvas, List<Offset> positions, double brightness) {
    final random = math.Random((animationPhase * 100).floor());
    final fireColors = [
      const Color(0xFFFF4500),
      const Color(0xFFFF6600),
      const Color(0xFFFF8800),
      const Color(0xFFFFAA00),
    ];

    for (final pos in positions) {
      final flicker = 0.4 + random.nextDouble() * 0.6;
      final colorIndex = random.nextInt(fireColors.length);
      final fireColor = fireColors[colorIndex];

      final firePaint = Paint()
        ..color = fireColor.withValues(alpha: 0.7 * brightness * flicker)
        ..blendMode = BlendMode.screen
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      canvas.drawCircle(pos, 6 + random.nextDouble() * 4, firePaint);
    }
  }

  /// Paint solid color gradient across roofline
  void _paintSolid(Canvas canvas, Rect rect, List<Color> colors, double brightness) {
    final gradientColors = colors.length == 1
        ? [colors.first, colors.first]
        : colors;

    final paint = Paint()
      ..shader = LinearGradient(
        colors: gradientColors.map((c) => c.withValues(alpha: 0.6 * brightness)).toList(),
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(rect)
      ..blendMode = BlendMode.screen;

    // Draw main glow
    canvas.drawRect(rect, paint);

    // Add glow effect at the bottom edge (light spill)
    _paintGlowEdge(canvas, rect, colors.first, brightness);
  }

  /// Paint breathing/pulsing effect
  void _paintBreathe(Canvas canvas, Rect rect, List<Color> colors, double brightness) {
    // Use sine wave for smooth breathing
    final breathePhase = math.sin(animationPhase * math.pi * 2);
    final breatheIntensity = 0.3 + (breathePhase + 1) / 2 * 0.7; // 0.3 to 1.0

    final color = colors.first;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.6 * brightness * breatheIntensity)
      ..blendMode = BlendMode.screen;

    canvas.drawRect(rect, paint);
    _paintGlowEdge(canvas, rect, color, brightness * breatheIntensity);
  }

  /// Paint chase/running light effect
  void _paintChase(Canvas canvas, Rect rect, List<Color> colors, double brightness) {
    final ledWidth = rect.width / ledCount;
    // Longer chase segment for smoother visual flow
    final chaseLength = ledCount ~/ 3; // Chase segment is 1/3 of total length

    // Calculate chase position
    final chaseStart = (animationPhase * ledCount).floor();

    for (int i = 0; i < ledCount; i++) {
      // Calculate distance from chase head
      int distance = (i - chaseStart) % ledCount;
      if (distance < 0) distance += ledCount;

      double ledBrightness = 0.0;
      Color ledColor = colors.first;

      if (distance < chaseLength) {
        // In the chase segment
        final trailFade = 1.0 - (distance / chaseLength);
        ledBrightness = trailFade;
        // Cycle through colors
        final colorIndex = (i ~/ (ledCount / colors.length)) % colors.length;
        ledColor = colors[colorIndex];
      }

      if (ledBrightness > 0) {
        final ledRect = Rect.fromLTWH(
          rect.left + i * ledWidth,
          rect.top,
          ledWidth + 2, // Slight overlap for seamless look
          rect.height,
        );

        final paint = Paint()
          ..color = ledColor.withValues(alpha: 0.7 * brightness * ledBrightness)
          ..blendMode = BlendMode.screen;

        canvas.drawRect(ledRect, paint);
      }
    }
  }

  /// Paint rainbow cycling effect
  void _paintRainbow(Canvas canvas, Rect rect, double brightness) {
    final rainbowColors = <Color>[];
    for (int i = 0; i < 7; i++) {
      final hue = ((i / 7 + animationPhase) % 1.0) * 360;
      rainbowColors.add(HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor());
    }

    final paint = Paint()
      ..shader = LinearGradient(
        colors: rainbowColors.map((c) => c.withValues(alpha: 0.5 * brightness)).toList(),
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(rect)
      ..blendMode = BlendMode.screen;

    canvas.drawRect(rect, paint);
  }

  /// Paint twinkle/sparkle effect
  void _paintTwinkle(Canvas canvas, Rect rect, List<Color> colors, double brightness) {
    // Base layer with low opacity
    final basePaint = Paint()
      ..color = colors.first.withValues(alpha: 0.2 * brightness)
      ..blendMode = BlendMode.screen;
    canvas.drawRect(rect, basePaint);

    // Random sparkle points based on animation phase
    // Slower sparkle change rate for smoother, less chaotic animation
    final random = math.Random((animationPhase * 500).floor());
    final sparkleCount = (intensity / 40).ceil().clamp(3, 10); // Reduced max sparkles

    for (int i = 0; i < sparkleCount; i++) {
      final x = rect.left + random.nextDouble() * rect.width;
      final y = rect.top + random.nextDouble() * rect.height;
      final sparkleSize = 4.0 + random.nextDouble() * 8.0;
      final sparkleOpacity = 0.3 + random.nextDouble() * 0.7;

      final colorIndex = random.nextInt(colors.length);
      final sparkleColor = colors[colorIndex];

      final sparklePaint = Paint()
        ..color = sparkleColor.withValues(alpha: sparkleOpacity * brightness)
        ..blendMode = BlendMode.screen
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

      canvas.drawCircle(Offset(x, y), sparkleSize, sparklePaint);
    }
  }

  /// Paint wave effect
  void _paintWave(Canvas canvas, Rect rect, List<Color> colors, double brightness) {
    final ledWidth = rect.width / ledCount;

    for (int i = 0; i < ledCount; i++) {
      // Calculate wave position
      // Reduced wave frequency for smoother, more elegant motion
      final waveValue = math.sin((i / ledCount + animationPhase) * math.pi * 2.5);
      final ledBrightness = 0.3 + (waveValue + 1) / 2 * 0.7;

      // Cycle through colors
      final colorIndex = (i ~/ (ledCount / colors.length)) % colors.length;
      final ledColor = colors[colorIndex];

      final ledRect = Rect.fromLTWH(
        rect.left + i * ledWidth,
        rect.top,
        ledWidth + 1,
        rect.height,
      );

      final paint = Paint()
        ..color = ledColor.withValues(alpha: 0.6 * brightness * ledBrightness)
        ..blendMode = BlendMode.screen;

      canvas.drawRect(ledRect, paint);
    }
  }

  /// Paint fire-like flickering effect
  void _paintFire(Canvas canvas, Rect rect, double brightness) {
    final random = math.Random((animationPhase * 100).floor());

    // Fire colors: red, orange, yellow
    final fireColors = [
      const Color(0xFFFF4500), // Red-orange
      const Color(0xFFFF6600), // Orange
      const Color(0xFFFF8800), // Light orange
      const Color(0xFFFFAA00), // Yellow-orange
    ];

    final ledWidth = rect.width / ledCount;

    for (int i = 0; i < ledCount; i++) {
      final flicker = 0.4 + random.nextDouble() * 0.6;
      final colorIndex = random.nextInt(fireColors.length);
      final fireColor = fireColors[colorIndex];

      final ledRect = Rect.fromLTWH(
        rect.left + i * ledWidth,
        rect.top,
        ledWidth + 1,
        rect.height,
      );

      final paint = Paint()
        ..color = fireColor.withValues(alpha: 0.6 * brightness * flicker)
        ..blendMode = BlendMode.screen;

      canvas.drawRect(ledRect, paint);
    }
  }

  /// Paint glow effect at the bottom edge of the roofline
  void _paintGlowEdge(Canvas canvas, Rect rect, Color color, double brightness) {
    final glowHeight = rect.height * 0.5;
    final glowRect = Rect.fromLTWH(
      rect.left,
      rect.bottom - glowHeight / 2,
      rect.width,
      glowHeight,
    );

    final glowPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          color.withValues(alpha: 0.4 * brightness),
          color.withValues(alpha: 0.0),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(glowRect)
      ..blendMode = BlendMode.screen
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    canvas.drawRect(glowRect, glowPaint);
  }

  @override
  bool shouldRepaint(RooflineLightPainter oldDelegate) {
    return oldDelegate.colors != colors ||
        oldDelegate.animationPhase != animationPhase ||
        oldDelegate.effectId != effectId ||
        oldDelegate.isOn != isOn ||
        oldDelegate.brightness != brightness ||
        oldDelegate.speed != speed ||
        oldDelegate.intensity != intensity ||
        oldDelegate.mask != mask;
  }
}
