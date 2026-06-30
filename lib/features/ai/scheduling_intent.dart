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
// #58 — typed scheduling-intent contract. fromJson reproduces the EXACT
// defaulting/coercion the handler previously applied via raw Map access
// (scheduling_intent_handler.dart buildScheduleItemsFromIntents):
//   • timeLabel    absent/non-String → 'Sunset'
//   • offTimeLabel absent/non-String → null
//   • repeatDays   absent/non-List   → all 7 days; elements .toString()-coerced
//   • patternName  absent/non-String → 'Custom'
//   • wled         absent/non-Map    → null (defensively copied when present)
//
// Commit 2 removed the dead `action` field ("add"|"replace") from both this
// type and the prompt schema: no consumer ever read it (conflict resolution is
// user-driven via the schedule conflict dialog).
//
// [schemaPromptFragment] is the single source of truth for the scheduling
// schema description the model is held to — the producer (lumina_ai_service.dart
// Smart prompt) now assembles it from this fragment instead of inline prose.
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

  const SchedulingIntent({
    required this.timeLabel,
    this.offTimeLabel,
    required this.repeatDays,
    required this.patternName,
    this.wled,
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

  /// The scheduling-schema description the model is held to — the single
  /// source of truth shared by the producer (lumina_ai_service.dart Smart
  /// prompt assembles this verbatim) and this parser. Byte-for-byte the prior
  /// inline "SCHEDULING INTENT" prompt section, MINUS the dead `action` field
  /// (removed in #58 Commit 2). Pure static text — no dynamic interpolation;
  /// temporal grounding (clientNow/timezone) stays in the builder, outside
  /// this fragment.
  static const String schemaPromptFragment =
      '═══ SCHEDULING INTENT ═══\n'
      'When the user\'s request implies a recurring or future schedule (e.g. '
      '"turn on Chiefs colors every Thursday night this season", "warm white '
      'every night at sunset", "every Friday at 7pm", "Christmas pattern from '
      'Dec 1 to Dec 31"), generate BOTH the lighting design AND a '
      '`schedulingIntent` field in the JSON.\n'
      '`schedulingIntent` schema:\n'
      '  {\n'
      '    "timeLabel": "HH:MM" | "Sunset" | "Sunrise",\n'
      '    "offTimeLabel": "HH:MM" | "Sunset" | "Sunrise" | null,\n'
      '    "repeatDays": ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"],\n'
      '    "patternName": string\n'
      '  }\n'
      'Rules:\n'
      '• Omit `schedulingIntent` (or set null) for one-shot/now requests.\n'
      '• `repeatDays` uses three-letter day codes. Use all 7 for "every night", '
      '"nightly", "daily". Use the matching subset for "every Thursday", '
      '"weekends" → ["Sat","Sun"], "weekdays" → ["Mon","Tue","Wed","Thu","Fri"].\n'
      '• If the user says "sunset"/"sunrise", set the corresponding label '
      'literally as "Sunset"/"Sunrise" — the app resolves these from device '
      'location.\n'
      '• `patternName` mirrors the design\'s patternName so the schedule entry '
      'reads naturally (e.g. "Chiefs Game Day", "Warm White Wash").\n'
      '• Multi-day full-season requests (Christmas season, Halloween month, '
      'Independence week, etc.) still use the existing `isSchedule:true` / '
      '`scheduleType:"season_fill"` mechanism described in HOLIDAY SEASONS — '
      '`schedulingIntent` is for recurring weekly/daily patterns, not season-fill.\n'
      '• The `message` field must mention the schedule plainly: "Saved as Chiefs '
      'Game Day every Thursday from sunset to sunrise."\n'
      '─── COMPOUND SCHEDULES ───\n'
      'When the user asks for MULTIPLE distinct recurring schedules in one '
      'request (e.g. "warm white every night at sunset AND red every Friday '
      'at 7pm"), emit `schedulingIntents` as an ARRAY with one object per '
      'schedule. Each element uses the exact same shape as the single '
      '`schedulingIntent` form.\n'
      'Rules:\n'
      '• For a SINGLE schedule, continue using `schedulingIntent` (singular). '
      'A one-element `schedulingIntents` array is also accepted.\n'
      '• Do NOT emit both `schedulingIntent` and `schedulingIntents` in the '
      'same response. Prefer `schedulingIntents` when there are 2+; '
      '`schedulingIntent` for exactly 1.\n'
      '• COMPOUND IS RECURRING-ONLY. Date-bounded spans ("until Dec 25", '
      '"through New Year\'s", "for the month of October") STILL route to the '
      'existing `isSchedule:true` / `scheduleType:"season_fill"` mechanism — '
      'NOT `schedulingIntents`. Each element of `schedulingIntents` is a '
      'weekly-recurring pattern with time-of-day only, exactly like the '
      'singular form. Do not invent startDate/endDate fields.\n'
      '• Each element\'s `patternName` should be distinct enough that the '
      'user can tell the entries apart in their schedule list.\n'
      '• DISTINCT DESIGN PER SCHEDULE — when the user asks for different '
      'lighting on each schedule (e.g. "warm white nightly AND red on '
      'Friday"), include a per-element `"wled"` field on EACH element '
      'whose design differs from the top-level `"wled"`. The per-element '
      '`"wled"` uses the SAME format as the top-level `"wled"` (full WLED '
      'state — on/bri/seg/etc.). The top-level `"wled"` holds the '
      'primary/first design.\n'
      '• SAME DESIGN ACROSS SCHEDULES — when every schedule should run the '
      'same design (e.g. "warm white nightly AND on Saturday mornings"), '
      'OMIT per-element `"wled"` on the siblings; they\'ll reuse the '
      'top-level. Don\'t emit identical payloads N times.\n'
      '• NEVER emit a distinct `patternName` without the matching '
      'per-element `"wled"`. A schedule named "Friday Red" attached to a '
      'warm-white payload is a lying entry — the app drops it rather than '
      'create user confusion. If you can\'t produce a per-element payload '
      'for a sibling, use the same `patternName` as the top-level so the '
      'reuse is honest, or omit that sibling entirely.\n'
      'Example — user: "warm white every night at sunset, and red every '
      'Friday at 7pm":\n'
      '  "wled": {<warm white payload — primary design>},\n'
      '  "schedulingIntents": [\n'
      '    {"timeLabel":"Sunset","offTimeLabel":"Sunrise",'
      '"repeatDays":["Mon","Tue","Wed","Thu","Fri","Sat","Sun"],'
      '"patternName":"Warm White Wash"},\n'
      '    {"timeLabel":"19:00","offTimeLabel":null,'
      '"repeatDays":["Fri"],"patternName":"Friday Red",'
      '"wled":{"on":true,"bri":255,"seg":[{"fx":0,"col":[[255,0,0,0]]}]}}\n'
      '  ]\n\n'
      '─── SEQUENTIAL CHAINS (each segment hands off to the next) ───\n'
      'When the user asks for a SEQUENCE of timed states in one window — '
      '"A until T1, then B until T2, … then off" (each new color starts when '
      'the prior one ends) — emit `schedulingIntents` as an ARRAY with ONE '
      'element per colored segment, in order.\n'
      'Rules:\n'
      '• Set `offTimeLabel` to null on EVERY segment EXCEPT the last. The NEXT '
      'segment\'s `timeLabel` is the handoff — its ON trigger overwrites the '
      'prior segment automatically. Do NOT set an `offTimeLabel` on an '
      'intermediate segment: it arms a competing OFF that races the next '
      'segment\'s ON at the same time.\n'
      '• The LAST segment\'s `offTimeLabel` is the "then off" — the only off in '
      'the chain.\n'
      '• Each segment carries its OWN `wled` design.\n'
      '• SEQUENTIAL CHAINS ARE RECURRING-ONLY, like all `schedulingIntents`: '
      'every segment is a weekly-recurring pattern with time-of-day (see the '
      'ONE-SHOT restriction below).\n'
      '• Timer budget: N segments + the final off = N+1 device timers (max 8); '
      'keep chains within budget.\n'
      'Example — user: "red until 9, then blue until 11, then off, every '
      'night":\n'
      '  "schedulingIntents": [\n'
      '    { "timeLabel":"Sunset", "offTimeLabel":null,\n'
      '      "repeatDays":["Mon","Tue","Wed","Thu","Fri","Sat","Sun"],\n'
      '      "patternName":"Red",  "wled":{"on":true,"bri":255,"seg":[{"fx":0,"col":[[255,0,0,0]]}]}},\n'
      '    { "timeLabel":"21:00", "offTimeLabel":"23:00",\n'
      '      "repeatDays":["Mon","Tue","Wed","Thu","Fri","Sat","Sun"],\n'
      '      "patternName":"Blue", "wled":{"on":true,"bri":255,"seg":[{"fx":0,"col":[[0,0,255,0]]}]}}\n'
      '  ]\n'
      '─── ONE-SHOT TIMED SEQUENCES (not yet schedulable) ───\n'
      'A ONE-SHOT timed sequence — today-only / "tonight" / any non-recurring '
      '"X until T then off" — CANNOT be scheduled yet: there is no one-time '
      'timed off. Do NOT silently apply only the first color, do NOT emit a '
      '`schedulingIntent` with `repeatDays:[]` (it would never fire), and do '
      'NOT emit a weekly recurring schedule for a one-time request. Instead, '
      'say plainly in `message` that you can\'t set a one-time timed sequence '
      'yet, and offer the recurring alternative (e.g. "Want me to run this '
      'every night?"). If the user confirms recurring, use the sequential '
      'chain shape above.\n\n';

  /// Parse a raw intent Map into a typed [SchedulingIntent]. Never throws.
  /// Reproduces the handler's exact field defaulting; see the file header.
  factory SchedulingIntent.fromJson(Map<String, dynamic> json) {
    final rawTime = json['timeLabel'];
    final rawOff = json['offTimeLabel'];
    final rawDays = json['repeatDays'];
    final rawName = json['patternName'];
    final rawWled = json['wled'];

    return SchedulingIntent(
      timeLabel: rawTime is String ? rawTime : 'Sunset',
      offTimeLabel: rawOff is String ? rawOff : null,
      repeatDays: rawDays is List
          ? rawDays.map((e) => e.toString()).toList()
          : const [...SchedulingIntent._allDays],
      patternName: rawName is String ? rawName : 'Custom',
      wled: rawWled is Map ? Map<String, dynamic>.from(rawWled) : null,
    );
  }

  /// Round-trips with [fromJson] for the modeled fields. Used implicitly when
  /// a carried intent is persisted inside a ScheduleItem.wledPayload (which
  /// serializes via `jsonEncode`, whose default encoder calls `.toJson()`).
  Map<String, dynamic> toJson() => {
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
