// lib/features/schedule/calendar_entry.dart
//
// Date-specific schedule entries for the calendar view.
// These sit on top of (and override) the recurring ScheduleItem system.
// Lumina AI writes here; the calendar reads from here.

import 'package:flutter/material.dart';

import 'package:nexgen_command/features/patterns/utils/pattern_display_name.dart';

enum CalendarEntryType { auto, user, holiday, autopilot }

/// Provenance labels for [CalendarEntry.sourceTag]. Additive — does not
/// change the priority/type system, just carries a hint that the night
/// composer uses to map an entry to one of the lower (3-6) tiers.
///
/// `null` means user-created (the entry was authored directly via the
/// calendar editor, not by an autopilot source).
class CalendarEntrySourceTag {
  static const gameDay = 'game_day';
  static const gameDayGroup = 'game_day_group';
  static const neighborhoodSync = 'neighborhood_sync';
  static const autopilot = 'autopilot';
}

/// How an entry's END is determined — Scheduling V3 A1.
///
/// This describes INTENT, not a firing mechanism. Nothing in this prompt fires
/// on it; `schedule_sync.dart`, the lease manager and `fire_jobs` are untouched
/// (audit/SCHEDULING_V3_AUDIT.md §4). It exists so the display can stop
/// asserting an end time the firing layer never honoured.
enum CalendarEntryEndMode {
  /// The entry ends at [CalendarEntry.offTime], a real wall-clock boundary.
  /// This is what every user-authored and holiday entry means.
  fixedTime,

  /// Open-ended: the entry runs until the game is over. The real end is an
  /// ESPN final (server-side, `planGameDayFires`), which is why no clock time
  /// can be stated as fact. [CalendarEntry.estimatedEnd] is the display
  /// estimate; [CalendarEntry.hardCapAt] is the Policy-B fail-safe.
  untilGameEnd,

  /// Open-ended: runs until whatever is scheduled next takes over. Reserved —
  /// nothing writes this yet; it is the shape the base layer needs when
  /// Policy B lands.
  untilNextEvent;

  static CalendarEntryEndMode fromJson(String? raw) =>
      CalendarEntryEndMode.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => CalendarEntryEndMode.fixedTime,
      );
}

/// Stable per-date identity for an entry (Scheduling V3 A1).
///
/// Before V3 a date held exactly ONE entry, so the dateKey WAS the identity
/// (`next[e.dateKey] = e` — audit §2.2). Now a date holds many, and each needs
/// an id that survives a rewrite, or the weekly Game Day refresh would append a
/// duplicate every run instead of replacing its own row.
class CalendarEntryId {
  /// The id every pre-V3 document reads back as. A legacy document was written
  /// under a plain `YYYY-MM-DD` key, so it is by definition that date's primary.
  static const legacy = 'primary';

  /// Holiday defaults ([CalendarScheduleNotifier] seeds these locally and never
  /// persists them).
  static const holiday = 'holiday';

  /// One row per team per date — this is what makes the weekly Game Day refresh
  /// idempotent AND lets two teams share a night, which the single-key model
  /// made structurally impossible.
  static String gameDay(String teamSlug) => 'gd_$teamSlug';

  /// A user-authored entry. Millisecond stamp mirrors the recurring editor's
  /// `sch-<ms>` convention.
  static String user(DateTime now) => 'user_${now.millisecondsSinceEpoch}';
}

class CalendarEntry {
  /// Stable identity WITHIN [dateKey]. See [CalendarEntryId].
  ///
  /// Not globally unique — `(dateKey, entryId)` is the key. Legacy documents
  /// deserialize to [CalendarEntryId.legacy].
  final String entryId;

  final String dateKey;       // 'YYYY-MM-DD'
  final String patternName;
  final Color? color;
  final String? onTime;       // '18:00' (24-hr)
  final String? offTime;      // '23:30' (24-hr)
  final int brightness;       // 0–100
  final CalendarEntryType type;
  final bool autopilot;
  final String? note;

  /// Provenance hint used by the night composer to disambiguate entries
  /// that share the same [CalendarEntryType.autopilot] type. Null for
  /// user-authored entries. See [CalendarEntrySourceTag] for valid values.
  final String? sourceTag;

  /// WLED bus indices this entry applies to — 1:1 with the segment id
  /// (`DeviceChannel.id`, derived from `hw.led.ins`; audit §5.2).
  /// `null` = every channel, which is what every writer produces today.
  ///
  /// ⚠️ NOTHING CONSUMES THIS YET. It is written `null` everywhere and read by
  /// no payload builder, no timer, no preset. It exists so the field survives
  /// the #108 Parent Segment redesign without a second migration — that spec
  /// keeps the channel identity a bus index (audit §5.6). Per-channel FIRING is
  /// blocked in the firing layer, not here (audit §8, F2-2/F2-3).
  final List<int>? channels;

