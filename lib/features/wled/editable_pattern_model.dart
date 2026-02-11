import 'package:flutter/material.dart';
import 'package:nexgen_command/features/wled/wled_service.dart' show rgbToRgbw;

/// Direction for pattern animation flow.
enum PatternDirection {
  left,
  right,
  centerOut;

  String get displayName {
    switch (this) {
      case PatternDirection.left:
        return 'Left';
      case PatternDirection.right:
        return 'Right';
      case PatternDirection.centerOut:
        return 'Center';
    }
  }

  IconData get icon {
    switch (this) {
      case PatternDirection.left:
        return Icons.arrow_back;
      case PatternDirection.right:
        return Icons.arrow_forward;
      case PatternDirection.centerOut:
        return Icons.unfold_more;
    }
  }

  /// Cycle to next direction on tap.
  PatternDirection get next {
    switch (this) {
      case PatternDirection.left:
        return PatternDirection.right;
      case PatternDirection.right:
        return PatternDirection.centerOut;
      case PatternDirection.centerOut:
        return PatternDirection.left;
    }
  }
}

/// A user-editable pattern with up to 15 action colors, background color,
/// effect mode, direction, and WLED payload generation.
///
/// This model mirrors the native controller app's "Edit Pattern" data:
/// - ACTION COLORS: 1-15 color layers that repeat across the LED strip
/// - BG COLOR: background color for non-active pixels (default black/off)
/// - MODE: the WLED effect ID
/// - DIRECTION: animation flow direction
class EditablePattern {
  final String id;
  final String name;
  final List<Color> actionColors;
  final Color backgroundColor;
  final int effectId;
  final PatternDirection direction;
  final int speed;
  final int intensity;
  final int brightness;
  final int colorGroupSize;

  const EditablePattern({
    required this.id,
    this.name = 'New Pattern',
    this.actionColors = const [Color(0xFFFF0000)],
    this.backgroundColor = const Color(0xFF000000),
    this.effectId = 0,
    this.direction = PatternDirection.right,
    this.speed = 128,
    this.intensity = 128,
    this.brightness = 255,
    this.colorGroupSize = 1,
  });

  /// Create a default pattern with sensible starting values.
  factory EditablePattern.blank() {
    return EditablePattern(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: 'New Pattern',
      actionColors: const [Color(0xFFFFFFFF)],
      backgroundColor: const Color(0xFF000000),
    );
  }

  /// Create from a GradientPattern (existing library pattern).
  factory EditablePattern.fromGradientColors({
    required String id,
    required String name,
    required List<Color> colors,
    int effectId = 0,
    int speed = 128,
    int intensity = 128,
    int brightness = 255,
  }) {
    return EditablePattern(
      id: id,
      name: name,
      actionColors: colors.isNotEmpty ? colors : const [Color(0xFFFFFFFF)],
      backgroundColor: const Color(0xFF000000),
      effectId: effectId,
      speed: speed,
      intensity: intensity,
      brightness: brightness,
    );
  }

  // ---------------------------------------------------------------------------
  // WLED Payload Generation
  // ---------------------------------------------------------------------------

  /// Generate a WLED JSON payload for this pattern.
  ///
  /// For Static (effectId == 0): uses per-pixel `i` array for precise color
  /// placement of all action colors across the strip.
  ///
  /// For animated effects (effectId != 0): uses standard `col` array with
  /// the first 3 action colors + `grp`/`spc` for the effect engine to animate,
  /// plus sets background color in the tertiary color slot.
  Map<String, dynamic> toWledPayload(int totalPixels) {
    if (effectId == 0) {
      return _buildPerPixelPayload(totalPixels);
    } else {
      return _buildEffectPayload();
    }
  }

