import 'package:flutter/material.dart';
import 'package:nexgen_command/features/ai/pixel_renderer.dart';

/// Renders discrete LED pixels along a user-defined path over a house photo.
///
/// Designed to be placed in a [Stack] on top of the house image.  Accepts
/// normalized path points (0.0–1.0) and distributes [pixelCount] circles
/// evenly along the poly-line path.
///
/// The overlay adds a dark scrim (40% opacity) behind the pixels so the
/// lights are the clear focal point.
class RooflinePixelOverlay extends PixelRenderer {
  /// Ordered path points in **normalized** coordinates (0.0–1.0 for both
  /// x and y, relative to the container size).
  ///
  /// The pixel strip follows this polyline path.  If empty, a default
  /// gentle-arc roofline shape is used.
  final List<Offset> pathPoints;

  /// Pixel radius override. If null, scales with container width.
  final double? pixelRadius;

  /// Opacity of the dark scrim drawn behind the pixels.
  final double scrimOpacity;

  /// Whether to draw the scrim overlay.
  final bool showScrim;

  const RooflinePixelOverlay({
    super.key,
    required super.colors,
    this.pathPoints = const [],
    super.effectType,
    super.speed,
    super.brightness,
    super.pixelCount = 50,
    super.animate,
    super.specular,
    this.pixelRadius,
    this.scrimOpacity = 0.40,
    this.showScrim = true,
  });

  @override
  State<RooflinePixelOverlay> createState() => _RooflinePixelOverlayState();
}

class _RooflinePixelOverlayState
    extends PixelRendererState<RooflinePixelOverlay> {
  @override
  List<Offset> computePixelPositions(Size canvasSize) {
    final count = widget.pixelCount;
    if (count <= 0) return [];

    // Use explicit path points or generate a default arc
    final normPath = widget.pathPoints.isNotEmpty
        ? widget.pathPoints
        : _defaultArcPath();

    if (normPath.length < 2) {
      // Single point: place all pixels at that point
      final pt = Offset(
        normPath.first.dx * canvasSize.width,
        normPath.first.dy * canvasSize.height,
      );
      return List.filled(count, pt);
    }

    // Compute cumulative segment lengths along the path
    final segLengths = <double>[0.0];
    for (int i = 1; i < normPath.length; i++) {
      final a = Offset(
        normPath[i - 1].dx * canvasSize.width,
        normPath[i - 1].dy * canvasSize.height,
      );
      final b = Offset(
        normPath[i].dx * canvasSize.width,
        normPath[i].dy * canvasSize.height,
      );
      segLengths.add(segLengths.last + (b - a).distance);
    }
    final totalLength = segLengths.last;
    if (totalLength < 1.0) {
      return List.filled(count,
          Offset(normPath.first.dx * canvasSize.width,
              normPath.first.dy * canvasSize.height));
    }

    // Distribute pixels evenly along the path
    return List.generate(count, (i) {
      final t = count > 1 ? i / (count - 1) : 0.5;
      final targetDist = t * totalLength;

      // Find which segment this distance falls in
      int segIdx = 0;
      for (int s = 1; s < segLengths.length; s++) {
        if (segLengths[s] >= targetDist) {
          segIdx = s - 1;
          break;
        }
        segIdx = s - 1;
      }

      final segStart = segLengths[segIdx];
      final segEnd = segLengths[segIdx + 1];
      final segT = segEnd > segStart
          ? (targetDist - segStart) / (segEnd - segStart)
          : 0.0;

      final a = Offset(
        normPath[segIdx].dx * canvasSize.width,
        normPath[segIdx].dy * canvasSize.height,
      );
      final b = Offset(
        normPath[segIdx + 1].dx * canvasSize.width,
        normPath[segIdx + 1].dy * canvasSize.height,
      );

      return Offset.lerp(a, b, segT)!;
    });
  }

  @override
  double getPixelRadius(Size canvasSize) {
    if (widget.pixelRadius != null) return widget.pixelRadius!;
    // Scale radius with container width: ~0.35% of width, clamped
    return (canvasSize.width * 0.0035)
        .clamp(3.0, 6.0);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Dark scrim so pixels are the focal point
        if (widget.showScrim)
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: widget.scrimOpacity),
            ),
          ),

        // Pixel canvas
        buildPixelCanvas(),
      ],
    );
  }

  /// Default gentle-arc roofline path when no explicit path is provided.
  ///
  /// Creates a peaked roofline shape typical of a residential home.
  static List<Offset> _defaultArcPath() {
    const points = 12;
    return List.generate(points, (i) {
      final t = i / (points - 1);
      // Parabolic arc peaking at center
      final y = 0.35 - 0.12 * 4 * t * (1 - t);
      return Offset(0.08 + t * 0.84, y);
    });
  }
}
