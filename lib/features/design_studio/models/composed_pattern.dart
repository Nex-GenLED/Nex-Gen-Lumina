import 'package:flutter/material.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design_studio/models/design_intent.dart';

/// The final composed pattern ready to be applied to WLED devices.
///
/// This is the output of the pattern composition process, containing
/// everything needed to apply the design to the lights.
class ComposedPattern {
  /// User-friendly name for this pattern.
  final String name;

  /// Description of what this pattern does.
  final String? description;

  /// The original design intent this was composed from.
  final DesignIntent? sourceIntent;

  /// LED color groups defining the static colors.
  final List<LedColorGroup> colorGroups;

  /// Primary WLED effect ID (0 = solid).
  final int effectId;

  /// Effect speed (0-255).
  final int speed;

  /// Effect intensity (0-255).
  final int intensity;

  /// Overall brightness (0-255).
  final int brightness;

  /// Whether this pattern has motion/animation.
  final bool hasMotion;

  /// Direction of motion (if applicable).
  final MotionDirection? motionDirection;

  /// Whether effect direction is reversed.
  final bool reverse;

  /// The complete WLED JSON payload.
  final Map<String, dynamic> wledPayload;

  /// Colors used in this pattern (for display).
  final List<Color> usedColors;

  /// Total pixel count this pattern targets.
  final int totalPixels;

  /// When this pattern was composed.
  final DateTime composedAt;

  /// Any warnings about the composition.
  final List<String> warnings;

  const ComposedPattern({
    required this.name,
    this.description,
    this.sourceIntent,
    required this.colorGroups,
    this.effectId = 0,
    this.speed = 128,
    this.intensity = 128,
    this.brightness = 200,
    this.hasMotion = false,
    this.motionDirection,
    this.reverse = false,
    required this.wledPayload,
    this.usedColors = const [],
    this.totalPixels = 0,
    required this.composedAt,
    this.warnings = const [],
  });

  /// Create an empty/placeholder pattern.
  factory ComposedPattern.empty() => ComposedPattern(
        name: 'Empty',
        colorGroups: const [],
        wledPayload: const {'on': false},
        composedAt: DateTime.now(),
      );

  /// Create a simple solid color pattern.
  factory ComposedPattern.solid({
    required String name,
    required Color color,
    required int totalPixels,
    int brightness = 200,
  }) {
    final colorList = [color.red, color.green, color.blue, 0];
    return ComposedPattern(
      name: name,
      colorGroups: [
        LedColorGroup(
          startLed: 0,
          endLed: totalPixels - 1,
          color: colorList,
        ),
      ],
      brightness: brightness,
      wledPayload: {
        'on': true,
        'bri': brightness,
        'seg': [
          {
            'id': 0,
            'start': 0,
            'stop': totalPixels,
            'col': [colorList],
            'fx': 0,
          },
        ],
      },
      usedColors: [color],
      totalPixels: totalPixels,
      composedAt: DateTime.now(),
    );
  }

  /// Whether this is a valid, applyable pattern.
  bool get isValid => colorGroups.isNotEmpty || effectId > 0;

  /// Summary string for display.
  String get summary {
    final parts = <String>[];

    if (usedColors.isNotEmpty) {
      parts.add('${usedColors.length} color${usedColors.length > 1 ? 's' : ''}');
    }

    if (hasMotion && motionDirection != null) {
      parts.add('${motionDirection!.displayName} motion');
    }

    if (effectId > 0) {
      parts.add('effect #$effectId');
    }

    return parts.isNotEmpty ? parts.join(', ') : 'solid pattern';
  }

  ComposedPattern copyWith({
    String? name,
    String? description,
    DesignIntent? sourceIntent,
    List<LedColorGroup>? colorGroups,
    int? effectId,
    int? speed,
    int? intensity,
    int? brightness,
    bool? hasMotion,
    MotionDirection? motionDirection,
    bool? reverse,
    Map<String, dynamic>? wledPayload,
    List<Color>? usedColors,
    int? totalPixels,
    DateTime? composedAt,
    List<String>? warnings,
  }) {
    return ComposedPattern(
      name: name ?? this.name,
      description: description ?? this.description,
      sourceIntent: sourceIntent ?? this.sourceIntent,
      colorGroups: colorGroups ?? this.colorGroups,
      effectId: effectId ?? this.effectId,
      speed: speed ?? this.speed,
      intensity: intensity ?? this.intensity,
      brightness: brightness ?? this.brightness,
      hasMotion: hasMotion ?? this.hasMotion,
      motionDirection: motionDirection ?? this.motionDirection,
      reverse: reverse ?? this.reverse,
      wledPayload: wledPayload ?? this.wledPayload,
      usedColors: usedColors ?? this.usedColors,
      totalPixels: totalPixels ?? this.totalPixels,
      composedAt: composedAt ?? this.composedAt,
      warnings: warnings ?? this.warnings,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'color_groups': colorGroups.map((g) => {
              'start_led': g.startLed,
              'end_led': g.endLed,
              'color': g.color,
            }).toList(),
        'effect_id': effectId,
        'speed': speed,
        'intensity': intensity,
        'brightness': brightness,
        'has_motion': hasMotion,
        'motion_direction': motionDirection?.name,
        'reverse': reverse,
        'wled_payload': wledPayload,
        'used_colors': usedColors.map((c) => c.value).toList(),
        'total_pixels': totalPixels,
        'composed_at': composedAt.toIso8601String(),
        'warnings': warnings,
      };
}

/// Result of the pattern composition process.
class CompositionResult {
  /// The composed pattern (if successful).
  final ComposedPattern? pattern;

