// lib/features/schedule/day_timeline.dart
//
// Scheduling V3 A2 — THE DAY TIMELINE, and the one place precedence is decided.
//
// This replaces `day_resolution.dart`'s single-primary answer. That file's own
// header named the gap it left: "It does not make a multi-entry day DISPLAY all
// of its entries — it still returns one primary." This does.
//
// ── WHAT THIS IS AND IS NOT ───────────────────────────────────────────────────
//
// It is a DESCRIPTION of the firing layer, not a controller of it. Nothing here
// arms a timer, writes a preset, or touches a fire job — `schedule_sync.dart`,
// the lease manager and `planGameDayFires` are untouched by this work
// (audit/SCHEDULING_V3_AUDIT.md §4). If the display and the lights disagree,
// this file is wrong and the lights are right.
//
// ── WHY `lastWriteWins` IS THE HONEST DEFAULT ─────────────────────────────────
//
// A WLED clock timer fires on the controller. Nothing suppresses it while a
// Game Day design is running — no slot clearing, no timer disable, no arbiter
// (audit §4.3, verified by absence). The base layer stomping a Game Day at
// 8:00 PM is not a bug in this model; it is the documented RECOVERY mechanism
// that `base_layer_gate.dart` exists to warn accounts about when they lack one.
// So the timeline says "Warm White takes over at 8:00 PM", because that is what
// the house will do tonight.
//
// ── THE SEAM ──────────────────────────────────────────────────────────────────
//
// [kActiveSchedulePrecedence] is the ONLY thing a provider passes. Flipping it
// to [PrecedencePolicy.holdUntilEnd] changes every surface at once — and must
// not happen until the firing layer can actually hold. See the constant.

import 'package:nexgen_command/features/patterns/utils/pattern_display_name.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Policy
// ─────────────────────────────────────────────────────────────────────────────

/// How the timeline resolves two things wanting the same night.
enum PrecedencePolicy {
  /// TODAY'S TRUTH. Whatever fires later wins, because the controller has no
  /// concept of an override — each timer just fires. An open-ended entry is
  /// shown as being taken over by the next thing on the clock.
  lastWriteWins,

  /// POLICY B — DECLARED, IMPLEMENTED, NOT SELECTED. A Game Day holds until
  /// ESPN final or its hard cap, whichever comes first, and base entries inside
  /// that window are shown suppressed rather than taking over.
  holdUntilEnd,
}

/// The active policy. **The only value any provider passes.**
///
/// ⚠️ DO NOT FLIP THIS TO `holdUntilEnd` until the firing layer suppresses the
/// base while a Game Day is armed. Flipping it alone would make every surface
/// state that the base is suppressed while the controller cheerfully fires it
/// anyway — a display that lies, which is strictly worse than the honest
/// "takes over at 8:00 PM" it replaces.
///
/// Three things gate the flip, all recorded in audit/SCHEDULE_V3_P2.md under
/// "Gates on the Policy B prompt":
///   1. `config/gameday_planner.write_jobs` is false — the end fire job that
///      would release the hold has never executed in production.
///   2. There is no nightly restore row (S4_RESTORE.md); the `endsAt` companion
///      restore IS the end mechanism, and it rides that same disarmed path.
///   3. Suppressing the base before the end path is proven removes the only
///      working recovery and leaves nothing in its place.
const PrecedencePolicy kActiveSchedulePrecedence = PrecedencePolicy.lastWriteWins;

// ─────────────────────────────────────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────────────────────────────────────

/// Where a timeline row came from.
enum TimelineSource {
  /// A recurring [ScheduleItem] that falls on this weekday.
  recurring,

  /// A date-specific [CalendarEntry] authored by a user or a holiday default.
  dated,

  /// A date-specific [CalendarEntry] projected from Game Day autopilot
  /// (`sourceTag == game_day`). Split out from [dated] because it is the only
  /// source that is open-ended, and the only one the policies treat differently.
  gameDay,
}

/// One row on a day's timeline.
class TimelineEntry {
  /// Unique within the timeline. `rec:<scheduleId>` or `cal:<entryId>`.
  final String id;
  final TimelineSource source;

