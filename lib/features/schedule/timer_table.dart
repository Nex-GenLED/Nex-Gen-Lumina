// Pure-Dart (no flutter / dart:ui): THE controller timer table.
//
// Every write of `timers.ins` goes through [buildTimerTable] — schedule sync,
// one-night and Game Day lease writes, and the sunrise-off toggle. Before this
// file each of those assembled its own array, and they disagreed: the lease
// writer skipped every sunrise/sunset schedule (erasing their clock rows), and
// the sunrise-off toggle classified a lone sunset row as the sunrise.
//
// ── THE ENCODING, AND WHY (read from WLED source; see the sun-scheduling
// audit, 2026-11-02) ──────────────────────────────────────────────────────────
//
// Always exactly 10 rows:
//   0-7  clock rows (schedules, then leases), padded with all-zero stubs
//   8    sunrise: the owner, or a DISABLED placeholder {en:0, hour:255, macro:0}
//   9    sunset:  the owner with hour 254, or an all-zero stub
//
// * 0.15.1 / 0.15.4 identify the sun rows BY POSITION (cfg.cpp:568 jumps to
//   slot 8 at the first hour==255 row; slot 9's hour is never read). They
//   serialize cfg.json WITHOUT all-zero slots and re-parse it at boot, so a
//   stubbed slot 8 vanished from the file and a lone sunset row came back as
//   the SUNRISE row after a reboot. The placeholder keeps slot 8 in the file.
// * 16.0.1 identifies them BY HOUR (TH_SUNRISE 255, TH_SUNSET 254), replaces
//   the whole list on every write (clearTimers), and defaults a missing `en` to
//   disabled. A sunset sent as 255 became a second sunrise, and every 8-row
//   write deleted the sun rows. Hour 254 and a full 10-row table fix both, and
//   254 in row 9 is harmless on 0.15.x because row 8 is always a 255-row.

import 'package:nexgen_command/features/schedule/cfg_payload_builder.dart'
    as cfg;
import 'package:nexgen_command/features/schedule/schedule_models.dart';

/// General (clock) slots, 0-7.
const int kTableGeneralSlots = 8;

/// Index of the sunrise row in the table we send.
const int kTableSunriseSlot = 8;

/// Index of the sunset row in the table we send.
const int kTableSunsetSlot = 9;

/// Rows in every table we send.
const int kTableSlots = 10;

/// Sunrise marker: 0.15.x's "jump to slot 8" value, 16.x's TH_SUNRISE.
const int kSunriseHour = 255;

/// Sunset marker: 16.x's TH_SUNSET. 0.15.x stores it in slot 9 and ignores it.
const int kSunsetHour = 254;

/// Sun offset limit in minutes (16.x clamps here; 0.15.x stores an int8).
const int kSunOffsetLimit = 120;

/// True for a sun row's hour (either marker).
bool isSunHour(Object? hour) {
  final h = hour is num ? hour.toInt() : null;
  return h == kSunriseHour || h == kSunsetHour;
}

/// A disabled clock row. All-zero, so both firmwares drop it from cfg.json.
Map<String, dynamic> clockStub() =>
    <String, dynamic>{'en': 0, 'hour': 0, 'min': 0, 'macro': 0, 'dow': 0};

/// Slot 8 when nothing owns sunrise: disabled (macro 0 never fires on either
/// firmware), but hour 255 so 0.15.x keeps it in cfg.json and the boot parse
/// still finds slot 8 where it was.
Map<String, dynamic> sunrisePlaceholder() => <String, dynamic>{
      'en': 0,
      'hour': kSunriseHour,
      'min': 0,
      'macro': 0,
      'dow': 0,
    };

/// An enabled sun row. `en` is an INT: WLED reads it type-strictly.
Map<String, dynamic> sunRow({
  required bool sunrise,
  required int offsetMinutes,
  required int macro,
  required int dow,
}) =>
    <String, dynamic>{
      'en': 1,
      'hour': sunrise ? kSunriseHour : kSunsetHour,
      'min': offsetMinutes.clamp(-kSunOffsetLimit, kSunOffsetLimit),
      'macro': macro,
      'dow': dow,
    };

bool _isSunrise(String? label) => label?.trim().toLowerCase() == 'sunrise';

/// Which [armable] schedules fit [maxSlots] general rows. Mirrors
/// [cfg.buildCfgPayload]'s ON-then-OFF consumption.
({List<ScheduleItem> armed, bool overflowed}) splitByCapacity(
  List<ScheduleItem> armable, {
  bool solarEnabled = false,
  int maxSlots = kTableGeneralSlots,
}) {
  final budget = maxSlots.clamp(0, kTableGeneralSlots);
  final armed = <ScheduleItem>[];
  var slotsUsed = 0;
  var overflowed = false;
  for (final s in armable) {
    final onSolar = solarEnabled && cfg.isSolarLabel(s.timeLabel);
    final offSolar = solarEnabled &&
        s.hasOffTime &&
        s.offTimeLabel != null &&
        cfg.isSolarLabel(s.offTimeLabel!);
    if (!onSolar && slotsUsed >= budget) {
      overflowed = true;
      break;
    }
    if (!onSolar) slotsUsed += 1;
    if (s.hasOffTime &&
        s.offTimeLabel != null &&
        !offSolar &&
        slotsUsed < budget) {
      slotsUsed += 1;
    }
    armed.add(s);
  }
  return (armed: armed, overflowed: overflowed);
}

