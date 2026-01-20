import 'package:flutter/material.dart';

/// Defines the type of segment-aware pattern template.
///
/// Each template type has different behavior for generating LED patterns
/// that respect the roofline segment structure.
enum PatternTemplateType {
  /// Anchors always lit + evenly spaced single LEDs between anchors.
  /// Perfect for subtle downlighting effects.
  downlighting,

  /// Chase effect that respects segment boundaries.
  /// Animation stays within each segment before moving to the next.
  chaseBySegment,

  /// Different colors assigned to alternating segments.
  /// Creates visual distinction between roofline sections.
  alternatingSegments,

  /// Special color treatment for corner and peak segments.
  /// Highlights architectural features.
  cornerAccent,

  /// Uniform color/effect across all segments.
  /// Standard fill pattern that ignores segment boundaries.
  uniform,
}

/// Extension for PatternTemplateType display and serialization.
extension PatternTemplateTypeExtension on PatternTemplateType {
  String get name {
    switch (this) {
      case PatternTemplateType.downlighting:
        return 'downlighting';
      case PatternTemplateType.chaseBySegment:
        return 'chase_by_segment';
      case PatternTemplateType.alternatingSegments:
        return 'alternating_segments';
      case PatternTemplateType.cornerAccent:
        return 'corner_accent';
      case PatternTemplateType.uniform:
        return 'uniform';
    }
  }

  String get displayName {
    switch (this) {
      case PatternTemplateType.downlighting:
        return 'Downlighting';
      case PatternTemplateType.chaseBySegment:
        return 'Chase by Segment';
      case PatternTemplateType.alternatingSegments:
        return 'Alternating Segments';
      case PatternTemplateType.cornerAccent:
        return 'Corner Accent';
      case PatternTemplateType.uniform:
        return 'Uniform';
    }
  }

  String get description {
    switch (this) {
      case PatternTemplateType.downlighting:
        return 'Corner lights always on with evenly spaced lights between';
      case PatternTemplateType.chaseBySegment:
        return 'Animation flows through each segment sequentially';
      case PatternTemplateType.alternatingSegments:
        return 'Different colors for odd and even segments';
      case PatternTemplateType.cornerAccent:
        return 'Highlight corners and peaks with accent color';
      case PatternTemplateType.uniform:
        return 'Same color/effect across entire roofline';
    }
  }

  IconData get icon {
    switch (this) {
      case PatternTemplateType.downlighting:
        return Icons.light_mode;
      case PatternTemplateType.chaseBySegment:
        return Icons.animation;
      case PatternTemplateType.alternatingSegments:
        return Icons.swap_horiz;
      case PatternTemplateType.cornerAccent:
        return Icons.star;
      case PatternTemplateType.uniform:
        return Icons.format_paint;
    }
  }

  static PatternTemplateType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'downlighting':
        return PatternTemplateType.downlighting;
      case 'chase_by_segment':
        return PatternTemplateType.chaseBySegment;
      case 'alternating_segments':
        return PatternTemplateType.alternatingSegments;
      case 'corner_accent':
        return PatternTemplateType.cornerAccent;
      case 'uniform':
        return PatternTemplateType.uniform;
      default:
        return PatternTemplateType.downlighting;
    }
  }
}

/// A pattern template that understands segment structure.
///
/// This model defines the parameters for generating segment-aware patterns
/// that respect architectural features like corners, peaks, and anchor points.
class SegmentAwarePattern {
  /// Unique identifier
  final String id;

  /// Display name
  final String name;

  /// Type of pattern template
  final PatternTemplateType templateType;

  /// Color for anchor LEDs (corners, peaks)
  final Color anchorColor;

  /// Color for spaced/fill LEDs between anchors
  final Color spacedColor;

  /// Number of lit LEDs to place between anchor zones.
  /// Only used for downlighting pattern.
  final int spacingCount;

  /// Whether anchor points should always remain lit
  final bool anchorAlwaysOn;

  /// WLED effect ID (0 = solid, 2 = breathe, etc.)
  final int effectId;

  /// Animation speed (0-255)
  final int speed;

  /// Effect intensity (0-255)
  final int intensity;

  /// Optional secondary color for alternating patterns
  final Color? secondaryColor;

  /// Whether the pattern is animated
  bool get isAnimated => effectId > 0;

  const SegmentAwarePattern({
    required this.id,
    required this.name,
    required this.templateType,
    required this.anchorColor,
    required this.spacedColor,
    this.spacingCount = 3,
    this.anchorAlwaysOn = true,
    this.effectId = 0,
    this.speed = 128,
    this.intensity = 128,
    this.secondaryColor,
  });

  SegmentAwarePattern copyWith({
    String? id,
    String? name,
    PatternTemplateType? templateType,
    Color? anchorColor,
    Color? spacedColor,
    int? spacingCount,
    bool? anchorAlwaysOn,
    int? effectId,
    int? speed,
    int? intensity,
    Color? secondaryColor,
  }) {
    return SegmentAwarePattern(
      id: id ?? this.id,
      name: name ?? this.name,
      templateType: templateType ?? this.templateType,
      anchorColor: anchorColor ?? this.anchorColor,
      spacedColor: spacedColor ?? this.spacedColor,
      spacingCount: spacingCount ?? this.spacingCount,
      anchorAlwaysOn: anchorAlwaysOn ?? this.anchorAlwaysOn,
      effectId: effectId ?? this.effectId,
      speed: speed ?? this.speed,
      intensity: intensity ?? this.intensity,
      secondaryColor: secondaryColor ?? this.secondaryColor,
    );
  }

