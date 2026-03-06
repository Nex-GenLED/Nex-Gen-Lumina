import 'package:flutter/material.dart';
import 'package:nexgen_command/features/ai/light_effect_animator.dart';
import 'package:nexgen_command/features/ar/ar_preview_providers.dart';
import 'package:nexgen_command/models/roofline_mask.dart';
import 'package:nexgen_command/widgets/roofline_light_painter.dart';

/// Renders discrete LED pixels along a user-defined path over a house photo.
///
/// Designed to be placed in a [Stack] on top of the house image.  Accepts
/// normalized path points (0.0–1.0) and distributes [pixelCount] circles
/// evenly along the poly-line path.
///
/// The overlay adds a dark scrim (40% opacity) behind the pixels so the
/// lights are the clear focal point.
///
/// Internally delegates all rendering to [RooflineLightPainter].
class RooflinePixelOverlay extends StatefulWidget {
  /// Base palette (repeats cyclically across pixels).
  final List<Color> colors;

  /// Ordered path points in **normalized** coordinates (0.0–1.0 for both
  /// x and y, relative to the container size).
  ///
  /// The pixel strip follows this polyline path.  If empty, a default
  /// gentle-arc roofline shape is used.
  final List<Offset> pathPoints;

  /// Which effect animation to run.
  final EffectType effectType;

  /// Normalized speed 0.0–1.0.
  final double speed;

  /// Normalized brightness 0.0–1.0.
  final double brightness;

  /// Number of virtual LED pixels.
  final int pixelCount;

  /// Whether to animate (false = static snapshot at t=0).
  final bool animate;

  /// Whether to draw the specular highlight on each pixel (kept for API
  /// compatibility; the shared painter always renders its own highlight).
  final bool specular;

  /// Pixel radius override. If null, scales with container width.
  final double? pixelRadius;

  /// Opacity of the dark scrim drawn behind the pixels.
  final double scrimOpacity;

  /// Whether to draw the scrim overlay.
  final bool showScrim;

  const RooflinePixelOverlay({
    super.key,
    required this.colors,
    this.pathPoints = const [],
    this.effectType = EffectType.solid,
    this.speed = 0.5,
    this.brightness = 1.0,
    this.pixelCount = 50,
    this.animate = true,
    this.specular = true,
    this.pixelRadius,
    this.scrimOpacity = 0.40,
    this.showScrim = true,
  });

  @override
  State<RooflinePixelOverlay> createState() => _RooflinePixelOverlayState();
}

class _RooflinePixelOverlayState extends State<RooflinePixelOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    if (widget.animate) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant RooflinePixelOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.animate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectId = _effectTypeToWledId(widget.effectType);
    final category = categorizeEffect(effectId);
    final needsAnimation = category != EffectCategory.solid;
    final wledSpeed = (widget.speed * 255).round().clamp(0, 255);
    final wledBrightness = (widget.brightness * 255).round().clamp(0, 255);

    // Update animation duration based on effect
    if (needsAnimation) {
      final duration = speedToDurationForEffect(wledSpeed, category);
      if (_controller.duration != duration) {
        _controller.duration = duration;
        if (!_controller.isAnimating && widget.animate) {
          _controller.repeat();
        }
      }
    } else {
      _controller.stop();
    }

    // Build a RooflineMask from the normalized path points
    final mask = widget.pathPoints.isNotEmpty
        ? RooflineMask(points: widget.pathPoints, isManuallyDrawn: true)
        : null;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.showScrim)
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: widget.scrimOpacity),
            ),
          ),
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return CustomPaint(
                painter: RooflineLightPainter(
                  colors: widget.colors,
                  animationPhase: needsAnimation ? _controller.value : 0.0,
                  effectId: effectId,
                  speed: wledSpeed,
                  intensity: 128,
                  mask: mask,
                  isOn: true,
                  brightness: wledBrightness,
                  ledCount: widget.pixelCount,
                ),
                size: Size.infinite,
              );
            },
          ),
        ),
      ],
    );
  }

  /// Map the simplified [EffectType] to a representative WLED effect ID so
  /// [RooflineLightPainter] and [categorizeEffect] produce the right
  /// rendering category.
  static int _effectTypeToWledId(EffectType type) {
    switch (type) {
      case EffectType.solid:
        return 0;
      case EffectType.breathe:
        return 2;
      case EffectType.chase:
        return 28;
      case EffectType.twinkle:
        return 49;
      case EffectType.sparkle:
        return 52;
      case EffectType.rainbow:
        return 9;
      case EffectType.fade:
        return 1;
      case EffectType.gradient:
        return 46;
    }
  }
}
