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
        _paintRainbow(canvas, rooflineRect, effectiveColors, brightnessFactor);
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

  /// Paint solid color along the roofline path
  void _paintSolidPath(Canvas canvas, Path path, List<Offset> positions, List<Color> colors, double brightness) {
    // Draw subtle outer glow along the path (reduced height)
    final glowPaint = Paint()
      ..color = colors.first.withValues(alpha: 0.5 * brightness)
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.screen
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawPath(path, glowPaint);

    // Draw main light line (tighter, more defined)
    final mainPaint = Paint()
      ..color = colors.first.withValues(alpha: 0.9 * brightness)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.screen
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawPath(path, mainPaint);

    // Draw LED points for texture (smaller, brighter)
    for (int i = 0; i < positions.length; i++) {
      final colorIndex = (i * colors.length ~/ positions.length) % colors.length;
      final color = colors[colorIndex];
      final ledPaint = Paint()
        ..color = color.withValues(alpha: 1.0 * brightness)
        ..blendMode = BlendMode.screen
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
      canvas.drawCircle(positions[i], 2.5, ledPaint);
    }
  }

  /// Paint breathing effect along path
  void _paintBreathePath(Canvas canvas, Path path, List<Offset> positions, List<Color> colors, double brightness) {
    final breathePhase = math.sin(animationPhase * math.pi * 2);
    final breatheIntensity = 0.4 + (breathePhase + 1) / 2 * 0.6;
    final effectiveBrightness = brightness * breatheIntensity;

    // Tighter glow with higher opacity
    final glowPaint = Paint()
      ..color = colors.first.withValues(alpha: 0.8 * effectiveBrightness)
      ..strokeWidth = 8 + breathePhase * 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.screen
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 + breathePhase * 2);
    canvas.drawPath(path, glowPaint);

    // Core bright line
    final corePaint = Paint()
      ..color = colors.first.withValues(alpha: 1.0 * effectiveBrightness)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.screen;
    canvas.drawPath(path, corePaint);
  }

  /// Paint chase effect along path
  void _paintChasePath(Canvas canvas, List<Offset> positions, List<Color> colors, double brightness, int effectiveLedCount) {
    // Longer chase segment for smoother visual flow (40% of total length)
    final chaseLength = effectiveLedCount * 2 ~/ 5;
    // Use smooth interpolation for chase position instead of floor()
    final chasePosition = animationPhase * effectiveLedCount;

    for (int i = 0; i < positions.length; i++) {
      // Calculate distance from chase head with smooth interpolation
      double distance = (i - chasePosition) % effectiveLedCount;
      if (distance < 0) distance += effectiveLedCount;

      if (distance < chaseLength) {
        // Smooth fade using cosine curve for elegant transition
        final normalizedDist = distance / chaseLength;
        final trailFade = math.cos(normalizedDist * math.pi / 2);
        final colorIndex = (i * colors.length ~/ positions.length) % colors.length;
        final color = colors[colorIndex];

        // Brighter, tighter LED points
        final ledPaint = Paint()
          ..color = color.withValues(alpha: 1.0 * brightness * trailFade)
          ..blendMode = BlendMode.screen
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2 + 2 * trailFade);
        canvas.drawCircle(positions[i], 3 + 2 * trailFade, ledPaint);
      }
    }
  }

  /// Paint rainbow/gradient effect along path
  /// If colors has multiple entries, cycles through those colors instead of generating rainbow
  void _paintRainbowPath(Canvas canvas, List<Offset> positions, List<Color> colors, double brightness) {
    // Use provided colors if multiple are available, otherwise generate rainbow
    final usePatternColors = colors.length > 1;

    for (int i = 0; i < positions.length; i++) {
      Color color;
      if (usePatternColors) {
        // Cycle through the pattern colors with animation
        final colorProgress = (i / positions.length + animationPhase) % 1.0;
        final colorIndex = (colorProgress * colors.length).floor() % colors.length;
        final nextIndex = (colorIndex + 1) % colors.length;
        final blend = (colorProgress * colors.length) % 1.0;

        // Smooth interpolation between adjacent colors
        color = Color.lerp(colors[colorIndex], colors[nextIndex], blend) ?? colors[colorIndex];
      } else {
        // Fall back to rainbow hue generation
        final hue = ((i / positions.length + animationPhase) % 1.0) * 360;
        color = HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();
      }

      // Brighter, tighter LED points
      final ledPaint = Paint()
        ..color = color.withValues(alpha: 1.0 * brightness)
        ..blendMode = BlendMode.screen
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      canvas.drawCircle(positions[i], 3.5, ledPaint);
    }
  }

  /// Paint twinkle effect along path
  void _paintTwinklePath(Canvas canvas, List<Offset> positions, List<Color> colors, double brightness, int effectiveLedCount) {
    // Much slower sparkle change rate for smooth, elegant animation
    final sparkleSet = (animationPhase * 10).floor();
    final random = math.Random(sparkleSet);

    // Base glow - tighter, brighter for consistent appearance
    for (final pos in positions) {
      final basePaint = Paint()
        ..color = colors.first.withValues(alpha: 0.5 * brightness)
        ..blendMode = BlendMode.screen
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1);
      canvas.drawCircle(pos, 2, basePaint);
    }

    // Calculate sparkle transition for smooth fade in/out
    final sparklePhase = (animationPhase * 10) % 1.0;
    final fadeMultiplier = sparklePhase < 0.3
        ? sparklePhase / 0.3
        : sparklePhase > 0.7
            ? (1.0 - sparklePhase) / 0.3
            : 1.0;

    // Reduced sparkle count based on display size for elegant effect
    final maxSparkles = (effectiveLedCount / 15).ceil().clamp(3, 12);
    final sparkleCount = (intensity / 40).ceil().clamp(2, maxSparkles);

    for (int i = 0; i < sparkleCount; i++) {
      final posIndex = random.nextInt(positions.length);
      final pos = positions[posIndex];
      final sparkleOpacity = (0.7 + random.nextDouble() * 0.3) * fadeMultiplier;
      final sparkleSize = 3.0 + random.nextDouble() * 3.0;
      final colorIndex = random.nextInt(colors.length);

      // Brighter sparkles with tighter blur
      final sparklePaint = Paint()
        ..color = colors[colorIndex].withValues(alpha: sparkleOpacity * brightness)
        ..blendMode = BlendMode.screen
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      canvas.drawCircle(pos, sparkleSize, sparklePaint);
    }
  }

  /// Paint wave effect along path
  void _paintWavePath(Canvas canvas, List<Offset> positions, List<Color> colors, double brightness) {
    for (int i = 0; i < positions.length; i++) {
      // Lower wave frequency (1.5 cycles) for smoother, more elegant motion
      final waveValue = math.sin((i / positions.length + animationPhase) * math.pi * 1.5);
      // Higher minimum brightness for more consistent appearance
      final ledBrightness = 0.5 + (waveValue + 1) / 2 * 0.5;
      final colorIndex = (i * colors.length ~/ positions.length) % colors.length;
      final color = colors[colorIndex];

      // Tighter, brighter LED points
      final ledPaint = Paint()
        ..color = color.withValues(alpha: 1.0 * brightness * ledBrightness)
        ..blendMode = BlendMode.screen
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1 + 1.5 * ledBrightness);
      canvas.drawCircle(positions[i], 2.5 + 1.5 * ledBrightness, ledPaint);
    }
  }

  /// Paint fire effect along path
  void _paintFirePath(Canvas canvas, List<Offset> positions, double brightness) {
    // Slower flicker rate for more realistic fire effect
    final flickerSet = (animationPhase * 15).floor();
    final fireColors = [
      const Color(0xFFFF4500),
      const Color(0xFFFF6600),
      const Color(0xFFFF8800),
      const Color(0xFFFFAA00),
    ];

    // Calculate flicker transition for smooth changes
    final flickerPhase = (animationPhase * 15) % 1.0;
    final transitionBlend = flickerPhase < 0.2
        ? flickerPhase / 0.2
        : flickerPhase > 0.8
            ? (1.0 - flickerPhase) / 0.2
            : 1.0;

    for (int i = 0; i < positions.length; i++) {
      final pos = positions[i];
      // Use position index in random seed for spatial consistency
      final posRandom = math.Random(flickerSet + i);
      final flicker = (0.6 + posRandom.nextDouble() * 0.4) * (0.7 + transitionBlend * 0.3);
      final colorIndex = posRandom.nextInt(fireColors.length);
      final fireColor = fireColors[colorIndex];

      // Tighter, brighter fire effect
      final firePaint = Paint()
        ..color = fireColor.withValues(alpha: 0.95 * brightness * flicker)
        ..blendMode = BlendMode.screen
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      canvas.drawCircle(pos, 3 + posRandom.nextDouble() * 1.5, firePaint);
    }
  }

  /// Paint solid color gradient across roofline
  void _paintSolid(Canvas canvas, Rect rect, List<Color> colors, double brightness) {
    final gradientColors = colors.length == 1
        ? [colors.first, colors.first]
        : colors;

    final paint = Paint()
      ..shader = LinearGradient(
        colors: gradientColors.map((c) => c.withValues(alpha: 0.9 * brightness)).toList(),
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(rect)
      ..blendMode = BlendMode.screen;

    // Draw main glow
    canvas.drawRect(rect, paint);

    // Add subtle glow effect at the bottom edge (light spill)
    _paintGlowEdge(canvas, rect, colors.first, brightness * 0.5);
  }

  /// Paint breathing/pulsing effect
  void _paintBreathe(Canvas canvas, Rect rect, List<Color> colors, double brightness) {
    // Use sine wave for smooth breathing
    final breathePhase = math.sin(animationPhase * math.pi * 2);
    final breatheIntensity = 0.4 + (breathePhase + 1) / 2 * 0.6;

    final color = colors.first;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.9 * brightness * breatheIntensity)
      ..blendMode = BlendMode.screen;

    canvas.drawRect(rect, paint);
    _paintGlowEdge(canvas, rect, color, brightness * breatheIntensity * 0.4);
  }

  /// Paint chase/running light effect
  void _paintChase(Canvas canvas, Rect rect, List<Color> colors, double brightness) {
    // Calculate LED count based on rect width for rect-based effects
    final effectiveLedCount = ledCount ?? (rect.width / 4).round().clamp(30, 120);
    final ledWidth = rect.width / effectiveLedCount;
    // Longer chase segment for smoother visual flow (40% of total length)
    final chaseLength = effectiveLedCount * 2 ~/ 5;

    // Calculate chase position with smooth interpolation
    final chasePosition = animationPhase * effectiveLedCount;

    for (int i = 0; i < effectiveLedCount; i++) {
      // Calculate distance from chase head with smooth interpolation
      double distance = (i - chasePosition) % effectiveLedCount;
      if (distance < 0) distance += effectiveLedCount;

      double ledBrightness = 0.0;
      Color ledColor = colors.first;

      if (distance < chaseLength) {
        // Smooth fade using cosine curve for elegant transition
        final normalizedDist = distance / chaseLength;
        final trailFade = math.cos(normalizedDist * math.pi / 2);
        ledBrightness = trailFade;
        // Cycle through colors
        final colorIndex = (i ~/ (effectiveLedCount / colors.length)).clamp(0, colors.length - 1);
        ledColor = colors[colorIndex];
      }

      if (ledBrightness > 0) {
        final ledRect = Rect.fromLTWH(
          rect.left + i * ledWidth,
          rect.top,
          ledWidth + 2, // Slight overlap for seamless look
          rect.height,
        );

        // Brighter chase effect
        final paint = Paint()
          ..color = ledColor.withValues(alpha: 1.0 * brightness * ledBrightness)
          ..blendMode = BlendMode.screen;

        canvas.drawRect(ledRect, paint);
      }
    }
  }

  /// Paint rainbow/gradient cycling effect
  /// If colors has multiple entries, cycles through those colors instead of generating rainbow
  void _paintRainbow(Canvas canvas, Rect rect, List<Color> colors, double brightness) {
    List<Color> gradientColors;

    if (colors.length > 1) {
      // Use provided pattern colors, cycling with animation
      // Create a smooth cycling gradient by repeating the colors
      gradientColors = <Color>[];
      final colorCount = colors.length;
      for (int i = 0; i < colorCount * 2; i++) {
        final progress = (i / (colorCount * 2) + animationPhase) % 1.0;
        final colorIndex = (progress * colorCount).floor() % colorCount;
        gradientColors.add(colors[colorIndex]);
      }
    } else {
      // Fall back to rainbow hue generation
      gradientColors = <Color>[];
      for (int i = 0; i < 7; i++) {
        final hue = ((i / 7 + animationPhase) % 1.0) * 360;
        gradientColors.add(HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor());
      }
    }

    final paint = Paint()
      ..shader = LinearGradient(
        colors: gradientColors.map((c) => c.withValues(alpha: 0.85 * brightness)).toList(),
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ).createShader(rect)
      ..blendMode = BlendMode.screen;

    canvas.drawRect(rect, paint);
  }

  /// Paint twinkle/sparkle effect
  void _paintTwinkle(Canvas canvas, Rect rect, List<Color> colors, double brightness) {
    // Base layer with higher opacity
    final basePaint = Paint()
      ..color = colors.first.withValues(alpha: 0.5 * brightness)
      ..blendMode = BlendMode.screen;
    canvas.drawRect(rect, basePaint);

    // Much slower sparkle change rate (about 10 changes per full cycle)
    final sparkleSet = (animationPhase * 10).floor();
    final random = math.Random(sparkleSet);

    // Calculate sparkle transition for smooth fade in/out
    final sparklePhase = (animationPhase * 10) % 1.0;
    final fadeMultiplier = sparklePhase < 0.3
        ? sparklePhase / 0.3
        : sparklePhase > 0.7
            ? (1.0 - sparklePhase) / 0.3
            : 1.0;

    // Reduced sparkle count for elegant effect
    final sparkleCount = (intensity / 40).ceil().clamp(3, 8);

    for (int i = 0; i < sparkleCount; i++) {
      final x = rect.left + random.nextDouble() * rect.width;
      final y = rect.top + random.nextDouble() * rect.height;
      final sparkleSize = 3.0 + random.nextDouble() * 4.0;
      final sparkleOpacity = (0.6 + random.nextDouble() * 0.4) * fadeMultiplier;

      final colorIndex = random.nextInt(colors.length);
      final sparkleColor = colors[colorIndex];

      // Brighter, tighter sparkles
      final sparklePaint = Paint()
        ..color = sparkleColor.withValues(alpha: sparkleOpacity * brightness)
        ..blendMode = BlendMode.screen
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

      canvas.drawCircle(Offset(x, y), sparkleSize, sparklePaint);
    }
  }

  /// Paint wave effect
  void _paintWave(Canvas canvas, Rect rect, List<Color> colors, double brightness) {
    // Calculate LED count based on rect width
    final effectiveLedCount = ledCount ?? (rect.width / 4).round().clamp(30, 120);
    final ledWidth = rect.width / effectiveLedCount;

    for (int i = 0; i < effectiveLedCount; i++) {
      // Lower wave frequency (1.5 cycles) for smoother, more elegant motion
      final waveValue = math.sin((i / effectiveLedCount + animationPhase) * math.pi * 1.5);
      // Higher minimum brightness for consistent appearance
      final ledBrightness = 0.5 + (waveValue + 1) / 2 * 0.5;

      // Cycle through colors
      final colorIndex = (i ~/ (effectiveLedCount / colors.length)).clamp(0, colors.length - 1);
      final ledColor = colors[colorIndex];

      final ledRect = Rect.fromLTWH(
        rect.left + i * ledWidth,
        rect.top,
        ledWidth + 1,
        rect.height,
      );

      // Brighter wave effect
      final paint = Paint()
        ..color = ledColor.withValues(alpha: 0.95 * brightness * ledBrightness)
        ..blendMode = BlendMode.screen;

      canvas.drawRect(ledRect, paint);
    }
  }

  /// Paint fire-like flickering effect
  void _paintFire(Canvas canvas, Rect rect, double brightness) {
    // Calculate LED count based on rect width
    final effectiveLedCount = ledCount ?? (rect.width / 4).round().clamp(30, 120);

    // Slower flicker rate (about 15 changes per full cycle)
    final flickerSet = (animationPhase * 15).floor();

    // Fire colors: red, orange, yellow
    final fireColors = [
      const Color(0xFFFF4500), // Red-orange
      const Color(0xFFFF6600), // Orange
      const Color(0xFFFF8800), // Light orange
      const Color(0xFFFFAA00), // Yellow-orange
    ];

    // Calculate flicker transition for smooth changes
    final flickerPhase = (animationPhase * 15) % 1.0;
    final transitionBlend = flickerPhase < 0.2
        ? flickerPhase / 0.2
        : flickerPhase > 0.8
            ? (1.0 - flickerPhase) / 0.2
            : 1.0;

    final ledWidth = rect.width / effectiveLedCount;

    for (int i = 0; i < effectiveLedCount; i++) {
      // Use position index in random seed for spatial consistency
      final posRandom = math.Random(flickerSet + i);
      final flicker = (0.6 + posRandom.nextDouble() * 0.4) * (0.7 + transitionBlend * 0.3);
      final colorIndex = posRandom.nextInt(fireColors.length);
      final fireColor = fireColors[colorIndex];

      final ledRect = Rect.fromLTWH(
        rect.left + i * ledWidth,
        rect.top,
        ledWidth + 1,
        rect.height,
      );

      // Brighter fire effect
      final paint = Paint()
        ..color = fireColor.withValues(alpha: 0.95 * brightness * flicker)
        ..blendMode = BlendMode.screen;

      canvas.drawRect(ledRect, paint);
    }
  }

  /// Paint glow effect at the bottom edge of the roofline (reduced height)
  void _paintGlowEdge(Canvas canvas, Rect rect, Color color, double brightness) {
    final glowHeight = rect.height * 0.3; // Reduced from 0.5 to 0.3
    final glowRect = Rect.fromLTWH(
      rect.left,
      rect.bottom - glowHeight / 2,
      rect.width,
      glowHeight,
    );

    final glowPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          color.withValues(alpha: 0.3 * brightness), // Reduced from 0.4
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
        oldDelegate.mask != mask ||
        oldDelegate.targetAspectRatio != targetAspectRatio ||
        oldDelegate.imageAlignment != imageAlignment ||
        oldDelegate.useBoxFitCover != useBoxFitCover;
  }
}
