import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexgen_command/models/roofline_segment.dart';

/// Complete roofline configuration containing all segments for a user's home.
///
/// This configuration defines the physical layout of the LED roofline,
/// including segment names, pixel counts, types, and anchor points.
/// It is used by the pattern generator to create segment-aware patterns
/// like downlighting.
class RooflineConfiguration {
  /// Unique identifier for this configuration
  final String id;

  /// User-friendly name (e.g., "My Home Roofline")
  final String name;

  /// Ordered list of segments that make up the roofline
  final List<RooflineSegment> segments;

  /// When this configuration was created
  final DateTime createdAt;

  /// When this configuration was last updated
  final DateTime updatedAt;

  const RooflineConfiguration({
    required this.id,
    required this.name,
    required this.segments,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Total number of pixels across all segments
  int get totalPixelCount =>
      segments.fold(0, (sum, segment) => sum + segment.pixelCount);

  /// Total number of segments
  int get segmentCount => segments.length;

  /// Get all global anchor pixel indices across all segments, sorted
  List<int> get allGlobalAnchorPixels {
    final anchors = <int>[];
    for (final segment in segments) {
      anchors.addAll(segment.globalAnchorPixels);
    }
    anchors.sort();
    return anchors;
  }

  /// Total number of anchor points across all segments
  int get totalAnchorCount =>
      segments.fold(0, (sum, seg) => sum + seg.anchorPixels.length);

  /// Get indices of segments that are not connected to the previous segment
  /// (i.e., segments that start a new physical LED run).
  /// Note: First segment (index 0) is never included since it has no previous.
  List<int> get disconnectedSegmentIndices {
    final indices = <int>[];
    for (int i = 1; i < segments.length; i++) {
      if (!segments[i].isConnectedToPrevious) {
        indices.add(i);
      }
    }
    return indices;
  }

  /// Group segments into physically connected runs.
  /// Each inner list contains segments that are physically connected to each other.
  /// A new run starts when a segment has isConnectedToPrevious = false.
  List<List<RooflineSegment>> get connectedRuns {
    if (segments.isEmpty) return [];

    final runs = <List<RooflineSegment>>[];
    var currentRun = <RooflineSegment>[segments.first];

    for (int i = 1; i < segments.length; i++) {
      if (segments[i].isConnectedToPrevious) {
        currentRun.add(segments[i]);
      } else {
        runs.add(currentRun);
        currentRun = [segments[i]];
      }
    }
    runs.add(currentRun);

    return runs;
  }

  /// Get all segments on a specific level/story.
  List<RooflineSegment> segmentsOnLevel(int level) {
    return segments.where((s) => s.level == level).toList();
  }

  /// Get all unique levels/stories in this configuration, sorted.
  List<int> get allLevels {
    final levels = segments.map((s) => s.level).toSet().toList();
    levels.sort();
    return levels;
  }

  /// Find the segment containing a given global pixel index.
  /// Returns null if the pixel is out of range.
  RooflineSegment? segmentForPixel(int globalPixel) {
    for (final segment in segments) {
      if (globalPixel >= segment.startPixel && globalPixel <= segment.endPixel) {
        return segment;
      }
    }
    return null;
  }

  /// Get the segment at a specific index
  RooflineSegment? segmentAtIndex(int index) {
    if (index < 0 || index >= segments.length) return null;
    return segments[index];
  }

  /// Find a segment by its ID
  RooflineSegment? segmentById(String segmentId) {
    try {
      return segments.firstWhere((s) => s.id == segmentId);
    } catch (_) {
      return null;
    }
  }

  /// Check if a global pixel index is an anchor pixel in any segment
  bool isAnchorPixel(int globalPixel) {
    final segment = segmentForPixel(globalPixel);
    if (segment == null) return false;
    return segment.isGlobalAnchorPixel(globalPixel);
  }

  /// Validate that the total pixel count matches the expected device count.
  /// Returns true if they match, false otherwise.
  bool validateAgainstDevice(int devicePixelCount) {
    return totalPixelCount == devicePixelCount;
  }

  /// Recalculate start pixels for all segments based on their order.
  /// Returns a new configuration with updated start pixels.
  RooflineConfiguration recalculateStartPixels() {
    int currentStart = 0;
    final updatedSegments = <RooflineSegment>[];

    for (int i = 0; i < segments.length; i++) {
      final segment = segments[i];
      updatedSegments.add(segment.copyWith(
        startPixel: currentStart,
        sortOrder: i,
      ));
      currentStart += segment.pixelCount;
    }

    return copyWith(
      segments: updatedSegments,
      updatedAt: DateTime.now(),
    );
  }

  /// Add a new segment and recalculate start pixels
  RooflineConfiguration addSegment(RooflineSegment segment) {
    final newSegments = [...segments, segment];
    return copyWith(segments: newSegments).recalculateStartPixels();
  }

  /// Update a segment by ID and recalculate start pixels
  RooflineConfiguration updateSegment(String segmentId, RooflineSegment updated) {
    final newSegments = segments.map((s) {
      return s.id == segmentId ? updated : s;
    }).toList();
    return copyWith(segments: newSegments).recalculateStartPixels();
  }

  /// Remove a segment by ID and recalculate start pixels
  RooflineConfiguration removeSegment(String segmentId) {
    final newSegments = segments.where((s) => s.id != segmentId).toList();
    return copyWith(segments: newSegments).recalculateStartPixels();
  }

  /// Reorder segments (move from oldIndex to newIndex) and recalculate start pixels
  RooflineConfiguration reorderSegments(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= segments.length) return this;
    if (newIndex < 0 || newIndex >= segments.length) return this;
    if (oldIndex == newIndex) return this;

    final newSegments = List<RooflineSegment>.from(segments);
    final segment = newSegments.removeAt(oldIndex);
    newSegments.insert(newIndex, segment);

    return copyWith(segments: newSegments).recalculateStartPixels();
  }

  RooflineConfiguration copyWith({
    String? id,
    String? name,
    List<RooflineSegment>? segments,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return RooflineConfiguration(
      id: id ?? this.id,
      name: name ?? this.name,
      segments: segments ?? this.segments,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  /// Create an empty configuration for a new user
  factory RooflineConfiguration.empty() {
    final now = DateTime.now();
    return RooflineConfiguration(
      id: '',
      name: 'My Roofline',
      segments: [],
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Create from Firestore document
  factory RooflineConfiguration.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return RooflineConfiguration.fromJson(doc.id, data);
  }

  /// Create from JSON/Firestore data with explicit ID
  factory RooflineConfiguration.fromJson(String id, Map<String, dynamic> json) {
    return RooflineConfiguration(
      id: id,
      name: json['name'] as String? ?? 'My Roofline',
      segments: (json['segments'] as List<dynamic>?)
              ?.map((s) => RooflineSegment.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: (json['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (json['updated_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// Convert to JSON for Firestore storage
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'segments': segments.map((s) => s.toJson()).toList(),
      'created_at': Timestamp.fromDate(createdAt),
      'updated_at': Timestamp.fromDate(updatedAt),
    };
  }

  @override
  String toString() {
    return 'RooflineConfiguration(id: $id, name: $name, '
        'segmentCount: ${segments.length}, totalPixels: $totalPixelCount)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RooflineConfiguration &&
        other.id == id &&
        other.name == name &&
        _segmentListEquals(other.segments, segments);
  }

  @override
  int get hashCode => Object.hash(id, name, Object.hashAll(segments));
}

bool _segmentListEquals(List<RooflineSegment> a, List<RooflineSegment> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Example configuration matching the user's roofline (166 pixels, 9 segments)
RooflineConfiguration createExampleConfiguration() {
  final now = DateTime.now();
  return RooflineConfiguration(
    id: 'example_config',
    name: 'My Home Roofline',
    segments: [
      const RooflineSegment(
        id: 'seg_1',
        name: '3rd Car Garage',
        pixelCount: 20,
        startPixel: 0,
        type: SegmentType.run,
        anchorPixels: [0, 18],
        anchorLedCount: 2,
        sortOrder: 0,
      ),
      const RooflineSegment(
        id: 'seg_2',
        name: 'Garage Side',
        pixelCount: 8,
        startPixel: 20,
        type: SegmentType.corner,
        anchorPixels: [0, 6],
        anchorLedCount: 2,
        sortOrder: 1,
      ),
      const RooflineSegment(
        id: 'seg_3',
        name: 'Garage Peak',
        pixelCount: 14,
        startPixel: 28,
        type: SegmentType.peak,
        anchorPixels: [0, 6, 12],
        anchorLedCount: 2,
        sortOrder: 2,
      ),
      const RooflineSegment(
        id: 'seg_4',
        name: 'Connector',
        pixelCount: 11,
        startPixel: 42,
        type: SegmentType.connector,
        anchorPixels: [0, 9],
        anchorLedCount: 2,
        sortOrder: 3,
      ),
      const RooflineSegment(
        id: 'seg_5',
        name: 'Front of Home',
        pixelCount: 47,
        startPixel: 53,
        type: SegmentType.run,
        anchorPixels: [0, 45],
        anchorLedCount: 2,
        sortOrder: 4,
      ),
      const RooflineSegment(
        id: 'seg_6',
        name: 'Front Peak',
        pixelCount: 24,
        startPixel: 100,
        type: SegmentType.peak,
        anchorPixels: [0, 11, 22],
        anchorLedCount: 2,
        sortOrder: 5,
      ),
      const RooflineSegment(
        id: 'seg_7',
        name: 'Front Porch',
        pixelCount: 10,
        startPixel: 124,
        type: SegmentType.run,
        anchorPixels: [0, 8],
        anchorLedCount: 2,
        sortOrder: 6,
      ),
      const RooflineSegment(
        id: 'seg_8',
        name: 'Column 1',
        pixelCount: 16,
        startPixel: 134,
        type: SegmentType.column,
        anchorPixels: [0, 14],
        anchorLedCount: 2,
        sortOrder: 7,
      ),
      const RooflineSegment(
        id: 'seg_9',
        name: 'Column 2',
        pixelCount: 16,
        startPixel: 150,
        type: SegmentType.column,
        anchorPixels: [0, 14],
        anchorLedCount: 2,
        sortOrder: 8,
      ),
    ],
    createdAt: now,
    updatedAt: now,
  );
}
