import 'package:cloud_firestore/cloud_firestore.dart';

/// Computed status of a [CommercialEvent] based on the current time.
///
/// This is intentionally NOT stored on the Firestore doc — computing it
/// at read time prevents stale data (e.g. an event that becomes "past"
/// while the app is offline would otherwise show "active" until the
/// next write).
enum EventStatus {
  upcoming,
  active,
  past,
}

extension EventStatusLabel on EventStatus {
  String get displayName {
    switch (this) {
      case EventStatus.upcoming:
        return 'Upcoming';
      case EventStatus.active:
        return 'Active';
      case EventStatus.past:
        return 'Past';
    }
  }
}

/// Type of commercial event. The customer picks one when creating an
/// event; downstream the type drives default mood for AI design
/// suggestions and the icon shown on the event card.
enum EventType {
  sale,
  grandOpening,
  holiday,
  corporate,
  community,
  custom,
}

extension EventTypeSerde on EventType {
  /// snake_case persistence key.
  String get key {
    switch (this) {
      case EventType.sale:
        return 'sale';
      case EventType.grandOpening:
        return 'grand_opening';
      case EventType.holiday:
        return 'holiday';
      case EventType.corporate:
        return 'corporate';
      case EventType.community:
        return 'community';
      case EventType.custom:
        return 'custom';
    }
  }

  String get displayName {
    switch (this) {
      case EventType.sale:
        return 'Sale';
      case EventType.grandOpening:
        return 'Grand Opening';
      case EventType.holiday:
        return 'Holiday';
      case EventType.corporate:
        return 'Corporate';
      case EventType.community:
        return 'Community';
      case EventType.custom:
        return 'Custom';
    }
  }

  static EventType fromKey(String? key) {
    switch (key) {
      case 'sale':
        return EventType.sale;
      case 'grand_opening':
        return EventType.grandOpening;
      case 'holiday':
        return EventType.holiday;
      case 'corporate':
        return EventType.corporate;
      case 'community':
        return EventType.community;
      case 'custom':
      default:
        return EventType.custom;
    }
  }
}

/// One sales / marketing event for a commercial customer, persisted at
/// /users/{uid}/commercial_events/{eventId}.
///
/// On save, the Events feature optionally creates one or two
/// [ScheduleItem] entries via SchedulesNotifier.add():
///   • An "activate" schedule that fires at sunset on each event day
///     and applies [designPayload].
///   • A "revert" schedule that fires the day after [endDate] and
///     applies [revertDesignPayload] (or turns the lights off when the
///     payload is null).
/// Their ids are stored in [scheduleItemId] / [revertScheduleItemId]
/// so cancelling the event can clean them up.
///
/// Status (`upcoming`, `active`, `past`) is COMPUTED from
/// [startDate] / [endDate] and is not part of the Firestore document —
/// see [EventStatus] for the rationale.
class CommercialEvent {
  /// Firestore doc id. Empty when the event is being constructed for a
  /// fresh write; populated on read via [CommercialEvent.fromFirestore].
  final String eventId;

  final String name;
  final String description;
  final DateTime startDate;
  final DateTime endDate;
  final EventType type;

  /// WLED JSON payload to apply when the event activates. Null when the
  /// customer chose to skip the design step in the create flow.
  final Map<String, dynamic>? designPayload;

  /// Friendly name for [designPayload] ("Black Friday Blitz"). Stored
  /// alongside the payload so the events screen can display it without
  /// reverse-engineering the WLED state.
  final String? designName;

  /// Optional WLED JSON to apply when the event ends. Null = "turn off"
  /// (the revert schedule, if any, will write `{on: false}`).
  final Map<String, dynamic>? revertDesignPayload;

  /// Id of the activate-schedule [ScheduleItem]. Null when the customer
  /// chose Manual-Only automation in the create flow.
  final String? scheduleItemId;

  /// Id of the revert-schedule [ScheduleItem]. Null when auto-revert is
  /// disabled.
  final String? revertScheduleItemId;

  /// Uid of the user who created the event.
  final String createdBy;
  final DateTime createdAt;

  /// True when [designPayload] came from the Lumina AI suggestions
  /// flow (vs a manually picked or skipped design). Drives the small
  /// "AI generated" chip on the event card.
  final bool aiGenerated;

