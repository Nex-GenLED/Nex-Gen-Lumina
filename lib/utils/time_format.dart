import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';

/// Valid values for [UserModel.timeFormat].
const String kTimeFormat12h = '12h';
const String kTimeFormat24h = '24h';
const String kTimeFormatDefault = kTimeFormat12h;

String _normalizeTimeFormat(String? value) {
  return value == kTimeFormat24h ? kTimeFormat24h : kTimeFormat12h;
}

/// Format a [DateTime] for display, respecting the user's time format pref.
///
/// Always converts to local time first so callers don't need to remember
/// `.toLocal()` for UTC-origin values (e.g. ESPN game times parsed from
/// ISO8601 with a `Z` suffix, or Firestore Timestamps).
String formatTime(DateTime dt, {String timeFormat = kTimeFormatDefault}) {
  final local = dt.toLocal();
  final fmt = _normalizeTimeFormat(timeFormat);
  final minute = local.minute.toString().padLeft(2, '0');
  if (fmt == kTimeFormat24h) {
    final hour = local.hour.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
  final rawHour = local.hour;
  final hour = rawHour % 12 == 0 ? 12 : rawHour % 12;
  final period = rawHour < 12 ? 'AM' : 'PM';
  return '$hour:$minute $period';
}

/// Format a [TimeOfDay] respecting the user's time format pref.
String formatTimeOfDay(TimeOfDay t, {String timeFormat = kTimeFormatDefault}) {
  final fmt = _normalizeTimeFormat(timeFormat);
  final minute = t.minute.toString().padLeft(2, '0');
  if (fmt == kTimeFormat24h) {
    final hour = t.hour.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
  final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
  final period = t.period == DayPeriod.am ? 'AM' : 'PM';
  return '$h:$minute $period';
}

/// Format a heterogeneous time label string in the user's preferred format.
///
/// Accepts any of:
///   * 24-hour `"HH:mm"` (e.g. `"19:30"`) — wire format used by CalendarEntry
///   * 12-hour `"h:mm AM/PM"` (e.g. `"7:30 PM"`) — display label format used
///     by ScheduleItem.timeLabel
///   * Tokens such as `"Sunset"` / `"Sunrise"` — passed through normalized to
///     title-case
///
/// Unparseable input is returned unchanged. `null`/empty returns the empty
/// string. Use this at display sites where the source label could be in any
/// of the above forms (e.g. CalendarEntry.onTime falling back to
/// ScheduleItem.timeLabel).
String formatTimeLabel(String? label, {String timeFormat = kTimeFormatDefault}) {
  if (label == null) return '';
  final trimmed = label.trim();
  if (trimmed.isEmpty) return '';

  // Solar tokens — return title-cased pass-through.
  final lower = trimmed.toLowerCase();
  if (lower == 'sunset' || lower == 'sunrise') {
    return '${trimmed[0].toUpperCase()}${lower.substring(1)}';
  }

  // 12-hour with AM/PM suffix — parse and re-format.
  final twelve = RegExp(
    r'^(\d{1,2}):(\d{2})\s*(am|pm)$',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (twelve != null) {
    var h = int.parse(twelve.group(1)!);
    final m = int.parse(twelve.group(2)!);
    final isPm = twelve.group(3)!.toUpperCase() == 'PM';
    if (h == 12) h = 0;
    if (isPm) h += 12;
    if (h >= 0 && h <= 23 && m >= 0 && m <= 59) {
      return formatTimeOfDay(TimeOfDay(hour: h, minute: m), timeFormat: timeFormat);
    }
  }

  // 24-hour HH:mm — parse and re-format.
  final twentyFour = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(trimmed);
  if (twentyFour != null) {
    final h = int.parse(twentyFour.group(1)!);
    final m = int.parse(twentyFour.group(2)!);
    if (h >= 0 && h <= 23 && m >= 0 && m <= 59) {
      return formatTimeOfDay(TimeOfDay(hour: h, minute: m), timeFormat: timeFormat);
    }
  }

  // Unrecognized — pass through.
  return label;
}

/// Render a schedule's on/off window for display.
///
/// When [offLabel] is present and non-empty, BOTH boundaries are shown with an
/// explicit "off at" so the sunrise/evening OFF that turns the lights off is
/// never silent:
///   "Sunset → off at Sunrise"  ·  "7:00 PM → off at 11:00 PM"
/// When there is no off boundary, only the ON time is shown. Solar tokens
/// render as their word (Sunrise/Sunset) via [formatTimeLabel].
///
/// This is the single source of truth for the "X → off at Y" phrasing so no
/// schedule surface can display an ON boundary while hiding its OFF.
String formatScheduleWindow(
  String? onLabel,
  String? offLabel, {
  String timeFormat = kTimeFormatDefault,
}) {
  final on = formatTimeLabel(onLabel, timeFormat: timeFormat);
  final hasOff = offLabel != null && offLabel.trim().isNotEmpty;
  if (!hasOff) return on;
  final off = formatTimeLabel(offLabel, timeFormat: timeFormat);
  return '$on → off at $off';
}

/// +126 (g) — one plain-words line for the schedule editor, built from the
/// wheel values: "Lights on at 5:00 PM, off at 6:00 AM the next morning."
///
/// [onLabel] / [offLabel] are the labels the editor would save (a clock time
/// in either format, or `Sunrise` / `Sunset`). [offNextDay] is the firing
/// side's own answer (`offFallsNextDay`), so the sentence and the timers can
/// never disagree about which day the lights go off. The part-of-day word
/// follows the OFF time: before noon "morning", noon to 5 PM "afternoon",
/// later "evening"; a same-day off says "this …", an overnight off says
/// "the next …". No off time: the lights stay on until turned off.
String scheduleWindowSentence({
  required String onLabel,
  String? offLabel,
  required bool offNextDay,
  String timeFormat = kTimeFormatDefault,
}) {
  final on = _sentenceTime(onLabel, timeFormat: timeFormat);
  final hasOff = offLabel != null && offLabel.trim().isNotEmpty;
  if (!hasOff) {
    return 'Lights on at $on and they stay on until you turn them off.';
  }
  final off = _sentenceTime(offLabel, timeFormat: timeFormat);
  final part = _partOfDay(offLabel);
  final when = offNextDay ? 'the next $part' : 'this $part';
  return 'Lights on at $on, off at $off $when.';
}

/// A label as it reads inside a sentence: clock times in the user's format,
/// solar words in lower case ("at sunset", never "at Sunset").
String _sentenceTime(String label, {required String timeFormat}) {
  final lower = label.trim().toLowerCase();
  if (lower == 'sunset' || lower == 'sunrise') return lower;
  return formatTimeLabel(label, timeFormat: timeFormat);
}

/// "morning" / "afternoon" / "evening" for an OFF label. Sunrise is a
/// morning, sunset an evening; a clock time goes by its hour; anything
/// unreadable is called a day ("this day" never renders in practice because
/// the editor only hands over labels it built itself).
String _partOfDay(String label) {
  final lower = label.trim().toLowerCase();
  if (lower == 'sunrise') return 'morning';
  if (lower == 'sunset') return 'evening';
  final t = _clockHour(lower);
  if (t == null) return 'day';
  if (t < 12) return 'morning';
  if (t < 17) return 'afternoon';
  return 'evening';
}

/// The 0–23 hour a clock label names (either format), or null.
int? _clockHour(String lower) {
  final twelve = RegExp(r'^(\d{1,2}):(\d{2})\s*(am|pm)$').firstMatch(lower);
  if (twelve != null) {
    var h = int.parse(twelve.group(1)!);
    if (h < 1 || h > 12) return null;
    if (h == 12) h = 0;
    if (twelve.group(3) == 'pm') h += 12;
    return h;
  }
  final twentyFour = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(lower);
  if (twentyFour != null) {
    final h = int.parse(twentyFour.group(1)!);
    return h <= 23 ? h : null;
  }
  return null;
}

/// Exposes the current user's [UserModel.timeFormat] preference.
/// Falls back to 12-hour when the profile is unloaded or unset.
final timeFormatPreferenceProvider = Provider<String>((ref) {
  final profile = ref.watch(currentUserProfileProvider);
  return _normalizeTimeFormat(profile.valueOrNull?.timeFormat);
});
