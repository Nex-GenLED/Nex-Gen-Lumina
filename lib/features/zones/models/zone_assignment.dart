import 'fixture_type.dart';

class ZoneAssignment {
  final int segmentId;
  final FixtureType fixtureType;
  final String locationLabel;
  final DateTime assignedAt;

  const ZoneAssignment({
    required this.segmentId,
    required this.fixtureType,
    required this.locationLabel,
    required this.assignedAt,
  });

  ZoneAssignment copyWith({
    int? segmentId,
    FixtureType? fixtureType,
    String? locationLabel,
    DateTime? assignedAt,
  }) {
    return ZoneAssignment(
      segmentId: segmentId ?? this.segmentId,
      fixtureType: fixtureType ?? this.fixtureType,
      locationLabel: locationLabel ?? this.locationLabel,
      assignedAt: assignedAt ?? this.assignedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'segmentId': segmentId,
      'fixtureType': fixtureType.name,
      'locationLabel': locationLabel,
      'assignedAt': assignedAt.toIso8601String(),
    };
  }

  factory ZoneAssignment.fromJson(Map<String, dynamic> json) {
    return ZoneAssignment(
      segmentId: json['segmentId'] as int,
      fixtureType: FixtureType.values.byName(json['fixtureType'] as String),
      locationLabel: json['locationLabel'] as String,
      assignedAt: DateTime.parse(json['assignedAt'] as String),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ZoneAssignment &&
          runtimeType == other.runtimeType &&
          segmentId == other.segmentId;

  @override
  int get hashCode => segmentId.hashCode;
}
