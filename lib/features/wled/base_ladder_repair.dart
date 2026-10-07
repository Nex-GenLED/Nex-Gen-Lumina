// lib/features/wled/base_ladder_repair.dart
//
// +114 item 1c — the ONE-TIME on-connect repair of a ladder that does not light.
//
// WHAT TRIGGERS IT. The healer measures `base_ladder_restore_lit` on every LAN
// connect (base_ladder_restore.dart). When it is false and at least one PRESENT
// ladder slot is bad, this repair rewrites exactly those slots with the
// builders' own output — the ON ladder in the base look (base_look.dart), the
// OFF preset as all-off — and nothing else.
//
// IT REPLACES HEALER STEP (e). `_healOnPresetMasterPower` psaved ladder slots
// on EVERY connect, unguarded: no game check, no timer check, no backup, no
// restore of the live look (a psave APPLIES its state live on this firmware).
// It is gone; this is the only automatic ladder writer left on connect, and
// every write it makes passes the guards below.
//
// THE GUARDS (all must pass, evaluated on FRESH reads immediately before the
// first write, and again on the way in):
//   • LAN only — the caller hands it a direct-LAN WledService and it re-checks
//     that the app is still connected to that same service before writing.
//   • Never during a live Game Day — a followed game in progress or about to
//     start, an active Game Day session, or a Game Day calendar window that
//     contains now (± [kLadderRepairGameGuard]). UNKNOWN is a refusal: if the
//     calendar or the team list has not loaded, the repair waits for the next
//     connect. Server status joins this list in a later commit.
//   • Never within [kLadderRepairTimerGuard] of ANY armed device timer — lease
//     rows (presets 26-41) are named, but every row counts: the repair's
//     restore re-applies the look captured before the writes, and a restore
//     landing just after a timer fired would undo that timer (a sunset ON put
//     back to "off" all night). The timer table is read from the controller
//     itself, not from the app's lease ledger.
//   • Clock healthy — WLED fires timers on its own clock; with the clock unset
//     or the timezone suspect there is no way to say when "10 minutes from a
//     timer" is, so it refuses.
//
// THE PROCEDURE (mode `repair`):
//   1. dry run — re-read presets, re-measure, build the plan (which slots, why,
//      what each becomes); recorded before anything is written;
//   2. backup — the stored bodies of presets 1-5, to this phone (REQUIRED: a
//      failed backup aborts) and to the controller doc (best effort);
//   3. capture the live state (REQUIRED: without it the psaves would change the
//      house's look with no way back);
//   3b. a SECOND fresh read of the controller: the guards run again on it (a
//      lease armed while the record write stalled is seen), and any planned
//      slot that changed since the plan aborts the run (never overwrite what
//      was not backed up). Firestore writes are bounded and best effort;
//   4. one psave per bad preset, through the geometry gate, no retry pass;
//   5. restore the captured live state;
//   6. read back, record the outcome, republish the ladder facts, and set the
//      one-time marker so it never runs again on this phone for this
//      controller (whatever the outcome — a repair that did not take is a
//      support case, not a loop).
//
// MODES — `config/base_ladder_repair.connect_repair`: `repair` is the ONLY
// value that writes. Absent document, unreadable document, missing field or any
// other value = `dry_run` (plan recorded, nothing written, marker NOT set so a
// later flip to repair still runs). `off` records nothing. The existing kill
// switch `enabled:false` on the same document means off. Owner decision
// 2026-10-02: the first customer rollout is dry run by default.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:nexgen_command/features/schedule/gated_preset_save.dart';
import 'package:nexgen_command/features/schedule/geometry_gate.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/wled/base_boundary_denormalizer.dart';
import 'package:nexgen_command/features/wled/base_ladder_denormalizer.dart'
    show kBaseRestorePresetIds, ladderAssertsSegments, presetAssertsAllChannels;
import 'package:nexgen_command/features/wled/base_ladder_restore.dart';
import 'package:nexgen_command/features/wled/base_look.dart'
    show baseLookSegmentFields, kBaseLookEffectId;
import 'package:nexgen_command/features/wled/clock_health.dart';
import 'package:nexgen_command/features/wled/device_channel.dart'
    show deviceChannelsFromConfig;
import 'package:nexgen_command/features/wled/geometry_wire_pin.dart'
    show stripGeometry;
import 'package:nexgen_command/features/wled/wled_dow.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/utils/sun_utils.dart';

/// No repair within this long either side of an armed device timer.
const Duration kLadderRepairTimerGuard = Duration(minutes: 10);

/// No repair within this long either side of a Game Day calendar window.
const Duration kLadderRepairGameGuard = Duration(minutes: 10);

/// Bumping this re-arms the one-time repair on every phone (a later build that
/// needs a second pass). Part of every local key and of the record.
const String kLadderRepairVersion = 'v1';

/// Settle between consecutive psaves (back-to-back saves can 2xx without
/// persisting on this firmware — the healer's own measured settle).
const Duration kLadderRepairSettle = Duration(milliseconds: 900);

/// The controller-doc field holding the repair record.
const String kLadderRepairRecordField = 'base_ladder_repair';

// ── Mode ─────────────────────────────────────────────────────────────────────

enum LadderRepairMode { repair, dryRun, off }

/// `config/base_ladder_repair` → mode.
///
/// WRITES NEED AN EXPLICIT OPT-IN (owner decision 2026-10-02, first customer
/// rollout). Only `connect_repair: "repair"` lets the repair write to a
/// controller. An absent document, an unreadable one (null here — see
/// [readLadderRepairMode]), a missing field, or any other value is DRY RUN:
/// the plan is recorded, nothing is written. `"off"` records nothing either.
/// The older kill switch on the same document, `enabled: false`, still wins
/// over everything and means off.
///
/// This is deliberately the opposite of `baseLadderRepairEnabledProvider`,
/// which fails OPEN for schedule sync's segment check: that one guards a
/// predicate on a user-initiated sync; this one decides whether every 114
/// phone writes presets on its own at the next connect.
LadderRepairMode ladderRepairModeFrom(Map<String, dynamic>? data) {
  if (data == null) return LadderRepairMode.dryRun;
  if (data['enabled'] == false) return LadderRepairMode.off;
  switch (data['connect_repair']) {
    case 'repair':
      return LadderRepairMode.repair;
    case 'off':
      return LadderRepairMode.off;
    default:
      return LadderRepairMode.dryRun;
  }
}

