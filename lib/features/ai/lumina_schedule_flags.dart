// lib/features/ai/lumina_schedule_flags.dart
//
// Typed carrier for the multi-night schedule flags in a Lumina reply
// (`isSchedule`, `scheduleType`, `dayCount`, `schedule[]`, …).
//
// These flags sit at the TOP LEVEL of the reply JSON, beside `wled` — see
// LuminaSmartScheduler.planToResponseJson. The cloud parser only ever copied
// `wled` plus a fixed set of display keys into the payload, so the flags were
// dropped at parse time and no dispatch site could see them (UX audit row 7).
// Carrying them on LuminaCommandResult keeps them independent of the payload,
// the same way schedulingIntents is carried (#58b).

/// Multi-night schedule flags parsed from the top level of a Lumina reply.
class LuminaScheduleFlags {
  /// Top-level reply keys that describe the schedule. Anything else in the
  /// reply (the design itself, display metadata) stays on the payload.
  static const List<String> carriedKeys = [
    'isSchedule',
    'scheduleType',
    'seasonId',
    'dayCount',
    'hasVariety',
    'varietyLevel',
    'startTrigger',
    'endTrigger',
    'usesSunsetSunrise',
    'patternName',
    'themeName',
    'schedule',
  ];

  /// Always true on a parsed instance — [fromResponseJson] returns null
  /// otherwise. Kept as a field so dispatch reads the flag, not the type.
  final bool isSchedule;

  /// `multi_day` (local smart scheduler) or `season_fill` (cloud prompt).
  final String? scheduleType;

  /// Season named by a `season_fill` reply, e.g. `christmas_season`.
  final String? seasonId;

  /// Number of nights the reply claims. 0 when absent.
  final int dayCount;

  /// True when the plan rotates effects across nights.
  final bool hasVariety;

  /// Display name for the whole schedule, e.g. "Christmas — 7-Night Schedule".
  final String? patternName;

  /// One entry per night, in order. Empty when the reply carried the flags
  /// but no plan (the cloud `season_fill` shape).
  final List<Map<String, dynamic>> schedule;

  /// The carried top-level keys exactly as emitted, for consumers that read
  /// the raw plan shape.
  final Map<String, dynamic> raw;

  const LuminaScheduleFlags({
    required this.isSchedule,
    required this.scheduleType,
    required this.seasonId,
    required this.dayCount,
    required this.hasVariety,
    required this.patternName,
    required this.schedule,
    required this.raw,
  });

  /// True when the reply carried at least one night to schedule.
  bool get hasOccurrences => schedule.isNotEmpty;

  /// The WLED payload for night 1, or null when the first night has none.
  Map<String, dynamic>? get firstNightWled {
    if (schedule.isEmpty) return null;
    final wled = schedule.first['wled'];
    return wled is Map ? Map<String, dynamic>.from(wled) : null;
  }

  /// The plan in the shape AutopilotScheduler.importSmartSchedule reads.
  Map<String, dynamic> toImportPayload() => {
        ...raw,
        'schedule': schedule,
      };

  /// Parses the flags from the decoded top-level reply object. Returns null
  /// unless the reply sets `isSchedule: true`. Malformed entries are dropped
  /// defensively — never throws on a bad model response.
  static LuminaScheduleFlags? fromResponseJson(Map<String, dynamic>? obj) {
    if (obj == null || obj['isSchedule'] != true) return null;

    final schedule = <Map<String, dynamic>>[];
    final rawSchedule = obj['schedule'];
    if (rawSchedule is List) {
      for (final entry in rawSchedule) {
        if (entry is Map) schedule.add(Map<String, dynamic>.from(entry));
      }
    }

    final dayCount = obj['dayCount'];
    final scheduleType = obj['scheduleType'];
    final seasonId = obj['seasonId'];
    final patternName = obj['patternName'];

    return LuminaScheduleFlags(
      isSchedule: true,
      scheduleType: scheduleType is String ? scheduleType : null,
      seasonId: seasonId is String ? seasonId : null,
      dayCount: dayCount is num ? dayCount.toInt() : 0,
      hasVariety: obj['hasVariety'] == true,
      patternName: patternName is String ? patternName : null,
      schedule: schedule,
      raw: {
        for (final key in carriedKeys)
          if (obj.containsKey(key)) key: obj[key],
      },
    );
  }
}
