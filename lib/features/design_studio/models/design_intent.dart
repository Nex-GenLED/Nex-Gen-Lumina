import 'package:flutter/material.dart';

/// Structured representation of a user's design intent parsed from natural language.
///
/// This model captures everything the user wants their lighting to do,
/// broken down into discrete layers that can be composed into a WLED payload.
class DesignIntent {
  /// The original user prompt that generated this intent.
  final String originalPrompt;

  /// Ordered list of design layers (later layers override earlier ones).
  final List<DesignLayer> layers;

  /// Global settings that apply to the entire design.
  final GlobalSettings globalSettings;

  /// Constraints that were validated (satisfied or not).
  final List<DesignConstraint> constraints;

  /// Ambiguities detected that need user clarification.
  final List<AmbiguityFlag> ambiguities;

  /// Confidence score (0.0-1.0) in the intent parsing.
  final double confidence;

  /// When this intent was parsed.
  final DateTime parsedAt;

  const DesignIntent({
    required this.originalPrompt,
    required this.layers,
    this.globalSettings = const GlobalSettings(),
    this.constraints = const [],
    this.ambiguities = const [],
    this.confidence = 1.0,
    DateTime? parsedAt,
  }) : parsedAt = parsedAt ?? const _DefaultDateTime();

  /// Whether this intent needs clarification before it can be composed.
  bool get needsClarification => ambiguities.isNotEmpty;

  /// Whether all constraints are satisfied.
  bool get allConstraintsSatisfied =>
      constraints.every((c) => c.isSatisfied);

  /// Whether this intent is ready to be composed into a pattern.
  bool get isReady => !needsClarification && allConstraintsSatisfied;

  DesignIntent copyWith({
    String? originalPrompt,
    List<DesignLayer>? layers,
    GlobalSettings? globalSettings,
    List<DesignConstraint>? constraints,
    List<AmbiguityFlag>? ambiguities,
    double? confidence,
    DateTime? parsedAt,
  }) {
    return DesignIntent(
      originalPrompt: originalPrompt ?? this.originalPrompt,
      layers: layers ?? this.layers,
      globalSettings: globalSettings ?? this.globalSettings,
      constraints: constraints ?? this.constraints,
      ambiguities: ambiguities ?? this.ambiguities,
      confidence: confidence ?? this.confidence,
      parsedAt: parsedAt ?? this.parsedAt,
    );
  }

  /// Create an empty intent for initialization.
  factory DesignIntent.empty() => DesignIntent(
        originalPrompt: '',
        layers: const [],
        parsedAt: DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'original_prompt': originalPrompt,
        'layers': layers.map((l) => l.toJson()).toList(),
        'global_settings': globalSettings.toJson(),
        'constraints': constraints.map((c) => c.toJson()).toList(),
        'ambiguities': ambiguities.map((a) => a.toJson()).toList(),
        'confidence': confidence,
        'parsed_at': parsedAt.toIso8601String(),
      };
}

// Helper class for const default DateTime
class _DefaultDateTime implements DateTime {
  const _DefaultDateTime();

  @override
  dynamic noSuchMethod(Invocation invocation) => DateTime.now();
}

/// A single layer of the design (e.g., "base color", "accent on peaks", "chase effect").
///
/// Layers are composited in order, with later layers overriding earlier ones
/// for any overlapping pixels.
class DesignLayer {
  /// Unique identifier for this layer.
  final String id;

  /// Human-readable name for this layer.
  final String name;

  /// Which zones/segments this layer targets.
  final ZoneSelector targetZone;

  /// Color assignments for this layer.
  final ColorAssignment colors;

  /// Pattern rule (solid, alternating, gradient, etc.).
  final PatternRule pattern;

  /// Motion/animation settings (optional).
  final MotionSettings? motion;

  /// Priority for layer stacking (higher = on top).
  final int priority;

  /// Whether this layer is enabled.
  final bool enabled;

  const DesignLayer({
    required this.id,
    required this.name,
    required this.targetZone,
    required this.colors,
    this.pattern = const PatternRule.solid(),
    this.motion,
    this.priority = 0,
    this.enabled = true,
  });