  /// Set when [source] is [TimelineSource.recurring].
  final ScheduleItem? recurring;

  /// Set when [source] is [TimelineSource.dated] or [TimelineSource.gameDay].
  final CalendarEntry? dated;

  /// Resolved local start. Null when the label could not be resolved — a solar
  /// token with no sun times supplied. Such a row is still SHOWN (dropping it
  /// would hide a real schedule) but sorts last and takes no part in takeover
  /// or conflict derivation, because an unknown time cannot be compared.
  final DateTime? startsAt;

  /// Resolved local end for a fixed-time row. Null for an open-ended row —
  /// and null here means "no stated end", never "ends at midnight".
  final DateTime? endsAt;

  final CalendarEntryEndMode endMode;

  /// Display-only estimate for an open-ended row. Never a firing time.
  final DateTime? estimatedEnd;

  /// Policy-B fail-safe end. Only consulted under [PrecedencePolicy.holdUntilEnd].
  final DateTime? hardCapAt;

  /// Bus indices, or null for "all". Used ONLY for conflict detection here.
  final List<int>? channels;

  /// Human label, already slug-resolved.
  final String label;

  /// [PrecedencePolicy.lastWriteWins] only — when something later begins and
  /// this row stops being what the house is doing.
  final DateTime? takenOverAt;

  /// The label of whatever takes over at [takenOverAt].
  final String? takenOverByLabel;

  /// [PrecedencePolicy.holdUntilEnd] only — this row is inside a Game Day hold
  /// and will not run when its clock time arrives.
  final bool suppressed;

  /// When a [suppressed] row resumes.
  final DateTime? suppressedUntil;

  /// [PrecedencePolicy.holdUntilEnd] only — an open-ended row holds until here.
  final DateTime? holdsUntil;

  /// This row starts at the same minute as another on overlapping channels.
  /// Today's firing order between them is genuinely indeterminate, so it is
  /// FLAGGED and deliberately not resolved.
  final bool conflict;

  const TimelineEntry({
    required this.id,
    required this.source,
    this.recurring,
    this.dated,
    required this.startsAt,
    required this.endsAt,
    required this.endMode,
    this.estimatedEnd,
    this.hardCapAt,
    this.channels,
    required this.label,
    this.takenOverAt,
    this.takenOverByLabel,
    this.suppressed = false,
    this.suppressedUntil,
    this.holdsUntil,
    this.conflict = false,
  });

  bool get isOpenEnded => endMode != CalendarEntryEndMode.fixedTime;

  /// True when the start time could not be resolved from its label.
  bool get timeUnresolved => startsAt == null;

  TimelineEntry _copy({
    DateTime? takenOverAt,
    String? takenOverByLabel,
    bool? suppressed,
    DateTime? suppressedUntil,
    DateTime? holdsUntil,
    bool? conflict,
  }) =>
      TimelineEntry(
        id: id,
        source: source,
        recurring: recurring,
        dated: dated,
        startsAt: startsAt,
        endsAt: endsAt,
        endMode: endMode,
        estimatedEnd: estimatedEnd,
        hardCapAt: hardCapAt,
        channels: channels,
        label: label,
        takenOverAt: takenOverAt ?? this.takenOverAt,
        takenOverByLabel: takenOverByLabel ?? this.takenOverByLabel,
        suppressed: suppressed ?? this.suppressed,
        suppressedUntil: suppressedUntil ?? this.suppressedUntil,
        holdsUntil: holdsUntil ?? this.holdsUntil,
        conflict: conflict ?? this.conflict,
      );
}

/// Everything covering one date, ordered by start time.
class DayTimeline {
  final String dateKey;
  final PrecedencePolicy policy;

  /// Ordered by [TimelineEntry.startsAt]; unresolved-time rows last.
  final List<TimelineEntry> entries;

  const DayTimeline({
    required this.dateKey,
    required this.policy,
    required this.entries,
  });

  static const DayTimeline empty = DayTimeline(
    dateKey: '',
    policy: kActiveSchedulePrecedence,
    entries: <TimelineEntry>[],
  );

  bool get isEmpty => entries.isEmpty;
  bool get isNotEmpty => entries.isNotEmpty;