  const CommercialEvent({
    this.eventId = '',
    required this.name,
    this.description = '',
    required this.startDate,
    required this.endDate,
    this.type = EventType.custom,
    this.designPayload,
    this.designName,
    this.revertDesignPayload,
    this.scheduleItemId,
    this.revertScheduleItemId,
    required this.createdBy,
    required this.createdAt,
    this.aiGenerated = false,
  });

  // ─── Computed status ───────────────────────────────────────────────────

  /// Returns the event's status relative to [now] (defaults to
  /// `DateTime.now()`). Computed, never stored.
  EventStatus statusAt([DateTime? now]) {
    final t = now ?? DateTime.now();
    if (t.isBefore(startDate)) return EventStatus.upcoming;
    if (t.isAfter(endDate)) return EventStatus.past;
    return EventStatus.active;
  }

  bool get isCurrentlyActive => statusAt() == EventStatus.active;
  bool get isUpcoming => statusAt() == EventStatus.upcoming;
  bool get isPast => statusAt() == EventStatus.past;

  // ─── Serialization ─────────────────────────────────────────────────────

  factory CommercialEvent.fromJson(Map<String, dynamic> json) {
    return CommercialEvent(
      eventId: (json['event_id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      startDate:
          (json['start_date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endDate:
          (json['end_date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      type: EventTypeSerde.fromKey(json['type'] as String?),
      designPayload: _asMap(json['design_payload']),
      designName: json['design_name'] as String?,
      revertDesignPayload: _asMap(json['revert_design_payload']),
      scheduleItemId: json['schedule_item_id'] as String?,
      revertScheduleItemId: json['revert_schedule_item_id'] as String?,
      createdBy: (json['created_by'] as String?) ?? '',
      createdAt:
          (json['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      aiGenerated: (json['ai_generated'] as bool?) ?? false,
    );
  }

  factory CommercialEvent.fromFirestore(DocumentSnapshot<Object?> doc) {
    final raw = doc.data();
    final data = raw is Map<String, dynamic>
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    data['event_id'] = doc.id;
    return CommercialEvent.fromJson(data);
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'start_date': Timestamp.fromDate(startDate),
        'end_date': Timestamp.fromDate(endDate),
        'type': type.key,
        if (designPayload != null) 'design_payload': designPayload,
        if (designName != null) 'design_name': designName,
        if (revertDesignPayload != null)
          'revert_design_payload': revertDesignPayload,
        if (scheduleItemId != null) 'schedule_item_id': scheduleItemId,
        if (revertScheduleItemId != null)
          'revert_schedule_item_id': revertScheduleItemId,
        'created_by': createdBy,
        'created_at': Timestamp.fromDate(createdAt),
        'ai_generated': aiGenerated,
      };

  CommercialEvent copyWith({
    String? eventId,
    String? name,
    String? description,
    DateTime? startDate,
    DateTime? endDate,
    EventType? type,
    Map<String, dynamic>? designPayload,
    String? designName,
    Map<String, dynamic>? revertDesignPayload,
    String? scheduleItemId,
    String? revertScheduleItemId,
    String? createdBy,
    DateTime? createdAt,
    bool? aiGenerated,
  }) {
    return CommercialEvent(
      eventId: eventId ?? this.eventId,
      name: name ?? this.name,
      description: description ?? this.description,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      type: type ?? this.type,
      designPayload: designPayload ?? this.designPayload,
      designName: designName ?? this.designName,
      revertDesignPayload: revertDesignPayload ?? this.revertDesignPayload,
      scheduleItemId: scheduleItemId ?? this.scheduleItemId,
      revertScheduleItemId: revertScheduleItemId ?? this.revertScheduleItemId,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      aiGenerated: aiGenerated ?? this.aiGenerated,
    );
  }

  static Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }
}

/// One AI-generated design suggestion returned from EventLuminaService.
/// Lives only in memory — when the user picks one, the parent screen
/// extracts [wledPayload] + [name] into the event being saved.
class EventDesignSuggestion {
  const EventDesignSuggestion({
    required this.name,
    required this.description,
    required this.mood,
    required this.wledPayload,
  });

  /// Short, marketable design name (max 4 words).
  final String name;

  /// One-sentence designer rationale.
  final String description;

  /// Single mood word ("energetic", "elegant", etc.).
  final String mood;

  /// Concrete WLED JSON the design generates. Same shape as
  /// CommercialEvent.designPayload.
  final Map<String, dynamic> wledPayload;
}
