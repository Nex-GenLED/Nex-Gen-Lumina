// Pure-Dart (no flutter / dart:ui): WHO OWNS EACH TIMER ROW — build 127.
//
// Every controller write used to rebuild the whole `timers.ins` table from the
// account's stored schedules. Two writer families then dropped enabled
// schedules from the table they sent:
//
//   (i)  schedule sync: a schedule it refused this time (a design whose
//        read-back mismatched or could not be read, anything the arm checks
//        held back) had its rows OMITTED, and the POST still went out because
//        the always-enabled sunrise-off row made the clobber guard see a
//        table that was not empty;
//   (ii) the lease manager (promotion, update, expiry zeroing, delete release,
//        heir re-derivation, Game Day retraction) and the Settings sunrise-off
//        toggle composed the table from stored schedules and resolved each
//        schedule's macro as `presetId ?? presetForAction(label)`. No stored
//        schedule carries a presetId and presetForAction knows only Turn On,
//        Turn Off and Brightness, so every "Pattern: …", Lumina-chat and
//        Autopilot schedule — 29 of the 30 enabled schedules in the fleet —
//        resolved to null, was refused silently, and the table went out
//        without it.
//
// THE RULE: a writer changes only the rows it OWNS and preserves every other
// row already on the device, byte for byte.
//   * lease writers own lease rows (macro 26–41);
//   * the sunrise-off toggle owns the system_off row in the sunrise slot
//     (hour 255, macro 2, every day);
//   * schedule sync owns schedule rows, and keeps a refused schedule's
//     existing device rows instead of omitting them (schedule_sync.dart).
//
// A row's owner is read off its `macro` with EXACTLY the classification the
// healer already publishes for `base_boundaries` ([wledPresetRole]): schedule,
// lease, system_off, system_on, user_pattern, unknown. Never by slot position
// — a lease record's `slotIndex` is bookkeeping for the free-slot count, and
// the readback is compacted anyway, so position says nothing about ownership.

import 'package:nexgen_command/features/schedule/cfg_payload_builder.dart'
    as cfg;
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/timer_landing.dart';
import 'package:nexgen_command/features/schedule/timer_table.dart';
import 'package:nexgen_command/features/wled/wled_preset_ranges.dart';

int _int(Object? v) => v is num ? v.toInt() : 0;

/// `en` as the firmware reads it (type-strict int; a bool is tolerated here
/// because a readback may carry either).
int _en(Map<String, dynamic> row) => (row['en'] == true || row['en'] == 1) ? 1 : 0;

/// The role of [row]'s macro — the healer's `base_boundaries` classification.
String timerRowRole(Map<String, dynamic> row) =>
    wledPresetRole(_int(row['macro']));

/// A row a lease writer owns: its macro is in the lease band (26–41).
bool isLeaseRow(Map<String, dynamic> row) => timerRowRole(row) == 'lease';

/// A row carrying a sun marker (255 sunrise, 254 sunset).
bool isSunMarkerRow(Map<String, dynamic> row) => isSunHour(row['hour']);

/// The daily sunrise-off exactly as the Settings toggle arms it: enabled,
/// the sunrise marker, master off (macro 2), every day. This is the one row
/// the toggle owns.
bool isGlobalSunriseOffRow(Map<String, dynamic> row) =>
    _en(row) == 1 &&
    _int(row['hour']) == kSunriseHour &&
    _int(row['macro']) == cfg.kNglOffPresetIdCfg &&
    _int(row['dow']) == 127;

/// A deep copy of a row (nested `start`/`end` maps included), so a preserved
/// row that is sent back can never alias the readback.
Map<String, dynamic> copyRow(Map<String, dynamic> row) {
  Object? copy(Object? v) {
    if (v is Map) return {for (final e in v.entries) e.key.toString(): copy(e.value)};
    if (v is List) return [for (final x in v) copy(x)];
    return v;
  }

  return copy(row) as Map<String, dynamic>;
}

/// The controller's timer table, re-assembled from a compacted readback.
class DeviceTimerTable {
  /// The general (clock) rows, in readback order, byte for byte.
  final List<Map<String, dynamic>> general;

