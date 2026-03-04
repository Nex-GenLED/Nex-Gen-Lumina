import 'sport_type.dart';

/// Types of scoring or significant game events that trigger LED alerts.
enum AlertEventType {
  // NFL
  touchdown,
  fieldGoal,
  safety,

  // NHL / MLS / shared
  goal,

  // MLB
  run,

  // Period/quarter boundaries
  quarterEndWinning,

  // NBA
  clutchBasket,

  // Phase 2
  turnover;

  factory AlertEventType.fromJson(String json) =>
      AlertEventType.values.firstWhere((e) => e.name == json);

  String toJson() => name;
}

/// A discrete scoring event detected by the polling service.
class ScoreAlertEvent {
  final String teamSlug;
  final SportType sport;
  final AlertEventType eventType;
  final int pointsScored;
  final String gameId;
  final DateTime timestamp;

  const ScoreAlertEvent({
    required this.teamSlug,
    required this.sport,
    required this.eventType,
    required this.pointsScored,
    required this.gameId,
    required this.timestamp,
  });

  ScoreAlertEvent copyWith({
    String? teamSlug,
    SportType? sport,
    AlertEventType? eventType,
    int? pointsScored,
    String? gameId,
    DateTime? timestamp,
  }) {
    return ScoreAlertEvent(
      teamSlug: teamSlug ?? this.teamSlug,
      sport: sport ?? this.sport,
      eventType: eventType ?? this.eventType,
      pointsScored: pointsScored ?? this.pointsScored,
      gameId: gameId ?? this.gameId,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  factory ScoreAlertEvent.fromJson(Map<String, dynamic> json) {
    return ScoreAlertEvent(
      teamSlug: json['teamSlug'] as String,
      sport: SportType.fromJson(json['sport'] as String),
      eventType: AlertEventType.fromJson(json['eventType'] as String),
      pointsScored: json['pointsScored'] as int,
      gameId: json['gameId'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'teamSlug': teamSlug,
        'sport': sport.toJson(),
        'eventType': eventType.toJson(),
        'pointsScored': pointsScored,
        'gameId': gameId,
        'timestamp': timestamp.toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScoreAlertEvent &&
          runtimeType == other.runtimeType &&
          teamSlug == other.teamSlug &&
          eventType == other.eventType &&
          gameId == other.gameId &&
          timestamp == other.timestamp;

  @override
  int get hashCode => Object.hash(teamSlug, eventType, gameId, timestamp);

  @override
  String toString() =>
      'ScoreAlertEvent(teamSlug: $teamSlug, eventType: $eventType, '
      'pointsScored: $pointsScored, gameId: $gameId)';
}