  /// How this entry ends. Legacy documents infer it — see [fromJson].
  final CalendarEntryEndMode endMode;

  /// DISPLAY ONLY. Never a firing time, never written to a WLED timer.
  ///
  /// For [CalendarEntryEndMode.untilGameEnd] this is `gameStart + estimated
  /// duration`. The UI must label it as an estimate; the honest statement is
  /// "until the game ends", and this is the parenthetical.
  final DateTime? estimatedEnd;

  /// The Policy-B fail-safe end: `gameStart + estimatedGameDuration(sport) +
  /// 60min`, matching the foreground session fallback at
  /// `game_day_autopilot_service.dart:626` so there is exactly one such
  /// constant in the codebase.
  ///
  /// ⚠️ NEVER LOAD-BEARING ON THE CLIENT. Under Policy B the authoritative cap
  /// is a server-side fire job written by the planner from
  /// `gameDayPlanning.ts:572 estimatedDurationMs` — not this field. This is a
  /// display value and a design record. A mixed-version write strips it
  /// (audit/SCHEDULE_V3_P2.md P4), which is only safe *because* it is never
  /// load-bearing. Do not make it so.
  final DateTime? hardCapAt;

  const CalendarEntry({
    this.entryId = CalendarEntryId.legacy,
    required this.dateKey,
    required this.patternName,
    this.color,
    this.onTime,
    this.offTime,
    this.brightness = 85,
    this.type = CalendarEntryType.auto,
    this.autopilot = true,
    this.note,
    this.sourceTag,
    this.channels,
    this.endMode = CalendarEntryEndMode.fixedTime,
    this.estimatedEnd,
    this.hardCapAt,
  });

  /// True when this entry has no stated clock end — the display must not
  /// render [offTime] as a real boundary for these.
  bool get isOpenEnded => endMode != CalendarEntryEndMode.fixedTime;

  CalendarEntry copyWith({
    String? entryId,
    String? dateKey,
    String? patternName,
    Color? color,
    String? onTime,
    String? offTime,
    bool clearOffTime = false,
    int? brightness,
    CalendarEntryType? type,
    bool? autopilot,
    String? note,
    String? sourceTag,
    List<int>? channels,
    CalendarEntryEndMode? endMode,
    DateTime? estimatedEnd,
    DateTime? hardCapAt,
  }) =>
      CalendarEntry(
        entryId: entryId ?? this.entryId,
        dateKey: dateKey ?? this.dateKey,
        patternName: patternName ?? this.patternName,
        color: color ?? this.color,
        onTime: onTime ?? this.onTime,
        offTime: clearOffTime ? null : (offTime ?? this.offTime),
        brightness: brightness ?? this.brightness,
        type: type ?? this.type,
        autopilot: autopilot ?? this.autopilot,
        note: note ?? this.note,
        sourceTag: sourceTag ?? this.sourceTag,
        channels: channels ?? this.channels,
        endMode: endMode ?? this.endMode,
        estimatedEnd: estimatedEnd ?? this.estimatedEnd,
        hardCapAt: hardCapAt ?? this.hardCapAt,
      );

