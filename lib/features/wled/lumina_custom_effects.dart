/// Custom Lumina effects that extend beyond standard WLED capabilities.
/// These effects are implemented via timed segment manipulation at the app level.
///
/// Effect IDs 1000+ are reserved for Lumina custom effects to avoid
/// collision with WLED's native effect IDs (0-186).
library lumina_custom_effects;

import 'dart:async';
import 'package:flutter/foundation.dart';

/// Represents a custom Lumina effect with animation logic.
class LuminaCustomEffect {
  final int id;
  final String name;
  final String description;
  final String category;
  final bool isAnimated;

  const LuminaCustomEffect({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    this.isAnimated = true,
  });
}

/// Custom effect animation controller.
/// Handles timed segment updates for effects not natively supported by WLED.
class LuminaEffectController {
  Timer? _animationTimer;
  bool _isRunning = false;

  bool get isRunning => _isRunning;

  /// Stops any running animation.
  void stop() {
    _animationTimer?.cancel();
    _animationTimer = null;
    _isRunning = false;
  }

  /// Generates WLED payloads for the Rising Tide effect.
  /// Lights progressively fill from one end to the other.
  List<Map<String, dynamic>> generateRisingTideFrames({
    required List<List<int>> colors,
    required int totalPixels,
    int steps = 20,
    bool reverse = false,
  }) {
    final frames = <Map<String, dynamic>>[];
    final pixelsPerStep = (totalPixels / steps).ceil();

    for (int i = 1; i <= steps; i++) {
      final litPixels = reverse ? totalPixels - (i * pixelsPerStep) : i * pixelsPerStep;
      final clampedPixels = litPixels.clamp(0, totalPixels);

      frames.add({
        'on': true,
        'bri': 255,
        'seg': [
          {
            'id': 0,
            'start': reverse ? clampedPixels : 0,
            'stop': reverse ? totalPixels : clampedPixels,
            'on': true,
            'col': colors,
            'fx': 0, // Solid
          },
          if (clampedPixels < totalPixels && !reverse)
            {
              'id': 1,
              'start': clampedPixels,
              'stop': totalPixels,
              'on': true,
              'col': [[0, 0, 0]], // Off
              'fx': 0,
            },
          if (clampedPixels > 0 && reverse)
            {
              'id': 1,
              'start': 0,
              'stop': clampedPixels,
              'on': true,
              'col': [[0, 0, 0]], // Off
              'fx': 0,
            },
        ],
      });
    }

    return frames;
  }

  /// Generates WLED payloads for the Pulse Burst effect.
  /// Animation radiates from center outward to edges.
  List<Map<String, dynamic>> generatePulseBurstFrames({
    required List<List<int>> colors,
    required int totalPixels,
    int steps = 15,
    bool inward = false,
  }) {
    final frames = <Map<String, dynamic>>[];
    final center = totalPixels ~/ 2;

    for (int i = 1; i <= steps; i++) {
      final progress = inward ? (steps - i + 1) / steps : i / steps;
      final spread = (center * progress).round();

      final leftStart = (center - spread).clamp(0, totalPixels);
      final rightEnd = (center + spread).clamp(0, totalPixels);

      frames.add({
        'on': true,
        'bri': 255,
        'seg': [
          // Left dark section
          if (leftStart > 0)
            {
              'id': 0,
              'start': 0,
              'stop': leftStart,
              'on': true,
              'col': [[0, 0, 0]],
              'fx': 0,
            },
          // Center lit section
          {
            'id': 1,
            'start': leftStart,
            'stop': rightEnd,
            'on': true,
            'col': colors,
            'fx': 0,
          },
          // Right dark section
          if (rightEnd < totalPixels)
            {
              'id': 2,
              'start': rightEnd,
              'stop': totalPixels,
              'on': true,
              'col': [[0, 0, 0]],
              'fx': 0,
            },
        ],
      });
    }

    return frames;
  }

  /// Generates WLED payloads for the Grand Reveal effect.
  /// Curtain-like opening from center, revealing colors underneath.
  List<Map<String, dynamic>> generateGrandRevealFrames({
    required List<List<int>> colors,
    required int totalPixels,
    int steps = 20,
    bool closing = false,
  }) {
    final frames = <Map<String, dynamic>>[];
    final center = totalPixels ~/ 2;

    for (int i = 0; i <= steps; i++) {
      final progress = closing ? (steps - i) / steps : i / steps;
      final spread = (center * progress).round();

      final leftEnd = (center - spread).clamp(0, totalPixels);
      final rightStart = (center + spread).clamp(0, totalPixels);

      frames.add({
        'on': true,
        'bri': 255,
        'seg': [
          // Left revealed section
          {
            'id': 0,
            'start': 0,
            'stop': leftEnd,
            'on': true,
            'col': colors,
            'fx': 0,
          },
          // Center curtain (dark or secondary color)
          if (leftEnd < rightStart)
            {
              'id': 1,
              'start': leftEnd,
              'stop': rightStart,
              'on': true,
              'col': [[0, 0, 0]],
              'fx': 0,
            },
          // Right revealed section
          {
            'id': 2,
            'start': rightStart,
            'stop': totalPixels,
            'on': true,
            'col': colors,
            'fx': 0,
          },
        ],
      });
    }

    return frames;
  }

  /// Generates WLED payloads for the Ocean Swell effect.
  /// Sinusoidal wave motion through the colors.
  List<Map<String, dynamic>> generateOceanSwellFrames({
    required List<List<int>> colors,
    required int totalPixels,
    int wavelength = 30,
    int steps = 40,
  }) {
    final frames = <Map<String, dynamic>>[];
    // Note: This uses WLED's built-in Sine effect with custom parameters
    // for a more fluid wave appearance

    for (int i = 0; i < steps; i++) {
      final phase = (i / steps * 255).round();

      frames.add({
        'on': true,
        'bri': 255,
        'seg': [
          {
            'id': 0,
            'on': true,
            'col': colors,
            'fx': 108, // Sine effect
            'sx': 80,  // Speed
            'ix': wavelength.clamp(1, 255), // Intensity controls wavelength
            'o1': phase, // Phase offset for animation
          },
        ],
      });
    }

    return frames;
  }
}