  /// The sunrise-slot row (enabled, or the disabled placeholder), or null.
  final Map<String, dynamic>? sunrise;

  /// The sunset-slot row, or null.
  final Map<String, dynamic>? sunset;

  const DeviceTimerTable({
    required this.general,
    required this.sunrise,
    required this.sunset,
  });
}

/// Why a readback could not be turned into a table.
const String kDeviceTableAmbiguousSunRow =
    'the controller holds one sun row written with an older encoding, and '
    'the wire cannot say whether it is the sunrise or the sunset';
const String kDeviceTableTooManyRows =
    'the controller reported more general timer rows than it has slots';

/// Re-assemble the 10-row table from what the controller READ BACK.
///
/// WLED compacts the readback — it echoes every row that is not all-zero
/// (`macro == 0 && hour == 0 && min == 0` is skipped) and drops the padding
/// stubs — so positions are lost and a sun row is known by its CONTENT:
/// * `hour == 254` is a sunset; `hour == 255` is a sunrise (the current
///   encoding, timer_table.dart: the sunset is written as 254 and a disabled
///   255 placeholder holds slot 8 when nothing owns sunrise);
/// * two 255 rows and no 254 is a table written before the sunset marker:
///   order is preserved on the wire, so the first is the sunrise and the
///   second the sunset (base_boundary_denormalizer.dart);
/// * ONE 255 row, no 254 and no disabled placeholder: the sunrise slot is
///   the only slot a master-OFF row is written to in every fleet shape
///   (the daily sunrise-off, a schedule's "off at sunrise"; the sunset slot
///   holds an all-zero stub that the readback drops), so a lone `system_off`
///   row is the sunrise. A lone row with an ON macro is genuinely
///   undecidable — a sunrise ON under the current encoding, a legacy
///   "Sunset → 11 PM" under the old one — and is refused
///   ([kDeviceTableAmbiguousSunRow]); the next schedule sync rewrites the
///   table in the current encoding and the refusal clears.
/// Every general row (clock hour) is kept byte for byte, disabled ones too:
/// a disabled row with content is somebody's row (the WLED UI can disable a
/// timer), not padding.
///
/// Returns null, with the reason in [refusal], when the table cannot be
/// re-assembled.
({DeviceTimerTable? table, String? refusal}) deviceTableFromReadback(
    List<Map<String, dynamic>> readback) {
  final general = <Map<String, dynamic>>[];
  final sun = <Map<String, dynamic>>[];
  for (final raw in readback) {
    final row = copyRow(raw);
    if (isSunMarkerRow(row)) {
      sun.add(row);
    } else {
      // A padding stub that somehow came back is not a row.
      if (!carriesAnyEnabledEntry(row) &&
          _int(row['macro']) == 0 &&
          _int(row['hour']) == 0 &&
          _int(row['min']) == 0) {
        continue;
      }
      general.add(row);
    }
  }
  if (general.length > kTableGeneralSlots) {
    return (table: null, refusal: kDeviceTableTooManyRows);
  }

  final marked = sun.any((r) =>
      _int(r['hour']) == kSunsetHour ||
      (_int(r['hour']) == kSunriseHour && !carriesAnyEnabledEntry(r)));

  Map<String, dynamic>? sunrise;
  Map<String, dynamic>? sunset;
  if (marked) {
    // Current encoding: content names the slot. An enabled sunrise beats the
    // placeholder if (oddly) both came back.
    for (final r in sun) {
      if (_int(r['hour']) == kSunsetHour) {
        sunset ??= r;
      } else if (sunrise == null || !carriesAnyEnabledEntry(sunrise)) {
        sunrise = r;
      }
    }
  } else if (sun.length == 2) {
    sunrise = sun[0];
    sunset = sun[1];
  } else if (sun.length == 1) {
    final only = sun.single;
    if (isGlobalSunriseOffRow(only) || timerRowRole(only) == 'system_off') {
      sunrise = only;
    } else {
      return (table: null, refusal: kDeviceTableAmbiguousSunRow);
    }
  } else if (sun.length > 2) {
    sunrise = sun[0];
    sunset = sun[1];
  }
  return (
    table: DeviceTimerTable(general: general, sunrise: sunrise, sunset: sunset),
    refusal: null,
  );
}