/// Read the mode through [read] (the config document's data, null when the
/// document does not exist). A read that throws or does not answer within
/// [timeout] is UNREADABLE and reads as dry run — never as repair.
Future<LadderRepairMode> readLadderRepairMode(
  Future<Map<String, dynamic>?> Function() read, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  try {
    return ladderRepairModeFrom(await read().timeout(timeout));
  } catch (_) {
    return LadderRepairMode.dryRun;
  }
}

// ── Guards (pure) ────────────────────────────────────────────────────────────

/// What the Game Day side knows right now. [known] false = something it needs
/// has not loaded, which the guard treats as "a game might be on".
@immutable
class GameDayActivity {
  final bool known;

  /// Non-null when a game is live, starting soon, or holding the house.
  final String? liveReason;

  /// What has not loaded, when [known] is false.
  final String? unknownReason;

  const GameDayActivity.quiet()
      : known = true,
        liveReason = null,
        unknownReason = null;
  const GameDayActivity.live(String reason)
      : known = true,
        liveReason = reason,
        unknownReason = null;
  const GameDayActivity.unknown(String reason)
      : known = false,
        liveReason = null,
        unknownReason = reason;
}

/// Why the guards said no, or that they said yes.
@immutable
class LadderRepairGate {
  final bool allowed;
  final String code;
  final String reason;

  const LadderRepairGate._(this.allowed, this.code, this.reason);
  const LadderRepairGate.allow() : this._(true, 'ok', 'all guards passed');
  const LadderRepairGate.refuse(String code, String reason)
      : this._(false, code, reason);

  @override
  String toString() => allowed ? 'allowed' : 'refused($code: $reason)';
}

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// The local instants [row] fires on the day before, the day of, and the day
/// after [now] — or none when it cannot fire (dow 0, or a solar row on a
/// controller with no usable coordinates, which the firmware cannot compute).
///
/// [now] and the returned instants are in the CONTROLLER's wall clock. Sun
/// times come from [SunUtils] in the phone's zone and are shifted by
/// [clockOffset] into that frame.
List<DateTime> timerFiresAround(
  BaseBoundaryRow row,
  DateTime now, {
  double? latitude,
  double? longitude,
  Duration clockOffset = Duration.zero,
}) {
  final out = <DateTime>[];
  final coordsUsable = latitude != null &&
      longitude != null &&
      !(latitude == 0 && longitude == 0);
  for (final d in const [-1, 0, 1]) {
    final day = DateTime(now.year, now.month, now.day + d);
    if (row.dow & wledDowMaskForWeekday(day.weekday) == 0) continue;
    if (!row.isSolar) {
      out.add(DateTime(day.year, day.month, day.day, row.hour, row.minute));
      continue;
    }
    if (!coordsUsable) continue;
    final events = <DateTime?>[
      if (row.kind != kBoundaryKindSunset)
        SunUtils.sunriseLocal(latitude, longitude, day),
      if (row.kind != kBoundaryKindSunrise)
        SunUtils.sunsetLocal(latitude, longitude, day),
    ];
    for (final e in events) {
      if (e != null) {
        out.add(e.add(clockOffset).add(Duration(minutes: row.minute)));
      }
    }
  }
  return out;
}

/// The controller's wall clock minus the phone's, to the nearest 15 minutes —
/// i.e. the timezone difference, with sub-quarter-hour drift dropped. Timer
/// rows are in the CONTROLLER's wall clock; a phone in another zone (which
/// clock health tolerates) must compare in that frame. Zero when unknown.
Duration deviceClockOffset(DateTime? deviceTime, DateTime phoneNow) {
  if (deviceTime == null) return Duration.zero;
  final minutes = deviceTime.difference(phoneNow).inSeconds / 60.0;
  return Duration(minutes: (minutes / 15).round() * 15);
}

/// PURE. May the repair write to the controller right now?
///
/// [now] is the phone's local time; [clockOffset] ([deviceClockOffset]) moves
/// it into the controller's wall clock, which is the frame its timer rows fire
/// in. Sun times are computed in the phone's zone and moved the same way.
LadderRepairGate evaluateLadderRepairGuards({
  required DateTime now,
  required List<BaseBoundaryRow>? timerRows,
  required ClockHealth? clockHealth,
  required GameDayActivity gameDay,
  double? latitude,
  double? longitude,
  Duration clockOffset = Duration.zero,
}) {
  if (!gameDay.known) {
    return LadderRepairGate.refuse(
        'game_day_unknown', 'Game Day state not loaded (${gameDay.unknownReason})');
  }
  if (gameDay.liveReason != null) {
    return LadderRepairGate.refuse('game_day_live', gameDay.liveReason!);
  }
  if (clockHealth == null) {
    return const LadderRepairGate.refuse(
        'clock_unknown', 'controller clock could not be read');
  }
  if (clockHealth.clockUnset || clockHealth.tzSuspect) {
    return const LadderRepairGate.refuse('clock_unhealthy',
        'controller clock unset or timezone suspect — timer times unknowable');
  }
  if (timerRows == null) {
    return const LadderRepairGate.refuse(
        'timers_unreadable', 'controller timer table could not be read');
  }
  final deviceNow = now.add(clockOffset);
  for (final row in timerRows) {
    for (final at in timerFiresAround(row, deviceNow,
        latitude: latitude, longitude: longitude, clockOffset: clockOffset)) {
      if (at.difference(deviceNow).abs() <= kLadderRepairTimerGuard) {
        final what = row.role == 'lease' ? 'a lease timer' : 'a timer';
        return LadderRepairGate.refuse(
          row.role == 'lease' ? 'lease_timer_near' : 'timer_near',
          '$what (preset ${row.macro}) fires at ${_hhmm(at)}',
        );
      }
    }
  }
  return const LadderRepairGate.allow();
}

// ── Plan (pure) ──────────────────────────────────────────────────────────────

/// One slot the repair will rewrite.
@immutable
class LadderRepairStep {
  final int presetId;
  final String name;
  final List<String> faults;

  const LadderRepairStep(this.presetId, this.name, this.faults);

  Map<String, Object?> toJson() => {
        'preset': presetId,
        'name': name,
        'faults': faults,
      };

  @override
  String toString() => 'p$presetId→$name(${faults.join('+')})';
}