/// The two sun rows across all [armed] schedules. One sunrise row and one
/// sunset row exist on 0.15.x; extra boundaries come back in `rejected`.
/// [sunriseTaken]: the global sunrise-off owns slot 8, so a schedule's sunrise
/// OFF is superseded (same macro 2 effect) and is neither assigned nor
/// rejected.
({
  Map<String, dynamic>? sunrise,
  Map<String, dynamic>? sunset,
  List<String> rejected,
}) sunSlotsFor(
  List<ScheduleItem> armed, {
  bool sunriseTaken = false,
  void Function(String)? debug,
}) {
  Map<String, dynamic>? sunrise;
  Map<String, dynamic>? sunset;
  final rejected = <String>[];

  void assign(bool isSunrise, Map<String, dynamic> row, String who) {
    if (isSunrise) {
      if (sunriseTaken) {
        debug?.call('TimerTable: sunrise slot owned by the global '
            'sunrise-off — superseded $who (same master-OFF effect)');
        return;
      }
      if (sunrise == null) {
        sunrise = row;
      } else {
        rejected.add(who);
      }
    } else {
      if (sunset == null) {
        sunset = row;
      } else {
        rejected.add(who);
      }
    }
  }

  for (final s in armed) {
    final dow = cfg.computeDowMask(s.repeatDays);
    if (dow == 0) continue;
    final presetId = s.presetId ?? cfg.presetForAction(s.actionLabel);
    if (presetId == null) {
      debug?.call('TimerTable: REFUSED solar "${s.actionLabel}" — action not '
          'recognised and no design payload');
      continue;
    }
    if (cfg.isSolarLabel(s.timeLabel)) {
      final up = _isSunrise(s.timeLabel);
      assign(
        up,
        sunRow(sunrise: up, offsetMinutes: 0, macro: presetId, dow: dow),
        '${s.actionLabel} (${s.timeLabel} ON)',
      );
    }
    if (s.hasOffTime &&
        s.offTimeLabel != null &&
        cfg.isSolarLabel(s.offTimeLabel!)) {
      final up = _isSunrise(s.offTimeLabel);
      assign(
        up,
        sunRow(sunrise: up, offsetMinutes: 0, macro: cfg.kNglOffPresetIdCfg,
            dow: dow),
        '${s.actionLabel} (${s.offTimeLabel} OFF)',
      );
    }
  }
  return (sunrise: sunrise, sunset: sunset, rejected: rejected);
}

/// Exactly [kTableSlots] rows: [general] padded/truncated into 0-7, then the
/// sunrise row (or the placeholder), then the sunset row (or a stub).
List<Map<String, dynamic>> assembleTable(
  List<Map<String, dynamic>> general, {
  Map<String, dynamic>? sunrise,
  Map<String, dynamic>? sunset,
}) {
  final out = general.length > kTableGeneralSlots
      ? general.sublist(0, kTableGeneralSlots)
      : List<Map<String, dynamic>>.from(general);
  while (out.length < kTableGeneralSlots) {
    out.add(clockStub());
  }
  out.add(sunrise != null
      ? Map<String, dynamic>.from(sunrise)
      : sunrisePlaceholder());
  out.add(sunset != null ? Map<String, dynamic>.from(sunset) : clockStub());
  return out;
}

/// The result of one table build.
class TimerTable {
  /// The 10 rows to POST.
  final List<Map<String, dynamic>> ins;

  /// The same table built from schedules alone — no lease rows, no global
  /// sunrise-off — so "schedules produced nothing" can be detected without a
  /// preserved lease or sunrise-off masking it.
  final List<Map<String, dynamic>> scheduleIns;

  /// The schedules that armed.
  final List<ScheduleItem> armed;

  /// Plain-words warnings for the sync status.
  final List<String> warnings;

  const TimerTable({
    required this.ins,
    required this.scheduleIns,
    required this.armed,
    required this.warnings,
  });
}

