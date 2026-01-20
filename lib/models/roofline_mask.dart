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

  const RooflineMask({
    this.points = const [],
    this.maskHeight = 0.25,
    this.isManuallyDrawn = false,
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
    );
  }

  /// Convert to JSON for Firestore storage
  Map<String, dynamic> toJson() {
    return {
      'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
      'mask_height': maskHeight,
      'is_manually_drawn': isManuallyDrawn,
    };
  }

  /// Create a copy with modified values
  RooflineMask copyWith({
    List<Offset>? points,
    double? maskHeight,
    bool? isManuallyDrawn,
  }) {
    return RooflineMask(
      points: points ?? this.points,
      maskHeight: maskHeight ?? this.maskHeight,
      isManuallyDrawn: isManuallyDrawn ?? this.isManuallyDrawn,
    );
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
        _listEquals(points, other.points);
  }

  @override
  int get hashCode => Object.hash(
        maskHeight,
        isManuallyDrawn,
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
