import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:nexgen_command/features/ai/light_effect_animator.dart';

// ---------------------------------------------------------------------------
// Per-pixel twinkle / sparkle state machine
// ---------------------------------------------------------------------------

enum _FlashPhase { idle, rising, holding, falling }

class _FlashState {
  _FlashPhase phase = _FlashPhase.idle;
  double elapsed = 0.0;
  double peakBrightness = 1.0;
}

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

/// Manages per-pixel animation state for discrete LED rendering.
///
/// Driven by calling [update] each frame with the elapsed seconds since the
/// last frame.  Exposes [colors], [brightnesses], and [radiusScales] arrays
/// that represent the current visual state of every pixel.
///
/// All effect types produce DISTINCT per-pixel values — no blending between
/// adjacent pixels.
class PixelEffectController {
  /// Number of virtual pixels.
  int _pixelCount;

  /// Base palette (repeats cyclically across pixels).
  List<Color> _baseColors;

  /// Current effect type.
  EffectType _effectType;

  /// Normalized speed 0.0–1.0.
  double _speed;

  /// Normalized brightness 0.0–1.0.
  double _brightness;

  // --- Per-pixel output arrays (mutated in-place for perf) ---
  late List<Color> _colors;
  late List<double> _brightnesses;
  late List<double> _radiusScales;

  // --- Internal state ---
  double _elapsed = 0.0;
  late List<double> _phaseOffsets; // per-pixel random phase offset (static)
  late List<_FlashState> _flashStates; // twinkle / sparkle
  final math.Random _rng = math.Random();

  // Chase state
  double _chasePos = 0.0;

  PixelEffectController({
    required int pixelCount,
    required List<Color> baseColors,
    required EffectType effectType,
    double speed = 0.5,
    double brightness = 1.0,
  })  : _pixelCount = pixelCount,
        _baseColors = baseColors,
        _effectType = effectType,
        _speed = speed,
        _brightness = brightness {
    _allocate();
  }

  // --- Public accessors ---
  List<Color> get colors => _colors;
  List<double> get brightnesses => _brightnesses;
  List<double> get radiusScales => _radiusScales;
  int get pixelCount => _pixelCount;

  /// Reconfigure without reallocating if pixel count unchanged.
  void updateConfig({
    List<Color>? baseColors,
    EffectType? effectType,
    double? speed,
    double? brightness,
    int? pixelCount,
  }) {
    final needRealloc = pixelCount != null && pixelCount != _pixelCount;
    if (baseColors != null) _baseColors = baseColors;
    if (effectType != null) _effectType = effectType;
    if (speed != null) _speed = speed;
    if (brightness != null) _brightness = brightness;
    if (pixelCount != null) _pixelCount = pixelCount;
    if (needRealloc) _allocate();
  }

  /// Reset all internal state (e.g. on effect type change).
  void reset() {
    _elapsed = 0.0;
    _chasePos = 0.0;
    for (int i = 0; i < _pixelCount; i++) {
      _flashStates[i] = _FlashState();
      _brightnesses[i] = 1.0;
      _radiusScales[i] = 1.0;
    }
  }

  // -----------------------------------------------------------------------
  // Frame update — called once per animation frame
  // -----------------------------------------------------------------------

  /// Advance the animation by [dt] seconds and update output arrays.
  void update(double dt) {
    _elapsed += dt;

    switch (_effectType) {
      case EffectType.solid:
        _updateStatic(dt);
      case EffectType.chase:
        _updateChase(dt);
      case EffectType.fade:
        _updateFade();
      case EffectType.breathe:
        _updateBreathe();
      case EffectType.twinkle:
        _updateFlash(dt, isSpark: false);
      case EffectType.sparkle:
        _updateFlash(dt, isSpark: true);
      case EffectType.gradient:
        _updateGradient();
      case EffectType.rainbow:
        _updateRainbow();
    }
  }

