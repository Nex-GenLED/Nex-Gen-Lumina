/// Architectural role of a segment for natural language control.
///
/// Allows users to say "light up the peaks" or "chase the eaves"
/// - [peak]: Roof peak/gable apex point
/// - [eave]: Horizontal edge where roof meets wall
/// - [valley]: Inside corner where two roof slopes meet
/// - [ridge]: Top horizontal edge of roof
/// - [corner]: Outside corner where walls meet
/// - [fascia]: Vertical board along roof edge
/// - [soffit]: Underside of roof overhang
/// - [gutter]: Rain gutter along roof edge
/// - [column]: Vertical post/pillar
/// - [archway]: Architectural arch
enum ArchitecturalRole {
  peak,
  eave,
  valley,
  ridge,
  corner,
  fascia,
  soffit,
  gutter,
  column,
  archway,
}

/// Defines the type of segment for pattern generation logic.
///
/// Different segment types may have different default behaviors:
/// - [run]: Horizontal/diagonal run of lights - default anchors at start/end
/// - [corner]: 90-degree corner or direction change - anchor at corner point
/// - [peak]: Roof peak (apex point) - anchor at peak
/// - [column]: Vertical column/pillar - anchors at top/bottom
/// - [connector]: Transition between sections - may have no anchors
enum SegmentType {
  run,
  corner,
  peak,
  column,
  connector,
}

/// Direction of LED flow within a segment.
/// Used for chase animations and gradient calculations.
enum SegmentDirection {
  /// Left to right (horizontal)
  leftToRight,
  /// Right to left (horizontal)
  rightToLeft,
  /// Upward (vertical or ascending)
  upward,
  /// Downward (vertical or descending)
  downward,
  /// Toward the street (away from house)
  towardStreet,
  /// Away from street (toward house)
  awayFromStreet,
  /// Clockwise around a feature
  clockwise,
  /// Counter-clockwise around a feature
  counterClockwise,
}

/// Type of anchor point for accent lighting.
enum AnchorType {
  /// Corner where roofline changes direction
  corner,
  /// Peak/apex of a gable or roof
  peak,
  /// Boundary between segments
  boundary,
  /// User-defined custom anchor point
  custom,
  /// Center point of a segment
  center,
}

/// Represents a specific anchor point with metadata.
class AnchorPoint {
  /// Local LED index within the segment
  final int ledIndex;

  /// Type of anchor
  final AnchorType type;

  /// Optional user-friendly label
  final String? label;

  /// Number of LEDs in this anchor zone (default: 2)
  final int zoneSize;

  const AnchorPoint({
    required this.ledIndex,
    required this.type,
    this.label,
    this.zoneSize = 2,
  });

  AnchorPoint copyWith({
    int? ledIndex,
    AnchorType? type,
    String? label,
    int? zoneSize,
  }) {
    return AnchorPoint(
      ledIndex: ledIndex ?? this.ledIndex,
      type: type ?? this.type,
      label: label ?? this.label,
      zoneSize: zoneSize ?? this.zoneSize,
    );
  }

  factory AnchorPoint.fromJson(Map<String, dynamic> json) {
    return AnchorPoint(
      ledIndex: json['led_index'] as int? ?? 0,
      type: AnchorTypeExtension.fromString(json['type'] as String? ?? 'custom'),
      label: json['label'] as String?,
      zoneSize: json['zone_size'] as int? ?? 2,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'led_index': ledIndex,
      'type': type.name,
      if (label != null) 'label': label,
      'zone_size': zoneSize,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AnchorPoint &&
        other.ledIndex == ledIndex &&
        other.type == type &&
        other.label == label &&
        other.zoneSize == zoneSize;
  }

  @override
  int get hashCode => Object.hash(ledIndex, type, label, zoneSize);
}

/// Extension for ArchitecturalRole serialization and display
extension ArchitecturalRoleExtension on ArchitecturalRole {
  String get name {
    switch (this) {
      case ArchitecturalRole.peak:
        return 'peak';
      case ArchitecturalRole.eave:
        return 'eave';
      case ArchitecturalRole.valley:
        return 'valley';
      case ArchitecturalRole.ridge:
        return 'ridge';
      case ArchitecturalRole.corner:
        return 'corner';
      case ArchitecturalRole.fascia:
        return 'fascia';
      case ArchitecturalRole.soffit:
        return 'soffit';
      case ArchitecturalRole.gutter:
        return 'gutter';
      case ArchitecturalRole.column:
        return 'column';
      case ArchitecturalRole.archway:
        return 'archway';
    }
  }

