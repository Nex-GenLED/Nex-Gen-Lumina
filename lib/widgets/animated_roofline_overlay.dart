import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/ar/ar_preview_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/models/roofline_mask.dart';
import 'package:nexgen_command/widgets/roofline_light_painter.dart';

/// Animated overlay widget that renders LED light effects on the roofline.
///
/// This widget manages its own animation controller and responds to:
/// - Live WLED device state (colors, effects, brightness)
/// - Preview state from Lumina AI suggestions
class AnimatedRooflineOverlay extends ConsumerStatefulWidget {
  /// Optional override colors for preview mode
  final List<Color>? previewColors;

  /// Optional override effect ID for preview mode
  final int? previewEffectId;

  /// Optional override speed for preview mode
  final int? previewSpeed;

  /// Custom roofline mask (if user has drawn their own)
  final RooflineMask? mask;

  /// Whether the lights should be shown as on
  final bool? forceOn;

  /// Brightness override (0-255)
  final int? brightness;

  const AnimatedRooflineOverlay({
    super.key,
    this.previewColors,
    this.previewEffectId,
    this.previewSpeed,
    this.mask,
    this.forceOn,
    this.brightness,
  });

  @override
  ConsumerState<AnimatedRooflineOverlay> createState() => _AnimatedRooflineOverlayState();
}

class _AnimatedRooflineOverlayState extends ConsumerState<AnimatedRooflineOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Get live WLED state
    final wledState = ref.watch(wledStateProvider);

    // Get AR preview state (from Lumina AI)
    final arPreview = ref.watch(arPreviewProvider);

    // Determine effective values (preview overrides live state)
    final isPreviewMode = widget.previewColors != null || arPreview.isActive;

    List<Color> effectiveColors;
    int effectiveEffectId;
    int effectiveSpeed;
    int effectiveBrightness;
    bool isOn;

    if (widget.previewColors != null) {
      // Widget-level preview override
      effectiveColors = widget.previewColors!;
      effectiveEffectId = widget.previewEffectId ?? 0;
      effectiveSpeed = widget.previewSpeed ?? 128;
      effectiveBrightness = widget.brightness ?? 255;
      isOn = widget.forceOn ?? true;
    } else if (arPreview.isActive) {
      // AR preview mode (from Lumina AI)
      effectiveColors = arPreview.colors;
      effectiveEffectId = arPreview.effectId;
      effectiveSpeed = arPreview.speed;
      effectiveBrightness = widget.brightness ?? 255;
      isOn = true;
    } else {
      // Live WLED state
      effectiveColors = [wledState.color];
      effectiveEffectId = wledState.effectId;
      effectiveSpeed = wledState.speed;
      effectiveBrightness = widget.brightness ?? wledState.brightness;
      isOn = widget.forceOn ?? wledState.isOn;
    }

    // Get mask from widget or provider
    final mask = widget.mask ?? ref.watch(rooflineMaskProvider);

    // Determine if we need animation
    final category = categorizeEffect(effectiveEffectId);
    final needsAnimation = category != EffectCategory.solid;

    // Update animation duration based on speed
    if (needsAnimation) {
      final duration = speedToDuration(effectiveSpeed);
      if (_controller.duration != duration) {
        _controller.duration = duration;
        if (!_controller.isAnimating) {
          _controller.repeat();
        }
      }
    } else {
      _controller.stop();
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: RooflineLightPainter(
            colors: effectiveColors,
            animationPhase: needsAnimation ? _controller.value : 0.0,
            effectId: effectiveEffectId,
            speed: effectiveSpeed,
            intensity: 128, // Default intensity
            mask: mask,
            isOn: isOn,
            brightness: effectiveBrightness,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

/// Simplified version for static color preview (no animation)
class StaticRooflineOverlay extends StatelessWidget {
  final List<Color> colors;
  final RooflineMask? mask;
  final int brightness;

  const StaticRooflineOverlay({
    super.key,
    required this.colors,
    this.mask,
    this.brightness = 255,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: RooflineLightPainter(
        colors: colors,
        animationPhase: 0.0,
        effectId: 0, // Solid
        mask: mask,
        isOn: true,
        brightness: brightness,
      ),
      size: Size.infinite,
    );
  }
}