/// Catalog of custom Lumina effects.
class LuminaCustomEffectsCatalog {
  LuminaCustomEffectsCatalog._();

  /// Rising Tide - Lights progressively fill from one end
  static const risingTide = LuminaCustomEffect(
    id: 1001,
    name: 'Rising Tide',
    description: 'Lights progressively fill from one end to the other, like water rising',
    category: 'Build',
  );

  /// Falling Tide - Lights progressively empty from one end
  static const fallingTide = LuminaCustomEffect(
    id: 1002,
    name: 'Falling Tide',
    description: 'Lights progressively empty, like water receding',
    category: 'Build',
  );

  /// Pulse Burst - Animation radiates from center outward
  static const pulseBurst = LuminaCustomEffect(
    id: 1003,
    name: 'Pulse Burst',
    description: 'Colors radiate from the center outward to the edges',
    category: 'Radiate',
  );

  /// Pulse Gather - Animation contracts from edges to center
  static const pulseGather = LuminaCustomEffect(
    id: 1004,
    name: 'Pulse Gather',
    description: 'Colors contract from the edges inward to the center',
    category: 'Radiate',
  );

  /// Grand Reveal - Curtain-like opening from center
  static const grandReveal = LuminaCustomEffect(
    id: 1005,
    name: 'Grand Reveal',
    description: 'Dramatic curtain-like opening from the center',
    category: 'Theatrical',
  );

  /// Curtain Call - Curtain-like closing to center
  static const curtainCall = LuminaCustomEffect(
    id: 1006,
    name: 'Curtain Call',
    description: 'Elegant curtain-like closing toward the center',
    category: 'Theatrical',
  );

  /// Ocean Swell - Sinusoidal wave motion
  static const oceanSwell = LuminaCustomEffect(
    id: 1007,
    name: 'Ocean Swell',
    description: 'Gentle sinusoidal wave motion, like ocean waves',
    category: 'Wave',
  );

  /// All custom effects
  static const List<LuminaCustomEffect> allEffects = [
    risingTide,
    fallingTide,
    pulseBurst,
    pulseGather,
    grandReveal,
    curtainCall,
    oceanSwell,
  ];

  /// Get effect by ID
  static LuminaCustomEffect? getById(int id) {
    try {
      return allEffects.firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Get effect name by ID
  static String getName(int id) {
    return getById(id)?.name ?? 'Custom Effect #$id';
  }

  /// Check if an effect ID is a custom Lumina effect
  static bool isCustomEffect(int id) => id >= 1000;

  /// IDs for pattern generation (most visually distinct custom effects)
  static const List<int> patternEffectIds = [
    1001, // Rising Tide
    1003, // Pulse Burst
    1005, // Grand Reveal
    1007, // Ocean Swell
  ];
}

/// Service for executing custom Lumina effects on WLED devices.
class LuminaEffectService {
  final LuminaEffectController _controller = LuminaEffectController();
  final Future<void> Function(Map<String, dynamic> payload) _sendToWled;

  LuminaEffectService({
    required Future<void> Function(Map<String, dynamic> payload) sendToWled,
  }) : _sendToWled = sendToWled;

  /// Stops any running effect animation.
  void stop() => _controller.stop();

  /// Executes a custom effect by ID.
  Future<void> executeEffect({
    required int effectId,
    required List<List<int>> colors,
    required int totalPixels,
    int durationMs = 2000,
    bool loop = false,
  }) async {
    _controller.stop();

    List<Map<String, dynamic>> frames;

    switch (effectId) {
      case 1001: // Rising Tide
        frames = _controller.generateRisingTideFrames(
          colors: colors,
          totalPixels: totalPixels,
        );
        break;
      case 1002: // Falling Tide
        frames = _controller.generateRisingTideFrames(
          colors: colors,
          totalPixels: totalPixels,
          reverse: true,
        );
        break;
      case 1003: // Pulse Burst
        frames = _controller.generatePulseBurstFrames(
          colors: colors,
          totalPixels: totalPixels,
        );
        break;
      case 1004: // Pulse Gather
        frames = _controller.generatePulseBurstFrames(
          colors: colors,
          totalPixels: totalPixels,
          inward: true,
        );
        break;
      case 1005: // Grand Reveal
        frames = _controller.generateGrandRevealFrames(
          colors: colors,
          totalPixels: totalPixels,
        );
        break;
      case 1006: // Curtain Call
        frames = _controller.generateGrandRevealFrames(
          colors: colors,
          totalPixels: totalPixels,
          closing: true,
        );
        break;
      case 1007: // Ocean Swell
        frames = _controller.generateOceanSwellFrames(
          colors: colors,
          totalPixels: totalPixels,
        );
        break;
      default:
        debugPrint('Unknown custom effect ID: $effectId');
        return;
    }

    await _playFrames(frames, durationMs, loop);
  }

  Future<void> _playFrames(
    List<Map<String, dynamic>> frames,
    int durationMs,
    bool loop,
  ) async {
    if (frames.isEmpty) return;

    final frameDelay = durationMs ~/ frames.length;

    do {
      for (final frame in frames) {
        if (!_controller.isRunning && !loop) break;
        await _sendToWled(frame);
        await Future.delayed(Duration(milliseconds: frameDelay));
      }
    } while (loop && _controller.isRunning);
  }
}
