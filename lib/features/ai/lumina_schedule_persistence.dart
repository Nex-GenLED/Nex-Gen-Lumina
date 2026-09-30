import 'package:flutter/material.dart';

import 'package:nexgen_command/features/ai/lumina_schedule_flags.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/utils/sun_utils.dart';

// +110 package E2, item 4 / audit row 7 — the multi-night plan PERSISTS.
//
// The foundation revived the schedule branch: night 1 is applied and the
// reply says "I've scheduled N nights", but nights 2 onward went to the
// in-memory autopilot scheduler only — lost when the app closed, never in
// the Schedule tab, never armed on the controller.
//
// Each night is now a DATED calendar entry (`CalendarEntry`), keyed by date,
// with a clock on/off time. The calendar's lease manager arms the ones inside
// its window on the controller and the Schedule tab lists them. What could
// not be persisted is said plainly, never claimed.
//
// +110 E2 follow-up D2 — the entries are the CUSTOMER'S (type `user`,
// `autopilot: true`, source `lumina_ai`): they asked for these nights, so the
// Schedule tab shows "You" / "AI-Generated", Edit opens the ordinary editor,
// and the night composer treats them as user-authored. And Lumina never
// overwrites: a night whose date already holds a Game Day entry, an armed
// lease, or a user-authored entry is skipped and named in the reply
// ([planLuminaNightWrites]); a night the controller's timer pool cannot fit
// is dropped and counted ([ScheduleNightsOutcome.unfitted]). The customer is
// never asked mid-conversation.

/// Provenance tag on entries this module writes.
const String kLuminaAiSourceTag = 'lumina_ai';

/// What persisting a plan achieved.
class ScheduleNightsOutcome {
  const ScheduleNightsOutcome({
    required this.requested,
    required this.persisted,
    this.message,
    this.saved = const [],
    this.skipped = const [],
    this.unfitted = 0,
  });

  /// Nights the plan asked for.
  final int requested;

  /// Nights that were written and confirmed.
  final int persisted;

  /// Why some (or all) nights were not persisted. Customer-readable.
  final String? message;

  /// Indexes (into the plan's nights) that were written. Empty when the
  /// caller did not track them; [composeScheduleReply] then treats the first
  /// [persisted] nights as the saved ones.
  final List<int> saved;

  /// One customer-readable sentence per night skipped because its date was
  /// already taken (D2). Never claimed as saved.
  final List<String> skipped;

  /// Nights dropped because the controller's timer pool was full (D2).
  final int unfitted;

  bool get all => requested > 0 && persisted == requested;
  bool get none => persisted == 0;

  /// Nothing to persist: a one-night plan is the live apply itself.
  static const ScheduleNightsOutcome nothingToPersist =
      ScheduleNightsOutcome(requested: 1, persisted: 1);
}

/// One night of a plan, translated for the calendar. [onTime]/[offTime] are
/// null when the plan's trigger cannot be turned into a clock time.
class PlannedNight {
  const PlannedNight({
    required this.index,
    required this.date,
    required this.patternName,
    required this.effectName,
    required this.wled,
    required this.onTime,
    required this.offTime,
    required this.color,
    required this.brightnessPercent,
  });

  final int index;
  final DateTime date;
  final String patternName;
  final String effectName;
  final Map<String, dynamic> wled;
  final String? onTime;
  final String? offTime;
  final Color? color;
  final int brightnessPercent;

  String get dateKey => '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  bool get hasClockTimes => onTime != null && offTime != null;

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// "Tue", for the reply.
  String get dayLabel => _days[(date.weekday - 1).clamp(0, 6)];

