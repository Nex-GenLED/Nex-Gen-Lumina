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

  /// Number of dark (off) LEDs after each lit group.
  /// With colorGroupSize=1 and spacing=2: ● ○ ○ ● ○ ○ ...
  final int spacing;

  /// Whether the animation direction is reversed (WLED seg.rev).
  final bool reverse;

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
    this.spacing = 0,
    this.reverse = false,
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
    // Use approximately 1 LED per 8 pixels for a balanced look
    // Minimum 10 LEDs, maximum 75 to avoid performance issues
    final effectiveLedCount = ledCount ?? (totalLength / 8).round().clamp(10, 75);

    // Get positions along the path for each virtual LED
    var ledPositions = _getLedPositionsAlongPath(points, totalLength, effectiveLedCount);

    // Reverse LED order when WLED segment reverse flag is set
    if (reverse) {
      ledPositions = ledPositions.reversed.toList();
    }

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
      case EffectCategory.explosive:
        _paintExplosivePath(canvas, ledPositions, colors, brightness, effectiveLedCount);
        break;
      case EffectCategory.scanning:
        _paintScanningPath(canvas, ledPositions, colors, brightness);
        break;
      case EffectCategory.dripping:
        _paintDrippingPath(canvas, ledPositions, colors, brightness, effectiveLedCount);
        break;
      case EffectCategory.bouncing:
        _paintBouncingPath(canvas, ledPositions, colors, brightness, effectiveLedCount);
        break;
      case EffectCategory.morphing:
        _paintMorphingPath(canvas, ledPositions, colors, brightness);
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

  /// Draw a single LED pixel with 3-pass rendering: fascia wash, tight halo,
  /// and pixel node with emitter lens.
  void _drawLedDot(Canvas canvas, Offset pos, Color color, double brightness, {double radius = 3.0, bool showHalo = true}) {
    if (brightness <= 0.01) return;

    final r = (color.r * 255).round();
    final g = (color.g * 255).round();
    final b = (color.b * 255).round();
    final luminance = math.sqrt(r * r + g * g + b * b) / 441.0 * brightness;
    if (luminance < 0.02) return;

    final dotRadius = radius;

    // --- Pass 1: Fascia surface wash ---
    if (showHalo) {
      final washRadius = 9.0 * dotRadius;
      final washCenter = Offset(pos.dx, pos.dy + 1.5 * dotRadius);
      final washGradient = RadialGradient(
        colors: [
          color.withValues(alpha: luminance * 0.22),
          color.withValues(alpha: luminance * 0.10),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.35, 1.0],
      );
      final washRect = Rect.fromCircle(center: washCenter, radius: washRadius);
      final washPaint = Paint()
        ..shader = washGradient.createShader(washRect)
        ..style = PaintingStyle.fill;

      canvas.save();
      // Scale 2.2x horizontally around the wash center
      canvas.translate(washCenter.dx, washCenter.dy);
      canvas.scale(2.2, 1.0);
      canvas.translate(-washCenter.dx, -washCenter.dy);
      canvas.drawCircle(washCenter, washRadius, washPaint);
      canvas.restore();
    }

    // --- Pass 2: Tight halo ---
    final haloRadius = 3.5 * dotRadius;
    final haloGradient = RadialGradient(
      colors: [
        color.withValues(alpha: luminance * 0.9),
        color.withValues(alpha: luminance * 0.45),
        color.withValues(alpha: luminance * 0.12),
        color.withValues(alpha: 0.0),
      ],
      stops: const [0.0, 0.3, 0.7, 1.0],
    );
    final haloRect = Rect.fromCircle(center: pos, radius: haloRadius);
    final haloPaint = Paint()
      ..shader = haloGradient.createShader(haloRect)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pos, haloRadius, haloPaint);

    // --- Pass 3: Pixel node ---
    final whiteR = (r + 60).clamp(0, 255);
    final whiteG = (g + 60).clamp(0, 255);
    final whiteB = (b + 60).clamp(0, 255);
    final brightCenter = Color.fromARGB(255, whiteR, whiteG, whiteB);
    final darkEdge = Color.fromARGB(
      255,
      (r * 0.4).round(),
      (g * 0.4).round(),
      (b * 0.4).round(),
    );

    final nodeGradient = RadialGradient(
      colors: [brightCenter, color, darkEdge],
      stops: const [0.0, 0.5, 1.0],
    );
    final nodeRect = Rect.fromCircle(center: pos, radius: dotRadius);
    final nodePaint = Paint()
      ..shader = nodeGradient.createShader(nodeRect)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pos, dotRadius, nodePaint);

    // Emitter lens highlight
    final lensPaint = Paint()
      ..color = Colors.white.withValues(alpha: luminance * 0.95)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pos, dotRadius * 0.35, lensPaint);
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

  /// Paint solid color along the roofline path - every pixel is color1.
  void _paintSolidPath(Canvas canvas, Path path, List<Offset> positions, List<Color> colors, double brightness) {
    final color = colors.first;
    final cycle = colorGroupSize + spacing;
    for (int i = 0; i < positions.length; i++) {
      if (spacing > 0 && cycle > 0 && (i % cycle) >= colorGroupSize) continue;
      _drawLedDot(canvas, positions[i], color, brightness);
    }
  }

  /// Paint breathing effect along path - every pixel is color1, brightness pulsing.
  void _paintBreathePath(Canvas canvas, Path path, List<Offset> positions, List<Color> colors, double brightness) {
    final breathePhase = math.sin(animationPhase * math.pi * 2);
    final breatheIntensity = 0.3 + (breathePhase + 1) / 2 * 0.7;
    final effectiveBrightness = brightness * breatheIntensity;
    final color = colors.first;
    final cycle = colorGroupSize + spacing;

    for (int i = 0; i < positions.length; i++) {
      if (spacing > 0 && cycle > 0 && (i % cycle) >= colorGroupSize) continue;
      _drawLedDot(canvas, positions[i], color, effectiveBrightness);
    }
  }

  /// Paint chase effect along path - comet head is color1, background is
  /// color2 at low opacity (or dark when only one color is provided).
  void _paintChasePath(Canvas canvas, List<Offset> positions, List<Color> colors, double brightness, int effectiveLedCount) {
    final chaseLength = effectiveLedCount * 2 ~/ 5;
    final chasePosition = animationPhase * effectiveLedCount;
    final cometColor = colors.first;
    final bgColor = colors.length > 1 ? colors[1] : backgroundColor;
    final hasBg = bgColor != const Color(0xFF000000);

    for (int i = 0; i < positions.length; i++) {
      double distance = (i - chasePosition) % effectiveLedCount;
      if (distance < 0) distance += effectiveLedCount;

      if (distance < chaseLength) {
        final normalizedDist = distance / chaseLength;
        final trailFade = math.cos(normalizedDist * math.pi / 2);
        _drawLedDot(canvas, positions[i], cometColor, brightness * trailFade, showHalo: trailFade > 0.5);
      } else if (hasBg) {
        _drawLedDot(canvas, positions[i], bgColor, brightness * 0.15, showHalo: false);
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

    // Base layer: show all LEDs at background color (or dim color1)
    final baseColor = hasBgColor ? backgroundColor : colors.first;
    final baseOpacity = hasBgColor ? 0.7 : 0.2;
    for (int i = 0; i < positions.length; i++) {
      _drawLedDot(canvas, positions[i], baseColor, brightness * baseOpacity, showHalo: false);
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

  /// Paint wipe/flowing effect along path — a moving boundary transitions
  /// pixels from color2 to color1.  At phase 0 all pixels are color2,
  /// at phase 1 all pixels are color1.
  void _paintWavePath(Canvas canvas, List<Offset> positions, List<Color> colors, double brightness) {
    final color1 = colors.first;
    final color2 = colors.length > 1 ? colors[1] : color1.withValues(alpha: 0.15);
    final total = positions.length;
    if (total == 0) return;

    // The wipe front position (0 = far left, total = far right)
    final frontPos = animationPhase * total;
    // Width of the soft transition zone (in LEDs)
    const transitionWidth = 6.0;

    for (int i = 0; i < total; i++) {
      final distFromFront = i - frontPos;
      // blend: 0 = fully color2, 1 = fully color1
      final blend = (distFromFront / transitionWidth + 0.5).clamp(0.0, 1.0);
      final color = Color.lerp(color1, color2, blend) ?? color1;
      _drawLedDot(canvas, positions[i], color, brightness);
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

  /// Paint explosive burst effect — random pixel groups fire each cycle with fast
  /// attack and quadratic decay.
  void _paintExplosivePath(Canvas canvas, List<Offset> positions, List<Color> colors, double brightness, int effectiveLedCount) {
    final burstCycle = (animationPhase * 4).floor();
    final random = math.Random(burstCycle);
    final cyclePhase = (animationPhase * 4) % 1.0;

    // Attack is first 15%, decay is remaining 85%
    final burstBrightness = cyclePhase < 0.15
        ? cyclePhase / 0.15
        : math.pow(1.0 - (cyclePhase - 0.15) / 0.85, 2).toDouble();

    // Pick which pixels fire this cycle (~25% of strip)
    final burstCount = (effectiveLedCount * 0.25).ceil();
    final burstIndices = <int>{};
    for (int i = 0; i < burstCount; i++) {
      burstIndices.add(random.nextInt(positions.length));
    }

    final burstColor = colors.first;
    for (int i = 0; i < positions.length; i++) {
      if (burstIndices.contains(i)) {
        _drawLedDot(canvas, positions[i], burstColor, brightness * burstBrightness,
            showHalo: burstBrightness > 0.5);
      }
    }
  }

  /// Paint scanning beam effect — single soft beam bouncing back and forth.
  void _paintScanningPath(Canvas canvas, List<Offset> positions, List<Color> colors, double brightness) {
    final total = positions.length;
    if (total == 0) return;

    final beamPos = math.sin(animationPhase * math.pi).abs() * (total - 1);
    const beamWidth = 4.0;

    final beamColor = colors.first;
    for (int i = 0; i < total; i++) {
      final dist = (i - beamPos).abs();
      if (dist < beamWidth) {
        final falloff = math.pow(math.max(0.0, 1.0 - dist / beamWidth), 2).toDouble();
        _drawLedDot(canvas, positions[i], beamColor, brightness * falloff,
            showHalo: falloff > 0.4);
      }
    }
  }

  /// Paint dripping effect — 3 drops traveling forward with exponential falloff
  /// and dimming as they travel.
  void _paintDrippingPath(Canvas canvas, List<Offset> positions, List<Color> colors, double brightness, int effectiveLedCount) {
    final total = positions.length;
    if (total == 0) return;

    const dropCount = 3;
    const tailLength = 8;
    final stagger = total / dropCount;

    for (int i = 0; i < total; i++) {
      double maxIntensity = 0.0;
      Color ledColor = colors.first;

      for (int d = 0; d < dropCount; d++) {
        final dropPos = (animationPhase * total + d * stagger) % (total * 1.2);
        final dist = i - dropPos;

        // Only light pixels behind the leading edge (trail)
        if (dist >= 0 && dist < tailLength) {
          final falloff = math.exp(-dist * 0.4);
          final travelFade = math.max(0.0, 1.0 - dropPos / (total * 1.2));
          final intensity = falloff * travelFade;
          if (intensity > maxIntensity) {
            maxIntensity = intensity;
            ledColor = _getColorForLed(d, colors);
          }
        }
      }

      if (maxIntensity > 0.01) {
        _drawLedDot(canvas, positions[i], ledColor, brightness * maxIntensity,
            showHalo: maxIntensity > 0.5);
      }
    }
  }

  /// Paint bouncing balls effect — 3 balls with different speeds and phase
  /// offsets bouncing along the strip.
  void _paintBouncingPath(Canvas canvas, List<Offset> positions, List<Color> colors, double brightness, int effectiveLedCount) {
    final total = positions.length;
    if (total == 0) return;

    const ballSpeeds = [1.1, 0.8, 1.4];
    const ballOffsets = [0.0, 1.8, 3.4];
    const ballRadius = 3.0;
    // Ball 0 and 2 use color1, ball 1 uses color2
    final ballColors = [
      colors.first,
      colors.length > 1 ? colors[1] : colors.first,
      colors.first,
    ];

    // Accumulate brightness per pixel from all balls
    final pixelBrightness = List.filled(total, 0.0);
    final pixelColor = List.filled(total, colors.first);

    for (int b = 0; b < 3; b++) {
      final ballPos = math.sin(animationPhase * ballSpeeds[b] + ballOffsets[b]).abs() * (total - 1);

      for (int i = 0; i < total; i++) {
        final dist = (i - ballPos).abs();
        if (dist < ballRadius) {
          final falloff = math.pow(1.0 - dist / ballRadius, 2).toDouble();
          if (falloff > pixelBrightness[i]) {
            pixelBrightness[i] = falloff;
            pixelColor[i] = ballColors[b];
          }
        }
      }
    }

    for (int i = 0; i < total; i++) {
      if (pixelBrightness[i] > 0.01) {
        _drawLedDot(canvas, positions[i], pixelColor[i], brightness * pixelBrightness[i],
            showHalo: pixelBrightness[i] > 0.4);
      }
    }
  }

  /// Paint morphing effect — 3 layered sine waves blending between two colors
  /// along the strip.
  void _paintMorphingPath(Canvas canvas, List<Offset> positions, List<Color> colors, double brightness) {
    final total = positions.length;
    if (total == 0) return;

    final color1 = colors.first;
    final color2 = colors.length > 1 ? colors[1] : colors.first;

    for (int i = 0; i < total; i++) {
      final t = i / total;
      final p1 = math.sin(t * math.pi * 3 + animationPhase * 1.3);
      final p2 = math.sin(t * math.pi * 5 - animationPhase * 0.9 + 2.1);
      final p3 = math.sin(t * math.pi * 1.5 + animationPhase * 0.5 + 4.2);

      // Weighted sum normalized to 0–1
      final raw = p1 * 0.5 + p2 * 0.3 + p3 * 0.2;
      final blend = (raw + 1.0) / 2.0;

      final color = Color.lerp(color2, color1, blend) ?? color1;
      _drawLedDot(canvas, positions[i], color, brightness);
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
        oldDelegate.colorGroupSize != colorGroupSize ||
        oldDelegate.spacing != spacing ||
        oldDelegate.reverse != reverse;
  }
}
