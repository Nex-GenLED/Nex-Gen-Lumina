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

  const RooflineSegment({
    required this.id,
    required this.name,
    required this.pixelCount,
    this.startPixel = 0,
    this.type = SegmentType.run,
    this.anchorPixels = const [],
    this.anchorLedCount = 2,
    this.sortOrder = 0,
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

  RooflineSegment copyWith({
    String? id,
    String? name,
    int? pixelCount,
    int? startPixel,
    SegmentType? type,
    List<int>? anchorPixels,
    int? anchorLedCount,
    int? sortOrder,
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
    };
  }

  @override
  String toString() {
    return 'RooflineSegment(id: $id, name: $name, pixelCount: $pixelCount, '
        'startPixel: $startPixel, type: ${type.name}, '
        'anchors: $anchorPixels, anchorLedCount: $anchorLedCount)';
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
        other.sortOrder == sortOrder;
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