  /// "Tue — Running", for the reply.
  String get summary => '$dayLabel — $effectName';
}

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Resolves the plan's trigger names to clock times for [date]. Sun times
/// come from the account's coordinates when it has them, else from the same
/// fixed fallbacks the autopilot scheduler uses (sunset 20:00, dusk 20:30,
/// sunrise 06:00, dawn 05:30). A `specificTime` trigger carries no hours on
/// the plan, so it cannot be resolved here.
({String? on, String? off}) resolveNightClock({
  required String startTrigger,
  required String endTrigger,
  required DateTime date,
  double? latitude,
  double? longitude,
}) {
  DateTime? sunsetOf(DateTime d) => latitude != null && longitude != null
      ? SunUtils.sunsetLocal(latitude, longitude, d)
      : null;
  DateTime? sunriseOf(DateTime d) => latitude != null && longitude != null
      ? SunUtils.sunriseLocal(latitude, longitude, d)
      : null;

  String? on;
  switch (startTrigger.toLowerCase()) {
    case 'sunset':
      final s = sunsetOf(date);
      on = s == null ? '20:00' : _hhmm(s);
    case 'dusk':
      final s = sunsetOf(date);
      on = s == null ? '20:30' : _hhmm(s.add(const Duration(minutes: 30)));
    case 'sunrise':
      final s = sunriseOf(date);
      on = s == null ? '06:00' : _hhmm(s);
    case 'dawn':
      on = '05:30';
    case 'allday':
      on = '00:00';
    default:
      on = null;
  }

  String? off;
  final nextDay = date.add(const Duration(days: 1));
  switch (endTrigger.toLowerCase()) {
    case 'sunrise':
      final s = sunriseOf(nextDay);
      off = s == null ? '06:00' : _hhmm(s);
    case 'dawn':
      off = '05:30';
    case 'sunset':
      final s = sunsetOf(date);
      off = s == null ? '20:00' : _hhmm(s);
    case 'dusk':
      off = '20:30';
    case 'allday':
      off = '23:59';
    default:
      off = null;
  }
  return (on: on, off: off);
}

/// The plan's nights, in order. Nights with no date are dropped. Pure.
List<PlannedNight> plannedNightsOf(
  LuminaScheduleFlags flags, {
  double? latitude,
  double? longitude,
}) {
  final out = <PlannedNight>[];
  final startDefault = flags.raw['startTrigger'] as String? ?? 'sunset';
  final endDefault = flags.raw['endTrigger'] as String? ?? 'sunrise';
  for (var i = 0; i < flags.schedule.length; i++) {
    final entry = flags.schedule[i];
    final dateStr = entry['date'];
    final date = dateStr is String ? DateTime.tryParse(dateStr) : null;
    if (date == null) continue;
    final wledRaw = entry['wled'];
    final wled = wledRaw is Map
        ? Map<String, dynamic>.from(wledRaw)
        : const <String, dynamic>{};
    final effectName = entry['effectName'] as String? ?? 'Effect';
    final patternName = entry['patternName'] as String? ??
        flags.patternName ??
        'Lumina $effectName';
    final clock = resolveNightClock(
      startTrigger: entry['startTrigger'] as String? ?? startDefault,
      endTrigger: entry['endTrigger'] as String? ?? endDefault,
      date: date,
      latitude: latitude,
      longitude: longitude,
    );
    Color? color;
    final colors = entry['colors'];
    if (colors is List && colors.isNotEmpty && colors.first is Map) {
      final rgb = (colors.first as Map)['rgb'];
      if (rgb is List && rgb.length >= 3) {
        color = Color.fromARGB(255, (rgb[0] as num).toInt(),
            (rgb[1] as num).toInt(), (rgb[2] as num).toInt());
      }
    }
    final bri = wled['bri'];
    final briPercent =
        bri is num ? (bri / 255 * 100).round().clamp(1, 100) : 100;
    out.add(PlannedNight(
      index: i,
      date: DateTime(date.year, date.month, date.day),
      patternName: patternName,
      effectName: effectName,
      wled: wled,
      onTime: clock.on,
      offTime: clock.off,
      color: color,
      brightnessPercent: briPercent,
    ));
  }
  return out;
}

