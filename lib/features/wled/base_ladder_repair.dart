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
    show ladderAssertsSegments;
import 'package:nexgen_command/features/wled/base_ladder_restore.dart';
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
List<LadderRepairStep> planLadderRepair(LadderRestoreVerdict verdict) => [
      for (final p in verdict.presets)
        if (p.present && !p.ok)
          LadderRepairStep(p.presetId, ladderSlotName(p.presetId), p.faults),
    ];

/// PURE. The state a slot is rewritten with — the builders' output, nothing
/// hand-written here.
Map<String, dynamic> ladderRepairState(
    int presetId, Map<String, dynamic>? liveState) {
  if (presetId == kLadderOffPresetId) {
    return ScheduleSyncService.buildNglOffPresetState(liveState);
  }
  final spec = ScheduleSyncService.kOnPresetSpecs[presetId]!;
  return ScheduleSyncService.buildNglOnPresetState(spec.bri, liveState);
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
}

/// What one consideration did.
@immutable
class LadderRepairRun {
  final LadderRepairOutcome outcome;
  final String reason;
  final List<LadderRepairStep> plan;
  final List<int> repairedIds;
  final List<int> stillBadIds;

  const LadderRepairRun(
    this.outcome,
    this.reason, {
    this.plan = const [],
    this.repairedIds = const [],
    this.stillBadIds = const [],
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

  const LadderRepairStatus({
    required this.controllerId,
    required this.outcome,
    required this.repairedIds,
    required this.stillBadIds,
    required this.at,
  });

  Map<String, Object?> toJson() => {
        'controllerId': controllerId,
        'outcome': outcome.name,
        'repairedIds': repairedIds,
        'stillBadIds': stillBadIds,
        'at': at.toIso8601String(),
      };

  static LadderRepairStatus? fromJson(Object? raw) {
    if (raw is! Map) return null;
    try {
      final outcome = LadderRepairOutcome.values
          .firstWhere((o) => o.name == raw['outcome']);
      return LadderRepairStatus(
        controllerId: raw['controllerId'] as String,
        outcome: outcome,
        repairedIds: (raw['repairedIds'] as List).cast<int>(),
        stillBadIds: (raw['stillBadIds'] as List).cast<int>(),
        at: DateTime.parse(raw['at'] as String),
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

  /// Must return true only when the backup is durably stored — the repair
  /// aborts otherwise.
  Future<bool> saveBackup(String controllerId, String backupJson);

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
    required this.republish,
    required this.stillConnected,
    this.pausePolling,
    this.resumePolling,
    this.settle = kLadderRepairSettle,
    this.readinessTimeout = const Duration(minutes: 2),
    this.readinessPoll = const Duration(seconds: 5),
    this.recordTimeout = const Duration(seconds: 10),
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

  /// Best-effort, bounded record write (see [LadderRepairDeps.recordTimeout]).
  Future<void> _record(Map<String, Object?> record) async {
    try {
      await d.writeRecord(record).timeout(d.recordTimeout);
    } catch (e) {
      _log('record write did not complete ($e) — continuing');
    }
  }

  /// Consider a repair after a connect whose published verdict was
  /// [atConnect]. Never throws.
  Future<LadderRepairRun> consider(LadderRestoreVerdict? atConnect) async {
    if (atConnect == null || atConnect.restoreLit) {
      return const LadderRepairRun(
          LadderRepairOutcome.notNeeded, 'ladder lights (or unmeasured)');
    }
    if (planLadderRepair(atConnect).isEmpty) {
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

    // ── Wait for Game Day state to load — unknown is a refusal, not a pass.
    var activity = await d.gameDay();
    final deadline = d.now().add(d.readinessTimeout);
    while (!activity.known && d.now().isBefore(deadline)) {
      await Future<void>.delayed(d.readinessPoll);
      activity = await d.gameDay();
    }

    // ── 1. Dry run on FRESH reads.
    final fresh = await _freshReads();
    if (fresh == null) {
      return const LadderRepairRun(LadderRepairOutcome.aborted,
          'presets, cfg or bus list unreadable on the fresh read');
    }
    final verdict = fresh.verdict;
    if (verdict.restoreLit) {
      return const LadderRepairRun(
          LadderRepairOutcome.notNeeded, 'ladder lights on the fresh read');
    }
    final plan = planLadderRepair(verdict);
    if (plan.isEmpty) {
      return const LadderRepairRun(
          LadderRepairOutcome.notNeeded, 'nothing present to rewrite');
    }

    var gate = _gate(fresh, activity);
    final planJson = [for (final s in plan) s.toJson()];

    // Dry run writes nothing to the controller, so the guards do not stop it:
    // the record says what WOULD happen and whether the guards would allow it
    // now — which is what a fleet review of dry-run records needs.
    if (mode == LadderRepairMode.dryRun) {
      await _record({
        'version': kLadderRepairVersion,
        'state': 'dry_run',
        'plan': planJson,
        'dark_channels': verdict.darkChannels,
        'gate': gate.code,
      });
      return LadderRepairRun(LadderRepairOutcome.dryRun,
          'mode dry_run — nothing written (gate: $gate)', plan: plan);
    }
    if (!gate.allowed) {
      return LadderRepairRun(LadderRepairOutcome.deferred, gate.toString(),
          plan: plan);
    }

    // ── 2. Backup — local is REQUIRED.
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
          'local backup failed — nothing written', plan: plan);
    }
    await _record({
      'version': kLadderRepairVersion,
      'state': 'started',
      'plan': planJson,
      'dark_channels': verdict.darkChannels,
      // A STRING: preset bodies hold arrays of arrays, which Firestore refuses
      // (#84).
      'backup_json': backupJson,
    });

    // ── 3. Capture — REQUIRED.
    final live = await d.svc.getState();
    if (live == null) {
      return LadderRepairRun(LadderRepairOutcome.aborted,
          'live state unreadable — nothing written', plan: plan);
    }

    // ── Last look before the first write, on a SECOND fresh read. The steps
    // above include a Firestore write, which can stall; a lease armed, a clock
    // moved or a preset rewritten in the meantime must be seen, not assumed
    // from the first read. Still the same controller; every planned slot
    // still holds exactly what was planned (and backed up); the guards still
    // pass on the clock as it is NOW.
    if (!d.stillConnected()) {
      return LadderRepairRun(LadderRepairOutcome.deferred,
          'controller changed before the first write', plan: plan);
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
            'preset ${step.presetId} changed during the repair', plan: plan);
      }
    }
    gate = _gate(recheck, await d.gameDay());
    if (!gate.allowed) {
      return LadderRepairRun(LadderRepairOutcome.deferred, gate.toString(),
          plan: plan);
    }

    // ── 4. One psave per bad preset, gated, no retry pass.
    final saved = <int>[];
    // Any save that was ATTEMPTED may have applied live — a psave applies its
    // state before it persists, and a save that timed out or returned false
    // may still have landed. So the restore keys off attempts, not successes.
    var attempted = false;
    var restore = 'not_needed';
    d.pausePolling?.call();
    try {
      final expected = await _expectedShape();
      for (var i = 0; i < plan.length; i++) {
        final step = plan[i];
        if (i > 0) await Future<void>.delayed(d.settle);
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
              state: ladderRepairState(step.presetId, live),
              presetName: step.name,
            );
          },
        );
        if (out.saved) saved.add(step.presetId);
        if (!out.saved) _log('p${step.presetId} not saved: ${out.message}');
      }

      // ── 5. Restore the house exactly as it was captured — every psave
      // applied live, and the repair must leave no visible trace: an OFF house
      // stays off (master `on:false` restored), a lit house gets its look back
      // (master bri, every segment's on/colour/effect/palette/opacity/freeze).
      if (attempted) {
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
            participating: d.participating,
            deviceChannelIds: fresh.deviceChannelIds,
          )
        : null;
    final repaired = <int>[];
    final stillBad = <int>[];
    for (final step in plan) {
      final p = afterVerdict?.presets
          .where((v) => v.presetId == step.presetId)
          .firstOrNull;
      (p != null && p.ok ? repaired : stillBad).add(step.presetId);
    }
    final outcome = stillBad.isEmpty
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
    };
    await _record(record);
    await d.store.markRan(d.controllerId, record);
    await d.store.saveStatus(LadderRepairStatus(
      controllerId: d.controllerId,
      outcome: outcome,
      repairedIds: repaired,
      stillBadIds: stillBad,
      at: d.now(),
    ));
    if (after.isKnown) {
      try {
        await d
            .republish(
              ladderAssertsSegments(
                  presets: after.presets,
                  deviceChannelIds: fresh.deviceChannelIds),
              afterVerdict,
            )
            .timeout(d.recordTimeout);
      } catch (e) {
        _log('republish failed: $e');
      }
    }
    return LadderRepairRun(outcome,
        'wrote ${saved.length} of ${plan.length} planned preset(s)',
        plan: plan, repairedIds: repaired, stillBadIds: stillBad);
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
      participating: d.participating,
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
