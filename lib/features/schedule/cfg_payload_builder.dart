// Pure-Dart (no flutter / dart:ui) WLED timer cfg builder, extracted verbatim
// from ScheduleSyncService so the bench/ CLI builds the REAL /json/cfg timer
// payload. ScheduleSyncService delegates its buildCfgPayload + timer helpers to
// these, so app behavior is unchanged (the class methods are thin wrappers).
//
// Logging: the app path passes `debug: debugPrint`; the pure path leaves it null.

import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/wled/wled_dow.dart';

/// GENERAL (clock) timer slots — WLED 0.15.1 `timers.ins` indices 0-7.
/// (Mirror of ScheduleSyncService.kMaxWledTimers; a capacity literal, not logic.)
const int kWledMaxGeneralTimers = 8;

/// Parsed clock time (hour 0-23, minute 0-59).
class ParsedTime {
  final int hour;
  final int minute;
  const ParsedTime({required this.hour, required this.minute});
}

/// True for the two solar keywords the app (wrongly) maps to WLED hour 24/25.
bool isSolarLabel(String label) {
  final l = label.trim().toLowerCase();
  return l == 'sunrise' || l == 'sunset';
}

/// Compute the WLED dow bitmask for a list of weekday names (Mon=bit0..Sun=bit6).
int computeDowMask(List<String> days) => wledDowMaskForDayList(days);

/// Parse "7:05 PM" (12h) / "10:11", "23:30", "0:05" (24h). Returns null for a
/// genuinely unrecognized label — callers MUST treat null as "do not arm".
/// NEVER defaults an unparseable time to midnight.
ParsedTime? parseTimeLabel(String label) {
  final l = label.trim().toLowerCase();
  if (l == 'sunrise' || l == 'sunset') {
    return const ParsedTime(hour: 0, minute: 0);
  }
  final ampm = RegExp(r'^(\d{1,2}):(\d{2})\s*([ap]m)$', caseSensitive: false);
  final m = ampm.firstMatch(l);
  if (m != null) {
    var hh = int.tryParse(m.group(1)!) ?? -1;
    final mm = int.tryParse(m.group(2)!) ?? -1;
    final ap = m.group(3)!.toLowerCase();
    if (hh < 1 || hh > 12 || mm < 0 || mm > 59) return null;
    if (ap == 'pm' && hh != 12) hh += 12;
    if (ap == 'am' && hh == 12) hh = 0;
    return ParsedTime(hour: hh, minute: mm);
  }
  final h24 = RegExp(r'^(\d{1,2}):(\d{2})$');
  final m24 = h24.firstMatch(l);
  if (m24 != null) {
    final hh = int.tryParse(m24.group(1)!);
    final mm = int.tryParse(m24.group(2)!);
    if (hh == null || mm == null || hh > 23 || mm > 59) return null;
    return ParsedTime(hour: hh, minute: mm);
  }
  return null;
}

/// True when [label] is a time WLED can actually arm (solar keyword or a clock
/// time [parseTimeLabel] recognizes).
bool isArmableTimeLabel(String label) {
  final l = label.trim().toLowerCase();
  if (l == 'sunrise' || l == 'sunset') return true;
  return parseTimeLabel(label) != null;
}

/// Maps an action label to a WLED preset ID (1=on, 2=off, 3/4/5=dim/low/medium,
/// 10=pattern). See ScheduleSyncService docs for the preset conventions.
int presetForAction(String actionLabel) {
  final a = actionLabel.toLowerCase();
  if (a.contains('turn off') || a.contains('off')) return 2;
  if (a.contains('turn on') || a.contains('on')) return 1;
  if (a.startsWith('brightness')) {
    final percentMatch = RegExp(r'(\d+)%?').firstMatch(a);
    if (percentMatch != null) {
      final percent = int.tryParse(percentMatch.group(1)!) ?? 50;
      if (percent <= 25) return 3;
      if (percent <= 45) return 4;
      if (percent <= 70) return 5;
      return 1;
    }
    return 3;
  }
  if (a.startsWith('pattern') || a.contains('pattern')) return 10;
  return 1;
}

/// Builds a single timer entry from a time label. Returns null if unparseable
/// (NEVER a phantom midnight). `en` is a type-strict INT (WLED stores a bool as
/// 0 — curl-proven 2026-07-22 on vid 2507300).
Map<String, dynamic>? buildTimerEntry({
  required String timeLabel,
  required int dow,
  required int macro,
  void Function(String)? debug,
}) {
  final tl = timeLabel.trim().toLowerCase();
  if (tl == 'sunrise' || tl == 'sunset') {
    final isSunrise = tl == 'sunrise';
    return {
      'en': 1,
      'hour': isSunrise ? 24 : 25, // 24=sunrise, 25=sunset
      'min': 0,
      'macro': macro,
      'dow': dow,
    };
  }
  final parsed = parseTimeLabel(timeLabel);
  if (parsed == null) {
    debug?.call(
        'ScheduleSync: unparseable time label "$timeLabel" — timer not built');
    return null;
  }
  return {
    'en': 1,
    'hour': parsed.hour,
    'min': parsed.minute,
    'macro': macro,
    'dow': dow,
  };
}

/// Build the REAL cfg payload (`{"timers":{"ins":[...]}}`) for [schedules].
/// Returns the REAL timers only — deliberately UNPADDED (callers merge lease
/// timers then pad to [kWledMaxGeneralTimers]). Solar boundaries are OMITTED
/// from slots 0-7 here; syncAll places them positionally in slots 8/9. dow:0
/// and unparseable times are refused (never emit a dead/phantom timer).
Map<String, dynamic> buildCfgPayload(
  List<ScheduleItem> schedules, {
  bool solarEnabled = false,
  void Function(String)? debug,
}) {
  final enabled = schedules
      .where((s) => s.enabled && !s.isCurrentlyEvicted)
      .toList(growable: false);

  final List<Map<String, dynamic>> timers = [];

  for (final s in enabled) {
    if (timers.length >= kWledMaxGeneralTimers) break;

    final dow = computeDowMask(s.repeatDays);

    if (dow == 0) {
      debug?.call('ScheduleSync: skipped dow:0 timer for "${s.actionLabel}" '
          '(repeatDays=${s.repeatDays})');
      continue;
    }

    final onSolar = isSolarLabel(s.timeLabel);
    final offSolar = s.hasOffTime &&
        s.offTimeLabel != null &&
        isSolarLabel(s.offTimeLabel!);

    if (!solarEnabled) {
      if (onSolar || offSolar) {
        debug?.call('ScheduleSync: skipped solar timer for "${s.actionLabel}" '
            '(on=${s.timeLabel} off=${s.offTimeLabel}) — solar disabled '
            '(solar_scheduling flag off / bench gate)');
        continue;
      }
    }

    final presetId = s.presetId ?? presetForAction(s.actionLabel);

    if (!onSolar) {
      final onTimer = buildTimerEntry(
        timeLabel: s.timeLabel,
        dow: dow,
        macro: presetId,
        debug: debug,
      );
      if (onTimer != null) {
        timers.add(onTimer);
      }
    }

    if (s.hasOffTime &&
        s.offTimeLabel != null &&
        !offSolar &&
        timers.length < kWledMaxGeneralTimers) {
      final offTimer = buildTimerEntry(
        timeLabel: s.offTimeLabel!,
        dow: dow,
        macro: 2, // Preset 2 = off state (convention)
        debug: debug,
      );
      if (offTimer != null) {
        timers.add(offTimer);
      }
    }
  }

  return {
    'timers': {
      'ins': timers,
    },
  };
}