/// The calendar entry for [night]. Null when it has no clock times.
///
/// D2: the customer asked for this night, so it is THEIRS — `type: user`
/// (Schedule tab "You", ordinary editor, user tier in the composer) with
/// `autopilot: true` ("AI-Generated") and the `lumina_ai` source tag.
CalendarEntry? calendarEntryForNight(PlannedNight night, {required String batchId}) {
  if (!night.hasClockTimes) return null;
  return CalendarEntry(
    entryId: 'lumina_${batchId}_${night.index}',
    dateKey: night.dateKey,
    patternName: night.patternName,
    color: night.color,
    onTime: night.onTime,
    offTime: night.offTime,
    brightness: night.brightnessPercent,
    type: CalendarEntryType.user,
    autopilot: true,
    sourceTag: kLuminaAiSourceTag,
    note: 'Lumina: ${night.effectName}',
  );
}

// ── D2 — never overwrite ────────────────────────────────────────────────────

/// Why a planned night was not written.
enum LuminaNightSkipReason {
  /// The date already holds a Game Day entry: the game has that night.
  gameDay,

  /// The date already holds a lease (a timer armed on the controller).
  armed,

  /// The date already holds a user-authored entry (the A3 overwrite guard).
  userEntry,
}

/// A night that was skipped, with the sentence the reply says about it.
class SkippedNight {
  const SkippedNight({
    required this.night,
    required this.reason,
    required this.reply,
  });

  final PlannedNight night;
  final LuminaNightSkipReason reason;

  /// Customer-readable, e.g. "Skipped Sun — the Chiefs game already has that
  /// night."
  final String reply;
}

/// A night and the entry that will be written for it.
class LuminaNightWrite {
  const LuminaNightWrite(this.night, this.entry);
  final PlannedNight night;
  final CalendarEntry entry;
}

/// What [planLuminaNightWrites] decided.
class LuminaNightWritePlan {
  const LuminaNightWritePlan({
    required this.writes,
    required this.skipped,
    required this.noClock,
  });

  final List<LuminaNightWrite> writes;
  final List<SkippedNight> skipped;

  /// Nights with no usable clock time (not written, not "skipped").
  final int noClock;

  List<CalendarEntry> get entries => [for (final w in writes) w.entry];
  List<String> get skipReplies => [for (final s in skipped) s.reply];
}

/// True for an entry projected from Game Day autopilot.
bool isGameDayEntry(CalendarEntry e) =>
    e.sourceTag == CalendarEntrySourceTag.gameDay ||
    e.sourceTag == CalendarEntrySourceTag.gameDayGroup;

/// The team a Game Day entry is for, read from the note the Game Day
/// service writes ("TEAM vs OPPONENT — Game Day autopilot"). Null when the
/// note has no such shape.
String? gameDayTeamNameOf(CalendarEntry e) {
  final note = e.note;
  if (note == null) return null;
  for (final sep in const [' vs ', ' @ ']) {
    final i = note.indexOf(sep);
    if (i > 0) return note.substring(0, i).trim();
  }
  return null;
}

