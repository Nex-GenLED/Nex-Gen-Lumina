import 'sport_type.dart';

/// How sensitive the alert system is to scoring events.
enum AlertSensitivity {
  /// Flash on every scoring event.
  allEvents,

  /// Flash only on major scoring plays (touchdowns, goals, etc.).
  majorOnly,

  /// Flash only during clutch / end-of-game moments.
  clutchOnly;

  factory AlertSensitivity.fromJson(String json) =>
      AlertSensitivity.values.firstWhere((e) => e.name == json);

  String toJson() => name;
}

/// Persistent configuration for a single team's score-alert subscription.
class ScoreAlertConfig {
  final String id;
  final String teamSlug;
  final SportType sport;
  final bool isEnabled;
  final List<String> assignedZoneIds;
  final AlertSensitivity sensitivity;
  final DateTime? createdAt;

  /// The team's chosen celebration effect, carried from the Game Day config.
  ///
  /// IN-MEMORY ONLY — deliberately absent from [fromJson]. That factory exists
  /// solely to drain the retired prefs store during migration, and the retired
  /// store predates celebrations, so there is nothing there to read.
  /// [monitoringConfigFor] is what populates these, exactly as it already does
  /// for [sensitivity].
  ///
  /// `null` = the user has chosen nothing; the legacy hardcoded per-event
  /// sequences fire verbatim.
  final int? celebrationEffectId;
  final int celebrationSpeed;
  final int celebrationIntensity;

  const ScoreAlertConfig({
    required this.id,
    required this.teamSlug,
    required this.sport,
    this.isEnabled = true,
    this.assignedZoneIds = const [],
    this.sensitivity = AlertSensitivity.allEvents,
    this.createdAt,
    this.celebrationEffectId,
    this.celebrationSpeed = 240,
    this.celebrationIntensity = 240,
  });

  ScoreAlertConfig copyWith({
    String? id,
    String? teamSlug,
    SportType? sport,
    bool? isEnabled,
    List<String>? assignedZoneIds,
    AlertSensitivity? sensitivity,
    DateTime? createdAt,
    int? celebrationEffectId,
    int? celebrationSpeed,
    int? celebrationIntensity,
  }) {
    return ScoreAlertConfig(
      id: id ?? this.id,
      teamSlug: teamSlug ?? this.teamSlug,
      sport: sport ?? this.sport,
      isEnabled: isEnabled ?? this.isEnabled,
      assignedZoneIds: assignedZoneIds ?? this.assignedZoneIds,
      sensitivity: sensitivity ?? this.sensitivity,
      createdAt: createdAt ?? this.createdAt,
      celebrationEffectId: celebrationEffectId ?? this.celebrationEffectId,
      celebrationSpeed: celebrationSpeed ?? this.celebrationSpeed,
      celebrationIntensity: celebrationIntensity ?? this.celebrationIntensity,
    );
  }

  factory ScoreAlertConfig.fromJson(Map<String, dynamic> json) {
    return ScoreAlertConfig(
      id: json['id'] as String,
      teamSlug: json['teamSlug'] as String,
      sport: SportType.fromJson(json['sport'] as String),
      isEnabled: json['isEnabled'] as bool? ?? true,
      assignedZoneIds: (json['assignedZoneIds'] as List<dynamic>?)
              ?.cast<String>() ??
          const [],
      sensitivity: json['sensitivity'] != null
          ? AlertSensitivity.fromJson(json['sensitivity'] as String)
          : AlertSensitivity.allEvents,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
    );
  }

  // NOTE: no `toJson`. This type is no longer PERSISTED anywhere — it is an
  // in-memory value passed to AlertTriggerService.handleAlertEvent, and is what
  // resolveMonitoring/monitoringConfigFor return. Its only remaining serialized
  // form is INBOUND: [fromJson] drains the retired `sports_alert_configs` prefs
  // store during migration. Adding a writer back would recreate the disjoint
  // store this consolidation removed
  // (audit/SPORTS_ALERTS_SYNC_AUDIT.md §4.1-4.3).

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScoreAlertConfig &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          teamSlug == other.teamSlug &&
          sport == other.sport &&
          isEnabled == other.isEnabled &&
          sensitivity == other.sensitivity;

  @override
  int get hashCode => Object.hash(id, teamSlug, sport, isEnabled, sensitivity);

  @override
  String toString() =>
      'ScoreAlertConfig(id: $id, teamSlug: $teamSlug, sport: $sport, '
      'isEnabled: $isEnabled, sensitivity: $sensitivity)';
}