  String get displayName {
    switch (this) {
      case ArchitecturalRole.peak:
        return 'Peak';
      case ArchitecturalRole.eave:
        return 'Eave';
      case ArchitecturalRole.valley:
        return 'Valley';
      case ArchitecturalRole.ridge:
        return 'Ridge';
      case ArchitecturalRole.corner:
        return 'Corner';
      case ArchitecturalRole.fascia:
        return 'Fascia';
      case ArchitecturalRole.soffit:
        return 'Soffit';
      case ArchitecturalRole.gutter:
        return 'Gutter';
      case ArchitecturalRole.column:
        return 'Column';
      case ArchitecturalRole.archway:
        return 'Archway';
    }
  }

  String get description {
    switch (this) {
      case ArchitecturalRole.peak:
        return 'Roof peak or gable apex point';
      case ArchitecturalRole.eave:
        return 'Horizontal edge where roof meets wall';
      case ArchitecturalRole.valley:
        return 'Inside corner where two roof slopes meet';
      case ArchitecturalRole.ridge:
        return 'Top horizontal edge of roof';
      case ArchitecturalRole.corner:
        return 'Outside corner where walls meet';
      case ArchitecturalRole.fascia:
        return 'Vertical board along roof edge';
      case ArchitecturalRole.soffit:
        return 'Underside of roof overhang';
      case ArchitecturalRole.gutter:
        return 'Rain gutter along roof edge';
      case ArchitecturalRole.column:
        return 'Vertical post or pillar';
      case ArchitecturalRole.archway:
        return 'Architectural arch';
    }
  }

  String get pluralName {
    switch (this) {
      case ArchitecturalRole.peak:
        return 'peaks';
      case ArchitecturalRole.eave:
        return 'eaves';
      case ArchitecturalRole.valley:
        return 'valleys';
      case ArchitecturalRole.ridge:
        return 'ridges';
      case ArchitecturalRole.corner:
        return 'corners';
      case ArchitecturalRole.fascia:
        return 'fascias';
      case ArchitecturalRole.soffit:
        return 'soffits';
      case ArchitecturalRole.gutter:
        return 'gutters';
      case ArchitecturalRole.column:
        return 'columns';
      case ArchitecturalRole.archway:
        return 'archways';
    }
  }

  static ArchitecturalRole fromString(String value) {
    switch (value.toLowerCase()) {
      case 'peak':
        return ArchitecturalRole.peak;
      case 'eave':
        return ArchitecturalRole.eave;
      case 'valley':
        return ArchitecturalRole.valley;
      case 'ridge':
        return ArchitecturalRole.ridge;
      case 'corner':
        return ArchitecturalRole.corner;
      case 'fascia':
        return ArchitecturalRole.fascia;
      case 'soffit':
        return ArchitecturalRole.soffit;
      case 'gutter':
        return ArchitecturalRole.gutter;
      case 'column':
        return ArchitecturalRole.column;
      case 'archway':
        return ArchitecturalRole.archway;
      default:
        return ArchitecturalRole.eave; // Default to eave
    }
  }
}

/// Extension for AnchorType serialization
extension AnchorTypeExtension on AnchorType {
  String get displayName {
    switch (this) {
      case AnchorType.corner:
        return 'Corner';
      case AnchorType.peak:
        return 'Peak';
      case AnchorType.boundary:
        return 'Boundary';
      case AnchorType.custom:
        return 'Custom';
      case AnchorType.center:
        return 'Center';
    }
  }

  static AnchorType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'corner':
        return AnchorType.corner;
      case 'peak':
        return AnchorType.peak;
      case 'boundary':
        return AnchorType.boundary;
      case 'center':
        return AnchorType.center;
      default:
        return AnchorType.custom;
    }
  }
}

/// Extension for SegmentDirection serialization
extension SegmentDirectionExtension on SegmentDirection {
  String get displayName {
    switch (this) {
      case SegmentDirection.leftToRight:
        return 'Left to Right';
      case SegmentDirection.rightToLeft:
        return 'Right to Left';
      case SegmentDirection.upward:
        return 'Upward';
      case SegmentDirection.downward:
        return 'Downward';
      case SegmentDirection.towardStreet:
        return 'Toward Street';
      case SegmentDirection.awayFromStreet:
        return 'Away from Street';
      case SegmentDirection.clockwise:
        return 'Clockwise';
      case SegmentDirection.counterClockwise:
        return 'Counter-Clockwise';
    }
  }