  // -----------------------------------------------------------------------
  // Effect implementations
  // -----------------------------------------------------------------------

  /// Static: all pixels show assigned color with per-pixel phase-offset pulse.
  void _updateStatic(double dt) {
    const period = 4.0; // seconds
    for (int i = 0; i < _pixelCount; i++) {
      final phase = (_elapsed / period + _phaseOffsets[i]) * math.pi * 2;
      final pulse = 0.97 + 0.03 * math.sin(phase);
      _colors[i] = _baseColor(i);
      _brightnesses[i] = _brightness * pulse;
      _radiusScales[i] = 1.0;
    }
  }

  /// Chase: a window of active pixels moves along the strip.
  void _updateChase(double dt) {
    // Speed → pixels per second: slow=2, fast=15
    final pps = 2.0 + _speed * 13.0;
    _chasePos = (_chasePos + pps * dt) % _pixelCount;

    final windowSize = (_pixelCount / 6).clamp(3, _pixelCount * 0.6).toDouble();

    for (int i = 0; i < _pixelCount; i++) {
      _colors[i] = _baseColor(i);
      _radiusScales[i] = 1.0;

      // Distance from chase head (wrapping)
      double dist = (i - _chasePos) % _pixelCount;
      if (dist < 0) dist += _pixelCount;

      if (dist < windowSize) {
        // Smooth ease-in-out within the window
        final t = dist / windowSize;
        final fade = 0.5 + 0.5 * math.cos(t * math.pi);
        _brightnesses[i] = _brightness * (0.30 + 0.70 * fade);
      } else {
        _brightnesses[i] = _brightness * 0.30;
      }
    }
  }

  /// Fade: all pixels simultaneously transition brightness with a sine wave.
  void _updateFade() {
    // Period: speed 0 → 6s, speed 1 → 1.5s
    final period = 6.0 - _speed * 4.5;
    final phase = (_elapsed / period) * math.pi * 2;
    final pulse = 0.15 + 0.85 * ((math.sin(phase) + 1) / 2);

    for (int i = 0; i < _pixelCount; i++) {
      _colors[i] = _baseColor(i);
      _brightnesses[i] = _brightness * pulse;
      _radiusScales[i] = 1.0;
    }
  }

  /// Breathe: organic pulse with radius scaling.
  void _updateBreathe() {
    final period = 5.0 - _speed * 3.5;
    final t = (_elapsed / period) % 1.0;
    // Ease-in-out cubic
    final eased = t < 0.5
        ? 4 * t * t * t
        : 1 - math.pow(-2 * t + 2, 3) / 2;
    final pulse = 0.15 + 0.85 * eased;

    for (int i = 0; i < _pixelCount; i++) {
      _colors[i] = _baseColor(i);
      _brightnesses[i] = _brightness * pulse;
      // Radius: 85% at min brightness, 100% at max
      _radiusScales[i] = 0.85 + 0.15 * pulse;
    }
  }

