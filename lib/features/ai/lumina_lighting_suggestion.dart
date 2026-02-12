import 'package:flutter/material.dart';

import 'package:nexgen_command/features/ai/light_effect_animator.dart';
import 'package:nexgen_command/features/ai/lumina_sheet_controller.dart';

// ---------------------------------------------------------------------------
// Supporting info classes
// ---------------------------------------------------------------------------

/// Describes a named color palette with individual color labels.
class PaletteInfo {
  final String name;
  final String? description;
  final List<String> colorNames;

  const PaletteInfo({
    required this.name,
    this.description,
    this.colorNames = const [],
  });
}

/// Describes the effect applied to the lights.
class EffectInfo {
  final int id;
  final String name;
  final EffectType category;

  const EffectInfo({
    required this.id,
    required this.name,
    required this.category,
  });

  /// Human-readable speed label from a 0.0–1.0 normalized value.
  static String speedLabel(double speed) {
    if (speed <= 0.25) return 'Slow';
    if (speed <= 0.65) return 'Medium';
    return 'Fast';
  }

  bool get isStatic => category == EffectType.solid;
}

/// Zone targeting information.
class ZoneInfo {
  final String? id;
  final String name;

  const ZoneInfo({this.id, required this.name});

  static const allZones = ZoneInfo(name: 'All Zones');
}

// ---------------------------------------------------------------------------
// Main suggestion model
// ---------------------------------------------------------------------------

/// Encapsulates a complete lighting suggestion returned by Lumina,
/// including preview data, parameter transparency, and change tracking.
class LuminaLightingSuggestion {
  /// Lumina's conversational response text.
  final String responseText;

  /// Preview colors for the LED strip.
  final List<Color> colors;

  /// Named palette information.
  final PaletteInfo palette;

  /// Effect information (id, name, category).
  final EffectInfo effect;

  /// Brightness 0.0–1.0.
  final double brightness;

  /// Speed 0.0–1.0 (null for static effects).
  final double? speed;

  /// Target zone.
  final ZoneInfo zone;

  /// AI confidence in this suggestion (0.0–1.0).
  final double confidence;

  /// Parameters that were changed from the previous suggestion
  /// (used for "changed" indicator highlighting).
  final Set<String> changedParams;

  /// The raw WLED JSON payload to send to the device.
  final Map<String, dynamic>? wledPayload;

  const LuminaLightingSuggestion({
    required this.responseText,
    required this.colors,
    required this.palette,
    required this.effect,
    this.brightness = 1.0,
    this.speed,
    this.zone = const ZoneInfo(name: 'All Zones'),
    this.confidence = 0.9,
    this.changedParams = const {},
    this.wledPayload,
  });

  /// Creates a copy with selected fields overridden and those fields
  /// tracked in [changedParams].
  LuminaLightingSuggestion copyWithChanges({
    List<Color>? colors,
    PaletteInfo? palette,
    EffectInfo? effect,
    double? brightness,
    double? speed,
    ZoneInfo? zone,
  }) {
    final changes = <String>{};
    if (colors != null) changes.add('palette');
    if (palette != null) changes.add('palette');
    if (effect != null) changes.add('effect');
    if (brightness != null) changes.add('brightness');
    if (speed != null) changes.add('speed');
    if (zone != null) changes.add('zone');

    return LuminaLightingSuggestion(
      responseText: responseText,
      colors: colors ?? this.colors,
      palette: palette ?? this.palette,
      effect: effect ?? this.effect,
      brightness: brightness ?? this.brightness,
      speed: speed ?? this.speed,
      zone: zone ?? this.zone,
      confidence: confidence,
      changedParams: changes,
      wledPayload: wledPayload,
    );
  }

  /// Build a [LuminaLightingSuggestion] from an existing
  /// [LuminaPatternPreview] and response context.
  factory LuminaLightingSuggestion.fromPreview({
    required String responseText,
    required LuminaPatternPreview preview,
    Map<String, dynamic>? wledPayload,
    double confidence = 0.9,
  }) {
    final effectId = preview.effectId ?? 0;
    final effectName = preview.effectName ?? (effectId == 0 ? 'Static' : 'Effect $effectId');
    final category = effectTypeFromWledId(effectId);

    // Normalize WLED speed (0–255) to 0.0–1.0
    final normalizedSpeed = preview.speed != null
        ? (preview.speed! / 255).clamp(0.0, 1.0)
        : (category == EffectType.solid ? null : 0.5);

    // Extract brightness from WLED payload if available
    double brightness = 1.0;
    if (wledPayload != null) {
      final bri = wledPayload['bri'];
      if (bri is num) brightness = (bri / 255).clamp(0.0, 1.0);
    }

    return LuminaLightingSuggestion(
      responseText: responseText,
      colors: preview.colors,
      palette: PaletteInfo(
        name: preview.patternName ?? 'Custom Palette',
        colorNames: preview.colorNames,
      ),
      effect: EffectInfo(
        id: effectId,
        name: effectName,
        category: category,
      ),
      brightness: brightness,
      speed: normalizedSpeed,
      confidence: confidence,
      wledPayload: wledPayload,
    );
  }
}