  String get shortName {
    switch (this) {
      case SegmentDirection.leftToRight:
        return 'L→R';
      case SegmentDirection.rightToLeft:
        return 'R→L';
      case SegmentDirection.upward:
        return '↑';
      case SegmentDirection.downward:
        return '↓';
      case SegmentDirection.towardStreet:
        return '→St';
      case SegmentDirection.awayFromStreet:
        return '←St';
      case SegmentDirection.clockwise:
        return '↻';
      case SegmentDirection.counterClockwise:
        return '↺';
    }
  }

  static SegmentDirection fromString(String value) {
    switch (value.toLowerCase()) {
      case 'lefttoright':
      case 'left_to_right':
        return SegmentDirection.leftToRight;
      case 'righttoleft':
      case 'right_to_left':
        return SegmentDirection.rightToLeft;
      case 'upward':
        return SegmentDirection.upward;
      case 'downward':
        return SegmentDirection.downward;
      case 'towardstreet':
      case 'toward_street':
        return SegmentDirection.towardStreet;
      case 'awayfromstreet':
      case 'away_from_street':
        return SegmentDirection.awayFromStreet;
      case 'clockwise':
        return SegmentDirection.clockwise;
      case 'counterclockwise':
      case 'counter_clockwise':
        return SegmentDirection.counterClockwise;
      default:
        return SegmentDirection.leftToRight;
    }
  }
}

/// Extension to convert SegmentType to/from string for serialization.
extension SegmentTypeExtension on SegmentType {
  String get name {
    switch (this) {
      case SegmentType.run:
        return 'run';
      case SegmentType.corner:
        return 'corner';
      case SegmentType.peak:
        return 'peak';
      case SegmentType.column:
        return 'column';
      case SegmentType.connector:
        return 'connector';
    }
  }

  String get displayName {
    switch (this) {
      case SegmentType.run:
        return 'Run';
      case SegmentType.corner:
        return 'Corner';
      case SegmentType.peak:
        return 'Peak';
      case SegmentType.column:
        return 'Column';
      case SegmentType.connector:
        return 'Connector';
    }
  }

  String get description {
    switch (this) {
      case SegmentType.run:
        return 'Horizontal or diagonal run of lights';
      case SegmentType.corner:
        return '90-degree corner or direction change';
      case SegmentType.peak:
        return 'Roof peak or apex point';
      case SegmentType.column:
        return 'Vertical column or pillar';
      case SegmentType.connector:
        return 'Transition between sections';
    }
  }

  static SegmentType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'run':
        return SegmentType.run;
      case 'corner':
        return SegmentType.corner;
      case 'peak':
        return SegmentType.peak;
      case 'column':
        return SegmentType.column;
      case 'connector':
        return SegmentType.connector;
      default:
        return SegmentType.run;
    }
  }
}

/// Represents a single segment in a roofline configuration.
///
/// Each segment has:
/// - A unique identifier and display name
/// - Pixel count (number of LEDs in this segment)
/// - Start pixel index (global position in the full LED strip)
/// - Segment type for pattern generation logic
/// - Anchor pixels (local indices within segment that are anchor points)
/// - Anchor LED count (how many LEDs form each anchor zone, typically 2)
/// - Direction of LED flow
/// - Optional description and physical location info
class RooflineSegment {
  /// Unique identifier for this segment
  final String id;

  /// Display name (e.g., "3rd Car Garage", "Front Peak")
  final String name;

  /// Number of LEDs in this segment
  final int pixelCount;

  /// Global start pixel index (0-based, auto-calculated from segment order)
  final int startPixel;

  /// Type of segment for pattern logic
  final SegmentType type;

  /// Local pixel indices within this segment that are anchor points.
  /// For example, [0, 18] means anchors at the first and 19th pixel of this segment.
  final List<int> anchorPixels;

  /// Number of LEDs per anchor zone (default: 2).
  /// When an anchor is at position X, LEDs X through X+(anchorLedCount-1) are part of that anchor.
  final int anchorLedCount;

  /// Sort order for display and calculation purposes
  final int sortOrder;

  /// Direction of LED flow within this segment
  final SegmentDirection direction;

  /// Enhanced anchor points with type information
  final List<AnchorPoint> anchorPoints;

  /// Optional description of this segment's physical location
  final String? description;

  /// Whether this segment is part of the primary roofline (vs secondary features)
  final bool isPrimary;

  /// Segment this one connects to (for symmetry calculations)
  final String? symmetryPairId;

  /// Architectural role for natural language understanding (e.g., "light the peaks")
  final ArchitecturalRole? architecturalRole;

  /// Physical location relative to the house (front, back, left, right)
  final String? location;

  /// IDs of adjacent segments for intelligent pattern flow
  final List<String> adjacentSegmentIds;

  /// Whether this segment is visually prominent (for AI suggestions)
  final bool isProminent;