  /// What a "+N" badge counts.
  int get count => entries.length;

  /// True when more covers this day than a single-row surface can show.
  bool get hasMore => entries.length > 1;

  bool get hasConflict => entries.any((e) => e.conflict);

  /// The row a one-line surface shows: the FIRST by clock.
  ///
  /// Note this differs from the pre-V3 `newestRecurring`, which showed the
  /// newest by insertion order regardless of time. First-by-clock is what
  /// "tonight, next" means to a reader.
  TimelineEntry? get primary => entries.isEmpty ? null : entries.first;

  /// Rows beyond [primary].
  List<TimelineEntry> get rest =>
      entries.length <= 1 ? const [] : entries.sublist(1);
}

// ─────────────────────────────────────────────────────────────────────────────
// Inputs
// ─────────────────────────────────────────────────────────────────────────────

/// Everything the pure resolver needs. No Riverpod, no widgets, no clock.
class DayTimelineInputs {
  /// `'YYYY-MM-DD'`.
  final String dateKey;

  /// ALL recurring schedules — filtering to this weekday happens inside, so
  /// every surface filters identically.
  final List<ScheduleItem> recurringSchedules;

  /// Every dated entry for this date (see `CalendarEntrySet.forDate`).
  final List<CalendarEntry> datedEntries;

  /// `'HH:mm'` local sunrise/sunset for this date, when known. Without them a
  /// `Sunrise`/`Sunset` label cannot be placed on the clock, and the row is
  /// marked [TimelineEntry.timeUnresolved] rather than guessed at.
  final String? sunriseHhmm;
  final String? sunsetHhmm;