/// Build the table every controller write sends.
///
/// [armable] = schedules that passed every arm check. [leaseRows] = active
/// one-night / Game Day rows (clock rows). [globalSunriseOff] = the daily
/// sunrise-off row when the setting is on; it outranks a schedule's sunrise.
TimerTable buildTimerTable({
  required List<ScheduleItem> armable,
  List<Map<String, dynamic>> leaseRows = const [],
  Map<String, dynamic>? globalSunriseOff,
  required bool solarEnabled,
  void Function(String)? debug,
}) {
  final warnings = <String>[];
  final capacity = splitByCapacity(armable,
      solarEnabled: solarEnabled,
      maxSlots: kTableGeneralSlots - leaseRows.length);
  final armed = capacity.armed;
  if (capacity.overflowed) {
    warnings.add("Schedule saved but couldn't arm — controller timer slots "
        'are full (8/8). Delete an old schedule.');
    debug?.call('TimerTable: ${armable.length - armed.length} schedule(s) '
        'could not arm — WLED timer table full (8/8)');
  }

  final clock = ((cfg.buildCfgPayload(armed,
              solarEnabled: solarEnabled, debug: debug)['timers']
          as Map)['ins'] as List)
      .cast<Map<String, dynamic>>();

  final sun = solarEnabled
      ? sunSlotsFor(armed,
          sunriseTaken: globalSunriseOff != null, debug: debug)
      : (
          sunrise: null,
          sunset: null,
          rejected: const <String>[],
        );
  for (final who in sun.rejected) {
    warnings.add('Only one sunrise and one sunset schedule are supported per '
        'controller — "$who" was not armed.');
  }

  return TimerTable(
    ins: assembleTable([...clock, ...leaseRows],
        sunrise: globalSunriseOff ?? sun.sunrise, sunset: sun.sunset),
    scheduleIns:
        assembleTable(clock, sunrise: sun.sunrise, sunset: sun.sunset),
    armed: armed,
    warnings: warnings,
  );
}

// ─── Arm checks that need no controller ─────────────────────────────────────

/// What a table build needs to know about the controller and the account.
class TimerTableContext {
  /// `config/solar_scheduling.enabled`.
  final bool solarFlagOn;

  /// The flag is on AND the controller reports usable coordinates.
  final bool solarEnabled;

  /// The daily sunrise-off row, or null when the setting is off.
  final Map<String, dynamic>? globalSunriseOff;

  const TimerTableContext({
    required this.solarFlagOn,
    required this.solarEnabled,
    this.globalSunriseOff,
  });
}

/// Why [s] cannot arm, in the words the sync status shows — or null when it
/// can. These are the arm checks that need no controller; schedule sync runs
/// its preset check first, then this.
String? timerArmRefusal(ScheduleItem s, TimerTableContext ctx) {
  final badLabels = <String>[
    if (!cfg.isArmableTimeLabel(s.timeLabel)) s.timeLabel,
    if (s.hasOffTime &&
        s.offTimeLabel != null &&
        !cfg.isArmableTimeLabel(s.offTimeLabel!))
      s.offTimeLabel!,
  ];
  if (badLabels.isNotEmpty) {
    return '"${s.actionLabel}" has an unrecognized time '
        '(${badLabels.join(", ")}) — not armed. Re-open the schedule and '
        'set a valid time.';
  }
  if (ctx.globalSunriseOff != null && _isSunrise(s.timeLabel)) {
    return '"${s.actionLabel}" turns lights ON at sunrise, which conflicts '
        'with "Turn lights off at sunrise daily" — not armed. Turn that '
        'setting off, or give this schedule a different time.';
  }
  final usesSun = cfg.isSolarLabel(s.timeLabel) ||
      (s.hasOffTime &&
          s.offTimeLabel != null &&
          cfg.isSolarLabel(s.offTimeLabel!));
  if (usesSun && !ctx.solarEnabled) {
    final why = ctx.solarFlagOn
        ? 'needs your location set on the controller — sunrise/sunset '
            'can\'t be computed without it'
        : 'isn\'t supported yet — please set a specific time';
    return '"${s.actionLabel}" uses sunrise/sunset timing, which $why.';
  }
  if (cfg.computeDowMask(s.repeatDays) == 0) {
    return '"${s.actionLabel}" has no repeat days — not armed. Re-open the '
        'schedule and pick at least one day.';
  }
  return null;
}

/// The table for writers that hold no fresh preset state — the lease manager
/// and the sunrise-off toggle. Enabled, non-evicted schedules that pass
/// [timerArmRefusal] arm; their presets were saved by the last schedule sync.
TimerTable composeTimerTable({
  required List<ScheduleItem> schedules,
  List<Map<String, dynamic>> leaseRows = const [],
  required TimerTableContext ctx,
  void Function(String)? debug,
}) {
  final armable = [
    for (final s in schedules)
      if (s.enabled && !s.isCurrentlyEvicted && timerArmRefusal(s, ctx) == null)
        s,
  ];
  return buildTimerTable(
    armable: armable,
    leaseRows: leaseRows,
    globalSunriseOff: ctx.globalSunriseOff,
    solarEnabled: ctx.solarEnabled,
    debug: debug,
  );
}