/// The name a repaired slot is saved under — the builders' own names.
String ladderSlotName(int presetId) => presetId == kLadderOffPresetId
    ? ScheduleSyncService.kNglOffPresetName
    : ScheduleSyncService.kOnPresetSpecs[presetId]!.name;

/// PURE. The dry run: one step per PRESENT bad slot, ascending. A missing slot
/// is never created here — schedule sync owns creating the ladder.
///
/// A slot is bad when the restore verdict says it does not light (or does not
/// darken), AND — for the two presets a server restore can load, 1 and 2 —
/// when it does not STATE `on` for every live bus ([presetAssertsAllChannels],
/// the server gate's R2). That second rule is the bus-change case (#183): a
/// bus added outside the app leaves preset 2 killing the master, so it still
/// "darkens every bus" and the restore verdict is fine, while the server gate
/// reads a preset that never names the new bus and blocks the account. Given
/// [presets] and [deviceChannelIds], such a slot is planned with
/// [LadderFault.channelUnstated]; without them the plan is the verdict's alone.
List<LadderRepairStep> planLadderRepair(
  LadderRestoreVerdict verdict, {
  Map<int, Map<String, dynamic>>? presets,
  List<int> deviceChannelIds = const [],
}) {
  final out = <LadderRepairStep>[];
  for (final p in verdict.presets) {
    if (!p.present) continue;
    final faults = [...p.faults];
    if (presets != null &&
        deviceChannelIds.isNotEmpty &&
        kBaseRestorePresetIds.contains(p.presetId) &&
        !presetAssertsAllChannels(presets[p.presetId], deviceChannelIds)) {
      faults.add(LadderFault.channelUnstated);
    }
    if (faults.isEmpty) continue;
    out.add(LadderRepairStep(p.presetId, ladderSlotName(p.presetId), faults));
  }
  return out;
}

/// PURE. Does a dry run have something new to record?
///
/// True unless [recorded] is a dry-run record with the same plan (slot ids and
/// their fault codes, in order), the same dark channels and the same gate
/// code. Unknown (null), a record from another state (`started`, `repaired`,
/// …), an older version, or anything malformed counts as different — the
/// safe direction is one extra write, never a missing record.
bool dryRunRecordDiffers({
  required Map<String, dynamic>? recorded,
  required List<LadderRepairStep> plan,
  required List<int> darkChannels,
  required String gate,
}) {
  if (recorded == null) return true;
  if (recorded['state'] != 'dry_run') return true;
  if (recorded['version'] != kLadderRepairVersion) return true;
  if (recorded['gate'] != gate) return true;

  String want(Iterable<(int, List<String>)> entries) =>
      [for (final (id, faults) in entries) '$id:${faults.join('+')}'].join('|');
  final storedPlan = recorded['plan'];
  if (storedPlan is! List) return true;
  final stored = <(int, List<String>)>[];
  for (final e in storedPlan) {
    if (e is! Map) return true;
    final id = e['preset'];
    final faults = e['faults'];
    if (id is! num || faults is! List) return true;
    stored.add((id.toInt(), [for (final f in faults) '$f']));
  }
  if (want(stored) != want([for (final s in plan) (s.presetId, s.faults)])) {
    return true;
  }

  final storedDark = recorded['dark_channels'];
  if (storedDark is! List) return true;
  final dark = [for (final c in storedDark) if (c is num) c.toInt()];
  return dark.join(',') != darkChannels.join(',');
}

/// PURE. The state a slot is rewritten with: one segment entry per LIVE BUS,
/// built from the controller's bus list, not from the live segments.
///
/// The builders in schedule_sync walk the live `seg` array; after a bus is
/// added the live array can still hold the OLD segment count until the
/// geometry gate re-splits it, and a preset built from it would again fail to
/// name the new bus — the exact fault being repaired. The bus list is the
/// ground truth the server gate reads, so the shape is built from it.
///
/// The shape is the manual repair procedure's, exactly (owner, 2026-10-06):
///   ON (1/3/4/5): root `on:true`, `bri` 200/51/102/153, `ib:true`; per bus
///                 `on:true`, Solid (fx 0), colour slot 1 Lumina Blue
///                 `[0,212,255,0]`, slots 2 and 3 black.
///   OFF (2):      root `on:false`, `ib:true`; per bus `on:false`, Solid,
///                 every slot black.
/// `ib:true` makes the firmware persist the root state. The live state is no
/// longer an input, so a mock or relay repository changes nothing here.
Map<String, dynamic> ladderRepairState(int presetId, List<int> busIds) {
  final ids = [...busIds]..sort();
  if (presetId == kLadderOffPresetId) {
    return <String, dynamic>{
      'on': false,
      'ib': true,
      'seg': [
        for (final id in ids)
          <String, dynamic>{
            'id': id,
            'on': false,
            'fx': kBaseLookEffectId,
            'col': <List<int>>[
              <int>[0, 0, 0, 0],
              <int>[0, 0, 0, 0],
              <int>[0, 0, 0, 0],
            ],
          },
      ],
    };
  }
  final spec = ScheduleSyncService.kOnPresetSpecs[presetId]!;
  return <String, dynamic>{
    'on': true,
    'bri': spec.bri,
    'ib': true,
    'seg': [
      for (final id in ids)
        <String, dynamic>{'id': id, 'on': true, ...baseLookSegmentFields()},
    ],
  };
}

bool _sameInts(Object? a, Object? b) {
  if (a is! List || b is! List || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final x = a[i], y = b[i];
    if (x is num && y is num) {
      if (x.toInt() != y.toInt()) return false;
    } else {
      return false;
    }
  }
  return true;
}

/// PURE. Did the controller store what the repair sent? Read back after each
/// psave: a 2xx is not persistence on this firmware.
///
/// Root keys must match (`ib` is a request flag the firmware never stores,
/// and `n` is the name). Every sent segment must be present by id with the
/// same `on`; a lit segment must also hold the sent effect and colour slot 1.
bool ladderSlotStored(
    Map<String, dynamic>? stored, Map<String, dynamic> sent) {
  if (stored == null) return false;
  for (final e in sent.entries) {
    if (e.key == 'ib' || e.key == 'seg' || e.key == 'n') continue;
    if (stored[e.key] != e.value) return false;
  }
  final raw = stored['seg'];
  final byId = <int, Map>{};
  if (raw is List) {
    for (var i = 0; i < raw.length; i++) {
      final s = raw[i];
      if (s is Map) byId[s['id'] is int ? s['id'] as int : i] = s;
    }
  }
  for (final s in (sent['seg'] as List).cast<Map>()) {
    final got = byId[s['id'] as int];
    if (got == null || got['on'] != s['on']) return false;
    if (s['on'] == true) {
      if (got['fx'] != s['fx']) return false;
      final want = (s['col'] as List).first;
      final have = got['col'];
      if (have is! List || have.isEmpty || !_sameInts(have.first, want)) {
        return false;
      }
    }
  }
  return true;
}

