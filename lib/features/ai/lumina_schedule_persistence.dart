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
// Each night is now a DATED calendar entry (`CalendarEntry`), the same shape
// the Game Day planner writes, keyed by date, with a clock on/off time. The
// calendar's lease manager arms the ones inside its window on the controller
// and the Schedule tab lists them. What could not be persisted is said
// plainly, never claimed.

/// Provenance tag on entries this module writes.
const String kLuminaAiSourceTag = 'lumina_ai';

/// What persisting a plan achieved.
class ScheduleNightsOutcome {
  const ScheduleNightsOutcome({
    required this.requested,
    required this.persisted,
    this.message,
  });

  /// Nights the plan asked for.
  final int requested;

  /// Nights that were written and confirmed.
  final int persisted;

  /// Why some (or all) nights were not persisted. Customer-readable.
  final String? message;

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

  /// "Tue — Running", for the reply.
  String get summary {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[(date.weekday - 1).clamp(0, 6)]} — $effectName';
  }
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
    type: CalendarEntryType.autopilot,
    autopilot: true,
    sourceTag: kLuminaAiSourceTag,
    note: 'Lumina: ${night.effectName}',
  );
}

/// The reply for a plan, from what actually happened. Pure.
///
///  * [appliedOk] — whether tonight's look reached the lights (null when the
///    plan had no payload for tonight);
///  * [applyMessage] — why not, in the customer's words;
///  * [nights] — the plan's nights, for the per-night summary;
///  * [outcome] — what was persisted.
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
  final otherNights = nights.skip(1).map((n) => n.summary).join(', ');
  final String rest;
  if (outcome.persisted >= requested) {
    rest = 'The other $others ${others == 1 ? 'night is' : 'nights are'} '
        'in your Schedule: $otherNights.';
  } else if (outcome.persisted <= 0) {
    rest = 'Only tonight was applied — I couldn\'t save the other $others '
        '${others == 1 ? 'night' : 'nights'}'
        '${outcome.message == null ? '.' : ': ${outcome.message}'} '
        "They won't run on their own.";
  } else {
    final saved = (outcome.persisted - 1).clamp(0, others);
    rest = 'I saved $saved of the other $others nights to your Schedule'
        '${outcome.message == null ? '.' : ' — ${outcome.message}'}';
  }
  return tonight == null ? rest : '$tonight $rest';
}