  /// Whether composition was successful.
  final bool isSuccess;

  /// Error message (if failed).
  final String? errorMessage;

  /// Warnings that don't prevent success but should be shown.
  final List<String> warnings;

  /// Suggestions for improvement.
  final List<String> suggestions;

  /// Whether manual intervention is recommended.
  final bool recommendManual;

  const CompositionResult({
    this.pattern,
    required this.isSuccess,
    this.errorMessage,
    this.warnings = const [],
    this.suggestions = const [],
    this.recommendManual = false,
  });

  /// Create a successful result.
  factory CompositionResult.success(ComposedPattern pattern, {
    List<String> warnings = const [],
    List<String> suggestions = const [],
  }) {
    return CompositionResult(
      pattern: pattern,
      isSuccess: true,
      warnings: warnings,
      suggestions: suggestions,
    );
  }

  /// Create a failed result.
  factory CompositionResult.failure(String errorMessage, {
    bool recommendManual = false,
    List<String> suggestions = const [],
  }) {
    return CompositionResult(
      isSuccess: false,
      errorMessage: errorMessage,
      recommendManual: recommendManual,
      suggestions: suggestions,
    );
  }
}

/// A preview of a pattern before full composition.
///
/// Used for showing quick previews during clarification.
class PatternPreview {
  /// Unique ID for this preview.
  final String id;

  /// Display name.
  final String name;

  /// Simplified WLED payload for quick preview.
  final Map<String, dynamic> previewPayload;

  /// Representative colors.
  final List<Color> colors;

  /// Whether this has animation.
  final bool isAnimated;

  /// Thumbnail data (base64 encoded if available).
  final String? thumbnailData;

  const PatternPreview({
    required this.id,
    required this.name,
    required this.previewPayload,
    this.colors = const [],
    this.isAnimated = false,
    this.thumbnailData,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'preview_payload': previewPayload,
        'colors': colors.map((c) => c.value).toList(),
        'is_animated': isAnimated,
        'thumbnail_data': thumbnailData,
      };
}

/// Statistics about a composed pattern.
class PatternStats {
  /// Number of distinct LED groups.
  final int groupCount;

  /// Number of unique colors used.
  final int uniqueColorCount;

  /// Total pixels covered.
  final int totalPixels;

  /// Percentage of roofline covered.
  final double coveragePercent;

  /// Whether pattern uses anchors.
  final bool usesAnchors;

  /// Whether pattern has spacing.
  final bool hasSpacing;

  /// Whether pattern has motion.
  final bool hasMotion;

  const PatternStats({
    required this.groupCount,
    required this.uniqueColorCount,
    required this.totalPixels,
    required this.coveragePercent,
    required this.usesAnchors,
    required this.hasSpacing,
    required this.hasMotion,
  });

  factory PatternStats.fromPattern(ComposedPattern pattern, int rooflineTotalPixels) {
    final uniqueColors = <int>{};
    for (final group in pattern.colorGroups) {
      uniqueColors.add(Color.fromARGB(
        255,
        group.color[0],
        group.color[1],
        group.color[2],
      ).value);
    }

    return PatternStats(
      groupCount: pattern.colorGroups.length,
      uniqueColorCount: uniqueColors.length,
      totalPixels: pattern.totalPixels,
      coveragePercent: rooflineTotalPixels > 0
          ? (pattern.totalPixels / rooflineTotalPixels * 100)
          : 0,
      usesAnchors: pattern.sourceIntent?.layers.any(
            (l) => l.colors.spacingRule?.type == SpacingType.anchorsOnly,
          ) ??
          false,
      hasSpacing: pattern.sourceIntent?.layers.any(
            (l) => l.colors.spacingRule != null,
          ) ??
          false,
      hasMotion: pattern.hasMotion,
    );
  }

  String get summaryText {
    final parts = <String>[];
    parts.add('$groupCount groups');
    parts.add('$uniqueColorCount colors');
    if (hasMotion) parts.add('animated');
    if (hasSpacing) parts.add('spaced');
    return parts.join(' • ');
  }
}