// ── Outcome ──────────────────────────────────────────────────────────────────

enum LadderRepairOutcome {
  /// restore_lit was true, unmeasured, or only missing slots failed.
  notNeeded,
  modeOff,
  alreadyRan,
  inFlight,

  /// A guard refused, or Game Day state did not load. Retries next connect.
  deferred,

  /// Mode dry_run: plan recorded, nothing written.
  dryRun,

  /// Nothing written: the fresh read, backup or live capture failed.
  aborted,

  /// Every planned slot reads back good.
  repaired,

  /// Some planned slots read back good, some did not.
  partial,

  /// No planned slot reads back good.
  failed,

  /// The caller cancelled (the account changed) before the first write.
  cancelled,
}

/// What one consideration did.
@immutable
class LadderRepairRun {
  final LadderRepairOutcome outcome;
  final String reason;
  final List<LadderRepairStep> plan;
  final List<int> repairedIds;
  final List<int> stillBadIds;

  /// The slot whose save or read-back failed and stopped the run, if any.
  /// Every later planned slot was left untouched.
  final int? stoppedAtId;

  const LadderRepairRun(
    this.outcome,
    this.reason, {
    this.plan = const [],
    this.repairedIds = const [],
    this.stillBadIds = const [],
    this.stoppedAtId,
  });

  bool get wrote =>
      outcome == LadderRepairOutcome.repaired ||
      outcome == LadderRepairOutcome.partial ||
      outcome == LadderRepairOutcome.failed;

  @override
  String toString() => '${outcome.name}: $reason'
      '${plan.isEmpty ? '' : ' plan=$plan'}'
      '${repairedIds.isEmpty ? '' : ' repaired=$repairedIds'}'
      '${stillBadIds.isEmpty ? '' : ' still_bad=$stillBadIds'}';
}

/// What the customer is shown about a repair that wrote. Persisted on the phone
/// until dismissed.
@immutable
class LadderRepairStatus {
  final String controllerId;
  final LadderRepairOutcome outcome;
  final List<int> repairedIds;
  final List<int> stillBadIds;
  final DateTime at;

  /// The customer asked for it ("Repair base lighting"), not a connect.
  final bool userInitiated;

  /// See [LadderRepairRun.stoppedAtId].
  final int? stoppedAtId;

  const LadderRepairStatus({
    required this.controllerId,
    required this.outcome,
    required this.repairedIds,
    required this.stillBadIds,
    required this.at,
    this.userInitiated = false,
    this.stoppedAtId,
  });

  Map<String, Object?> toJson() => {
        'controllerId': controllerId,
        'outcome': outcome.name,
        'repairedIds': repairedIds,
        'stillBadIds': stillBadIds,
        'at': at.toIso8601String(),
        'userInitiated': userInitiated,
        if (stoppedAtId != null) 'stoppedAtId': stoppedAtId,
      };

  static LadderRepairStatus? fromJson(Object? raw) {
    if (raw is! Map) return null;
    try {
      final outcome = LadderRepairOutcome.values
          .firstWhere((o) => o.name == raw['outcome']);
      final stopped = raw['stoppedAtId'];
      return LadderRepairStatus(
        controllerId: raw['controllerId'] as String,
        outcome: outcome,
        repairedIds: (raw['repairedIds'] as List).cast<int>(),
        stillBadIds: (raw['stillBadIds'] as List).cast<int>(),
        at: DateTime.parse(raw['at'] as String),
        userInitiated: raw['userInitiated'] == true,
        stoppedAtId: stopped is num ? stopped.toInt() : null,
      );
    } catch (_) {
      return null;
    }
  }
}

// ── Persistence seam ─────────────────────────────────────────────────────────

/// Where the one-time marker, the backup and the banner status live on the
/// phone. An interface so tests run without SharedPreferences.
abstract class LadderRepairStore {
  Future<bool> hasRun(String controllerId);
  Future<bool> markRan(String controllerId, Map<String, Object?> record);

  /// Re-arms the one-time repair (the bus list changed, #183).
  Future<void> clearRan(String controllerId);

  /// Must return true only when the backup is durably stored — the repair
  /// aborts otherwise.
  Future<bool> saveBackup(String controllerId, String backupJson);

  /// The last backup saved for [controllerId], or null. What
  /// [BaseLadderRepairRunner.restoreFromBackup] puts back.
  Future<String?> readBackup(String controllerId);

  Future<void> saveStatus(LadderRepairStatus status);
}

// ── Runner ───────────────────────────────────────────────────────────────────

/// Everything the runner reads or writes, injected. The provider wires the
/// real ones (base_ladder_repair_providers.dart); tests wire fakes.
class LadderRepairDeps {
  final WledService svc;
  final String controllerId;

  /// The participating buses the connect-time verdict was measured against.
  final List<int> participating;

  final DateTime Function() now;
  final Duration phoneUtcOffset;
  final Future<LadderRepairMode> Function() mode;

  /// Polled until [GameDayActivity.known] or [readinessTimeout].
  final Future<GameDayActivity> Function() gameDay;

  final LadderRepairStore store;

  /// Merge-writes the repair record onto the controller doc. Best effort:
  /// returns false on failure, never throws.
  final Future<bool> Function(Map<String, Object?> record) writeRecord;

  /// Reads the record already on the controller doc (null = none). Used to
  /// keep the dry-run review record from being rewritten on every connect.
  /// Null here, a throw, or no answer within [recordTimeout] all mean
  /// "unknown", and the dry run writes.
  final Future<Map<String, dynamic>?> Function()? readRecord;

  /// Republishes the ladder facts after a write (R2 + restore-lit).
  final Future<void> Function(bool? assertsSegments, LadderRestoreVerdict? v)
      republish;

  /// True while the app is still connected to [svc] — checked before writing.
  final bool Function() stillConnected;

  final void Function()? pausePolling;
  final void Function()? resumePolling;

  final Duration settle;
  final Duration readinessTimeout;
  final Duration readinessPoll;