  const DayTimelineInputs({
    required this.dateKey,
    this.recurringSchedules = const [],
    this.datedEntries = const [],
    this.sunriseHhmm,
    this.sunsetHhmm,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Resolver
// ─────────────────────────────────────────────────────────────────────────────

/// Build one day's timeline under [policy].
///
/// PURE. Same inputs ⇒ same output, no `DateTime.now()` except through
/// [ScheduleItem.isCurrentlyEvicted], which is the pre-existing eviction
/// semantic this preserves verbatim from `resolveDay`.
DayTimeline resolveDayTimeline(
  DayTimelineInputs inputs,
  PrecedencePolicy policy,
) {
  final DateTime day;
  try {
    day = DateTime.parse(inputs.dateKey);
  } catch (_) {
    return DayTimeline(
        dateKey: inputs.dateKey, policy: policy, entries: const []);
  }
  final weekday = day.weekday % 7; // 0=Sun..6=Sat, matching every surface

  final rows = <TimelineEntry>[
    ..._recurringRows(inputs, day, weekday),
    ..._datedRows(inputs, day),
  ];

  _sortByStart(rows);

  final conflicted = _markConflicts(rows);
  return DayTimeline(
    dateKey: inputs.dateKey,
    policy: policy,
    entries: switch (policy) {
      PrecedencePolicy.lastWriteWins => _deriveLastWriteWins(conflicted),
      PrecedencePolicy.holdUntilEnd => _deriveHoldUntilEnd(conflicted),
    },
  );
}

// ── Row construction ─────────────────────────────────────────────────────────

List<TimelineEntry> _recurringRows(
    DayTimelineInputs inputs, DateTime day, int weekday) {
  final out = <TimelineEntry>[];
  for (final s in inputs.recurringSchedules) {
    // Same three filters resolveDay applied, in the same order.
    if (!s.enabled) continue;
    if (s.isCurrentlyEvicted) continue;
    if (!scheduleAppliesToWeekday(s, weekday)) continue;

    final start = _resolveLabel(s.timeLabel, day, inputs);
    final end = s.hasOffTime
        ? _resolveLabel(s.offTimeLabel!, day, inputs, notBefore: start)
        : null;

    out.add(TimelineEntry(
      id: 'rec:${s.id}',
      source: TimelineSource.recurring,
      recurring: s,
      startsAt: start,
      endsAt: end,
      // A recurring schedule always states a real boundary or none at all —
      // there is no open-ended recurring shape today.
      endMode: CalendarEntryEndMode.fixedTime,
      channels: s.channels,
      label: timelineLabelForAction(s.actionLabel),
    ));
  }
  return out;
}

List<TimelineEntry> _datedRows(DayTimelineInputs inputs, DateTime day) {
  final out = <TimelineEntry>[];
  for (final e in inputs.datedEntries) {
    final isGameDay = e.sourceTag == CalendarEntrySourceTag.gameDay ||
        e.sourceTag == CalendarEntrySourceTag.gameDayGroup;

    final start = _resolveLabel(e.onTime, day, inputs);
    // An open-ended row has NO resolved end. Its `offTime`, where one exists,
    // is the fabricated legacy value already demoted to `estimatedEnd` by
    // CalendarEntry.fromJson — it must never re-enter as a boundary here.
    final end = e.isOpenEnded
        ? null
        : _resolveLabel(e.offTime, day, inputs, notBefore: start);

    out.add(TimelineEntry(
      id: 'cal:${e.entryId}',
      source: isGameDay ? TimelineSource.gameDay : TimelineSource.dated,
      dated: e,
      startsAt: start,
      endsAt: end,
      endMode: e.endMode,
      estimatedEnd: e.estimatedEnd,
      hardCapAt: e.hardCapAt,
      channels: e.channels,
      label: e.displayName,
    ));
  }
  return out;
}

/// Display label for a recurring schedule's `actionLabel`.
///
/// `"Pattern: Warm White"` → `"Warm White"`; `"Brightness: 70%"` and
/// `"Turn Off"` pass through unchanged.
///
/// WHY NOT `ScheduleItem.displayActionLabel`: that KEEPS the `"Pattern: "`
/// prefix (it only slug-resolves the name after it), which is right for the
/// schedule LIST — where a row has no other context — but wrong on a day
/// surface, where every row is a schedule and the prefix is noise on all of
/// them. Every pre-V3 day surface stripped it via a local `_labelFromAction`.
/// There were TWO such copies in `my_schedule_page.dart` and they had DRIFTED:
/// one stripped only a `pattern`-prefixed label, the other split on the first
/// `:` unconditionally and so turned `"Brightness: 70%"` into `"70%"`. This is
/// the correct one, kept in a single place.
String timelineLabelForAction(String actionLabel) {
  final a = actionLabel.trim();
  if (a.toLowerCase().startsWith('pattern')) {
    final idx = a.indexOf(':');
    final name = idx != -1 && idx + 1 < a.length ? a.substring(idx + 1).trim() : a;
    return displayNameFor(name);
  }
  return a;
}

/// Does [s] run on [weekday] (0=Sun..6=Sat)?
///
/// Lifted verbatim from the day-abbreviation matching the three pre-V3 surfaces
/// each open-coded (`_itemsForWeekday`, and the Tonight card's inline copy) so
/// there is now one definition.
bool scheduleAppliesToWeekday(ScheduleItem s, int weekday) {
  const map = {
    0: {'sun', 'sunday'},
    1: {'mon', 'monday'},
    2: {'tue', 'tues', 'tuesday'},
    3: {'wed', 'wednesday'},
    4: {'thu', 'thurs', 'thursday'},
    5: {'fri', 'friday'},
    6: {'sat', 'saturday'},
  };
  final dl = s.repeatDays.map((e) => e.toLowerCase()).toSet();
  if (dl.contains('daily')) return true;
  return (map[weekday] ?? const <String>{}).any(dl.contains);
}

// ── Time resolution ──────────────────────────────────────────────────────────

/// Resolve a schedule label onto [day]'s clock.
///
/// Handles `'7:00 PM'`, `'19:00'`, and the solar tokens. Returns null for
/// anything it cannot place — including a solar token with no sun time
/// supplied. NEVER defaults to midnight; an invented time is how a display
/// starts lying (the same rule `parseTimeLabel` enforces on the firing side).
DateTime? _resolveLabel(
  String? label,
  DateTime day,
  DayTimelineInputs inputs, {
  DateTime? notBefore,
}) {
  if (label == null) return null;
  final l = label.trim().toLowerCase();
  if (l.isEmpty) return null;

  String? hhmm;
  if (l == 'sunrise') {
    hhmm = inputs.sunriseHhmm;
  } else if (l == 'sunset') {
    hhmm = inputs.sunsetHhmm;
  } else {
    hhmm = _to24h(l);
  }
  if (hhmm == null) return null;

  var out = CalendarEntry.resolveWallClock(
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}',
    hhmm,
  );
  if (out == null) return null;

  // An end at or before its own start is an overnight window.
  if (notBefore != null && !out.isAfter(notBefore)) {
    out = out.add(const Duration(days: 1));
  }
  return out;
}

/// `'7:05 pm'` / `'19:05'` → `'19:05'`. Null when unrecognised.
String? _to24h(String lower) {
  final ampm =
      RegExp(r'^(\d{1,2}):(\d{2})\s*([ap]m)$').firstMatch(lower);
  if (ampm != null) {
    var h = int.parse(ampm.group(1)!);
    final m = int.parse(ampm.group(2)!);
    if (h < 1 || h > 12 || m > 59) return null;
    if (ampm.group(3) == 'pm' && h != 12) h += 12;
    if (ampm.group(3) == 'am' && h == 12) h = 0;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
  final h24 = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(lower);
  if (h24 != null) {
    final h = int.parse(h24.group(1)!);
    final m = int.parse(h24.group(2)!);
    if (h > 23 || m > 59) return null;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
  return null;
}

void _sortByStart(List<TimelineEntry> rows) {
  rows.sort((a, b) {
    final sa = a.startsAt, sb = b.startsAt;
    if (sa == null && sb == null) return a.id.compareTo(b.id);
    if (sa == null) return 1; // unresolved last
    if (sb == null) return -1;
    final c = sa.compareTo(sb);
    return c != 0 ? c : a.id.compareTo(b.id); // stable
  });
}

// ── Conflict detection ───────────────────────────────────────────────────────

/// Two rows starting at the SAME MINUTE on overlapping channels.
///
/// Today's firing order between them is genuinely indeterminate — two WLED
/// timers in the same minute, or a timer against a cloud fire, have no defined
/// winner (audit §4.4: "last write wins, with no arbiter"). So this FLAGS and
/// does not resolve. Inventing a winner would be the display asserting
/// something the system does not guarantee.
///
/// `channels == null` means "all channels", so it overlaps everything.
List<TimelineEntry> _markConflicts(List<TimelineEntry> rows) {
  final conflicting = <int>{};
  for (var i = 0; i < rows.length; i++) {
    final a = rows[i];
    if (a.startsAt == null) continue;
    for (var j = i + 1; j < rows.length; j++) {
      final b = rows[j];
      if (b.startsAt == null) continue;
      if (!_sameMinute(a.startsAt!, b.startsAt!)) continue;
      if (!_channelsOverlap(a.channels, b.channels)) continue;
      conflicting.add(i);
      conflicting.add(j);
    }
  }
  if (conflicting.isEmpty) return rows;
  return [
    for (var i = 0; i < rows.length; i++)
      conflicting.contains(i) ? rows[i]._copy(conflict: true) : rows[i],
  ];
}

bool _sameMinute(DateTime a, DateTime b) =>
    a.year == b.year &&
    a.month == b.month &&
    a.day == b.day &&
    a.hour == b.hour &&
    a.minute == b.minute;

bool _channelsOverlap(List<int>? a, List<int>? b) {
  if (a == null || b == null) return true; // null = all
  if (a.isEmpty || b.isEmpty) return false; // explicitly none
  return a.toSet().intersection(b.toSet()).isNotEmpty;
}

// ── Derivation: lastWriteWins ────────────────────────────────────────────────

/// TODAY'S TRUTH — the derivation Prompt 4 replaces.
///
/// ⚠️ **THIS FUNCTION AND [_deriveHoldUntilEnd] ARE THE WHOLE PRECEDENCE
/// SURFACE.** When the firing layer changes, this is the one place that
/// changes. Nothing downstream re-derives takeover; the surfaces render what
/// these two return.
///
/// Rule: a row is taken over by the next row that starts strictly later, when
/// this row would otherwise still be running — i.e. it is open-ended, has no
/// stated end, or its end is after that later start. A conflicted row claims no
/// takeover, because we do not know which of the two is running.
List<TimelineEntry> _deriveLastWriteWins(List<TimelineEntry> rows) {
  final out = <TimelineEntry>[];
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    if (row.startsAt == null || row.conflict) {
      out.add(row);
      continue;
    }

    TimelineEntry? successor;
    for (var j = i + 1; j < rows.length; j++) {
      final cand = rows[j];
      if (cand.startsAt == null) continue;
      if (cand.startsAt!.isAfter(row.startsAt!)) {
        successor = cand;
        break;
      }
    }

    if (successor == null) {
      out.add(row);
      continue;
    }

    final stillRunning =
        row.endsAt == null || row.endsAt!.isAfter(successor.startsAt!);
    out.add(stillRunning
        ? row._copy(
            takenOverAt: successor.startsAt,
            takenOverByLabel: successor.label,
          )
        : row);
  }
  return out;
}

// ── Derivation: holdUntilEnd (Policy B — implemented, not selected) ──────────

/// POLICY B. A Game Day holds; base rows inside its window are suppressed.
///
/// ── WHERE THE HOLD ENDS, AND WHY IT IS NOT A `min()` ─────────────────────────
///
/// B says the show ends at "ESPN final or a hard cap, whichever comes first".
/// Only ONE of those is knowable when the display is drawn. The ESPN final
/// arrives asynchronously, server-side, and `estimatedEnd` is a GUESS at it —
/// not a measurement.
///
/// So the hold ends at [TimelineEntry.hardCapAt], and `estimatedEnd` is used
/// ONLY as a fallback when no cap was stored (a legacy row, which carries an
/// inferred estimate and nothing else). Taking `min(cap, estimate)` would end
/// the window at a guessed time and present that as the schedule — which is
/// precisely the fabricated-off-time defect A1 removes. A cap is a CEILING; an
/// estimate is a caption.
///
/// The real final still ends the show earlier than the cap in practice. It does
/// so by firing, not by being predicted here — and when it does, the entry
/// stops being open-ended and this derivation no longer applies to it.
///
/// NOT SELECTED. [kActiveSchedulePrecedence] is `lastWriteWins`. This exists so
/// the flip is a one-constant change with tests already green behind it.
List<TimelineEntry> _deriveHoldUntilEnd(List<TimelineEntry> rows) {
  final holds = <({DateTime start, DateTime end})>[];
  for (final r in rows) {
    if (r.source != TimelineSource.gameDay) continue;
    if (!r.isOpenEnded || r.startsAt == null) continue;
    final end = _holdEndFor(r);
    if (end == null || !end.isAfter(r.startsAt!)) continue;
    holds.add((start: r.startsAt!, end: end));
  }

  final out = <TimelineEntry>[];
  for (final row in rows) {
    if (row.conflict) {
      out.add(row);
      continue;
    }

    if (row.source == TimelineSource.gameDay && row.isOpenEnded) {
      out.add(row._copy(holdsUntil: _holdEndFor(row)));
      continue;
    }

    final start = row.startsAt;
    if (start == null) {
      out.add(row);
      continue;
    }

    // Suppressed when it would begin inside a hold. `!isBefore(start)` so a row
    // starting exactly AT the Game Day's start is suppressed too — under B the
    // Game Day owns the window from its first instant.
    ({DateTime start, DateTime end})? covering;
    for (final h in holds) {
      if (!start.isBefore(h.start) && start.isBefore(h.end)) {
        covering = h;
        break;
      }
    }
    out.add(covering == null
        ? row
        : row._copy(suppressed: true, suppressedUntil: covering.end));
  }
  return out;
}

/// Where an open-ended row's Policy-B hold ends.
///
/// The cap, always, when there is one. `estimatedEnd` is the fallback for a
/// legacy row that carries an inferred estimate and no cap — without it such a
/// row would have an unbounded window and suppress the rest of the night.
DateTime? _holdEndFor(TimelineEntry row) => row.hardCapAt ?? row.estimatedEnd;
