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
  final int? ledCount; // Virtual LED count for simulation (null = auto-calculate)

  /// Target aspect ratio of the display container (width/height).
  /// Used to transform roofline points for BoxFit.cover display.
  final double? targetAspectRatio;

  /// Image alignment within the container (for BoxFit.cover).
  /// Default is center (0, 0). Range: -1 to 1 for both x and y.
  final Offset imageAlignment;

  /// Whether the image is displayed with BoxFit.cover (true) or BoxFit.contain (false).
  final bool useBoxFitCover;

  /// Background color for non-active pixels (default black/off).
  /// Used in effects like Star/Twinkle where background pixels are visible.
  final Color backgroundColor;

  /// Number of consecutive LEDs per color in the repeating pattern.
  /// With colorGroupSize=2 and 3 colors: AABBCCAABBCC...
  final int colorGroupSize;

  RooflineLightPainter({
    required this.colors,
    this.animationPhase = 0.0,
    this.effectId = 0,
    this.speed = 128,
    this.intensity = 128,
    this.mask,
    this.isOn = true,
    this.brightness = 255,
    this.ledCount,
    this.targetAspectRatio,
    this.imageAlignment = Offset.zero,
    this.useBoxFitCover = false,
    this.backgroundColor = const Color(0xFF000000),
    this.colorGroupSize = 1,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!isOn || colors.isEmpty || brightness == 0) return;

    final effectiveColors = colors.isEmpty ? [Colors.white] : colors;
    final category = categorizeEffect(effectId);
    final brightnessFactor = brightness / 255.0;

    // Check if we have custom roofline points
    if (mask != null && mask!.hasCustomPoints && mask!.points.length >= 2) {
      // Get the points, potentially transformed for BoxFit.cover
      List<Offset> normalizedPoints = mask!.points;

      // Transform points if using BoxFit.cover and we have aspect ratio info
      if (useBoxFitCover && targetAspectRatio != null && mask!.sourceAspectRatio != null) {
        normalizedPoints = mask!.getPointsForCover(
          targetAspectRatio: targetAspectRatio!,
          alignment: imageAlignment,
        );
      }

      // Convert normalized points to canvas coordinates
      final canvasPoints = normalizedPoints
          .map((p) => Offset(p.dx * size.width, p.dy * size.height))
          .toList();

      _paintAlongPath(canvas, size, canvasPoints, effectiveColors, brightnessFactor, category);
      return;
    }

    // No custom mask — generate a default gentle-arc roofline path
    // and render discrete circular pixels along it.
    final maskHeight = mask?.maskHeight ?? 0.25;
    final arcPoints = _defaultRooflineArc(size, maskHeight);
    _paintAlongPath(canvas, size, arcPoints, effectiveColors, brightnessFactor, category);
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

    // Calculate effective LED count based on path length if not specified
    // Use approximately 1 LED per 4 pixels for a balanced look
    // Minimum 20 LEDs, maximum 150 to avoid performance issues
    final effectiveLedCount = ledCount ?? (totalLength / 4).round().clamp(20, 150);

    // Get positions along the path for each virtual LED
    final ledPositions = _getLedPositionsAlongPath(points, totalLength, effectiveLedCount);

    switch (category) {
      case EffectCategory.solid:
        _paintSolidPath(canvas, path, ledPositions, colors, brightness);
        break;
      case EffectCategory.breathe:
        _paintBreathePath(canvas, path, ledPositions, colors, brightness);
        break;
      case EffectCategory.chase:
        _paintChasePath(canvas, ledPositions, colors, brightness, effectiveLedCount);
        break;
      case EffectCategory.rainbow:
        _paintRainbowPath(canvas, ledPositions, colors, brightness);
        break;
      case EffectCategory.twinkle:
        _paintTwinklePath(canvas, ledPositions, colors, brightness, effectiveLedCount);
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
  List<Offset> _getLedPositionsAlongPath(List<Offset> points, double totalLength, int effectiveLedCount) {
    final positions = <Offset>[];
    final segmentLength = totalLength / effectiveLedCount;

    double accumulatedLength = 0;
    int segmentIndex = 0;

    for (int i = 0; i < effectiveLedCount; i++) {
      final targetLength = i * segmentLength;

      // Find the segment containing this position
      while (segmentIndex < points.length - 1) {
        final segStart = points[segmentIndex];
        final segEnd = points[segmentIndex + 1];
        final segLen = (segEnd - segStart).distance;

        if (accumulatedLength + segLen >= targetLength) {
          // Position is in this segment
          final progressInSegment = segLen > 0 ? (targetLength - accumulatedLength) / segLen : 0.0;
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

  /// Get the color for a specific LED index based on the action colors and group size.
  Color _getColorForLed(int ledIndex, List<Color> colors) {
    final groupSize = colorGroupSize.clamp(1, 10);
    final colorIndex = (ledIndex ~/ groupSize) % colors.length;
    return colors[colorIndex];
  }

  /// Draw a single crisp LED dot with optional glow halo.
  void _drawLedDot(Canvas canvas, Offset pos, Color color, double brightness, {double radius = 3.0, bool showHalo = true}) {
    // Skip fully transparent LEDs
    if (brightness <= 0.01) return;

    final adjustedColor = color.withValues(alpha: brightness);

    if (showHalo) {
      // Subtle glow halo around the dot (larger, transparent ring)
      final haloPaint = Paint()
        ..color = adjustedColor.withValues(alpha: 0.3 * brightness)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(pos, radius + 2, haloPaint);
    }

    // Crisp filled LED dot - no blur, no BlendMode.screen
    final dotPaint = Paint()
      ..color = adjustedColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pos, radius, dotPaint);

    // Bright center highlight for "lit bulb" look
    final highlightPaint = Paint()
      ..color = Color.lerp(color, Colors.white, 0.4)!.withValues(alpha: 0.7 * brightness)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pos, radius * 0.4, highlightPaint);
  }

  /// Generate a default gentle-arc roofline path when no custom mask exists.
  ///
  /// Creates a peaked roofline shape typical of a residential home,
  /// positioned within the [maskHeight] fraction of the canvas.
  List<Offset> _defaultRooflineArc(Size size, double maskHeight) {
    const points = 12;
    return List.generate(points, (i) {
      final t = i / (points - 1);
      // Horizontal: 8% padding on each side
      final x = (0.08 + t * 0.84) * size.width;
      // Vertical: parabolic peak centered in the mask area
      final centerY = maskHeight * size.height * 0.5;
      final peakOffset = maskHeight * size.height * 0.25;
      final y = centerY + peakOffset - (peakOffset * 2) * 4 * t * (1 - t);
      return Offset(x, y);
    });
  }

  /// Paint solid color along the roofline path - crisp discrete dots.
  void _paintSolidPath(Canvas canvas, Path path, List<Offset> positions, List<Color> colors, double brightness) {
    for (int i = 0; i < positions.length; i++) {
      final color = _getColorForLed(i, colors);
      _drawLedDot(canvas, positions[i], color, brightness);
    }
  }

  /// Paint breathing effect along path - crisp dots with pulsing opacity.
  void _paintBreathePath(Canvas canvas, Path path, List<Offset> positions, List<Color> colors, double brightness) {
    final breathePhase = math.sin(animationPhase * math.pi * 2);
    final breatheIntensity = 0.3 + (breathePhase + 1) / 2 * 0.7;
    final effectiveBrightness = brightness * breatheIntensity;

    for (int i = 0; i < positions.length; i++) {
      final color = _getColorForLed(i, colors);
      _drawLedDot(canvas, positions[i], color, effectiveBrightness);
    }
  }

  /// Paint chase effect along path - crisp dots with trailing fade.
  void _paintChasePath(Canvas canvas, List<Offset> positions, List<Color> colors, double brightness, int effectiveLedCount) {
    final chaseLength = effectiveLedCount * 2 ~/ 5;
    final chasePosition = animationPhase * effectiveLedCount;
    final hasBgColor = backgroundColor != const Color(0xFF000000);

    for (int i = 0; i < positions.length; i++) {
      double distance = (i - chasePosition) % effectiveLedCount;
      if (distance < 0) distance += effectiveLedCount;

      if (distance < chaseLength) {
        final normalizedDist = distance / chaseLength;
        final trailFade = math.cos(normalizedDist * math.pi / 2);
        final color = _getColorForLed(i, colors);
        _drawLedDot(canvas, positions[i], color, brightness * trailFade, showHalo: trailFade > 0.5);
      } else if (hasBgColor) {
        // Show background color for non-active pixels
        _drawLedDot(canvas, positions[i], backgroundColor, brightness * 0.6, showHalo: false);
      }
    }
  }

  /// Paint rainbow/gradient effect along path - crisp dots cycling through colors.
  void _paintRainbowPath(Canvas canvas, List<Offset> positions, List<Color> colors, double brightness) {
    final usePatternColors = colors.length > 1;

    for (int i = 0; i < positions.length; i++) {
      Color color;
      if (usePatternColors) {
        final colorProgress = (i / positions.length + animationPhase) % 1.0;
        final colorIndex = (colorProgress * colors.length).floor() % colors.length;
        final nextIndex = (colorIndex + 1) % colors.length;
        final blend = (colorProgress * colors.length) % 1.0;
        color = Color.lerp(colors[colorIndex], colors[nextIndex], blend) ?? colors[colorIndex];
      } else {
        final hue = ((i / positions.length + animationPhase) % 1.0) * 360;
        color = HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();
      }

      _drawLedDot(canvas, positions[i], color, brightness);
    }
  }

  /// Paint twinkle/star effect along path - background color base + sparkling action colors.
  void _paintTwinklePath(Canvas canvas, List<Offset> positions, List<Color> colors, double brightness, int effectiveLedCount) {
    final sparkleSet = (animationPhase * 10).floor();
    final random = math.Random(sparkleSet);
    final hasBgColor = backgroundColor != const Color(0xFF000000);

    // Base layer: show all LEDs at background color (or dim action color)
    for (int i = 0; i < positions.length; i++) {
      if (hasBgColor) {
        _drawLedDot(canvas, positions[i], backgroundColor, brightness * 0.7, showHalo: false);
      } else {
        // Dim base dots when no BG color
        final color = _getColorForLed(i, colors);
        _drawLedDot(canvas, positions[i], color, brightness * 0.2, showHalo: false);
      }
    }

    // Sparkle transition for smooth fade
    final sparklePhase = (animationPhase * 10) % 1.0;
    final fadeMultiplier = sparklePhase < 0.3
        ? sparklePhase / 0.3
        : sparklePhase > 0.7
            ? (1.0 - sparklePhase) / 0.3
            : 1.0;

    final maxSparkles = (effectiveLedCount / 10).ceil().clamp(3, 15);
    final sparkleCount = (intensity / 35).ceil().clamp(2, maxSparkles);

    for (int i = 0; i < sparkleCount; i++) {
      final posIndex = random.nextInt(positions.length);
      final pos = positions[posIndex];
      final sparkleOpacity = (0.7 + random.nextDouble() * 0.3) * fadeMultiplier;
      final colorIndex = random.nextInt(colors.length);
      final color = colors[colorIndex];

      _drawLedDot(canvas, pos, color, sparkleOpacity * brightness, radius: 3.5);
    }
  }

  /// Paint wave effect along path - crisp dots with brightness oscillation.
  void _paintWavePath(Canvas canvas, List<Offset> positions, List<Color> colors, double brightness) {
    for (int i = 0; i < positions.length; i++) {
      final waveValue = math.sin((i / positions.length + animationPhase) * math.pi * 1.5);
      final ledBrightness = 0.4 + (waveValue + 1) / 2 * 0.6;
      final color = _getColorForLed(i, colors);
      _drawLedDot(canvas, positions[i], color, brightness * ledBrightness, showHalo: ledBrightness > 0.7);
    }
  }

  /// Paint fire effect along path - crisp dots with flickering fire colors.
  void _paintFirePath(Canvas canvas, List<Offset> positions, double brightness) {
    final flickerSet = (animationPhase * 15).floor();
    final fireColors = [
      const Color(0xFFFF4500),
      const Color(0xFFFF6600),
      const Color(0xFFFF8800),
      const Color(0xFFFFAA00),
    ];

    final flickerPhase = (animationPhase * 15) % 1.0;
    final transitionBlend = flickerPhase < 0.2
        ? flickerPhase / 0.2
        : flickerPhase > 0.8
            ? (1.0 - flickerPhase) / 0.2
            : 1.0;

    for (int i = 0; i < positions.length; i++) {
      final posRandom = math.Random(flickerSet + i);
      final flicker = (0.6 + posRandom.nextDouble() * 0.4) * (0.7 + transitionBlend * 0.3);
      final colorIndex = posRandom.nextInt(fireColors.length);
      _drawLedDot(canvas, positions[i], fireColors[colorIndex], brightness * flicker);
    }
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
        oldDelegate.mask != mask ||
        oldDelegate.targetAspectRatio != targetAspectRatio ||
        oldDelegate.imageAlignment != imageAlignment ||
        oldDelegate.useBoxFitCover != useBoxFitCover ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.colorGroupSize != colorGroupSize;
  }
}