  /// Parse one change entry from Lumina AI JSON.
  static CalendarEntry? fromAiJson(Map<String, dynamic> json) {
    final dateKey = json['date'] as String?;
    if (dateKey == null || dateKey.isEmpty) return null;

    // Item #61 Decision 6 — defensive against malformed AI responses.
    // Must be strict YYYY-MM-DD with zero-padding. '2026-3-1' is
    // rejected; '2026-03-01' is accepted. Without this, a Claude
    // response that drops a zero corrupts the calendar map's key,
    // making the entry unmatchable by selectedCalendarDateProvider
    // lookups and orphaning the row in Firestore.
    final dateKeyRegex = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (!dateKeyRegex.hasMatch(dateKey)) {
      debugPrint(
        'CalendarEntry.fromAiJson: rejecting malformed dateKey '
        '"$dateKey" — must be strict YYYY-MM-DD',
      );
      return null;
    }
    // Regex passes for '2026-13-45'; verify the date actually exists.
    // DateTime.parse accepts ISO-8601 strings strictly enough here.
    DateTime? parsed;
    try {
      parsed = DateTime.parse(dateKey);
    } catch (e) {
      debugPrint(
        'CalendarEntry.fromAiJson: dateKey "$dateKey" matches format '
        'but is not a valid date',
      );
      return null;
    }
    // DateTime.parse rolls over invalid days/months (e.g. '2026-02-30'
    // becomes 2026-03-02). Round-trip check rejects rollover.
    final roundTrip =
        '${parsed.year.toString().padLeft(4, '0')}-'
        '${parsed.month.toString().padLeft(2, '0')}-'
        '${parsed.day.toString().padLeft(2, '0')}';
    if (roundTrip != dateKey) {
      debugPrint(
        'CalendarEntry.fromAiJson: dateKey "$dateKey" parsed to '
        '"$roundTrip" — rollover indicates invalid calendar date',
      );
      return null;
    }

    Color? color;
    final colorStr = json['color'] as String?;
    if (colorStr != null && colorStr.startsWith('#') && colorStr.length == 7) {
      try {
        color = Color(int.parse('FF${colorStr.substring(1)}', radix: 16));
      } catch (e) {
        debugPrint('Error in CalendarEntry.fromAiJson parsing color: $e');
      }
    }

    final brightness = (json['brightness'] as num?)?.toInt() ?? 85;
    // 'Off' pattern → color null, brightness 0
    final isOff = (json['pattern'] as String?)?.toLowerCase() == 'off' ||
        (colorStr == null && brightness == 0);

    return CalendarEntry(
      dateKey: dateKey,
      patternName: isOff ? 'Off' : (json['pattern'] as String? ?? 'Custom'),
      color: isOff ? null : color,
      onTime: isOff ? null : json['onTime'] as String?,
      offTime: isOff ? null : json['offTime'] as String?,
      brightness: isOff ? 0 : brightness,
      type: CalendarEntryType.user,
      autopilot: false,
      note: json['note'] as String?,
      sourceTag: json['sourceTag'] as String?,
    );
  }

  /// Serialize to Firestore-safe map.
  ///
  /// The four V3 fields are emitted only when set, so an entry that carries
  /// none produces a byte-identical document to the pre-V3 writer. `channels`
  /// is a flat `List<int>` — deliberately NOT a list of lists (#84).
  Map<String, dynamic> toJson() => {
        'entryId': entryId,
        'dateKey': dateKey,
        'patternName': patternName,
        'color': color != null
            ? '#${color!.value.toRadixString(16).padLeft(8, '0').substring(2)}'
            : null,
        'onTime': onTime,
        'offTime': offTime,
        'brightness': brightness,
        'type': type.name,
        'autopilot': autopilot,
        'note': note,
        'sourceTag': sourceTag,
        if (channels != null) 'channels': channels,
        'endMode': endMode.name,
        if (estimatedEnd != null) 'estimatedEnd': estimatedEnd!.toIso8601String(),
        if (hardCapAt != null) 'hardCapAt': hardCapAt!.toIso8601String(),
      };