  DesignLayer copyWith({
    String? id,
    String? name,
    ZoneSelector? targetZone,
    ColorAssignment? colors,
    PatternRule? pattern,
    MotionSettings? motion,
    int? priority,
    bool? enabled,
  }) {
    return DesignLayer(
      id: id ?? this.id,
      name: name ?? this.name,
      targetZone: targetZone ?? this.targetZone,
      colors: colors ?? this.colors,
      pattern: pattern ?? this.pattern,
      motion: motion ?? this.motion,
      priority: priority ?? this.priority,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'target_zone': targetZone.toJson(),
        'colors': colors.toJson(),
        'pattern': pattern.toJson(),
        'motion': motion?.toJson(),
        'priority': priority,
        'enabled': enabled,
      };
}

/// Selects which zones/segments a layer applies to.
class ZoneSelector {
  /// Type of zone selection.
  final ZoneSelectorType type;

  /// Specific segment IDs (when type is segments).
  final List<String>? segmentIds;

  /// Architectural roles to target (when type is architectural).
  final List<ArchitecturalRole>? roles;

  /// Location filter (front, back, left, right).
  final String? location;

  /// Level/story filter (1=ground, 2=second story, etc.).
  final int? level;

  /// Specific pixel ranges (when type is custom).
  final List<PixelRange>? pixelRanges;

  const ZoneSelector({
    required this.type,
    this.segmentIds,
    this.roles,
    this.location,
    this.level,
    this.pixelRanges,
  });

  /// Select all pixels.
  const ZoneSelector.all() : this(type: ZoneSelectorType.all);

  /// Select by architectural role (peaks, corners, etc.).
  const ZoneSelector.architectural(List<ArchitecturalRole> roles)
      : this(type: ZoneSelectorType.architectural, roles: roles);

  /// Select by location (front, back, etc.).
  const ZoneSelector.location(String location)
      : this(type: ZoneSelectorType.location, location: location);

  /// Select by level/story.
  const ZoneSelector.level(int level)
      : this(type: ZoneSelectorType.level, level: level);

  /// Select specific segments.
  const ZoneSelector.segments(List<String> segmentIds)
      : this(type: ZoneSelectorType.segments, segmentIds: segmentIds);

  /// Human-readable description of what this selector targets.
  String get description {
    switch (type) {
      case ZoneSelectorType.all:
        return 'everywhere';
      case ZoneSelectorType.segments:
        return segmentIds?.join(', ') ?? 'specific segments';
      case ZoneSelectorType.architectural:
        return roles?.map((r) => r.displayName).join(' and ') ?? 'architectural features';
      case ZoneSelectorType.location:
        return '$location side';
      case ZoneSelectorType.level:
        return level == 1 ? 'first floor' : 'floor $level';
      case ZoneSelectorType.custom:
        return 'custom selection';
    }
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'segment_ids': segmentIds,
        'roles': roles?.map((r) => r.name).toList(),
        'location': location,
        'level': level,
        'pixel_ranges': pixelRanges?.map((r) => r.toJson()).toList(),
      };
}

/// Types of zone selection.
enum ZoneSelectorType {
  /// All pixels in the roofline.
  all,

  /// Specific segments by ID.
  segments,

  /// By architectural role (peaks, corners, runs, etc.).
  architectural,

  /// By location (front, back, left, right).
  location,

  /// By level/story.
  level,

  /// Custom pixel ranges.
  custom,
}

/// Architectural roles that segments can have.
enum ArchitecturalRole {
  peak,
  corner,
  run,
  eave,
  valley,
  ridge,
  fascia,
  soffit,
  gutter,
  column,
  archway,
  connector;

  String get displayName {
    switch (this) {
      case ArchitecturalRole.peak:
        return 'peaks';
      case ArchitecturalRole.corner:
        return 'corners';
      case ArchitecturalRole.run:
        return 'runs';
      case ArchitecturalRole.eave:
        return 'eaves';
      case ArchitecturalRole.valley:
        return 'valleys';
      case ArchitecturalRole.ridge:
        return 'ridges';
      case ArchitecturalRole.fascia:
        return 'fascia';
      case ArchitecturalRole.soffit:
        return 'soffits';
      case ArchitecturalRole.gutter:
        return 'gutters';
      case ArchitecturalRole.column:
        return 'columns';
      case ArchitecturalRole.archway:
        return 'archways';
      case ArchitecturalRole.connector:
        return 'connectors';
    }
  }
}

/// A range of pixels.
class PixelRange {
  final int start;
  final int end;

  const PixelRange(this.start, this.end);