  /// Create from JSON
  factory SegmentAwarePattern.fromJson(Map<String, dynamic> json) {
    return SegmentAwarePattern(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Pattern',
      templateType: PatternTemplateTypeExtension.fromString(
        json['template_type'] as String? ?? 'downlighting',
      ),
      anchorColor: Color(json['anchor_color'] as int? ?? 0xFFFFE0B2),
      spacedColor: Color(json['spaced_color'] as int? ?? 0xFFFFE0B2),
      spacingCount: json['spacing_count'] as int? ?? 3,
      anchorAlwaysOn: json['anchor_always_on'] as bool? ?? true,
      effectId: json['effect_id'] as int? ?? 0,
      speed: json['speed'] as int? ?? 128,
      intensity: json['intensity'] as int? ?? 128,
      secondaryColor: json['secondary_color'] != null
          ? Color(json['secondary_color'] as int)
          : null,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'template_type': templateType.name,
      'anchor_color': anchorColor.value,
      'spaced_color': spacedColor.value,
      'spacing_count': spacingCount,
      'anchor_always_on': anchorAlwaysOn,
      'effect_id': effectId,
      'speed': speed,
      'intensity': intensity,
      if (secondaryColor != null) 'secondary_color': secondaryColor!.value,
    };
  }

  @override
  String toString() {
    return 'SegmentAwarePattern(id: $id, name: $name, '
        'type: ${templateType.displayName})';
  }

  // Preset patterns

  /// Default downlighting pattern with warm white colors
  static SegmentAwarePattern downlightingWarmWhite() {
    return const SegmentAwarePattern(
      id: 'preset_downlighting_warm',
      name: 'Warm White Downlighting',
      templateType: PatternTemplateType.downlighting,
      anchorColor: Color(0xFFFFE4C4), // Bisque/warm white
      spacedColor: Color(0xFFFFE4C4),
      spacingCount: 4,
      anchorAlwaysOn: true,
      effectId: 0, // Solid
    );
  }

  /// Downlighting with cool white
  static SegmentAwarePattern downlightingCoolWhite() {
    return const SegmentAwarePattern(
      id: 'preset_downlighting_cool',
      name: 'Cool White Downlighting',
      templateType: PatternTemplateType.downlighting,
      anchorColor: Color(0xFFF0F8FF), // Alice blue/cool white
      spacedColor: Color(0xFFF0F8FF),
      spacingCount: 4,
      anchorAlwaysOn: true,
      effectId: 0,
    );
  }

  /// Chase pattern that moves through segments
  static SegmentAwarePattern chaseBySegmentCyan() {
    return const SegmentAwarePattern(
      id: 'preset_chase_segment',
      name: 'Segment Chase',
      templateType: PatternTemplateType.chaseBySegment,
      anchorColor: Color(0xFF00E5FF), // Cyan
      spacedColor: Color(0xFF00E5FF),
      spacingCount: 0,
      anchorAlwaysOn: false,
      effectId: 28, // Chase effect
      speed: 128,
      intensity: 128,
    );
  }

  /// Alternating red and green for holidays
  static SegmentAwarePattern alternatingHoliday() {
    return const SegmentAwarePattern(
      id: 'preset_alternating_holiday',
      name: 'Holiday Alternating',
      templateType: PatternTemplateType.alternatingSegments,
      anchorColor: Color(0xFFFF0000), // Red
      spacedColor: Color(0xFF00FF00), // Green
      spacingCount: 0,
      anchorAlwaysOn: false,
      effectId: 0,
      secondaryColor: Color(0xFF00FF00),
    );
  }

  /// Corner accent with gold highlights
  static SegmentAwarePattern cornerAccentGold() {
    return const SegmentAwarePattern(
      id: 'preset_corner_gold',
      name: 'Gold Corner Accents',
      templateType: PatternTemplateType.cornerAccent,
      anchorColor: Color(0xFFFFD700), // Gold
      spacedColor: Color(0xFF1A1A1A), // Near black (off)
      spacingCount: 0,
      anchorAlwaysOn: true,
      effectId: 0,
    );
  }

  /// Uniform solid color fill
  static SegmentAwarePattern uniformSolid(Color color) {
    return SegmentAwarePattern(
      id: 'preset_uniform_solid',
      name: 'Solid Color',
      templateType: PatternTemplateType.uniform,
      anchorColor: color,
      spacedColor: color,
      spacingCount: 0,
      anchorAlwaysOn: false,
      effectId: 0,
    );
  }

  /// Get all preset patterns
  static List<SegmentAwarePattern> get presets => [
        downlightingWarmWhite(),
        downlightingCoolWhite(),
        chaseBySegmentCyan(),
        alternatingHoliday(),
        cornerAccentGold(),
        uniformSolid(const Color(0xFFFFFFFF)),
      ];
}
