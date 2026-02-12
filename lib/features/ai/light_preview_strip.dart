import 'package:flutter/material.dart';
import 'package:nexgen_command/features/ai/led_glow_painter.dart';
import 'package:nexgen_command/features/ai/light_effect_animator.dart';
import 'package:nexgen_command/theme.dart';

/// Animated horizontal LED preview strip for the Lumina chat interface.
///
/// Displays a row of glowing LED dots that animate according to the selected
/// [effectType]. Designed to be embedded inside a Lumina conversation message
/// bubble on a dark background.
///
/// Features:
/// - 8 effect types (solid, chase, fade, twinkle, sparkle, rainbow, gradient, breathe)
/// - Smooth color transitions when [colors] change (cross-fade)
/// - Optional arc layout for roofline previews
/// - Per-LED glow bloom via [LedGlowPainter]
/// - Optional zone label below the strip
///
/// Backwards-compatible: the legacy [ledCount], [ledSize], and [spacing]
/// parameters still work — [ledCount] maps to [pixelCount] and [ledSize]
/// overrides the auto-calculated dot size.
class LightPreviewStrip extends StatefulWidget {
  /// Colors to display across the strip.
  /// Repeats cyclically if fewer than [pixelCount].
  final List<Color> colors;

  /// Number of virtual LEDs to render (default 15 for compact preview).
  final int pixelCount;

  /// Which effect animation to run. Default [EffectType.solid].
  final EffectType effectType;

  /// Animation speed (0.0 = slowest, 1.0 = fastest). Default 0.5.
  final double speed;

  /// Overall brightness (0.0 = off, 1.0 = full). Default 1.0.
  final double brightness;

  /// Total height of the preview strip. Default 40.
  final double height;

  /// Diameter of each LED dot. If null, calculated automatically.
  final double? ledSize;

  /// Border radius for the background container.
  final double borderRadius;

  /// If true, LEDs follow a gentle upward arc (roofline shape).
  final bool arcLayout;

  /// Curvature for arc mode (0.0 = flat, 1.0 = deep curve). Default 0.2.
  final double arcCurvature;

  /// Optional zone label displayed below the strip (e.g. "Front Roofline").
  final String? zoneName;

  /// Whether to animate. Set false for a static snapshot.
  final bool animate;

  /// Legacy alias for [pixelCount].
  final int? ledCount;

  /// Legacy spacing (not used by CustomPainter but accepted for compat).
  final double? spacing;

  const LightPreviewStrip({
    super.key,
    required this.colors,
    this.pixelCount = 15,
    this.effectType = EffectType.solid,
    this.speed = 0.5,
    this.brightness = 1.0,
    this.height = 40,
    this.ledSize,
    this.borderRadius = 12.0,
    this.arcLayout = false,
    this.arcCurvature = 0.2,
    this.zoneName,
    this.animate = true,
    // Legacy compat
    this.ledCount,
    this.spacing,
  });

  @override
  State<LightPreviewStrip> createState() => _LightPreviewStripState();
}

class _LightPreviewStripState extends State<LightPreviewStrip>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  // Smooth color-change cross-fade
  List<Color> _previousColors = [];
  List<Color> _currentColors = [];
  double _colorTransition = 1.0; // 1.0 = fully arrived

  int get _effectivePixelCount => widget.ledCount ?? widget.pixelCount;

  @override
  void initState() {
    super.initState();
    _currentColors = List.of(widget.colors);
    _previousColors = List.of(widget.colors);

    _controller = AnimationController(
      vsync: this,
      duration: LightEffectAnimator.durationForEffect(
          widget.effectType, widget.speed),
    );

    if (widget.animate) _controller.repeat();
  }

  @override
  void didUpdateWidget(LightPreviewStrip oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Color change → cross-fade
    if (!_colorsMatch(oldWidget.colors, widget.colors)) {
      _previousColors = List.of(_currentColors);
      _currentColors = List.of(widget.colors);
      _colorTransition = 0.0;
    }

    // Duration change
    if (oldWidget.effectType != widget.effectType ||
        oldWidget.speed != widget.speed) {
      _controller.duration = LightEffectAnimator.durationForEffect(
          widget.effectType, widget.speed);
    }

    // Start / stop
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

  // ---------------------------------------------------------------------------

  bool _colorsMatch(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  List<Color> _blendedColors() {
    if (_colorTransition >= 1.0) return _currentColors;
    if (_currentColors.isEmpty) return _currentColors;

    final maxLen = _currentColors.length > _previousColors.length
        ? _currentColors.length
        : _previousColors.length;

    return List.generate(maxLen, (i) {
      final from = _previousColors.isNotEmpty
          ? _previousColors[i % _previousColors.length]
          : Colors.black;
      final to = _currentColors[i % _currentColors.length];
      return Color.lerp(from, to, _colorTransition)!;
    });
  }

  @override
  Widget build(BuildContext context) {
    final fallbackColors =
        widget.colors.isNotEmpty ? widget.colors : const [NexGenPalette.cyan];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ---- LED strip container ----
        Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: const Color(0xFF0D1117),
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: Border.all(
              color: NexGenPalette.line.withValues(alpha: 0.4),
              width: 0.5,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              // Advance cross-fade (~300 ms at 60 fps ≈ 18 frames × 0.055)
              if (_colorTransition < 1.0) {
                _colorTransition =
                    (_colorTransition + 0.055).clamp(0.0, 1.0);
              }

              final baseColors = _blendedColors().isNotEmpty
                  ? _blendedColors()
                  : fallbackColors;

              final phase = widget.animate ? _controller.value : 0.0;

              final frame = LightEffectAnimator.computeFrame(
                colors: baseColors,
                effect: widget.effectType,
                pixelCount: _effectivePixelCount,
                phase: phase,
                speed: widget.speed,
                brightness: widget.brightness,
              );

              return CustomPaint(
                painter: LedGlowPainter(
                  ledColors: frame,
                  ledSize: widget.ledSize ?? _autoLedSize(context),
                  arcLayout: widget.arcLayout,
                  arcCurvature: widget.arcCurvature,
                  brightness: widget.brightness,
                ),
                size: Size.infinite,
              );
            },
          ),
        ),

        // ---- Zone label ----
        if (widget.zoneName != null) ...[
          const SizedBox(height: 4),
          Text(
            'Preview — ${widget.zoneName}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: NexGenPalette.textMedium.withValues(alpha: 0.6),
                  fontSize: 11,
                ),
          ),
        ],
      ],
    );
  }

  /// Auto-size LEDs so they fill ~60 % of width with breathing room for glow.
  double _autoLedSize(BuildContext context) {
    final available = MediaQuery.of(context).size.width * 0.60;
    final perLed = available / _effectivePixelCount;
    return perLed.clamp(4.0, 10.0);
  }
}
