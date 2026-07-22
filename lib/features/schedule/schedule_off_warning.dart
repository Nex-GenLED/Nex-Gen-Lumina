import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/utils/time_format.dart';

/// Manual-apply awareness for the silent sunrise/evening OFF boundary.
///
/// Context: autopilot's baseline "Warm White (Daily evening lighting)" schedule
/// (and any user schedule with an off boundary) turns the lights OFF at its
/// off time — for solar schedules, at Sunrise. A user who manually applies a
/// pattern at night has no way to know a schedule will kill it hours later.
/// The [ScheduleSyncService] boundary invariant guarantees the OFF fires
/// regardless of the currently-applied design, so this is awareness only — it
/// never suppresses the boundary and never blocks.

/// How far ahead an OFF boundary must fall for a manual apply to warn about it.
/// Tunable. Chosen so applying at night surfaces the coming sunrise-OFF, but
/// applying in the morning (whose next OFF is ~a day away) stays quiet.
const Duration kManualApplyOffWarningWindow = Duration(hours: 18);

/// Coarse local hours used ONLY to estimate when a solar OFF boundary falls,
/// for the in-window decision. The app may not know the controller's exact
/// solar calc, so these are deliberately approximate — the surfaced message
/// always renders the solar WORD (Sunrise/Sunset), never a resolved clock time.
const int kApproxSunriseHour = 6;
const int kApproxSunsetHour = 19;

/// A pending OFF boundary worth warning the user about after a manual apply.
class ScheduleOffNotice {
  /// Friendly schedule name, e.g. "Warm White".
  final String scheduleName;

  /// Display label for the OFF boundary — a solar word ("Sunrise") or a
  /// formatted clock time ("11:00 PM").
  final String offLabel;

  const ScheduleOffNotice({required this.scheduleName, required this.offLabel});
}

/// Returns the soonest ENABLED schedule OFF boundary that falls within [window]
/// of [now], or null when none qualifies. Disabled schedules, schedules with no
/// off boundary, and off boundaries outside the window are all ignored.
///
/// Pure and deterministic — no geo/provider/IO. Solar OFF boundaries are
/// estimated with [kApproxSunriseHour]/[kApproxSunsetHour] for the in-window
/// test; the returned [ScheduleOffNotice.offLabel] still renders the solar word
/// via [formatTimeLabel].
ScheduleOffNotice? nextEnabledOffBoundaryWithin(
  List<ScheduleItem> schedules,
  DateTime now, {
  Duration window = kManualApplyOffWarningWindow,
  String timeFormat = kTimeFormatDefault,
}) {
  DateTime? bestWhen;
  ScheduleItem? best;
  for (final s in schedules) {
    if (!s.enabled) continue;
    if (!s.hasOffTime || s.offTimeLabel == null) continue;
    final tod = _offTimeOfDay(s.offTimeLabel!);
    if (tod == null) continue; // unparseable off — can't estimate a window
    final when = _nextOccurrence(now, s.repeatDays, tod.$1, tod.$2, window);
    if (when == null) continue;
    if (bestWhen == null || when.isBefore(bestWhen)) {
      bestWhen = when;
      best = s;
    }
  }
  if (best == null) return null;
  return ScheduleOffNotice(
    scheduleName: scheduleDisplayName(best),
    offLabel: formatTimeLabel(best.offTimeLabel, timeFormat: timeFormat),
  );
}

/// The soonest DateTime strictly after [now], on a day the schedule repeats, at
/// [hour]:[minute] — but only when it falls within [window]. Returns null when
/// the soonest such occurrence is beyond the window (the caller then leaves the
/// user unwarned — their manual apply survives well past the horizon).
DateTime? _nextOccurrence(
  DateTime now,
  List<String> repeatDays,
  int hour,
  int minute,
  Duration window,
) {
  final maxDays = window.inDays + 2; // enough forward scan to cover the window
  for (var d = 0; d <= maxDays; d++) {
    final day = DateTime(now.year, now.month, now.day).add(Duration(days: d));
    if (!_activeOnWeekday(repeatDays, day.weekday)) continue;
    final candidate = DateTime(day.year, day.month, day.day, hour, minute);
    if (!candidate.isAfter(now)) continue; // today's OFF already passed
    // First future active candidate is the soonest; if it's past the window,
    // nothing nearer exists.
    return candidate.difference(now) <= window ? candidate : null;
  }
  return null;
}