  /// Whether this segment is physically connected to the previous segment.
  /// When false, there's a discontinuity (jump to second story, detached area, etc.)
  /// First segment is always considered connected (no previous to connect to).
  final bool isConnectedToPrevious;

  /// The level/story this segment is on (1 = ground level, 2 = second story, etc.)
  /// Used for commands like "light up all second story segments"
  final int level;

  const RooflineSegment({
    required this.id,
    required this.name,
    required this.pixelCount,
    this.startPixel = 0,
    this.type = SegmentType.run,
    this.anchorPixels = const [],
    this.anchorLedCount = 2,
    this.sortOrder = 0,
    this.direction = SegmentDirection.leftToRight,
    this.anchorPoints = const [],
    this.description,
    this.isPrimary = true,
    this.symmetryPairId,
    this.architecturalRole,
    this.location,
    this.adjacentSegmentIds = const [],
    this.isProminent = false,
    this.isConnectedToPrevious = true,
    this.level = 1,
  });

  /// Global pixel index of the last LED in this segment (inclusive)
  int get endPixel => startPixel + pixelCount - 1;

  /// Convert local anchor pixel indices to global indices
  List<int> get globalAnchorPixels =>
      anchorPixels.map((localIndex) => startPixel + localIndex).toList();

  /// Returns the global pixel indices for an anchor zone starting at the given local anchor position.
  /// For example, if anchorLedCount is 2 and localAnchor is 0, this returns [startPixel, startPixel+1].
  List<int> getAnchorZoneGlobalPixels(int localAnchor) {
    final globalStart = startPixel + localAnchor;
    return List.generate(anchorLedCount, (i) => globalStart + i);
  }

  /// Check if a local pixel index is within an anchor zone
  bool isAnchorPixel(int localIndex) {
    for (final anchorStart in anchorPixels) {
      if (localIndex >= anchorStart && localIndex < anchorStart + anchorLedCount) {
        return true;
      }
    }
    return false;
  }

  /// Check if a global pixel index is within an anchor zone of this segment
  bool isGlobalAnchorPixel(int globalIndex) {
    if (globalIndex < startPixel || globalIndex > endPixel) return false;
    return isAnchorPixel(globalIndex - startPixel);
  }

  /// Get default anchor positions based on segment type
  List<int> get defaultAnchors {
    switch (type) {
      case SegmentType.run:
        // Anchors at start and end
        return [0, pixelCount - anchorLedCount];
      case SegmentType.corner:
        // Single anchor at the corner (middle of segment)
        final middle = (pixelCount - anchorLedCount) ~/ 2;
        return [middle];
      case SegmentType.peak:
        // Single anchor at the peak (middle of segment)
        final middle = (pixelCount - anchorLedCount) ~/ 2;
        return [middle];
      case SegmentType.column:
        // Anchors at top and bottom
        return [0, pixelCount - anchorLedCount];
      case SegmentType.connector:
        // No anchors by default
        return [];
    }
  }

  /// Get all anchor points including both legacy anchorPixels and new anchorPoints
  List<AnchorPoint> get effectiveAnchorPoints {
    if (anchorPoints.isNotEmpty) return anchorPoints;
    // Convert legacy anchorPixels to AnchorPoints
    return anchorPixels.map((idx) => AnchorPoint(
      ledIndex: idx,
      type: _inferAnchorType(idx),
      zoneSize: anchorLedCount,
    )).toList();
  }

  /// Infer anchor type based on position in segment
  AnchorType _inferAnchorType(int localIndex) {
    if (type == SegmentType.peak) {
      final middle = pixelCount ~/ 2;
      if ((localIndex - middle).abs() <= 2) return AnchorType.peak;
    }
    if (type == SegmentType.corner) {
      return AnchorType.corner;
    }
    if (localIndex == 0 || localIndex >= pixelCount - anchorLedCount) {
      return AnchorType.boundary;
    }
    return AnchorType.custom;
  }