  /// Bound on each Firestore write (record, republish). Best effort: a write
  /// that has not completed by then is abandoned, never awaited — an offline
  /// set() can wait for the network indefinitely.
  final Duration recordTimeout;

  /// True when the run must stop: the signed-in account changed under it.
  /// Checked before the first write and before every psave; a run that has
  /// already saved something stops where it is and restores the live look.
  final bool Function()? cancelled;

  /// Progress for a user-initiated run: `backup`, `capture`, `save:<id>`,
  /// `verify:<id>`, `restore`, `done`.
  final void Function(String step)? onProgress;

  const LadderRepairDeps({
    required this.svc,
    required this.controllerId,
    required this.participating,
    required this.now,
    required this.phoneUtcOffset,
    required this.mode,
    required this.gameDay,
    required this.store,
    required this.writeRecord,
    this.readRecord,
    required this.republish,
    required this.stillConnected,
    this.pausePolling,
    this.resumePolling,
    this.settle = kLadderRepairSettle,
    this.readinessTimeout = const Duration(minutes: 2),
    this.readinessPoll = const Duration(seconds: 5),
    this.recordTimeout = const Duration(seconds: 10),
    this.cancelled,
    this.onProgress,
  });
}

/// Controllers with a consideration in progress, process-wide. A second
/// connect while one runs is refused, never stacked.
final Set<String> _inFlight = <String>{};

@visibleForTesting
void resetLadderRepairInFlight() => _inFlight.clear();

class BaseLadderRepairRunner {
  final LadderRepairDeps d;
  BaseLadderRepairRunner(this.d);

  void _log(String m) => debugPrint('[LadderRepair] ${d.controllerId}: $m');

  /// The record already on the controller doc, or null when there is none or
  /// it could not be read (bounded; never throws).
  Future<Map<String, dynamic>?> _readRecorded() async {
    final read = d.readRecord;
    if (read == null) return null;
    try {
      return await read().timeout(d.recordTimeout);
    } catch (e) {
      _log('record read did not complete ($e) — treating as unknown');
      return null;
    }
  }

  /// Best-effort, bounded record write (see [LadderRepairDeps.recordTimeout]).
  Future<void> _record(Map<String, Object?> record) async {
    try {
      await d.writeRecord(record).timeout(d.recordTimeout);
    } catch (e) {
      _log('record write did not complete ($e) — continuing');
    }
  }

  /// Consider a repair after a connect whose published verdict was
  /// [atConnect] and whose R2 verdict was [assertsSegments]. Never throws.
  Future<LadderRepairRun> consider(
    LadderRestoreVerdict? atConnect, {
    bool? assertsSegments,
  }) async {
    if (atConnect == null) {
      return const LadderRepairRun(
          LadderRepairOutcome.notNeeded, 'ladder unmeasured');
    }
    // R2 false alone is a reason (#183): the restore verdict can be fine while
    // preset 1 or 2 never names a bus the server gate counts.
    if (atConnect.restoreLit && assertsSegments != false) {
      return const LadderRepairRun(LadderRepairOutcome.notNeeded,
          'ladder lights and states every bus (or unmeasured)');
    }
    if (assertsSegments != false && planLadderRepair(atConnect).isEmpty) {
      return LadderRepairRun(LadderRepairOutcome.notNeeded,
          'only missing slots ${atConnect.missingPresetIds} — schedule sync creates those');
    }
    if (!_inFlight.add(d.controllerId)) {
      return const LadderRepairRun(
          LadderRepairOutcome.inFlight, 'a repair is already being considered');
    }
    try {
      final run = await _consider();
      _log(run.toString());
      return run;
    } catch (e) {
      _log('threw: $e');
      return LadderRepairRun(LadderRepairOutcome.aborted, 'threw: $e');
    } finally {
      _inFlight.remove(d.controllerId);
    }
  }

  /// The customer's own "Repair base lighting" (#183). The tap is the
  /// consent: the fleet mode (`connect_repair`) and the one-time marker do not
  /// apply. Everything else holds — the LAN service, the Game Day / timer /
  /// clock guards, backup, capture, verify, restore. The kill switch
  /// `enabled:false` still means off. Never throws.
  Future<LadderRepairRun> repairNow() async {
    if (!_inFlight.add(d.controllerId)) {
      return const LadderRepairRun(
          LadderRepairOutcome.inFlight, 'a repair is already running');
    }
    try {
      final mode = await d.mode();
      if (mode == LadderRepairMode.off) {
        return const LadderRepairRun(
            LadderRepairOutcome.modeOff, 'config/base_ladder_repair says off');
      }
      final activity = await _awaitGameDay();
      final fresh = await _freshReads();
      if (fresh == null) {
        return const LadderRepairRun(LadderRepairOutcome.aborted,
            'presets, cfg or bus list unreadable on the fresh read');
      }
      final plan = _plan(fresh);
      if (plan.isEmpty) {
        return const LadderRepairRun(LadderRepairOutcome.notNeeded,
            'every ladder preset lights and states every bus — nothing to repair');
      }
      final gate = _gate(fresh, activity);
      if (!gate.allowed) {
        return LadderRepairRun(LadderRepairOutcome.deferred, gate.toString(),
            plan: plan);
      }
      final run = await _execute(fresh, plan, userInitiated: true);
      _log('user repair: $run');
      return run;
    } catch (e) {
      _log('user repair threw: $e');
      return LadderRepairRun(LadderRepairOutcome.aborted, 'threw: $e');
    } finally {
      _inFlight.remove(d.controllerId);
    }
  }

  /// Puts back the presets this phone backed up before its last repair of
  /// this controller — the "Restore previous settings" offer after a repair
  /// that failed. Each stored body is psaved under its own name with its
  /// geometry stripped (a backup carries the bounds of its time, and a psave
  /// must never re-bound a channel). Never throws.
  Future<LadderRepairRun> restoreFromBackup() async {
    if (!_inFlight.add(d.controllerId)) {
      return const LadderRepairRun(
          LadderRepairOutcome.inFlight, 'a repair is already running');
    }
    try {
      final run = await _restoreFromBackup();
      _log('backup restore: $run');
      return run;
    } catch (e) {
      _log('backup restore threw: $e');
      return LadderRepairRun(LadderRepairOutcome.aborted, 'threw: $e');
    } finally {
      _inFlight.remove(d.controllerId);
    }
  }

