// lib/features/ai/scheduling_intent.dart
//
// Typed model for ONE element of the cloud AI's scheduling-intent contract —
// the recurring weekly/daily schedule shape emitted under `schedulingIntent`
// (singular) or `schedulingIntents` (array, Item #51 compound schedules). The
// schema is defined in lumina_ai_service.dart's Smart-tier system prompt.
//
// Co-located with the sibling intent types (ephemeral_session_intent.dart,
// recurring_sports_autopilot_intent.dart). Those are SEPARATE top-level result
// shapes dispatched independently; this type models the per-element scheduling
// intent only.
//
// #58 Commit 1 of 2 — typing refactor with ZERO behavior change. fromJson
// reproduces the EXACT defaulting/coercion the handler previously applied via
// raw Map access (scheduling_intent_handler.dart buildScheduleItemsFromIntents):
//   • timeLabel    absent/non-String → 'Sunset'
//   • offTimeLabel absent/non-String → null
//   • repeatDays   absent/non-List   → all 7 days; elements .toString()-coerced
//   • patternName  absent/non-String → 'Custom'
//   • wled         absent/non-Map    → null (defensively copied when present)
// `action` ("add"|"replace") is carried as a passthrough field but read by no
// consumer (dead contract — its removal is Commit 2, a prompt change).
//
// Field-level parsing is tolerant (never throws) to honor the normalizer's
// "never throws / tolerate garbage scalars" contract now that fromJson runs
// inside CloudAIProcessor.normalizeSchedulingIntents. For all documented and
// tested inputs this is byte-identical to the prior `as String?` casts; it
// only diverges on the never-exercised non-String-field path (previously a
// late CastError at build time).

/// Parsed `schedulingIntent` / `schedulingIntents[*]` element. Models the
/// CONSUMED contract exactly — see the file header for the defaulting rules.
class SchedulingIntent {
  /// On/start time. 'HH:MM' clock time, or 'Sunset' / 'Sunrise' (resolved from
  /// device location downstream). Defaults to 'Sunset' when absent.
  final String timeLabel;

  /// Off/end time. 'HH:MM', 'Sunset', 'Sunrise', or null for no off-time.
  final String? offTimeLabel;

  /// Three-letter day codes (e.g. ['Mon','Tue']). Defaults to all 7 days when
  /// absent. Element values are `.toString()`-coerced.
  final List<String> repeatDays;

  /// Display name mirroring the design's patternName. Defaults to 'Custom'
  /// when absent.
  final String patternName;

  /// Optional per-element WLED state (Item #51 Type-A — distinct design per
  /// schedule). Null when absent or non-Map. Defensively copied at parse time.
  final Map<String, dynamic>? wled;

  /// Passthrough of the documented `action` field ("add"|"replace"). Carried
  /// for round-trip fidelity but read by no consumer (dead contract — conflict
  /// resolution is user-driven via the schedule conflict dialog).
  final String? action;

  const SchedulingIntent({
    required this.timeLabel,
    this.offTimeLabel,
    required this.repeatDays,
    required this.patternName,
    this.wled,
    this.action,
  });

  static const List<String> _allDays = [
    'Sun',
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
  ];

  /// Parse a raw intent Map into a typed [SchedulingIntent]. Never throws.
  /// Reproduces the handler's exact field defaulting; see the file header.
  factory SchedulingIntent.fromJson(Map<String, dynamic> json) {
    final rawTime = json['timeLabel'];
    final rawOff = json['offTimeLabel'];
    final rawDays = json['repeatDays'];
    final rawName = json['patternName'];
    final rawWled = json['wled'];
    final rawAction = json['action'];

    return SchedulingIntent(
      timeLabel: rawTime is String ? rawTime : 'Sunset',
      offTimeLabel: rawOff is String ? rawOff : null,
      repeatDays: rawDays is List
          ? rawDays.map((e) => e.toString()).toList()
          : const [...SchedulingIntent._allDays],
      patternName: rawName is String ? rawName : 'Custom',
      wled: rawWled is Map ? Map<String, dynamic>.from(rawWled) : null,
      action: rawAction is String ? rawAction : null,
    );
  }

  /// Round-trips with [fromJson] for the modeled fields. Used implicitly when
  /// a carried intent is persisted inside a ScheduleItem.wledPayload (which
  /// serializes via `jsonEncode`, whose default encoder calls `.toJson()`).
  Map<String, dynamic> toJson() => {
        if (action != null) 'action': action,
        'timeLabel': timeLabel,
        'offTimeLabel': offTimeLabel,
        'repeatDays': repeatDays,
        'patternName': patternName,
        if (wled != null) 'wled': wled,
      };

  @override
  String toString() =>
      'SchedulingIntent(name=$patternName, on=$timeLabel, off=$offTimeLabel, '
      'days=${repeatDays.length}, hasWled=${wled != null})';
}
