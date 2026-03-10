import 'package:cloud_firestore/cloud_firestore.dart';
import '../neighborhood_models.dart';

/// How an Autopilot Sync Event is triggered.
enum SyncEventTriggerType {
  scheduledTime,
  gameStart,
  manual,
}

extension SyncEventTriggerTypeX on SyncEventTriggerType {
  String get displayName {
    switch (this) {
      case SyncEventTriggerType.scheduledTime:
        return 'Scheduled Time';
      case SyncEventTriggerType.gameStart:
        return 'Game Start';
      case SyncEventTriggerType.manual:
        return 'Manual';
    }
  }

  String toJson() => name;

  static SyncEventTriggerType fromJson(String? value) {
    if (value == null) return SyncEventTriggerType.scheduledTime;
    return SyncEventTriggerType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => SyncEventTriggerType.scheduledTime,
    );
  }
}

/// What happens when a sync event ends.
enum PostEventBehavior {
  returnToAutopilot,
  stayOn,
  turnOff,
}

extension PostEventBehaviorX on PostEventBehavior {
  String get displayName {
    switch (this) {
      case PostEventBehavior.returnToAutopilot:
        return 'Return to Autopilot';
      case PostEventBehavior.stayOn:
        return 'Stay On';
      case PostEventBehavior.turnOff:
        return 'Turn Off';
    }
  }

  String toJson() => name;

  static PostEventBehavior fromJson(String? value) {
    if (value == null) return PostEventBehavior.returnToAutopilot;
    return PostEventBehavior.values.firstWhere(
      (e) => e.name == value,
      orElse: () => PostEventBehavior.returnToAutopilot,
    );
  }
}

/// Participation consent categories a member can opt into.
enum SyncEventCategory {
  gameDay,
  holiday,
  customEvent,
}

extension SyncEventCategoryX on SyncEventCategory {
  String get displayName {
    switch (this) {
      case SyncEventCategory.gameDay:
        return 'Game Day Syncs';
      case SyncEventCategory.holiday:
        return 'Holiday Syncs';
      case SyncEventCategory.customEvent:
        return 'Custom Event Syncs';
    }
  }

  String toJson() => name;

  static SyncEventCategory fromJson(String? value) {
    if (value == null) return SyncEventCategory.gameDay;
    return SyncEventCategory.values.firstWhere(
      (e) => e.name == value,
      orElse: () => SyncEventCategory.gameDay,
    );
  }
}

/// The lifecycle status of a sync event session.
enum SyncEventSessionStatus {
  pending,
  waitingForGameStart,
  active,
  ending,
  completed,
  cancelled,
}

extension SyncEventSessionStatusX on SyncEventSessionStatus {
  String toJson() => name;

  static SyncEventSessionStatus fromJson(String? value) {
    if (value == null) return SyncEventSessionStatus.pending;
    return SyncEventSessionStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => SyncEventSessionStatus.pending,
    );
  }
}

/// A reference to a lighting pattern (effect + colors + params).
class PatternRef {
  final String name;
  final int effectId;
  final List<int> colors;
  final int speed;
  final int intensity;
  final int brightness;

  const PatternRef({
    required this.name,
    this.effectId = 0,
    this.colors = const [0xFFFFFF],
    this.speed = 128,
    this.intensity = 128,
    this.brightness = 200,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'effectId': effectId,
        'colors': colors,
        'speed': speed,
        'intensity': intensity,
        'brightness': brightness,
      };

  factory PatternRef.fromJson(Map<String, dynamic> json) {
    return PatternRef(
      name: json['name'] ?? 'Unknown',
      effectId: json['effectId'] ?? 0,
      colors: List<int>.from(json['colors'] ?? [0xFFFFFF]),
      speed: json['speed'] ?? 128,
      intensity: json['intensity'] ?? 128,
      brightness: json['brightness'] ?? 200,
    );
  }

  /// Convert to a SyncPatternAssignment for broadcast.
  SyncPatternAssignment toSyncAssignment() => SyncPatternAssignment(
        name: name,
        effectId: effectId,
        colors: colors,
        speed: speed,
        intensity: intensity,
        brightness: brightness,
      );

  PatternRef copyWith({
    String? name,
    int? effectId,
    List<int>? colors,
    int? speed,
    int? intensity,
    int? brightness,
  }) {
    return PatternRef(
      name: name ?? this.name,
      effectId: effectId ?? this.effectId,
      colors: colors ?? this.colors,
      speed: speed ?? this.speed,
      intensity: intensity ?? this.intensity,
      brightness: brightness ?? this.brightness,
    );
  }
}

/// An Autopilot-scheduled Neighborhood Sync session.
///
/// Distinct from a standard schedule entry — this represents a coordinated
/// multi-home event triggered by Autopilot.
class SyncEvent {
  final String id;
  final String name;
  final String syncGroupId;
  final SyncEventTriggerType triggerType;
  final String? sportLeague;
  final String? teamId;
  final PatternRef basePattern;
  final PatternRef celebrationPattern;
  final int celebrationDurationSeconds;
  final PostEventBehavior postEventBehavior;
  final Map<String, PatternRef> participantOverrides;
  final DateTime? scheduledTime;
  final List<int> repeatDays; // 1=Mon..7=Sun, empty = one-time
  final String createdBy;
  final DateTime createdAt;
  final bool isEnabled;
  final String? espnTeamId;
  final SyncEventCategory category;

