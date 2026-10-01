// lib/features/schedule/dated_entry_compose.dart
//
// +112 (#124) — the pure half of "Just this day": how the "+" editor's state
// becomes ONE dated CalendarEntry, how a solar trigger becomes that date's
// clock time, and the one place recurring rows get their copy.
//
// PURE. No Riverpod, no Firestore, no widgets — unit-tested directly.

import 'package:flutter/material.dart';

import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/utils/sun_utils.dart';

/// A resolved clock time for a dated entry, and whether it came from the sun.
class DatedClock {
  const DatedClock({
    required this.hhmm,
    required this.fromSolar,
    required this.solarResolved,
  });

  /// 'HH:mm', 24-hour — what [CalendarEntry.onTime] / [offTime] store.
  final String hhmm;

  /// The trigger was Sunset / Sunrise.
  final bool fromSolar;

  /// True when the sun time was computed from the account's coordinates;
  /// false when [fromSolar] but no coordinates were available and a default
  /// stood in. The UI says so.
  final bool solarResolved;
}

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Resolve a trigger for ONE date.
///
/// [trigger] is `'HH:mm'` (24-hour), a [TimeOfDay] rendered through
/// [clockFromTimeOfDay], or the literal `'Sunset'` / `'Sunrise'`. A dated
/// entry cannot carry a solar boundary — WLED's per-date timer takes an hour
/// and a minute — so a solar trigger is resolved to THAT date's sun time from
/// the account's coordinates. An end-of-night sunrise belongs to the next
/// morning, so [isEnd] with `'Sunrise'` resolves on [date] + 1 day.
///
/// With no coordinates the pre-112 defaults stand in (sunset 20:00, sunrise
/// 06:00) and [DatedClock.solarResolved] is false so the editor can say
/// "set your home address for the exact time".
DatedClock resolveDatedClock({
  required String trigger,
  required DateTime date,
  required bool isEnd,
  double? latitude,
  double? longitude,
}) {
  final lower = trigger.trim().toLowerCase();
  final hasCoords = latitude != null && longitude != null;
  if (lower == 'sunset') {
    final s = hasCoords ? SunUtils.sunsetLocal(latitude, longitude, date) : null;
    return DatedClock(
        hhmm: s == null ? '20:00' : _hhmm(s), fromSolar: true, solarResolved: s != null);
  }
  if (lower == 'sunrise') {
    final day = isEnd ? date.add(const Duration(days: 1)) : date;
    final s = hasCoords ? SunUtils.sunriseLocal(latitude, longitude, day) : null;
    return DatedClock(
        hhmm: s == null ? '06:00' : _hhmm(s), fromSolar: true, solarResolved: s != null);
  }
  // A 12-hour label ("7:00 PM") from an older intent or a stored schedule
  // row becomes 24-hour; anything else passes through untouched.
  final m = RegExp(r'^(\d{1,2}):(\d{2})\s*([ap]m)$', caseSensitive: false)
      .firstMatch(trigger.trim());
  if (m != null) {
    var h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    final pm = m.group(3)!.toLowerCase() == 'pm';
    if (pm && h != 12) h += 12;
    if (!pm && h == 12) h = 0;
    return DatedClock(
      hhmm: '${h.clamp(0, 23).toString().padLeft(2, '0')}:'
          '${min.clamp(0, 59).toString().padLeft(2, '0')}',
      fromSolar: false,
      solarResolved: true,
    );
  }
  return DatedClock(hhmm: trigger.trim(), fromSolar: false, solarResolved: true);
}