  bool _cancelled() => d.cancelled?.call() ?? false;
  void _progress(String step) => d.onProgress?.call(step);

  /// Every bus participates unless the caller resolved a narrower set.
  List<int> _participating(List<int> busIds) =>
      d.participating.isEmpty ? busIds : d.participating;

  List<LadderRepairStep> _plan(_FreshReads f) => planLadderRepair(
        f.verdict,
        presets: f.presets,
        deviceChannelIds: f.deviceChannelIds,
      );

  /// Wait for Game Day state to load — unknown is a refusal, not a pass.
  Future<GameDayActivity> _awaitGameDay() async {
    var activity = await d.gameDay();
    final deadline = d.now().add(d.readinessTimeout);
    while (!activity.known && d.now().isBefore(deadline)) {
      await Future<void>.delayed(d.readinessPoll);
      activity = await d.gameDay();
    }
    return activity;
  }

  Future<LadderRepairRun> _consider() async {
    final mode = await d.mode();
    if (mode == LadderRepairMode.off) {
      return const LadderRepairRun(
          LadderRepairOutcome.modeOff, 'config/base_ladder_repair says off');
    }
    if (mode == LadderRepairMode.repair &&
        await d.store.hasRun(d.controllerId)) {
      return const LadderRepairRun(LadderRepairOutcome.alreadyRan,
          'one-time repair already ran for this controller');
    }

    final activity = await _awaitGameDay();

    // ── 1. Dry run on FRESH reads.
    final fresh = await _freshReads();
    if (fresh == null) {
      return const LadderRepairRun(LadderRepairOutcome.aborted,
          'presets, cfg or bus list unreadable on the fresh read');
    }
    final verdict = fresh.verdict;
    final plan = _plan(fresh);
    if (plan.isEmpty) {
      return LadderRepairRun(
          LadderRepairOutcome.notNeeded,
          verdict.restoreLit
              ? 'ladder lights on the fresh read'
              : 'nothing present to rewrite');
    }

    final gate = _gate(fresh, activity);
    final planJson = [for (final s in plan) s.toJson()];

    // Dry run writes nothing to the controller, so the guards do not stop it:
    // the record says what WOULD happen and whether the guards would allow it
    // now — which is what a fleet review of dry-run records needs.
    if (mode == LadderRepairMode.dryRun) {
      // ONE RECORD PER RESULT, NOT PER CONNECT. With dry run the default for
      // the whole fleet, every connect of a phone whose ladder does not light
      // lands here; rewriting an identical record each time is noise and a
      // write per app open. The record is written only when the plan (slots,
      // faults, dark channels) or the gate verdict differs from what the
      // controller doc already holds — whichever phone wrote it.
      final recorded = await _readRecorded();
      if (!dryRunRecordDiffers(
        recorded: recorded,
        plan: plan,
        darkChannels: verdict.darkChannels,
        gate: gate.code,
      )) {
        return LadderRepairRun(LadderRepairOutcome.dryRun,
            'mode dry_run — unchanged since the recorded review, nothing '
            'written (gate: $gate)',
            plan: plan);
      }
      await _record({
        'version': kLadderRepairVersion,
        'state': 'dry_run',
        'plan': planJson,
        'dark_channels': verdict.darkChannels,
        'gate': gate.code,
      });
      return LadderRepairRun(LadderRepairOutcome.dryRun,
          'mode dry_run — nothing written to the controller (gate: $gate)',
          plan: plan);
    }
    if (!gate.allowed) {
      return LadderRepairRun(LadderRepairOutcome.deferred, gate.toString(),
          plan: plan);
    }
    return _execute(fresh, plan, userInitiated: false);
  }