  // ── Season Schedule Fields ──────────────────────────────────────────
  /// Whether this event covers "every home game this season".
  final bool isSeasonSchedule;

  /// The season year (e.g. 2025 for the 2025-26 NFL season).
  final int? seasonYear;

  /// Game IDs the user has excluded from the season schedule.
  /// These games will be skipped when the sync event fires.
  final List<String> excludedGameIds;

  /// The last time the season schedule was reconciled with ESPN.
  final DateTime? lastScheduleReconciliation;

  const SyncEvent({
    required this.id,
    required this.name,
    required this.syncGroupId,
    this.triggerType = SyncEventTriggerType.scheduledTime,
    this.sportLeague,
    this.teamId,
    required this.basePattern,
    required this.celebrationPattern,
    this.celebrationDurationSeconds = 15,
    this.postEventBehavior = PostEventBehavior.returnToAutopilot,
    this.participantOverrides = const {},
    this.scheduledTime,
    this.repeatDays = const [],
    required this.createdBy,
    required this.createdAt,
    this.isEnabled = true,
    this.espnTeamId,
    this.category = SyncEventCategory.gameDay,
    this.isSeasonSchedule = false,
    this.seasonYear,
    this.excludedGameIds = const [],
    this.lastScheduleReconciliation,
  });

  bool get isGameDay =>
      triggerType == SyncEventTriggerType.gameStart &&
      teamId != null &&
      sportLeague != null;

  bool get isRecurring => repeatDays.isNotEmpty;