  /// Deserialize from Firestore map.
  ///
  /// ── LEGACY GAME DAY READ (V3 A1, no fleet repair) ────────────────────────
  /// 159 production entries across 11 users were written by the pre-V3 path
  /// (audit/SCHEDULE_V3_P2.md P1). Every Game Day one carries an `offTime` that
  /// was FABRICATED — `gameStart + estimatedDuration + 60min`
  /// (`game_day_autopilot_service.dart:745`) — and which the firing layer never
  /// honoured: the real end is an ESPN final. Those rows are NOT rewritten.
  /// They are re-INTERPRETED on read: a `game_day` entry with an `offTime` and
  /// no stored `endMode` becomes `untilGameEnd` with that time demoted from
  /// "the end" to `estimatedEnd`, which the UI labels as an estimate.
  ///
  /// Scoped to `sourceTag == game_day` on purpose. A user-authored or holiday
  /// `offTime` IS a real boundary and must keep meaning one.
  factory CalendarEntry.fromJson(Map<String, dynamic> json) {
    Color? color;
    final colorStr = json['color'] as String?;
    if (colorStr != null && colorStr.startsWith('#') && colorStr.length == 7) {
      try {
        color = Color(int.parse('FF${colorStr.substring(1)}', radix: 16));
      } catch (e) {
        debugPrint('Error in CalendarEntry.fromJson parsing color: $e');
      }
    }

    final dateKey = json['dateKey'] as String;
    final onTime = json['onTime'] as String?;
    final offTime = json['offTime'] as String?;
    final sourceTag = json['sourceTag'] as String?;
    final storedEndMode = json['endMode'] as String?;

    // Legacy inference — only when the document predates `endMode`.
    final isLegacyGameDay = storedEndMode == null &&
        sourceTag == CalendarEntrySourceTag.gameDay &&
        offTime != null;

    final endMode = isLegacyGameDay
        ? CalendarEntryEndMode.untilGameEnd
        : CalendarEntryEndMode.fromJson(storedEndMode);

    final estimatedEnd = _tryParseIso(json['estimatedEnd']) ??
        (isLegacyGameDay
            ? resolveWallClock(dateKey, offTime, notBefore: onTime)
            : null);

    return CalendarEntry(
      // Absent on every pre-V3 document → that date's primary, which is exactly
      // what it was (it owned the plain dateKey).
      entryId: (json['entryId'] as String?) ?? CalendarEntryId.legacy,
      dateKey: dateKey,
      patternName: json['patternName'] as String? ?? 'Custom',
      color: color,
      onTime: onTime,
      offTime: offTime,
      brightness: (json['brightness'] as num?)?.toInt() ?? 85,
      type: CalendarEntryType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => CalendarEntryType.user,
      ),
      autopilot: json['autopilot'] as bool? ?? false,
      note: json['note'] as String?,
      sourceTag: sourceTag,
      channels: _tryParseChannels(json['channels']),
      endMode: endMode,
      estimatedEnd: estimatedEnd,
      hardCapAt: _tryParseIso(json['hardCapAt']),
    );
  }

  /// Defensive ISO-8601 parse — absence, wrong type, or a malformed string all
  /// collapse to null. Mirrors `ScheduleItem._tryParseDisabledUntil`: a corrupt
  /// display field must never crash boot.
  static DateTime? _tryParseIso(dynamic raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      return DateTime.parse(raw);
    } catch (_) {
      return null;
    }
  }

  /// Tolerates `List<dynamic>` (what Firestore hands back) and drops anything
  /// non-integral rather than throwing. An empty list is preserved — it means
  /// "explicitly no channels", which is NOT the same as null ("all").
  static List<int>? _tryParseChannels(dynamic raw) {
    if (raw is! List) return null;
    return raw.whereType<num>().map((n) => n.toInt()).toList(growable: false);
  }

  /// Resolve a `'HH:mm'` wall clock against a `'YYYY-MM-DD'` date key.
  ///
  /// When [notBefore] (also `'HH:mm'`) is supplied and the resolved time is at
  /// or before it, the result rolls to the NEXT day — a 22:00→01:00 window ends
  /// tomorrow, and a Game Day estimate that crosses midnight must not read as
  /// having ended before it began.
  ///
  /// Returns null for anything unparseable. Never invents a time.
  static DateTime? resolveWallClock(
    String dateKey,
    String? hhmm, {
    String? notBefore,
  }) {
    final t = _parseHhmm(hhmm);
    if (t == null) return null;
    final DateTime day;
    try {
      day = DateTime.parse(dateKey);
    } catch (_) {
      return null;
    }
    var out = DateTime(day.year, day.month, day.day, t.$1, t.$2);
    final from = _parseHhmm(notBefore);
    if (from != null) {
      final start = DateTime(day.year, day.month, day.day, from.$1, from.$2);
      if (!out.isAfter(start)) out = out.add(const Duration(days: 1));
    }
    return out;
  }

  static (int, int)? _parseHhmm(String? hhmm) {
    if (hhmm == null) return null;
    final parts = hhmm.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      return null;
    }
    return (h, m);
  }

  /// Display-friendly on→off time string.
  ///
  /// An open-ended entry NEVER renders `offTime` as an arrow target — that is
  /// the fabricated-end defect this model exists to remove. It states the end
  /// condition, with the estimate parenthesised.
  String get timeRangeLabel {
    if (onTime == null) return '—';
    if (isOpenEnded) return '$onTime → ${endConditionLabel()}';
    if (offTime == null) return onTime!;
    return '$onTime → $offTime';
  }

  /// The honest end statement for an open-ended entry.
  ///
  /// [formatTime] lets a surface render [estimatedEnd] in the user's preferred
  /// format; the default is 24-hour `HH:mm`, matching this model's storage.
  String endConditionLabel({String Function(DateTime)? formatTime}) {
    final String base;
    switch (endMode) {
      case CalendarEntryEndMode.untilGameEnd:
        base = 'until game ends';
      case CalendarEntryEndMode.untilNextEvent:
        base = 'until next event';
      case CalendarEntryEndMode.fixedTime:
        return offTime ?? '—';
    }
    final est = estimatedEnd;
    if (est == null) return base;
    final fmt = formatTime ??
        (DateTime d) => '${d.hour.toString().padLeft(2, '0')}:'
            '${d.minute.toString().padLeft(2, '0')}';
    return '$base (est. ${fmt(est)})';
  }

  /// UI-safe pattern name. Routes the stored [patternName] through the
  /// centralized slug resolver so render sites can't leak snake_case
  /// identifiers. Authored strings pass through unchanged.
  String get displayName => displayNameFor(patternName);
}