/// Pure (D2): decides, night by night, what to write and what to skip.
///
///  * a date with a Game Day entry → skipped ("the TEAM game already has
///    that night");
///  * a date in [leasedDateKeys] (a timer already armed on the controller)
///    → skipped;
///  * a date with a user-authored entry → skipped, honouring the A3 overwrite
///    guard without asking mid-conversation;
///  * a night with no clock time → counted in [LuminaNightWritePlan.noClock].
///
/// Holidays and other generated entries do not block a night: the calendar
/// holds several entries per date and replacing nothing loses nothing.
LuminaNightWritePlan planLuminaNightWrites({
  required List<PlannedNight> nights,
  required String batchId,
  required List<CalendarEntry> Function(String dateKey) existingOn,
  Set<String> leasedDateKeys = const {},
}) {
  final writes = <LuminaNightWrite>[];
  final skipped = <SkippedNight>[];
  var noClock = 0;

  for (final night in nights) {
    final entry = calendarEntryForNight(night, batchId: batchId);
    if (entry == null) {
      noClock++;
      continue;
    }
    final existing = existingOn(night.dateKey);

    CalendarEntry? gameDay;
    CalendarEntry? mine;
    for (final e in existing) {
      if (gameDay == null && isGameDayEntry(e)) gameDay = e;
      if (mine == null && e.type == CalendarEntryType.user) mine = e;
    }

    if (gameDay != null) {
      final team = gameDayTeamNameOf(gameDay);
      skipped.add(SkippedNight(
        night: night,
        reason: LuminaNightSkipReason.gameDay,
        reply: 'Skipped ${night.dayLabel} — '
            '${team == null ? 'a Game Day' : 'the $team game'} already has '
            'that night.',
      ));
      continue;
    }
    if (leasedDateKeys.contains(night.dateKey)) {
      skipped.add(SkippedNight(
        night: night,
        reason: LuminaNightSkipReason.armed,
        reply: 'Skipped ${night.dayLabel} — that night is already set on '
            'your controller.',
      ));
      continue;
    }
    if (mine != null) {
      skipped.add(SkippedNight(
        night: night,
        reason: LuminaNightSkipReason.userEntry,
        reply: 'Skipped ${night.dayLabel} — you already have '
            '"${mine.patternName}" that night. Delete it in Schedule first '
            'if you want this instead.',
      ));
      continue;
    }
    writes.add(LuminaNightWrite(night, entry));
  }

  return LuminaNightWritePlan(writes: writes, skipped: skipped, noClock: noClock);
}

/// The reply for a plan, from what actually happened. Pure.
///
///  * [appliedOk] — whether tonight's look reached the lights (null when the
///    plan had no payload for tonight);
///  * [applyMessage] — why not, in the customer's words;
///  * [nights] — the plan's nights, for the per-night summary;
///  * [outcome] — what was persisted, skipped and dropped.
String composeScheduleReply({
  required String themeName,
  required bool? appliedOk,
  String? applyMessage,
  required List<PlannedNight> nights,
  required ScheduleNightsOutcome outcome,
}) {
  final requested = nights.length;
  final tonight = appliedOk == null
      ? null
      : appliedOk
          ? "Tonight's $themeName look is on your lights now."
          : "I couldn't put tonight's $themeName look on your lights"
              '${applyMessage == null ? '.' : ' — $applyMessage'}';

  if (requested <= 1) {
    return tonight ?? 'That plan is for tonight only.';
  }

  final others = requested - 1;

  // Which of the OTHER nights (after tonight) were saved.
  final Set<int> savedIdx = outcome.saved.isNotEmpty
      ? outcome.saved.toSet()
      : {
          for (var i = 0; i < outcome.persisted && i < nights.length; i++)
            nights[i].index,
        };
  final savedOthers = [
    for (final n in nights.skip(1))
      if (savedIdx.contains(n.index)) n,
  ];
  final list = savedOthers.map((n) => n.summary).join(', ');

  final parts = <String>[];
  if (savedOthers.length >= others) {
    parts.add('The other $others ${others == 1 ? 'night is' : 'nights are'} '
        'in your Schedule: $list.');
  } else if (savedOthers.isEmpty) {
    if (outcome.skipped.isEmpty && outcome.unfitted == 0) {
      parts.add('Only tonight was applied — I couldn\'t save the other '
          '$others ${others == 1 ? 'night' : 'nights'}'
          '${outcome.message == null ? '.' : ': ${outcome.message}'} '
          "They won't run on their own.");
    } else {
      parts.add('Only tonight was applied — none of the other $others '
          '${others == 1 ? 'night' : 'nights'} could be saved'
          '${outcome.message == null ? '.' : ': ${outcome.message}'}');
    }
  } else {
    parts.add('I saved ${savedOthers.length} of the other $others nights to '
        'your Schedule: $list'
        '${outcome.message == null ? '.' : ' — ${outcome.message}'}');
  }
  parts.addAll(outcome.skipped);
  if (outcome.unfitted > 0) {
    parts.add("I couldn't fit ${outcome.unfitted} "
        '${outcome.unfitted == 1 ? 'night' : 'nights'} — your schedule is '
        'full.');
  }
  final rest = parts.join(' ');
  return tonight == null ? rest : '$tonight $rest';
}