/// `TimeOfDay` → `'HH:mm'`.
String clockFromTimeOfDay(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// `'YYYY-MM-DD'` for [d].
String dateKeyOf(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// The first colour of a WLED payload's first segment, or null.
Color? firstColorOfPayload(Map<String, dynamic>? payload) {
  final seg = payload?['seg'];
  if (seg is! List || seg.isEmpty) return null;
  final first = seg.first;
  if (first is! Map) return null;
  final col = first['col'];
  if (col is! List || col.isEmpty) return null;
  final c = col.first;
  if (c is! List || c.length < 3) return null;
  int ch(dynamic v) => (v is num ? v.toInt() : 0).clamp(0, 255);
  return Color.fromARGB(255, ch(c[0]), ch(c[1]), ch(c[2]));
}

/// What a single-night entry does when it fires.
enum DatedAction { runPattern, powerOff, brightness }

/// Build the dated entry the "+" editor writes for "Just this day".
///
/// The entry is the customer's own: `type user`, `autopilot false`,
/// `sourceTag null` (the user contract, `CalendarEntrySourceTag`). A pattern
/// carries its full payload so the lease fires the real look; a brightness
/// action fires white at that level; Off fires dark.
CalendarEntry composeDatedEntry({
  required DateTime date,
  required DatedAction action,
  required String onHhmm,
  required String? offHhmm,
  String? patternName,
  Map<String, dynamic>? patternPayload,
  int brightnessPercent = 100,
  List<int>? channels,
  String? controllerId,
}) {
  switch (action) {
    case DatedAction.powerOff:
      return CalendarEntry(
        dateKey: dateKeyOf(date),
        patternName: 'Off',
        color: null,
        onTime: onHhmm,
        offTime: offHhmm,
        brightness: 0,
        type: CalendarEntryType.user,
        autopilot: false,
        channels: channels,
        controllerId: controllerId,
      );
    case DatedAction.brightness:
      return CalendarEntry(
        dateKey: dateKeyOf(date),
        patternName: 'Brightness ${brightnessPercent.clamp(1, 100)}%',
        color: const Color(0xFFFFFFFF),
        onTime: onHhmm,
        offTime: offHhmm,
        brightness: brightnessPercent.clamp(1, 100),
        type: CalendarEntryType.user,
        autopilot: false,
        channels: channels,
        controllerId: controllerId,
      );
    case DatedAction.runPattern:
      final payloadBri = patternPayload?['bri'];
      final bri = payloadBri is num
          ? (payloadBri / 255 * 100).round().clamp(1, 100)
          : brightnessPercent.clamp(1, 100);
      return CalendarEntry(
        dateKey: dateKeyOf(date),
        patternName: (patternName == null || patternName.trim().isEmpty)
            ? 'Custom'
            : patternName.trim(),
        color: firstColorOfPayload(patternPayload) ?? const Color(0xFFFFFFFF),
        onTime: onHhmm,
        offTime: offHhmm,
        brightness: bri,
        type: CalendarEntryType.user,
        autopilot: false,
        wledPayload: patternPayload,
        channels: channels,
        controllerId: controllerId,
      );
  }
}

const List<String> _kDayOrder = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const Map<String, String> _kDayFull = {
  'Mon': 'Monday',
  'Tue': 'Tuesday',
  'Wed': 'Wednesday',
  'Thu': 'Thursday',
  'Fri': 'Friday',
  'Sat': 'Saturday',
  'Sun': 'Sunday',
};

/// Plain-words recurrence for a recurring row — "Repeats every Tuesday",
/// "Repeats every day", "Repeats on weekdays", "Repeats Mon, Wed, Fri".
/// Tolerates the stored forms ('Daily', lower case, full names).
String recurrenceCopy(List<String> repeatDays) {
  final days = <String>{};
  for (final raw in repeatDays) {
    final s = raw.trim().toLowerCase();
    if (s.contains('daily') || s == 'every day') {
      days.addAll(_kDayOrder);
      continue;
    }
    final short = s.length >= 3 ? s.substring(0, 3) : s;
    for (final d in _kDayOrder) {
      if (d.toLowerCase() == short) days.add(d);
    }
  }
  if (days.isEmpty) return 'No repeat days set';
  if (days.length == 7) return 'Repeats every day';
  const weekdays = {'Mon', 'Tue', 'Wed', 'Thu', 'Fri'};
  const weekend = {'Sat', 'Sun'};
  if (days.length == 5 && days.containsAll(weekdays)) return 'Repeats on weekdays';
  if (days.length == 2 && days.containsAll(weekend)) return 'Repeats on weekends';
  if (days.length == 1) return 'Repeats every ${_kDayFull[days.first]}';
  final ordered = _kDayOrder.where(days.contains).join(', ');
  return 'Repeats $ordered';
}

const List<String> _kMonthShort = [
  '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "Sunday, Oct 4, 2026".
String formatDatedDate(DateTime d) {
  final weekday = _kDayFull[_kDayOrder[(d.weekday - 1).clamp(0, 6)]]!;
  return '$weekday, ${_kMonthShort[d.month]} ${d.day}, ${d.year}';
}

/// "6:58 PM" from 'HH:mm'.
String friendlyClock(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length != 2) return hhmm;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return hhmm;
  final period = h >= 12 ? 'PM' : 'AM';
  final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
  return '$h12:${m.toString().padLeft(2, '0')} $period';
}