  factory SyncEvent.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SyncEvent(
      id: doc.id,
      name: data['name'] ?? '',
      syncGroupId: data['syncGroupId'] ?? '',
      triggerType: SyncEventTriggerTypeX.fromJson(data['triggerType']),
      sportLeague: data['sportLeague'],
      teamId: data['teamId'],
      basePattern: PatternRef.fromJson(
        (data['basePattern'] as Map<String, dynamic>?) ?? {},
      ),
      celebrationPattern: PatternRef.fromJson(
        (data['celebrationPattern'] as Map<String, dynamic>?) ?? {},
      ),
      celebrationDurationSeconds: data['celebrationDurationSeconds'] ?? 15,
      postEventBehavior:
          PostEventBehaviorX.fromJson(data['postEventBehavior']),
      participantOverrides: _parseOverrides(data['participantOverrides']),
      scheduledTime: (data['scheduledTime'] as Timestamp?)?.toDate(),
      repeatDays: List<int>.from(data['repeatDays'] ?? []),
      createdBy: data['createdBy'] ?? '',
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isEnabled: data['isEnabled'] ?? true,
      espnTeamId: data['espnTeamId'],
      category: SyncEventCategoryX.fromJson(data['category']),
      isSeasonSchedule: data['isSeasonSchedule'] ?? false,
      seasonYear: data['seasonYear'],
      excludedGameIds: List<String>.from(data['excludedGameIds'] ?? []),
      lastScheduleReconciliation:
          (data['lastScheduleReconciliation'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'syncGroupId': syncGroupId,
      'triggerType': triggerType.toJson(),
      'sportLeague': sportLeague,
      'teamId': teamId,
      'basePattern': basePattern.toJson(),
      'celebrationPattern': celebrationPattern.toJson(),
      'celebrationDurationSeconds': celebrationDurationSeconds,
      'postEventBehavior': postEventBehavior.toJson(),
      'participantOverrides': participantOverrides.map(
        (k, v) => MapEntry(k, v.toJson()),
      ),
      'scheduledTime':
          scheduledTime != null ? Timestamp.fromDate(scheduledTime!) : null,
      'repeatDays': repeatDays,
      'createdBy': createdBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'isEnabled': isEnabled,
      'espnTeamId': espnTeamId,
      'category': category.toJson(),
      'isSeasonSchedule': isSeasonSchedule,
      'seasonYear': seasonYear,
      'excludedGameIds': excludedGameIds,
      'lastScheduleReconciliation': lastScheduleReconciliation != null
          ? Timestamp.fromDate(lastScheduleReconciliation!)
          : null,
    };
  }

  SyncEvent copyWith({
    String? id,
    String? name,
    String? syncGroupId,
    SyncEventTriggerType? triggerType,
    String? sportLeague,
    String? teamId,
    PatternRef? basePattern,
    PatternRef? celebrationPattern,
    int? celebrationDurationSeconds,
    PostEventBehavior? postEventBehavior,
    Map<String, PatternRef>? participantOverrides,
    DateTime? scheduledTime,
    List<int>? repeatDays,
    String? createdBy,
    DateTime? createdAt,
    bool? isEnabled,
    String? espnTeamId,
    SyncEventCategory? category,
    bool? isSeasonSchedule,
    int? seasonYear,
    List<String>? excludedGameIds,
    DateTime? lastScheduleReconciliation,
  }) {
    return SyncEvent(
      id: id ?? this.id,
      name: name ?? this.name,
      syncGroupId: syncGroupId ?? this.syncGroupId,
      triggerType: triggerType ?? this.triggerType,
      sportLeague: sportLeague ?? this.sportLeague,
      teamId: teamId ?? this.teamId,
      basePattern: basePattern ?? this.basePattern,
      celebrationPattern: celebrationPattern ?? this.celebrationPattern,
      celebrationDurationSeconds:
          celebrationDurationSeconds ?? this.celebrationDurationSeconds,
      postEventBehavior: postEventBehavior ?? this.postEventBehavior,
      participantOverrides: participantOverrides ?? this.participantOverrides,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      repeatDays: repeatDays ?? this.repeatDays,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      isEnabled: isEnabled ?? this.isEnabled,
      espnTeamId: espnTeamId ?? this.espnTeamId,
      category: category ?? this.category,
      isSeasonSchedule: isSeasonSchedule ?? this.isSeasonSchedule,
      seasonYear: seasonYear ?? this.seasonYear,
      excludedGameIds: excludedGameIds ?? this.excludedGameIds,
      lastScheduleReconciliation:
          lastScheduleReconciliation ?? this.lastScheduleReconciliation,
    );
  }

  static Map<String, PatternRef> _parseOverrides(dynamic raw) {
    if (raw == null || raw is! Map) return {};
    return raw.map<String, PatternRef>(
      (key, value) => MapEntry(
        key as String,
        PatternRef.fromJson(value as Map<String, dynamic>),
      ),
    );
  }
}

/// Tracks a live sync event session.
class SyncEventSession {
  final String id;
  final String syncEventId;
  final String groupId;
  final SyncEventSessionStatus status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String hostUid;
  final List<String> activeParticipantUids;
  final List<String> declinedUids;
  final String? gameId;
  final bool isCelebrating;
  final DateTime? celebrationStartedAt;

  const SyncEventSession({
    required this.id,
    required this.syncEventId,
    required this.groupId,
    this.status = SyncEventSessionStatus.pending,
    required this.startedAt,
    this.endedAt,
    required this.hostUid,
    this.activeParticipantUids = const [],
    this.declinedUids = const [],
    this.gameId,
    this.isCelebrating = false,
    this.celebrationStartedAt,
  });

