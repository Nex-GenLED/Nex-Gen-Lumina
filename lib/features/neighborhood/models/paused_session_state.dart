import 'package:cloud_firestore/cloud_firestore.dart';
import 'sync_event.dart';

/// Preserved state of a longForm session that has been paused by a shortForm
/// event taking temporary priority.
///
/// Stored per-user so that when the shortForm event ends, the longForm
/// session can resume with the correct pattern, skipping any scheduled
/// effects whose time has already passed.
class PausedSessionState {
  /// The group ID of the paused longForm session.
  final String groupId;

  /// The session ID being paused.
  final String sessionId;

  /// The sync event ID that was running.
  final String syncEventId;

  /// The pattern that was active when paused.
  final PatternRef currentPattern;

  /// When the longForm session originally started.
  final DateTime sessionStartTime;

  /// When this session was paused.
  final DateTime pausedAt;

  /// Any upcoming scheduled effects in the longForm session's schedule
  /// (e.g. a midnight color change). Stored as JSON-serializable maps.
  final List<ScheduledEffect> scheduledEffects;

  /// Whether the longForm session's host was still online when we paused.
  final bool hostIsActive;

  /// The shortForm group ID that caused the pause.
  final String pausedByGroupId;

  /// The shortForm session ID that caused the pause.
  final String pausedBySessionId;

  const PausedSessionState({
    required this.groupId,
    required this.sessionId,
    required this.syncEventId,
    required this.currentPattern,
    required this.sessionStartTime,
    required this.pausedAt,
    this.scheduledEffects = const [],
    this.hostIsActive = true,
    required this.pausedByGroupId,
    required this.pausedBySessionId,
  });

  /// Check if the longForm host is still reachable for resumption.
  bool get canResumeFromHost => hostIsActive;

  /// Filter out scheduled effects whose time has already passed.
  List<ScheduledEffect> get pendingEffects {
    final now = DateTime.now();
    return scheduledEffects
        .where((e) => e.scheduledTime.isAfter(now))
        .toList();
  }

  Map<String, dynamic> toJson() => {
        'groupId': groupId,
        'sessionId': sessionId,
        'syncEventId': syncEventId,
        'currentPattern': currentPattern.toJson(),
        'sessionStartTime': Timestamp.fromDate(sessionStartTime),
        'pausedAt': Timestamp.fromDate(pausedAt),
        'scheduledEffects': scheduledEffects.map((e) => e.toJson()).toList(),
        'hostIsActive': hostIsActive,
        'pausedByGroupId': pausedByGroupId,
        'pausedBySessionId': pausedBySessionId,
      };

  factory PausedSessionState.fromJson(Map<String, dynamic> json) {
    return PausedSessionState(
      groupId: json['groupId'] ?? '',
      sessionId: json['sessionId'] ?? '',
      syncEventId: json['syncEventId'] ?? '',
      currentPattern: PatternRef.fromJson(
        (json['currentPattern'] as Map<String, dynamic>?) ?? {},
      ),
      sessionStartTime:
          (json['sessionStartTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
      pausedAt: (json['pausedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      scheduledEffects: (json['scheduledEffects'] as List<dynamic>?)
              ?.map((e) =>
                  ScheduledEffect.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      hostIsActive: json['hostIsActive'] ?? true,
      pausedByGroupId: json['pausedByGroupId'] ?? '',
      pausedBySessionId: json['pausedBySessionId'] ?? '',
    );
  }

  PausedSessionState copyWith({
    String? groupId,
    String? sessionId,
    String? syncEventId,
    PatternRef? currentPattern,
    DateTime? sessionStartTime,
    DateTime? pausedAt,
    List<ScheduledEffect>? scheduledEffects,
    bool? hostIsActive,
    String? pausedByGroupId,
    String? pausedBySessionId,
  }) {
    return PausedSessionState(
      groupId: groupId ?? this.groupId,
      sessionId: sessionId ?? this.sessionId,
      syncEventId: syncEventId ?? this.syncEventId,
      currentPattern: currentPattern ?? this.currentPattern,
      sessionStartTime: sessionStartTime ?? this.sessionStartTime,
      pausedAt: pausedAt ?? this.pausedAt,
      scheduledEffects: scheduledEffects ?? this.scheduledEffects,
      hostIsActive: hostIsActive ?? this.hostIsActive,
      pausedByGroupId: pausedByGroupId ?? this.pausedByGroupId,
      pausedBySessionId: pausedBySessionId ?? this.pausedBySessionId,
    );
  }
}

/// A scheduled effect within a longForm session (e.g. midnight color change).
class ScheduledEffect {
  final String id;
  final DateTime scheduledTime;
  final PatternRef pattern;
  final String description;

  const ScheduledEffect({
    required this.id,
    required this.scheduledTime,
    required this.pattern,
    this.description = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'scheduledTime': Timestamp.fromDate(scheduledTime),
        'pattern': pattern.toJson(),
        'description': description,
      };

  factory ScheduledEffect.fromJson(Map<String, dynamic> json) {
    return ScheduledEffect(
      id: json['id'] ?? '',
      scheduledTime:
          (json['scheduledTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
      pattern: PatternRef.fromJson(
        (json['pattern'] as Map<String, dynamic>?) ?? {},
      ),
      description: json['description'] ?? '',
    );
  }
}
