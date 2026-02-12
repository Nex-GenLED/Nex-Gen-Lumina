import 'package:flutter/material.dart';
import 'package:nexgen_command/features/ai/discrete_pixel_light.dart';
import 'package:nexgen_command/features/ai/light_effect_animator.dart';
import 'package:nexgen_command/features/ai/pixel_effect_controller.dart';

// ---------------------------------------------------------------------------
// Abstract base widget
// ---------------------------------------------------------------------------

/// Abstract base for pixel-accurate LED renderers.
///
/// Manages:
/// - [PixelEffectController] for per-pixel animation state
/// - [AnimationController] for frame ticking
/// - Smooth cross-fade when [colors] change
/// - [RepaintBoundary] isolation for performance
///
/// Subclasses implement [computePixelPositions] (layout) and
/// [getPixelRadius] (sizing).  The base class handles everything else.
abstract class PixelRenderer extends StatefulWidget {
  /// Base palette (repeats cyclically across pixels).
  final List<Color> colors;

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

  /// Whether to draw the specular highlight on each pixel.
  final bool specular;

  const PixelRenderer({
    super.key,
    required this.colors,
    this.effectType = EffectType.solid,
    this.speed = 0.5,
    this.brightness = 1.0,
    this.pixelCount = 20,
    this.animate = true,
    this.specular = true,
  });
}

/// Base state for [PixelRenderer] subclasses.
///
/// Subclasses must extend this and override [computePixelPositions] and
/// [getPixelRadius].  Call `super.build(context)` (or use [buildPixelCanvas])
/// to get the RepaintBoundary + CustomPaint tree.
abstract class PixelRendererState<T extends PixelRenderer> extends State<T>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late PixelEffectController _effectController;

  // Cross-fade state
  List<Color> _prevColors = [];
  List<Color> _currentColors = [];
  double _crossFade = 1.0; // 1.0 = fully arrived
  DateTime _lastTick = DateTime.now();

  // -----------------------------------------------------------------------
  // Abstract: subclasses define layout
  // -----------------------------------------------------------------------

  /// Compute pixel center positions for the given [canvasSize].
  ///
  /// Must return exactly [widget.pixelCount] offsets.
  List<Offset> computePixelPositions(Size canvasSize);

  /// Compute the base radius for pixels given the canvas size.
  double getPixelRadius(Size canvasSize);

  // -----------------------------------------------------------------------
  // Lifecycle
  // -----------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _currentColors = List.of(widget.colors);
    _prevColors = List.of(widget.colors);

    _effectController = PixelEffectController(
      pixelCount: widget.pixelCount,
      baseColors: _currentColors,
      effectType: widget.effectType,
      speed: widget.speed,
      brightness: widget.brightness,
    );

    _animController = AnimationController(
      vsync: this,
      // Runs forever — we use elapsed time, not a fixed duration.
      duration: const Duration(seconds: 1),
    );
    _animController.addListener(_onTick);

    if (widget.animate) _animController.repeat();
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Color change → cross-fade
    if (!_colorsMatch(oldWidget.colors, widget.colors)) {
      _prevColors = List.of(_currentColors);
      _currentColors = List.of(widget.colors);
      _crossFade = 0.0;
    }

    // Config changes
    final effectChanged = oldWidget.effectType != widget.effectType;
    _effectController.updateConfig(
      baseColors: _blendedColors(),
      effectType: widget.effectType,
      speed: widget.speed,
      brightness: widget.brightness,
      pixelCount: widget.pixelCount,
    );
    if (effectChanged) _effectController.reset();

    // Start / stop
    if (widget.animate && !_animController.isAnimating) {
      _animController.repeat();
    } else if (!widget.animate && _animController.isAnimating) {
      _animController.stop();
    }
  }

  @override
  void dispose() {
    _animController.removeListener(_onTick);
    _animController.dispose();
    super.dispose();
  }

  // -----------------------------------------------------------------------
  // Frame tick
  // -----------------------------------------------------------------------

  void _onTick() {
    final now = DateTime.now();
    final dt = (now.difference(_lastTick).inMicroseconds / 1e6)
        .clamp(0.0, 0.1); // cap at 100ms to avoid jumps
    _lastTick = now;

    // Advance cross-fade (~300ms)
    if (_crossFade < 1.0) {
      _crossFade = (_crossFade + dt / 0.3).clamp(0.0, 1.0);
      _effectController.updateConfig(baseColors: _blendedColors());
    }

    _effectController.update(dt);
  }

  // -----------------------------------------------------------------------
  // Build
  // -----------------------------------------------------------------------

  /// Builds the RepaintBoundary + CustomPaint tree.
  ///
  /// Subclass [build] methods should call this (or wrap it in additional
  /// layout widgets like Column for zone labels).
  Widget buildPixelCanvas({double? height}) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _animController,
        builder: (context, _) {
          return CustomPaint(
            painter: _DiscretePixelCanvasPainter(
              effectController: _effectController,
              positionComputer: computePixelPositions,
              radiusComputer: getPixelRadius,
              specular: widget.specular,
            ),
            size: height != null ? Size(double.infinity, height) : Size.infinite,
          );
        },
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Helpers
  // -----------------------------------------------------------------------

  List<Color> _blendedColors() {
    if (_crossFade >= 1.0) return _currentColors;
    if (_currentColors.isEmpty) return _currentColors;
    final maxLen = _currentColors.length > _prevColors.length
        ? _currentColors.length
        : _prevColors.length;
    return List.generate(maxLen, (i) {
      final from = _prevColors.isNotEmpty
          ? _prevColors[i % _prevColors.length]
          : Colors.black;
      final to = _currentColors[i % _currentColors.length];
      return Color.lerp(from, to, _crossFade)!;
    });
  }

  static bool _colorsMatch(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// ---------------------------------------------------------------------------
// Internal CustomPainter
// ---------------------------------------------------------------------------

/// Paints discrete LED pixels using [DiscretePixelLight.paintBatch].
///
/// Position computation and radius sizing are delegated to callbacks
/// provided by the [PixelRendererState] subclass.
class _DiscretePixelCanvasPainter extends CustomPainter {
  final PixelEffectController effectController;
  final List<Offset> Function(Size) positionComputer;
  final double Function(Size) radiusComputer;
  final bool specular;

  // Cache to avoid recomputing positions every frame when size unchanged.
  Size? _cachedSize;
  List<Offset>? _cachedPositions;
  double? _cachedRadius;

  _DiscretePixelCanvasPainter({
    required this.effectController,
    required this.positionComputer,
    required this.radiusComputer,
    this.specular = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (effectController.pixelCount == 0) return;

    // Compute (or cache) positions
    if (_cachedSize != size) {
      _cachedSize = size;
      _cachedPositions = positionComputer(size);
      _cachedRadius = radiusComputer(size);
    }
    final positions = _cachedPositions!;
    final radius = _cachedRadius!;

    DiscretePixelLight.paintBatch(
      canvas,
      size,
      positions,
      effectController.colors,
      effectController.brightnesses,
      effectController.radiusScales,
      radius,
      specular: specular,
    );
  }

  @override
  bool shouldRepaint(_DiscretePixelCanvasPainter oldDelegate) => true;
}