  /// Twinkle / Sparkle: individual pixel state machines.
  void _updateFlash(double dt, {required bool isSpark}) {
    // Timing (seconds)
    final riseTime = isSpark ? 0.08 : 0.15;
    final holdTime = isSpark ? 0.05 : 0.10;
    final fallTime = isSpark ? 0.15 : 0.30;
    final chancePerSec = isSpark ? 0.08 : 0.03;
    final whiteBlend = isSpark ? 0.50 : 0.30;
    final baseBri = 0.70;

    for (int i = 0; i < _pixelCount; i++) {
      final fs = _flashStates[i];

      switch (fs.phase) {
        case _FlashPhase.idle:
          // Check probability of starting a flash
          if (_rng.nextDouble() < chancePerSec * dt) {
            fs.phase = _FlashPhase.rising;
            fs.elapsed = 0.0;
            fs.peakBrightness = 0.9 + _rng.nextDouble() * 0.1;
          }
          _colors[i] = _baseColor(i);
          _brightnesses[i] = _brightness * baseBri;
          _radiusScales[i] = 1.0;

        case _FlashPhase.rising:
          fs.elapsed += dt;
          final t = (fs.elapsed / riseTime).clamp(0.0, 1.0);
          final bri = baseBri + (fs.peakBrightness - baseBri) * t;
          _colors[i] = Color.lerp(_baseColor(i), Colors.white, whiteBlend * t)!;
          _brightnesses[i] = _brightness * bri;
          _radiusScales[i] = 1.0;
          if (fs.elapsed >= riseTime) {
            fs.phase = _FlashPhase.holding;
            fs.elapsed = 0.0;
          }

        case _FlashPhase.holding:
          fs.elapsed += dt;
          _colors[i] =
              Color.lerp(_baseColor(i), Colors.white, whiteBlend)!;
          _brightnesses[i] = _brightness * fs.peakBrightness;
          _radiusScales[i] = 1.0;
          if (fs.elapsed >= holdTime) {
            fs.phase = _FlashPhase.falling;
            fs.elapsed = 0.0;
          }

        case _FlashPhase.falling:
          fs.elapsed += dt;
          final t = (fs.elapsed / fallTime).clamp(0.0, 1.0);
          final bri = fs.peakBrightness - (fs.peakBrightness - baseBri) * t;
          _colors[i] = Color.lerp(
              _baseColor(i), Colors.white, whiteBlend * (1 - t))!;
          _brightnesses[i] = _brightness * bri;
          _radiusScales[i] = 1.0;
          if (fs.elapsed >= fallTime) {
            fs.phase = _FlashPhase.idle;
            fs.elapsed = 0.0;
          }
      }
    }
  }

  /// Gradient: color interpolation across pixels, optional scroll.
  void _updateGradient() {
    if (_baseColors.length < 2) {
      _updateStatic(0);
      return;
    }
    // Slow scroll: speed 0 → no scroll, speed 1 → full cycle in 4s
    final scrollOffset = _speed > 0.01 ? (_elapsed / (8.0 - _speed * 4.0)) % 1.0 : 0.0;

    for (int i = 0; i < _pixelCount; i++) {
      final t = (i / (_pixelCount - 1).clamp(1, _pixelCount) + scrollOffset) % 1.0;
      final scaledT = t * (_baseColors.length - 1);
      final fromIdx = scaledT.floor().clamp(0, _baseColors.length - 2);
      final blend = scaledT - fromIdx;
      _colors[i] =
          Color.lerp(_baseColors[fromIdx], _baseColors[fromIdx + 1], blend)!;
      _brightnesses[i] = _brightness;
      _radiusScales[i] = 1.0;
    }
  }

  /// Rainbow: hue distributed across pixels, scrolling.
  void _updateRainbow() {
    final scrollRate = 0.05 + _speed * 0.20; // revolutions per second
    final hueOffset = (_elapsed * scrollRate * 360) % 360;

    for (int i = 0; i < _pixelCount; i++) {
      final hue = ((i / _pixelCount) * 360 + hueOffset) % 360;
      _colors[i] = HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();
      _brightnesses[i] = _brightness;
      _radiusScales[i] = 1.0;
    }
  }

  // -----------------------------------------------------------------------
  // Helpers
  // -----------------------------------------------------------------------

  Color _baseColor(int index) {
    if (_baseColors.isEmpty) return Colors.white;
    return _baseColors[index % _baseColors.length];
  }

  void _allocate() {
    _colors = List<Color>.filled(_pixelCount, Colors.black);
    _brightnesses = List<double>.filled(_pixelCount, 1.0);
    _radiusScales = List<double>.filled(_pixelCount, 1.0);
    _phaseOffsets = List.generate(
        _pixelCount, (i) => math.Random(i * 7 + 3).nextDouble());
    _flashStates = List.generate(_pixelCount, (_) => _FlashState());
    _chasePos = 0.0;
  }
}
