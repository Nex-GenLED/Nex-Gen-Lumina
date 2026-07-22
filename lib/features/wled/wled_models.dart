import 'package:flutter/material.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';

class WledStateModel {
  final bool isOn;
  final int brightness; // 0-255
  final int speed; // 0-255
  final int intensity; // 0-255 (WLED 'ix' parameter)
  final Color color;
  final bool connected;
  final int warmWhite; // 0-255
  final bool supportsRgbw;
  final int effectId; // WLED fx value (0-255)
  final int paletteId; // WLED palette value
  final int presetId; // WLED ps value (0 = no preset active)

  /// Whether the first segment's effect direction is reversed (WLED seg[0].rev)
  final bool reverse;

  /// Full color sequence from the pattern (all segment colors)
  /// This preserves multi-color patterns like "Chiefs Red + Chiefs Gold"
  final List<Color> colorSequence;

  /// Color names from Lumina (e.g., ["Chiefs Red", "Chiefs Gold"])
  /// Empty if colors were not named by AI
  final List<String> colorNames;

  /// Custom effect name set by Lumina (overrides lookup if non-null)
  /// This preserves the exact effect name from AI responses
  final String? customEffectName;

  /// LEDs per color group (WLED `grp`). 1 = no grouping.
  /// Used by spacing/architectural patterns to render every Nth LED lit.
  final int colorGroupSize;

  /// Dark (off) LEDs after each lit group (WLED `spc`). 0 = no spacing.
  /// Used by spacing/architectural patterns (e.g. "1 On 2 Off").
  final int spacing;

  const WledStateModel({
    required this.isOn,
    required this.brightness,
    required this.speed,
    required this.intensity,
    required this.color,
    required this.connected,
    required this.warmWhite,
    required this.supportsRgbw,
    this.effectId = 0,
    this.paletteId = 0,
    this.presetId = 0,
    this.reverse = false,
    this.colorSequence = const [],
    this.colorNames = const [],
    this.customEffectName,
    this.colorGroupSize = 1,
    this.spacing = 0,
  });

  WledStateModel copyWith({
    bool? isOn,
    int? brightness,
    int? speed,
    int? intensity,
    Color? color,
    bool? connected,
    int? warmWhite,
    bool? supportsRgbw,
    int? effectId,
    int? paletteId,
    int? presetId,
    bool? reverse,
    List<Color>? colorSequence,
    List<String>? colorNames,
    String? customEffectName,
    bool clearCustomEffectName = false,
    int? colorGroupSize,
    int? spacing,
  }) =>
      WledStateModel(
        isOn: isOn ?? this.isOn,
        brightness: brightness ?? this.brightness,
        speed: speed ?? this.speed,
        intensity: intensity ?? this.intensity,
        color: color ?? this.color,
        connected: connected ?? this.connected,
        warmWhite: warmWhite ?? this.warmWhite,
        supportsRgbw: supportsRgbw ?? this.supportsRgbw,
        effectId: effectId ?? this.effectId,
        paletteId: paletteId ?? this.paletteId,
        presetId: presetId ?? this.presetId,
        reverse: reverse ?? this.reverse,
        colorSequence: colorSequence ?? this.colorSequence,
        colorNames: colorNames ?? this.colorNames,
        customEffectName: clearCustomEffectName ? null : (customEffectName ?? this.customEffectName),
        colorGroupSize: colorGroupSize ?? this.colorGroupSize,
        spacing: spacing ?? this.spacing,
      );

  /// Get the effect name - prefers custom name from Lumina, falls back to catalog lookup
  String get effectName => customEffectName ?? WledEffectsCatalog.getName(effectId);

  /// Get display colors - prefers color sequence, falls back to single color
  List<Color> get displayColors => colorSequence.isNotEmpty ? colorSequence : [color];

  static WledStateModel initial() => const WledStateModel(
        isOn: false,
        brightness: 128,
        speed: 128,
        intensity: 128,
        color: Colors.white,
        connected: false,
        warmWhite: 0,
        supportsRgbw: false,
        effectId: 0,
        paletteId: 0,
        presetId: 0,
        reverse: false,
        colorSequence: [],
        colorNames: [],
        customEffectName: null,
        colorGroupSize: 1,
        spacing: 0,
      );
}