/// Whether [repeatDays] fire on [weekday] (DateTime convention: 1=Mon..7=Sun).
/// Mirrors the day-token sets used by the My Schedule week strip and the
/// dashboard Tonight card so "which days does this fire" is consistent app-wide.
bool _activeOnWeekday(List<String> repeatDays, int weekday) {
  final dl = repeatDays.map((e) => e.toLowerCase().trim()).toSet();
  if (dl.any((e) => e.contains('daily'))) return true;
  const map = {
    1: {'mon', 'monday'},
    2: {'tue', 'tues', 'tuesday'},
    3: {'wed', 'wednesday'},
    4: {'thu', 'thurs', 'thursday'},
    5: {'fri', 'friday'},
    6: {'sat', 'saturday'},
    7: {'sun', 'sunday'},
  };
  return (map[weekday] ?? const <String>{}).any(dl.contains);
}

/// Resolve an off-time label to an approximate (hour, minute) for the window
/// check. Solar tokens map to the coarse [kApproxSunriseHour]/[kApproxSunsetHour]
/// constants; clock labels (12-hour "h:mm AM/PM" or 24-hour "HH:mm") parse
/// exactly. Returns null for anything unparseable.
(int, int)? _offTimeOfDay(String label) {
  final l = label.trim().toLowerCase();
  if (l == 'sunrise') return (kApproxSunriseHour, 0);
  if (l == 'sunset') return (kApproxSunsetHour, 0);

  final ampm = RegExp(r'^(\d{1,2}):(\d{2})\s*([ap]m)$').firstMatch(l);
  if (ampm != null) {
    var h = int.parse(ampm.group(1)!);
    final m = int.parse(ampm.group(2)!);
    final pm = ampm.group(3) == 'pm';
    if (h < 1 || h > 12 || m > 59) return null;
    if (h == 12) h = 0;
    if (pm) h += 12;
    return (h, m);
  }

  final h24 = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(l);
  if (h24 != null) {
    final h = int.parse(h24.group(1)!);
    final m = int.parse(h24.group(2)!);
    if (h > 23 || m > 59) return null;
    return (h, m);
  }
  return null;
}

/// Friendly display name for a schedule, derived from its action label:
///   "Warm White (Daily evening lighting)" → "Warm White"
///   "Pattern: Candy Cane"                 → "Candy Cane"
String scheduleDisplayName(ScheduleItem item) {
  var name = item.actionLabel.trim();
  if (name.toLowerCase().startsWith('pattern:')) {
    name = name.substring(name.indexOf(':') + 1).trim();
  }
  final paren = name.indexOf(' (');
  if (paren > 0) name = name.substring(0, paren).trim();
  return name.isEmpty ? 'schedule' : name;
}

/// After a manual pattern/design apply, surface a one-line non-blocking notice
/// when an ENABLED schedule will turn the lights off within
/// [kManualApplyOffWarningWindow]. No-op when nothing qualifies. Never blocks —
/// a floating SnackBar shown via the app-wide messenger, so it works from any
/// apply surface without a local Scaffold.
void maybeShowManualApplyOffWarning(WidgetRef ref) {
  final notice = nextEnabledOffBoundaryWithin(
    ref.read(schedulesProvider),
    DateTime.now(),
    timeFormat: ref.read(timeFormatPreferenceProvider),
  );
  if (notice == null) return;
  final messenger = AppRouter.scaffoldMessengerKey.currentState;
  messenger?.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 6),
      content: Text(
        "Heads up — your '${notice.scheduleName}' schedule turns the "
        'lights off at ${notice.offLabel}.',
      ),
    ),
  );
}