  RooflineSegment copyWith({
    String? id,
    String? name,
    int? pixelCount,
    int? startPixel,
    SegmentType? type,
    List<int>? anchorPixels,
    int? anchorLedCount,
    int? sortOrder,
    SegmentDirection? direction,
    List<AnchorPoint>? anchorPoints,
    String? description,
    bool? isPrimary,
    String? symmetryPairId,
    ArchitecturalRole? architecturalRole,
    String? location,
    List<String>? adjacentSegmentIds,
    bool? isProminent,
    bool? isConnectedToPrevious,
    int? level,
  }) {
    return RooflineSegment(
      id: id ?? this.id,
      name: name ?? this.name,
      pixelCount: pixelCount ?? this.pixelCount,
      startPixel: startPixel ?? this.startPixel,
      type: type ?? this.type,
      anchorPixels: anchorPixels ?? this.anchorPixels,
      anchorLedCount: anchorLedCount ?? this.anchorLedCount,
      sortOrder: sortOrder ?? this.sortOrder,
      direction: direction ?? this.direction,
      anchorPoints: anchorPoints ?? this.anchorPoints,
      description: description ?? this.description,
      isPrimary: isPrimary ?? this.isPrimary,
      symmetryPairId: symmetryPairId ?? this.symmetryPairId,
      architecturalRole: architecturalRole ?? this.architecturalRole,
      location: location ?? this.location,
      adjacentSegmentIds: adjacentSegmentIds ?? this.adjacentSegmentIds,
      isProminent: isProminent ?? this.isProminent,
      isConnectedToPrevious: isConnectedToPrevious ?? this.isConnectedToPrevious,
      level: level ?? this.level,
    );
  }

  /// Create from JSON/Firestore data
  factory RooflineSegment.fromJson(Map<String, dynamic> json) {
    return RooflineSegment(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unnamed Segment',
      pixelCount: json['pixel_count'] as int? ?? 0,
      startPixel: json['start_pixel'] as int? ?? 0,
      type: SegmentTypeExtension.fromString(json['type'] as String? ?? 'run'),
      anchorPixels: (json['anchor_pixels'] as List<dynamic>?)?.cast<int>() ?? [],
      anchorLedCount: json['anchor_led_count'] as int? ?? 2,
      sortOrder: json['sort_order'] as int? ?? 0,
      direction: SegmentDirectionExtension.fromString(
        json['direction'] as String? ?? 'left_to_right',
      ),
      anchorPoints: (json['anchor_points'] as List<dynamic>?)
              ?.map((e) => AnchorPoint.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      description: json['description'] as String?,
      isPrimary: json['is_primary'] as bool? ?? true,
      symmetryPairId: json['symmetry_pair_id'] as String?,
      architecturalRole: json['architectural_role'] != null
          ? ArchitecturalRoleExtension.fromString(json['architectural_role'] as String)
          : null,
      location: json['location'] as String?,
      adjacentSegmentIds: (json['adjacent_segment_ids'] as List<dynamic>?)?.cast<String>() ?? [],
      isProminent: json['is_prominent'] as bool? ?? false,
      isConnectedToPrevious: json['is_connected_to_previous'] as bool? ?? true,
      level: json['level'] as int? ?? 1,
    );
  }

  /// Convert to JSON for Firestore storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'pixel_count': pixelCount,
      'start_pixel': startPixel,
      'type': type.name,
      'anchor_pixels': anchorPixels,
      'anchor_led_count': anchorLedCount,
      'sort_order': sortOrder,
      'direction': direction.name,
      'anchor_points': anchorPoints.map((e) => e.toJson()).toList(),
      if (description != null) 'description': description,
      'is_primary': isPrimary,
      if (symmetryPairId != null) 'symmetry_pair_id': symmetryPairId,
      if (architecturalRole != null) 'architectural_role': architecturalRole!.name,
      if (location != null) 'location': location,
      if (adjacentSegmentIds.isNotEmpty) 'adjacent_segment_ids': adjacentSegmentIds,
      'is_prominent': isProminent,
      'is_connected_to_previous': isConnectedToPrevious,
      'level': level,
    };
  }

  @override
  String toString() {
    return 'RooflineSegment(id: $id, name: $name, pixelCount: $pixelCount, '
        'startPixel: $startPixel, type: ${type.name}, direction: ${direction.name}, '
        'anchors: $anchorPixels, anchorLedCount: $anchorLedCount, '
        'architecturalRole: ${architecturalRole?.name}, location: $location, '
        'isConnectedToPrevious: $isConnectedToPrevious, level: $level)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RooflineSegment &&
        other.id == id &&
        other.name == name &&
        other.pixelCount == pixelCount &&
        other.startPixel == startPixel &&
        other.type == type &&
        _listEquals(other.anchorPixels, anchorPixels) &&
        other.anchorLedCount == anchorLedCount &&
        other.sortOrder == sortOrder &&
        other.direction == direction &&
        other.isPrimary == isPrimary &&
        other.isConnectedToPrevious == isConnectedToPrevious &&
        other.level == level;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      name,
      pixelCount,
      startPixel,
      type,
      Object.hashAll(anchorPixels),
      anchorLedCount,
      sortOrder,
      direction,
      isPrimary,
      isConnectedToPrevious,
      level,
    );
  }
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
