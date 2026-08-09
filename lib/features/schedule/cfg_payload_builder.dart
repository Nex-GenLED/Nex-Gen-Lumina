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
/// Resolves a PAYLOAD-LESS schedule's action label to a system preset id, or
/// `null` when the label is not a recognised action.
///
/// ⚠️ ONLY payload-less schedules reach here. A schedule carrying a
/// `wledPayload` is psaved to its own 10–25 slot by `syncAll` and never
/// consults this function (audit/BASE_LADDER.md §5c). The canonical labels the
/// UI produces for the payload-less case are exactly `Turn On`, `Turn Off`, and
/// `Brightness: N%`.
///
/// WHY `null` AND NOT A DEFAULT (this is the fix): the previous version ended
/// `return 1`, so ANY unrecognised label silently armed macro 1 — the NGL On
/// ladder preset. `"Deep Blue"` and `"Warm White"` both exist in the fleet and
/// both landed there. Silently routing an unknown action to "turn the house on
/// at full brightness" is how a mis-typed or renamed label becomes lights
/// behaving unpredictably at 3am, with every layer reporting success. An
/// unknown action is now a REFUSAL the caller must handle, not a guess.
///
/// THE THREE SUBSTRING BUGS THIS REPLACES (all bench-visible on fleet labels):
///   1. `contains('off')` ran FIRST, so `"Pattern: 1 On 4 Off - Solid"` → 2,
///      the OFF preset. That label is live on two accounts; a payload-less
///      version would turn the lights OFF at its ON boundary.
///   2. `contains('on')` ran before the pattern test, so `Neon`, `Bronze`, and
///      `Monday` all resolved to macro 1.
///   3. The `return 1` fallthrough, above.
/// All three were unreachable only because every schedule in the fleet happens
/// to carry a payload. The path was unguarded, not unreachable.
///
/// ⚠️ MODEL PROBLEM, NAMED NOT PATCHED: `ScheduleItem` persists `actionLabel`,
/// a DISPLAY STRING, and has no action-type field. So this function is parsing
/// UI copy to recover intent that was never stored. Anchored matching makes
/// that parsing honest and its failures loud, but it cannot make it correct —
/// renaming a button, translating the app, or an AI-authored label all break
/// the mapping, and nothing outside this function knows. The real fix is an
/// `actionType` enum persisted on the schedule and written at authoring time,
/// with this reduced to a migration shim for pre-existing rows. Not done here:
/// it changes the model, the write paths, and needs a backfill.
int? presetForAction(String actionLabel) {
  final a = actionLabel.trim().toLowerCase();

  // Anchored, not substring. `==` for the fixed actions so a design named
  // "Turn On The Lights" cannot be mistaken for the Turn On action.
  if (a == 'turn off' || a == 'off') return kNglOffPresetIdCfg;
  if (a == 'turn on' || a == 'on') return 1;

  // `Brightness: N%` — the label the UI writes. Anchored so a design called
  // "Brightness Boost" does not match.
  final bri = RegExp(r'^brightness\s*:?\s*(\d{1,3})\s*%?$').firstMatch(a);
  if (bri != null) {
    final percent = int.tryParse(bri.group(1)!);
    if (percent == null || percent < 0 || percent > 100) return null;
    if (percent <= 25) return 3;
    if (percent <= 45) return 4;
    if (percent <= 70) return 5;
    return 1;
  }

  // A bare "Brightness" with no percentage is not actionable — the old code
  // guessed 3 (Dim). Refuse instead; the caller warns and does not arm.
  return null;
}

/// Preset id holding the master-OFF state. Mirrors
/// `ScheduleSyncService.kNglOffPresetId`; duplicated here because this file is
/// deliberately Flutter-free (the bench/CLI imports it).
const int kNglOffPresetIdCfg = 2;

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

    // UNRECOGNISED ACTION → REFUSE TO ARM. Previously an unknown label fell
    // through to macro 1 and armed the house ON. Skipping is the same posture
    // as the empty-macro guard in syncAll: an ON-timer we cannot resolve must
    // not fire something we did not choose.
    if (presetId == null) {
      debug?.call('ScheduleSync: REFUSED "${s.actionLabel}" — action not '
          'recognised and no design payload; nothing armed for this schedule');
      continue;
    }

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