/// What a lease write found when it composed its table.
class LeaseWriteComposition {
  /// The 10 rows to send, or null when [refusal] says why not.
  final List<Map<String, dynamic>>? ins;

  /// Plain words, or null when [ins] is set.
  final String? refusal;

  /// True when the refusal is "no free slot" — the lease is skipped, the
  /// night stays unarmed, nothing else is evicted.
  final bool noFreeSlot;

  /// Rows the controller holds that are NOT lease rows (kept byte for byte).
  final int keptRows;

  const LeaseWriteComposition({
    required this.ins,
    required this.refusal,
    this.noFreeSlot = false,
    required this.keptRows,
  });
}

/// The table a LEASE WRITER sends: every non-lease row the controller holds,
/// byte for byte, then the registry's lease rows [leaseRows]; the sun slots
/// exactly as read. The lease rows the device held are REPLACED by the
/// registry's — that is the one thing this writer owns.
///
/// If the kept rows leave no room for every lease row, nothing is evicted:
/// with [truncateLeases] false (arming a night) the write is refused with
/// [LeaseWriteComposition.noFreeSlot] and the night stays unarmed — nightly
/// schedules win over Game Day nights. With it true (a zeroing write, which
/// only ever removes lease rows) the lease rows that fit are sent and the
/// rest are dropped, since a lease that does not fit was never on the device.
LeaseWriteComposition composeLeaseWrite({
  required List<Map<String, dynamic>> readback,
  required List<Map<String, dynamic>> leaseRows,
  bool truncateLeases = false,
}) {
  final read = deviceTableFromReadback(readback);
  final device = read.table;
  if (device == null) {
    return LeaseWriteComposition(ins: null, refusal: read.refusal, keptRows: 0);
  }
  final kept = [for (final r in device.general) if (!isLeaseRow(r)) r];
  final free = kTableGeneralSlots - kept.length;
  var mine = [for (final r in leaseRows) copyRow(r)];
  if (mine.length > free) {
    if (!truncateLeases) {
      return LeaseWriteComposition(
        ins: null,
        refusal: 'no free timer slot: the controller holds ${kept.length} '
            '${kept.length == 1 ? 'row' : 'rows'} that are not lease rows and '
            '${mine.length} lease ${mine.length == 1 ? 'row is' : 'rows are'} '
            'registered; nothing is evicted',
        noFreeSlot: true,
        keptRows: kept.length,
      );
    }
    mine = mine.sublist(0, free.clamp(0, mine.length));
  }
  return LeaseWriteComposition(
    ins: assembleTable([...kept, ...mine],
        sunrise: device.sunrise, sunset: device.sunset),
    refusal: null,
    keptRows: kept.length,
  );
}

/// The table the SUNRISE-OFF TOGGLE sends: every general row and the sunset
/// row exactly as read; the sunrise slot is the toggle's row when [enabled],
/// or — when switching off — the disabled placeholder if the slot held the
/// toggle's own row, and otherwise whatever the slot held (a schedule's
/// sunrise boundary is not this writer's to clear).
({List<Map<String, dynamic>>? ins, String? refusal}) composeSunriseOffWrite({
  required List<Map<String, dynamic>> readback,
  required bool enabled,
  required Map<String, dynamic> sunriseOffRow,
}) {
  final read = deviceTableFromReadback(readback);
  final device = read.table;
  if (device == null) return (ins: null, refusal: read.refusal);
  Map<String, dynamic>? sunrise;
  if (enabled) {
    sunrise = copyRow(sunriseOffRow);
  } else {
    final held = device.sunrise;
    sunrise = held != null && isGlobalSunriseOffRow(held) ? null : held;
  }
  return (
    ins: assembleTable(device.general, sunrise: sunrise, sunset: device.sunset),
    refusal: null,
  );
}

// ─── Schedule sync: a schedule's own rows on the device ─────────────────────