  /// Steps 2–6: backup, record, capture, a final check, one gated psave per
  /// planned slot — each READ BACK before the next, stopping at the first
  /// that does not persist — restore the live look, record, republish the
  /// ladder facts, and (for a connect) the one-time marker.
  Future<LadderRepairRun> _execute(
    _FreshReads fresh,
    List<LadderRepairStep> plan, {
    required bool userInitiated,
  }) async {
    final verdict = fresh.verdict;
    final planJson = [for (final s in plan) s.toJson()];

    if (_cancelled()) {
      return LadderRepairRun(LadderRepairOutcome.cancelled,
          'the account changed before the first write',
          plan: plan);
    }

    // ── 2. Backup — local is REQUIRED.
    _progress('backup');
    final backupJson = jsonEncode({
      'version': kLadderRepairVersion,
      'at': d.now().toIso8601String(),
      'presets': {
        for (final id in const [1, 2, 3, 4, 5])
          if (fresh.presets[id] != null) '$id': fresh.presets[id],
      },
    });
    if (!await d.store.saveBackup(d.controllerId, backupJson)) {
      return LadderRepairRun(LadderRepairOutcome.aborted,
          'local backup failed — nothing written',
          plan: plan);
    }
    await _record({
      'version': kLadderRepairVersion,
      'state': 'started',
      'plan': planJson,
      'dark_channels': verdict.darkChannels,
      'user_initiated': userInitiated,
      // A STRING: preset bodies hold arrays of arrays, which Firestore refuses
      // (#84).
      'backup_json': backupJson,
    });

    // ── 3. Capture — REQUIRED.
    _progress('capture');
    final live = await d.svc.getState();
    if (live == null) {
      return LadderRepairRun(LadderRepairOutcome.aborted,
          'live state unreadable — nothing written',
          plan: plan);
    }

    // ── Last look before the first write, on a SECOND fresh read. The steps
    // above include a Firestore write, which can stall; a lease armed, a clock
    // moved or a preset rewritten in the meantime must be seen, not assumed
    // from the first read. Still the same controller; every planned slot
    // still holds exactly what was planned (and backed up); the guards still
    // pass on the clock as it is NOW; the account is still the one that asked.
    if (!d.stillConnected()) {
      return LadderRepairRun(LadderRepairOutcome.deferred,
          'controller changed before the first write',
          plan: plan);
    }
    final recheck = await _freshReads();
    if (recheck == null) {
      return LadderRepairRun(LadderRepairOutcome.aborted,
          'controller unreadable on the final check — nothing written',
          plan: plan);
    }
    for (final step in plan) {
      if (jsonEncode(recheck.presets[step.presetId]) !=
          jsonEncode(fresh.presets[step.presetId])) {
        return LadderRepairRun(LadderRepairOutcome.deferred,
            'preset ${step.presetId} changed during the repair',
            plan: plan);
      }
    }
    final gate = _gate(recheck, await d.gameDay());
    if (!gate.allowed) {
      return LadderRepairRun(LadderRepairOutcome.deferred, gate.toString(),
          plan: plan);
    }
    if (_cancelled()) {
      return LadderRepairRun(LadderRepairOutcome.cancelled,
          'the account changed before the first write',
          plan: plan);
    }

    // ── 4. One psave per planned slot, gated, read back, stopping at the
    // first failure. The shape is built from the FRESH bus list, never from
    // the live segments (see ladderRepairState).
    final busIds = recheck.deviceChannelIds;
    final saved = <int>[];
    final verified = <int>[];
    int? stoppedAt;
    var cancelledMidway = false;
    // Any save that was ATTEMPTED may have applied live — a psave applies its
    // state before it persists, and a save that timed out or returned false
    // may still have landed. So the restore keys off attempts, not successes.
    var attempted = false;
    var restore = 'not_needed';
    d.pausePolling?.call();
    try {
      final expected = await _expectedShape();
      for (final step in plan) {
        if (_cancelled()) {
          cancelledMidway = true;
          break;
        }
        final state = ladderRepairState(step.presetId, busIds);
        _progress('save:${step.presetId}');
        final out = await gatedPresetSave(
          presetId: step.presetId,
          presetName: step.name,
          expected: expected,
          read: () async => segmentShapeFromState(await d.svc.getState()),
          reprovision: _reprovision,
          label: 'ladder repair',
          save: () {
            attempted = true;
            return d.svc.savePreset(
              presetId: step.presetId,
              state: state,
              presetName: step.name,
            );
          },
        );
        if (!out.saved) {
          _log('p${step.presetId} not saved: ${out.message}');
          stoppedAt = step.presetId;
          break;
        }
        saved.add(step.presetId);
        // Read back before the next save: a 2xx is not persistence on this
        // firmware (the healer's measured settle), and a slot that did not
        // take stops the run — the rest stays as it was, backed up.
        _progress('verify:${step.presetId}');
        await Future<void>.delayed(d.settle);
        final back = await d.svc.readPresets();
        if (!back.isKnown ||
            !ladderSlotStored(back.presets[step.presetId], state)) {
          _log('p${step.presetId} did not read back as saved');
          stoppedAt = step.presetId;
          break;
        }
        verified.add(step.presetId);
      }

      // ── 5. Restore the house exactly as it was captured — every psave
      // applied live, and the repair must leave no visible trace: an OFF house
      // stays off (master `on:false` restored), a lit house gets its look back
      // (master bri, every segment's on/colour/effect/palette/opacity/freeze).
      if (attempted) {
        _progress('restore');
        restore = await _restoreLive(live) ? 'ok' : 'failed';
      }
    } finally {
      d.resumePolling?.call();
    }

    // ── 6. Read back, record, republish, mark.
    final after = await d.svc.readPresets();
    final afterVerdict = after.isKnown
        ? evaluateLadderRestore(
            presets: after.presets,
            participating: _participating(busIds),
            deviceChannelIds: busIds,
          )
        : null;
    final afterPlan = afterVerdict == null
        ? null
        : planLadderRepair(afterVerdict,
            presets: after.presets, deviceChannelIds: busIds);
    final repaired = <int>[];
    final stillBad = <int>[];
    for (final step in plan) {
      final good = verified.contains(step.presetId) &&
          afterPlan != null &&
          !afterPlan.any((s) => s.presetId == step.presetId);
      (good ? repaired : stillBad).add(step.presetId);
    }
    final outcome = cancelledMidway && !attempted
        ? LadderRepairOutcome.cancelled
        : stillBad.isEmpty
            ? LadderRepairOutcome.repaired
            : repaired.isEmpty
                ? LadderRepairOutcome.failed
                : LadderRepairOutcome.partial;

    final record = <String, Object?>{
      'version': kLadderRepairVersion,
      'state': outcome.name,
      'saved': saved,
      'repaired': repaired,
      'still_bad': stillBad,
      'restore': restore,
      'user_initiated': userInitiated,
      if (stoppedAt != null) 'stopped_at': stoppedAt,
      if (cancelledMidway) 'cancelled': true,
    };
    await _record(record);
    if (!userInitiated) await d.store.markRan(d.controllerId, record);
    await d.store.saveStatus(LadderRepairStatus(
      controllerId: d.controllerId,
      outcome: outcome,
      repairedIds: repaired,
      stillBadIds: stillBad,
      at: d.now(),
      userInitiated: userInitiated,
      stoppedAtId: stoppedAt,
    ));
    if (after.isKnown) {
      try {
        await d
            .republish(
              ladderAssertsSegments(
                  presets: after.presets, deviceChannelIds: busIds),
              afterVerdict,
            )
            .timeout(d.recordTimeout);
      } catch (e) {
        _log('republish failed: $e');
      }
    }
    _progress('done');
    return LadderRepairRun(
      outcome,
      cancelledMidway
          ? 'stopped: the account changed — wrote ${saved.length} of '
              '${plan.length}'
          : 'wrote ${saved.length} of ${plan.length} planned preset(s)'
              '${stoppedAt == null ? '' : ', stopped at preset $stoppedAt'}',
      plan: plan,
      repairedIds: repaired,
      stillBadIds: stillBad,
      stoppedAtId: stoppedAt,
    );
  }

