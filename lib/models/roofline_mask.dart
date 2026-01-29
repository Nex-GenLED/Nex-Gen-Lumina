import 'dart:ui';

/// Model representing the roofline mask for AR preview overlay.
///
/// The roofline can be defined either:
/// 1. As a percentage from the top (maskHeight) - simple top-edge overlay
/// 2. As custom points drawn by the user - precise roofline tracing
class RooflineMask {
  /// Normalized coordinates (0-1) defining the roofline path.
  /// If empty, the maskHeight percentage is used instead.
  final List<Offset> points;

  /// Default mask height as percentage from top (0.0-1.0).
  /// 0.25 means the top 25% of the image will have the light overlay.
  final double maskHeight;

  /// Whether the user manually drew this roofline.
  /// If false, the default top-edge mask is used.
  final bool isManuallyDrawn;

  /// The aspect ratio (width/height) of the source image when roofline was drawn.
  /// Used to correctly transform points when displaying with different BoxFit modes.
  final double? sourceAspectRatio;

  const RooflineMask({
    this.points = const [],
    this.maskHeight = 0.25,
    this.isManuallyDrawn = false,
    this.sourceAspectRatio,
  });

  /// Create from JSON stored in Firestore
  factory RooflineMask.fromJson(Map<String, dynamic> json) {
    final pointsList = json['points'] as List<dynamic>?;
    final points = pointsList?.map((p) {
      if (p is Map<String, dynamic>) {
        return Offset(
          (p['x'] as num?)?.toDouble() ?? 0.0,
          (p['y'] as num?)?.toDouble() ?? 0.0,
        );
      }
      return Offset.zero;
    }).toList() ?? const [];

    return RooflineMask(
      points: points,
      maskHeight: (json['mask_height'] as num?)?.toDouble() ?? 0.25,
      isManuallyDrawn: (json['is_manually_drawn'] as bool?) ?? false,
      sourceAspectRatio: (json['source_aspect_ratio'] as num?)?.toDouble(),
    );
  }

  /// Convert to JSON for Firestore storage
  Map<String, dynamic> toJson() {
    return {
      'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
      'mask_height': maskHeight,
      'is_manually_drawn': isManuallyDrawn,
      if (sourceAspectRatio != null) 'source_aspect_ratio': sourceAspectRatio,
    };
  }

  /// Create a copy with modified values
  RooflineMask copyWith({
    List<Offset>? points,
    double? maskHeight,
    bool? isManuallyDrawn,
    double? sourceAspectRatio,
  }) {
    return RooflineMask(
      points: points ?? this.points,
      maskHeight: maskHeight ?? this.maskHeight,
      isManuallyDrawn: isManuallyDrawn ?? this.isManuallyDrawn,
      sourceAspectRatio: sourceAspectRatio ?? this.sourceAspectRatio,
    );
  }

  /// Transform the roofline points for display with BoxFit.cover.
  ///
  /// When an image is displayed with BoxFit.cover, it's cropped to fill the container.
  /// This method transforms the normalized roofline points so they correctly align
  /// with the visible portion of the cropped image.
  ///
  /// [targetAspectRatio] - the aspect ratio (width/height) of the display container.
  /// [alignment] - the alignment used for the image (default center).
  List<Offset> getPointsForCover({
    required double targetAspectRatio,
    Offset alignment = Offset.zero,
  }) {
    // If no source aspect ratio stored, or points are empty, return as-is
    if (sourceAspectRatio == null || points.isEmpty) {
      return points;
    }

    final srcAspect = sourceAspectRatio!;

    // Calculate how the image is cropped with BoxFit.cover
    // If srcAspect > targetAspect: image is cropped horizontally (left/right cut off)
    // If srcAspect < targetAspect: image is cropped vertically (top/bottom cut off)

    double scaleX = 1.0;
    double scaleY = 1.0;
    double offsetX = 0.0;
    double offsetY = 0.0;

    if (srcAspect > targetAspectRatio) {
      // Image is wider than container - horizontal crop
      // The visible width is a fraction of the full image width
      final visibleFraction = targetAspectRatio / srcAspect;
      scaleX = 1.0 / visibleFraction;
      // Center alignment means we crop equally from both sides
      // alignment.dx ranges from -1 (left) to 1 (right), with 0 being center
      offsetX = (1.0 - visibleFraction) * (0.5 + alignment.dx * 0.5);
    } else if (srcAspect < targetAspectRatio) {
      // Image is taller than container - vertical crop
      final visibleFraction = srcAspect / targetAspectRatio;
      scaleY = 1.0 / visibleFraction;
      // alignment.dy ranges from -1 (top) to 1 (bottom)
      offsetY = (1.0 - visibleFraction) * (0.5 + alignment.dy * 0.5);
    }

    // Transform each point
    return points.map((p) {
      // Adjust for the cropping offset and scale
      final newX = (p.dx - offsetX) * scaleX;
      final newY = (p.dy - offsetY) * scaleY;
      return Offset(newX.clamp(0.0, 1.0), newY.clamp(0.0, 1.0));
    }).toList();
  }

  /// Whether this mask has custom user-drawn points
  bool get hasCustomPoints => points.isNotEmpty && isManuallyDrawn;

  /// Default mask for new users - top 25% of image
  static const RooflineMask defaultMask = RooflineMask(
    maskHeight: 0.25,
    isManuallyDrawn: false,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RooflineMask) return false;
    return maskHeight == other.maskHeight &&
        isManuallyDrawn == other.isManuallyDrawn &&
        sourceAspectRatio == other.sourceAspectRatio &&
        _listEquals(points, other.points);
  }

  @override
  int get hashCode => Object.hash(
        maskHeight,
        isManuallyDrawn,
        sourceAspectRatio,
        Object.hashAll(points),
      );

  static bool _listEquals(List<Offset> a, List<Offset> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