  factory SyncEventSession.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SyncEventSession(
      id: doc.id,
      syncEventId: data['syncEventId'] ?? '',
      groupId: data['groupId'] ?? '',
      status: SyncEventSessionStatusX.fromJson(data['status']),
      startedAt:
          (data['startedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endedAt: (data['endedAt'] as Timestamp?)?.toDate(),
      hostUid: data['hostUid'] ?? '',
      activeParticipantUids:
          List<String>.from(data['activeParticipantUids'] ?? []),
      declinedUids: List<String>.from(data['declinedUids'] ?? []),
      gameId: data['gameId'],
      isCelebrating: data['isCelebrating'] ?? false,
      celebrationStartedAt:
          (data['celebrationStartedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'syncEventId': syncEventId,
      'groupId': groupId,
      'status': status.toJson(),
      'startedAt': Timestamp.fromDate(startedAt),
      'endedAt': endedAt != null ? Timestamp.fromDate(endedAt!) : null,
      'hostUid': hostUid,
      'activeParticipantUids': activeParticipantUids,
      'declinedUids': declinedUids,
      'gameId': gameId,
      'isCelebrating': isCelebrating,
      'celebrationStartedAt': celebrationStartedAt != null
          ? Timestamp.fromDate(celebrationStartedAt!)
          : null,
    };
  }

  SyncEventSession copyWith({
    String? id,
    String? syncEventId,
    String? groupId,
    SyncEventSessionStatus? status,
    DateTime? startedAt,
    DateTime? endedAt,
    String? hostUid,
    List<String>? activeParticipantUids,
    List<String>? declinedUids,
    String? gameId,
    bool? isCelebrating,
    DateTime? celebrationStartedAt,
  }) {
    return SyncEventSession(
      id: id ?? this.id,
      syncEventId: syncEventId ?? this.syncEventId,
      groupId: groupId ?? this.groupId,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      hostUid: hostUid ?? this.hostUid,
      activeParticipantUids:
          activeParticipantUids ?? this.activeParticipantUids,
      declinedUids: declinedUids ?? this.declinedUids,
      gameId: gameId ?? this.gameId,
      isCelebrating: isCelebrating ?? this.isCelebrating,
      celebrationStartedAt:
          celebrationStartedAt ?? this.celebrationStartedAt,
    );
  }
}

/// Stored consent for a member's participation preferences in sync events.
class SyncParticipationConsent {
  final String oderId; // user ID
  final Map<SyncEventCategory, bool> categoryOptIns;
  final List<String> skipNextEventIds;
  final PostEventBehavior preferredPostBehavior;
  final DateTime updatedAt;

  const SyncParticipationConsent({
    required this.oderId,
    this.categoryOptIns = const {},
    this.skipNextEventIds = const [],
    this.preferredPostBehavior = PostEventBehavior.returnToAutopilot,
    required this.updatedAt,
  });

  bool isOptedInTo(SyncEventCategory category) =>
      categoryOptIns[category] ?? false;

  bool isSkippingEvent(String eventId) => skipNextEventIds.contains(eventId);

  factory SyncParticipationConsent.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final rawOptIns = data['categoryOptIns'] as Map<String, dynamic>? ?? {};
    final optIns = rawOptIns.map<SyncEventCategory, bool>(
      (key, value) => MapEntry(SyncEventCategoryX.fromJson(key), value as bool),
    );
    return SyncParticipationConsent(
      oderId: doc.id,
      categoryOptIns: optIns,
      skipNextEventIds: List<String>.from(data['skipNextEventIds'] ?? []),
      preferredPostBehavior:
          PostEventBehaviorX.fromJson(data['preferredPostBehavior']),
      updatedAt:
          (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'categoryOptIns': categoryOptIns.map(
        (k, v) => MapEntry(k.toJson(), v),
      ),
      'skipNextEventIds': skipNextEventIds,
      'preferredPostBehavior': preferredPostBehavior.toJson(),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  SyncParticipationConsent copyWith({
    String? oderId,
    Map<SyncEventCategory, bool>? categoryOptIns,
    List<String>? skipNextEventIds,
    PostEventBehavior? preferredPostBehavior,
    DateTime? updatedAt,
  }) {
    return SyncParticipationConsent(
      oderId: oderId ?? this.oderId,
      categoryOptIns: categoryOptIns ?? this.categoryOptIns,
      skipNextEventIds: skipNextEventIds ?? this.skipNextEventIds,
      preferredPostBehavior:
          preferredPostBehavior ?? this.preferredPostBehavior,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