  int get length => end - start + 1;

  Map<String, dynamic> toJson() => {'start': start, 'end': end};
}

/// Color assignments for a design layer.
class ColorAssignment {
  /// Primary color (main fill).
  final Color primaryColor;

  /// Secondary color (for alternating patterns).
  final Color? secondaryColor;

  /// Accent color (for highlights, anchors).
  final Color? accentColor;

  /// Fill/background color.
  final Color? fillColor;

  /// Spacing rule for color distribution.
  final SpacingRule? spacingRule;

  const ColorAssignment({
    required this.primaryColor,
    this.secondaryColor,
    this.accentColor,
    this.fillColor,
    this.spacingRule,
  });

  /// Single solid color.
  const ColorAssignment.solid(Color color)
      : primaryColor = color,
        secondaryColor = null,
        accentColor = null,
        fillColor = null,
        spacingRule = null;

  /// Two-color alternating.
  const ColorAssignment.alternating(Color color1, Color color2)
      : primaryColor = color1,
        secondaryColor = color2,
        accentColor = null,
        fillColor = null,
        spacingRule = null;

  /// Accent with fill.
  const ColorAssignment.accentedFill({
    required Color accent,
    required Color fill,
    SpacingRule? spacing,
  })  : accentColor = accent,
        fillColor = fill,
        primaryColor = fill,
        secondaryColor = null,
        spacingRule = spacing;

  Map<String, dynamic> toJson() => {
        'primary_color': _colorToList(primaryColor),
        'secondary_color': secondaryColor != null ? _colorToList(secondaryColor!) : null,
        'accent_color': accentColor != null ? _colorToList(accentColor!) : null,
        'fill_color': fillColor != null ? _colorToList(fillColor!) : null,
        'spacing_rule': spacingRule?.toJson(),
      };

  List<int> _colorToList(Color c) => [c.red, c.green, c.blue, c.alpha];
}

/// Rules for spacing LEDs in a pattern.
class SpacingRule {
  /// Type of spacing.
  final SpacingType type;

  /// Number of LEDs that are "on" in each group.
  final int onCount;

  /// Number of LEDs that are "off" (or different color) between groups.
  final int offCount;

  /// Whether to start with "on" LEDs.
  final bool startWithOn;

  /// Total spacing interval (for equally spaced).
  final int? interval;

  const SpacingRule({
    required this.type,
    this.onCount = 1,
    this.offCount = 1,
    this.startWithOn = true,
    this.interval,
  });

  /// Every other LED (1 on, 1 off).
  const SpacingRule.everyOther()
      : type = SpacingType.pattern,
        onCount = 1,
        offCount = 1,
        startWithOn = true,
        interval = null;

  /// One on, two off pattern.
  const SpacingRule.oneOnTwoOff()
      : type = SpacingType.pattern,
        onCount = 1,
        offCount = 2,
        startWithOn = true,
        interval = null;

  /// Two on, one off pattern.
  const SpacingRule.twoOnOneOff()
      : type = SpacingType.pattern,
        onCount = 2,
        offCount = 1,
        startWithOn = true,
        interval = null;

  /// Equally spaced LEDs across the zone.
  const SpacingRule.equallySpaced(int count)
      : type = SpacingType.equallySpaced,
        onCount = count,
        offCount = 0,
        startWithOn = true,
        interval = null;

  /// Every N pixels.
  const SpacingRule.everyNth(int n)
      : type = SpacingType.everyNth,
        onCount = 1,
        offCount = n - 1,
        startWithOn = true,
        interval = n;

  /// Human-readable description.
  String get description {
    switch (type) {
      case SpacingType.pattern:
        if (onCount == 1 && offCount == 1) return 'every other';
        if (onCount == 1 && offCount == 2) return '1 on, 2 off';
        if (onCount == 2 && offCount == 1) return '2 on, 1 off';
        return '$onCount on, $offCount off';
      case SpacingType.equallySpaced:
        return '$onCount equally spaced';
      case SpacingType.everyNth:
        return 'every ${interval ?? (onCount + offCount)} pixels';
      case SpacingType.anchorsOnly:
        return 'anchors only';
      case SpacingType.continuous:
        return 'continuous';
    }
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'on_count': onCount,
        'off_count': offCount,
        'start_with_on': startWithOn,
        'interval': interval,
      };
}

/// Types of spacing patterns.
enum SpacingType {
  /// Repeating on/off pattern.
  pattern,