  /// Per-pixel payload for Static mode: sets every LED individually.
  Map<String, dynamic> _buildPerPixelPayload(int totalPixels) {
    // Build the 'i' array: [index, [R,G,B,W], index, [R,G,B,W], ...]
    final iArray = <dynamic>[];

    for (int i = 0; i < totalPixels; i++) {
      final colorIndex = (i ~/ colorGroupSize) % actionColors.length;
      final c = actionColors[colorIndex];
      iArray.add(i);
      iArray.add(rgbToRgbw(c.red, c.green, c.blue, forceZeroWhite: true));
    }

    return {
      'on': true,
      'bri': brightness,
      'seg': [
        {
          'fx': 0, // Static
          'i': iArray,
        }
      ],
    };
  }

  /// Standard effect payload: sends up to 3 colors for the effect engine.
  Map<String, dynamic> _buildEffectPayload() {
    // Build col array: up to 3 action colors
    final cols = actionColors
        .take(3)
        .map((c) => rgbToRgbw(c.red, c.green, c.blue, forceZeroWhite: true))
        .toList();
    if (cols.isEmpty) {
      cols.add(rgbToRgbw(255, 255, 255, forceZeroWhite: true));
    }

    // If we have fewer than 3 colors and a non-black background, use the
    // background color as the third color slot (WLED uses col[2] as background
    // for many effects like Twinkle, Stars, etc.)
    if (cols.length < 3 && backgroundColor != const Color(0xFF000000)) {
      // Fill up to slot 2 with existing colors if needed
      while (cols.length < 2) {
        cols.add(cols.last);
      }
      cols.add(rgbToRgbw(
        backgroundColor.red,
        backgroundColor.green,
        backgroundColor.blue,
        forceZeroWhite: true,
      ));
    }

    return {
      'on': true,
      'bri': brightness,
      'seg': [
        {
          'fx': effectId,
          'sx': speed,
          'ix': intensity,
          'pal': 5, // "Colors Only" palette
          'grp': colorGroupSize,
          'spc': 0,
          'of': 0,
          'rev': direction == PatternDirection.left,
          'mi': direction == PatternDirection.centerOut,
          'col': cols,
        }
      ],
    };
  }

  // ---------------------------------------------------------------------------
  // Copy / Serialization
  // ---------------------------------------------------------------------------

  EditablePattern copyWith({
    String? id,
    String? name,
    List<Color>? actionColors,
    Color? backgroundColor,
    int? effectId,
    PatternDirection? direction,
    int? speed,
    int? intensity,
    int? brightness,
    int? colorGroupSize,
  }) {
    return EditablePattern(
      id: id ?? this.id,
      name: name ?? this.name,
      actionColors: actionColors ?? this.actionColors,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      effectId: effectId ?? this.effectId,
      direction: direction ?? this.direction,
      speed: speed ?? this.speed,
      intensity: intensity ?? this.intensity,
      brightness: brightness ?? this.brightness,
      colorGroupSize: colorGroupSize ?? this.colorGroupSize,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'actionColors': actionColors.map((c) => c.value).toList(),
      'backgroundColor': backgroundColor.value,
      'effectId': effectId,
      'direction': direction.name,
      'speed': speed,
      'intensity': intensity,
      'brightness': brightness,
      'colorGroupSize': colorGroupSize,
    };
  }

  factory EditablePattern.fromJson(Map<String, dynamic> json) {
    return EditablePattern(
      id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: json['name'] as String? ?? 'Pattern',
      actionColors: (json['actionColors'] as List?)
              ?.map((v) => Color(v as int))
              .toList() ??
          const [Color(0xFFFFFFFF)],
      backgroundColor: Color(json['backgroundColor'] as int? ?? 0xFF000000),
      effectId: json['effectId'] as int? ?? 0,
      direction: PatternDirection.values.firstWhere(
        (d) => d.name == (json['direction'] as String?),
        orElse: () => PatternDirection.right,
      ),
      speed: json['speed'] as int? ?? 128,
      intensity: json['intensity'] as int? ?? 128,
      brightness: json['brightness'] as int? ?? 255,
      colorGroupSize: json['colorGroupSize'] as int? ?? 1,
    );
  }

  /// Maximum number of action color layers.
  static const int maxActionColors = 15;

  @override
  String toString() => 'EditablePattern(id: $id, name: $name, '
      'colors: ${actionColors.length}, fx: $effectId)';
}