/// The macro roles a schedule's ON row can carry on the device: a design
/// payload — or any "Pattern: …" label, payload or not — is psaved into the
/// schedule band (role `schedule`); a payload-less action fires a system
/// preset (`system_on` for Turn On / Brightness, `system_off` for Turn Off).
/// An action the app cannot resolve at all (a Lumina-chat label with no
/// stored payload) may hold either kind of ON row from an earlier build, so
/// both ON roles count; it is never a `system_off` or a lease row.
Set<String> scheduleOnRoles(ScheduleItem s) {
  if (s.hasWledPayload ||
      s.actionLabel.trim().toLowerCase().startsWith('pattern')) {
    return const {'schedule'};
  }
  final macro = cfg.presetForAction(s.actionLabel);
  if (macro != null) return {wledPresetRole(macro)};
  return const {'schedule', 'system_on'};
}

/// The controller's ON row for [s]: a clock row at the schedule's on time
/// and weekday mask whose macro role is one of [scheduleOnRoles]. Null when
/// the schedule has no clock on time, no repeat days, or no such row.
Map<String, dynamic>? deviceOnRowFor(
    ScheduleItem s, List<Map<String, dynamic>> readback) {
  if (cfg.isSolarLabel(s.timeLabel)) return null;
  final t = cfg.parseTimeLabel(s.timeLabel);
  if (t == null) return null;
  final dow = cfg.computeDowMask(s.repeatDays);
  if (dow == 0) return null;
  final roles = scheduleOnRoles(s);
  if (roles.isEmpty) return null;
  for (final row in readback) {
    if (isSunMarkerRow(row)) continue;
    if (_int(row['hour']) == t.hour &&
        _int(row['min']) == t.minute &&
        _int(row['dow']) == dow &&
        roles.contains(timerRowRole(row))) {
      return row;
    }
  }
  return null;
}

/// The controller's OFF row for [s]: a clock `system_off` row at the
/// schedule's off time on the OFF days (the next day's bits for an overnight
/// schedule, [cfg.offDowFor]). Null when the schedule has no clock off time.
Map<String, dynamic>? deviceOffRowFor(
    ScheduleItem s, List<Map<String, dynamic>> readback) {
  if (!s.hasOffTime || s.offTimeLabel == null) return null;
  if (cfg.isSolarLabel(s.offTimeLabel!)) return null;
  final t = cfg.parseTimeLabel(s.offTimeLabel!);
  if (t == null) return null;
  final dow = cfg.computeDowMask(s.repeatDays);
  if (dow == 0) return null;
  final offDow = cfg.offDowFor(s, dow);
  for (final row in readback) {
    if (isSunMarkerRow(row)) continue;
    if (_int(row['hour']) == t.hour &&
        _int(row['min']) == t.minute &&
        _int(row['dow']) == offDow &&
        timerRowRole(row) == 'system_off') {
      return row;
    }
  }
  return null;
}

/// The rows the controller holds for [s] (ON, then OFF), byte for byte —
/// what a sync that cannot rebuild [s] this time keeps in its place. The OFF
/// row is kept only alongside an ON row: a lone OFF would be a half schedule.
List<Map<String, dynamic>> deviceRowsFor(
    ScheduleItem s, List<Map<String, dynamic>> readback) {
  final on = deviceOnRowFor(s, readback);
  if (on == null) return const [];
  final off = deviceOffRowFor(s, readback);
  return [copyRow(on), if (off != null) copyRow(off)];
}

/// The enabled schedules whose ON row the controller HOLDS and [outgoing]
/// would REMOVE: the device has a schedule-role ON row at the schedule's on
/// time and weekday mask, and the outgoing table has no ON row there. A sync
/// that changed the schedule's time or days intends to remove the old row
/// (it matches no enabled schedule any more), so it is not listed.
List<ScheduleItem> scheduleRowsDropped({
  required List<ScheduleItem> enabled,
  required List<Map<String, dynamic>> readback,
  required List<Map<String, dynamic>> outgoing,
}) {
  final dropped = <ScheduleItem>[];
  for (final s in enabled) {
    if (!s.enabled || s.isCurrentlyEvicted) continue;
    if (deviceOnRowFor(s, readback) == null) continue;
    final still = deviceOnRowFor(s, outgoing.where((r) => _en(r) == 1).toList());
    if (still == null) dropped.add(s);
  }
  return dropped;
}