  /// Equally distributed across the zone.
  equallySpaced,

  /// Every N pixels.
  everyNth,

  /// Only at anchor points.
  anchorsOnly,

  /// Continuous (no spacing).
  continuous,
}

/// Pattern rule for how colors are applied.
class PatternRule {
  /// Type of pattern.
  final PatternType type;

  /// Gradient stops (for gradient patterns).
  final List<GradientStop>? gradientStops;

  const PatternRule({
    required this.type,
    this.gradientStops,
  });

  const PatternRule.solid() : type = PatternType.solid, gradientStops = null;
  const PatternRule.alternating() : type = PatternType.alternating, gradientStops = null;
  const PatternRule.gradient(List<GradientStop> stops)
      : type = PatternType.gradient,
        gradientStops = stops;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'gradient_stops': gradientStops?.map((s) => s.toJson()).toList(),
      };
}

/// Types of patterns.
enum PatternType {
  /// Single solid color.
  solid,

  /// Alternating between colors.
  alternating,

  /// Gradient blend between colors.
  gradient,

  /// Wave pattern.
  wave,

  /// Twinkle/sparkle effect.
  twinkle,
}

/// A stop in a gradient.
class GradientStop {
  final double position; // 0.0 to 1.0
  final Color color;

  const GradientStop(this.position, this.color);

  Map<String, dynamic> toJson() => {
        'position': position,
        'color': [color.red, color.green, color.blue],
      };
}

/// Motion/animation settings for a layer.
class MotionSettings {
  /// Type of motion effect.
  final MotionType motionType;

  /// Direction of motion.
  final MotionDirection direction;

  /// Speed (0-255, maps to WLED sx parameter).
  final int speed;

  /// Intensity (0-255, maps to WLED ix parameter).
  final int intensity;

  /// Whether to reverse the motion.
  final bool reverse;

  /// WLED effect ID to use.
  final int? effectId;

  const MotionSettings({
    required this.motionType,
    required this.direction,
    this.speed = 128,
    this.intensity = 128,
    this.reverse = false,
    this.effectId,
  });

  /// Chase effect moving left to right.
  const MotionSettings.chaseLeftToRight({int speed = 128})
      : motionType = MotionType.chase,
        direction = MotionDirection.leftToRight,
        this.speed = speed,
        intensity = 128,
        reverse = false,
        effectId = 28;

  /// Chase effect moving right to left.
  const MotionSettings.chaseRightToLeft({int speed = 128})
      : motionType = MotionType.chase,
        direction = MotionDirection.rightToLeft,
        this.speed = speed,
        intensity = 128,
        reverse = true,
        effectId = 28;

  /// Wave effect.
  const MotionSettings.wave({
    required MotionDirection direction,
    int speed = 128,
  })  : motionType = MotionType.wave,
        this.direction = direction,
        this.speed = speed,
        intensity = 180,
        reverse = direction == MotionDirection.rightToLeft,
        effectId = 67; // Colorwaves

  Map<String, dynamic> toJson() => {
        'motion_type': motionType.name,
        'direction': direction.name,
        'speed': speed,
        'intensity': intensity,
        'reverse': reverse,
        'effect_id': effectId,
      };
}

/// Types of motion effects.
enum MotionType {
  /// No motion (static).
  none,

  /// Chase/running lights.
  chase,

  /// Wave/ripple effect.
  wave,

  /// Flowing/streaming.
  flow,

  /// Pulsing/breathing.
  pulse,

  /// Twinkling/sparkling.
  twinkle,

  /// Scanning back and forth.
  scan,
}

/// Direction of motion.
enum MotionDirection {
  /// Left to right.
  leftToRight,

  /// Right to left.
  rightToLeft,

  /// Inward (from both ends to center).
  inward,

  /// Outward (from center to both ends).
  outward,

  /// Upward.
  upward,

  /// Downward.
  downward,

  /// Clockwise (for circular arrangements).
  clockwise,

  /// Counter-clockwise.
  counterClockwise;