  Future<LadderRepairRun> _restoreFromBackup() async {
    final raw = await d.store.readBackup(d.controllerId);
    if (raw == null) {
      return const LadderRepairRun(
          LadderRepairOutcome.aborted, 'no backup on this phone');
    }
    final decoded = jsonDecode(raw);
    final stored = decoded is Map ? decoded['presets'] : null;
    final bodies = <int, Map<String, dynamic>>{};
    if (stored is Map) {
      for (final e in stored.entries) {
        final id = int.tryParse('${e.key}');
        final body = e.value;
        if (id != null && body is Map) {
          bodies[id] = Map<String, dynamic>.from(body);
        }
      }
    }
    if (bodies.isEmpty) {
      return const LadderRepairRun(
          LadderRepairOutcome.aborted, 'the backup holds no presets');
    }
    if (!d.stillConnected()) {
      return const LadderRepairRun(LadderRepairOutcome.deferred,
          'controller changed — nothing put back');
    }
    _progress('capture');
    final live = await d.svc.getState();
    if (live == null) {
      return const LadderRepairRun(LadderRepairOutcome.aborted,
          'live state unreadable — nothing put back');
    }

    final ids = bodies.keys.toList()..sort();
    final putBack = <int>[];
    final failed = <int>[];
    var attempted = false;
    var restore = 'not_needed';
    d.pausePolling?.call();
    try {
      for (final id in ids) {
        if (_cancelled()) break;
        if (attempted) await Future<void>.delayed(d.settle);
        final body = stripGeometry(Map<String, dynamic>.from(bodies[id]!));
        final name = body.remove('n');
        // `ib` persists the root state the body carries; a body that carries
        // none must not have the live root pinned onto it.
        if (body.containsKey('on') || body.containsKey('bri')) {
          body['ib'] = true;
        }
        _progress('save:$id');
        attempted = true;
        var ok = false;
        try {
          ok = await d.svc.savePreset(
            presetId: id,
            state: body,
            presetName: name is String ? name : null,
          );
        } catch (e) {
          _log('backup restore p$id threw: $e');
        }
        (ok ? putBack : failed).add(id);
      }
      if (attempted) {
        _progress('restore');
        restore = await _restoreLive(live) ? 'ok' : 'failed';
      }
    } finally {
      d.resumePolling?.call();
    }

    await _record({
      'version': kLadderRepairVersion,
      'state': 'backup_restored',
      'restored': putBack,
      'failed': failed,
      'restore': restore,
    });
    final after = await d.svc.readPresets();
    final info = await d.svc.fetchClockInfo();
    final busIds = info?.hardware == null
        ? const <int>[]
        : deviceChannelsFromConfig(info!.hardware!).map((c) => c.id).toList();
    if (after.isKnown && busIds.isNotEmpty) {
      try {
        await d
            .republish(
              ladderAssertsSegments(
                  presets: after.presets, deviceChannelIds: busIds),
              evaluateLadderRestore(
                presets: after.presets,
                participating: _participating(busIds),
                deviceChannelIds: busIds,
              ),
            )
            .timeout(d.recordTimeout);
      } catch (e) {
        _log('republish failed: $e');
      }
    }
    _progress('done');
    return LadderRepairRun(
      failed.isEmpty
          ? LadderRepairOutcome.repaired
          : putBack.isEmpty
              ? LadderRepairOutcome.failed
              : LadderRepairOutcome.partial,
      'put back ${putBack.length} of ${ids.length} saved preset(s)',
      repairedIds: putBack,
      stillBadIds: failed,
    );
  }

  /// PURE. The payload that puts [live] (a `/json/state` capture) back.
  ///
  /// Geometry (`start`/`stop`/`rev`/`mi`) is STRIPPED: a capture carries it,
  /// the repair never changed it, and an apply must never re-state shape —
  /// the wire pin strips it in release and ASSERTS in debug, which would
  /// abort the restore after the saves and leave the house on the repair's
  /// look. `transition: 0` snaps back with no fade.
  @visibleForTesting
  static Map<String, dynamic> restorePayloadFor(Map<String, dynamic> live) =>
      stripGeometry(<String, dynamic>{
        'transition': 0,
        if (live['on'] != null) 'on': live['on'],
        if (live['bri'] != null) 'bri': live['bri'],
        if (live['seg'] != null) 'seg': live['seg'],
      });

  /// Apply [restorePayloadFor] once, and once more after the settle if the
  /// controller did not accept it. True when it was accepted.
  Future<bool> _restoreLive(Map<String, dynamic> live) async {
    final payload = restorePayloadFor(live);
    if (payload.length <= 1) return true; // captured nothing restorable
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) await Future<void>.delayed(d.settle);
      try {
        if (await d.svc.applyJson(payload)) return true;
      } catch (e) {
        _log('restore attempt ${attempt + 1} threw: $e');
      }
    }
    _log('live-state restore after the repair FAILED twice');
    return false;
  }

  LadderRepairGate _gate(_FreshReads f, GameDayActivity activity) =>
      evaluateLadderRepairGuards(
        now: d.now(),
        timerRows: f.timerRows,
        clockHealth: f.clockHealth,
        gameDay: activity,
        latitude: f.latitude,
        longitude: f.longitude,
        clockOffset: f.clockOffset,
      );

  Future<_FreshReads?> _freshReads() async {
    final info = await d.svc.fetchClockInfo();
    if (info == null || info.hardware == null) return null;
    final buses =
        deviceChannelsFromConfig(info.hardware!).map((c) => c.id).toList();
    final read = await d.svc.readPresets();
    if (!read.isKnown) return null;
    final verdict = evaluateLadderRestore(
      presets: read.presets,
      participating: _participating(buses),
      deviceChannelIds: buses,
    );
    if (verdict == null) return null;
    return _FreshReads(
      presets: read.presets,
      verdict: verdict,
      deviceChannelIds: buses,
      timerRows: extractBaseBoundaries(info.timerRows),
      clockHealth: evaluateClockHealth(
        device: info,
        phoneNow: d.now(),
        phoneUtcOffset: d.phoneUtcOffset,
      ),
      latitude: info.latitude,
      longitude: info.longitude,
      clockOffset: deviceClockOffset(info.deviceTime, d.now()),
    );
  }

  Future<List<SegmentShape>> _expectedShape() async {
    try {
      final cfg = await d.svc.getConfig();
      if (cfg == null) return const [];
      return expectedShapeFromChannels(deviceChannelsFromConfig(cfg));
    } catch (_) {
      return const [];
    }
  }

  Future<bool> _reprovision(List<SegmentShape> want) async {
    try {
      return await d.svc.applyGeometryJson({
        'seg': [
          for (final s in want) {'id': s.id, 'start': s.start, 'stop': s.stop},
        ],
      });
    } catch (_) {
      return false;
    }
  }
}

class _FreshReads {
  final Map<int, Map<String, dynamic>> presets;
  final LadderRestoreVerdict verdict;
  final List<int> deviceChannelIds;
  final List<BaseBoundaryRow>? timerRows;
  final ClockHealth clockHealth;
  final double? latitude;
  final double? longitude;
  final Duration clockOffset;

  const _FreshReads({
    required this.presets,
    required this.verdict,
    required this.deviceChannelIds,
    required this.timerRows,
    required this.clockHealth,
    required this.latitude,
    required this.longitude,
    required this.clockOffset,
  });
}