  String get displayName {
    switch (this) {
      case MotionDirection.leftToRight:
        return 'left to right';
      case MotionDirection.rightToLeft:
        return 'right to left';
      case MotionDirection.inward:
        return 'inward';
      case MotionDirection.outward:
        return 'outward';
      case MotionDirection.upward:
        return 'upward';
      case MotionDirection.downward:
        return 'downward';
      case MotionDirection.clockwise:
        return 'clockwise';
      case MotionDirection.counterClockwise:
        return 'counter-clockwise';
    }
  }
}

/// Global settings that apply to the entire design.
class GlobalSettings {
  /// Overall brightness (0-255).
  final int brightness;

  /// Whether to transition smoothly from current state.
  final bool smoothTransition;

  /// Transition duration in milliseconds.
  final int transitionDuration;

  const GlobalSettings({
    this.brightness = 200,
    this.smoothTransition = true,
    this.transitionDuration = 500,
  });

  Map<String, dynamic> toJson() => {
        'brightness': brightness,
        'smooth_transition': smoothTransition,
        'transition_duration': transitionDuration,
      };
}

/// A constraint that was validated.
class DesignConstraint {
  /// Type of constraint.
  final ConstraintType type;

  /// Whether the constraint is satisfied.
  final bool isSatisfied;

  /// Reason for failure (if not satisfied).
  final String? failureReason;

  /// Alternative suggestions (if not satisfied).
  final List<AlternativeSuggestion>? alternatives;

  /// ID of the layer this constraint applies to.
  final String? layerId;

  const DesignConstraint({
    required this.type,
    required this.isSatisfied,
    this.failureReason,
    this.alternatives,
    this.layerId,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'is_satisfied': isSatisfied,
        'failure_reason': failureReason,
        'alternatives': alternatives?.map((a) => a.toJson()).toList(),
        'layer_id': layerId,
      };
}

/// Types of constraints.
enum ConstraintType {
  /// Spacing math validation.
  spacingMath,

  /// Symmetry requirement.
  symmetry,

  /// Color contrast validation.
  colorContrast,

  /// Zone overlap detection.
  zoneOverlap,

  /// Pixel count validation.
  pixelCount,
}

/// An alternative suggestion when a constraint isn't satisfied.
class AlternativeSuggestion {
  /// ID for this alternative.
  final String id;

  /// Human-readable label.
  final String label;

  /// Description of the alternative.
  final String description;

  /// Preview payload for visualizing this alternative.
  final Map<String, dynamic>? previewPayload;

  /// How different this is from the original request (0.0-1.0).
  final double deviationScore;

  const AlternativeSuggestion({
    required this.id,
    required this.label,
    required this.description,
    this.previewPayload,
    this.deviationScore = 0.0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'description': description,
        'preview_payload': previewPayload,
        'deviation_score': deviationScore,
      };
}

/// A flag indicating something needs clarification.
class AmbiguityFlag {
  /// Type of ambiguity.
  final AmbiguityType type;

  /// Human-readable description of the ambiguity.
  final String description;

  /// Options to choose from.
  final List<ClarificationChoice> choices;

  /// ID of the layer this applies to (if applicable).
  final String? affectedLayerId;

  /// The parsed clause that caused the ambiguity.
  final String? sourceClause;

  const AmbiguityFlag({
    required this.type,
    required this.description,
    required this.choices,
    this.affectedLayerId,
    this.sourceClause,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'description': description,
        'choices': choices.map((c) => c.toJson()).toList(),
        'affected_layer_id': affectedLayerId,
        'source_clause': sourceClause,
      };
}

/// Types of ambiguity.
enum AmbiguityType {
  /// Zone/segment selection is unclear.
  zoneAmbiguity,

  /// Color is vague (e.g., "greenish").
  colorAmbiguity,

  /// Spacing can't be achieved exactly.
  spacingImpossible,

  /// Motion direction is unclear.
  directionAmbiguity,

  /// Multiple layers conflict.
  conflictResolution,

  /// Effect/animation is unclear.
  effectAmbiguity,
}

/// A choice for resolving an ambiguity.
class ClarificationChoice {
  /// Unique ID for this choice.
  final String id;

  /// Display label.
  final String label;

  /// Optional description.
  final String? description;

  /// Whether this is the recommended choice.
  final bool isRecommended;

  /// Value to apply if this choice is selected.
  final dynamic value;

  const ClarificationChoice({
    required this.id,
    required this.label,
    this.description,
    this.isRecommended = false,
    this.value,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'description': description,
        'is_recommended': isRecommended,
        'value': value,
      };
}
