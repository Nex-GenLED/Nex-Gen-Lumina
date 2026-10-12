// #183 — the ladder repair after a bus is added outside the app.
//
// The scene: a controller with three buses and ladder presets 1-5 saved for
// them. A fourth bus is added in WLED's own LED settings page. Now presets 1
// and 2 name three of the four buses, the server gate (R2) reads that and
// blocks the account, and the on-connect repair never included preset 2.
//
// Pinned here:
//   1. the repair rewrites 1-5 for four channels in EXACTLY the manual shape;
//   2. presets that already name every bus are not rewritten;
//   3. a save that fails, or does not read back, STOPS the run — nothing after
//      it is touched — and the backup can be put back;
//   4. nothing is written when everything is already fine;
//   5. the customer's own repair works with the fleet flag absent, and never
//      during a live Game Day window;
//   6. an account switch mid-repair aborts;
//   7. a start with no end is treated as ended after kickoff + the hard cap;
//   8. the bus-change watcher re-arms and re-runs only on a real change.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/game_day/game_day_server_status.dart';
import 'package:nexgen_command/features/wled/base_ladder_denormalizer.dart';
import 'package:nexgen_command/features/wled/base_ladder_repair.dart';
import 'package:nexgen_command/features/wled/base_ladder_repair_providers.dart';
import 'package:nexgen_command/features/wled/base_ladder_restore.dart';
import 'package:nexgen_command/features/wled/base_look.dart';
import 'package:nexgen_command/features/wled/clock_health.dart';
import 'package:nexgen_command/features/wled/controller_defaults_healer.dart';
import 'package:nexgen_command/features/wled/wled_hardware_config.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';

// A quiet Tuesday afternoon, clear of every timer.
final DateTime _now = DateTime(2026, 10, 6, 13, 0);
const Duration _cdt = Duration(hours: -5);
const List<int> _three = [0, 1, 2];
const List<int> _four = [0, 1, 2, 3];

const WledHardwareConfig _threeBuses = WledHardwareConfig(
  totalLeds: 390,
  buses: [
    WledLedBus(pin: [2], start: 0, len: 162),
    WledLedBus(pin: [14], start: 162, len: 128),
    WledLedBus(pin: [16], start: 290, len: 100),
  ],
);

const WledHardwareConfig _fourBuses = WledHardwareConfig(
  totalLeds: 480,
  buses: [
    WledLedBus(pin: [2], start: 0, len: 162),
    WledLedBus(pin: [14], start: 162, len: 128),
    WledLedBus(pin: [16], start: 290, len: 100),
    WledLedBus(pin: [18], start: 390, len: 90),
  ],
);

List<List<int>> _black() => [
      [0, 0, 0, 0],
      [0, 0, 0, 0],
      [0, 0, 0, 0],
    ];

/// The exact shape the manual procedure saved (owner, 2026-10-06), as a
/// STORED preset (no `ib`, with its name) for [buses].
Map<String, dynamic> _storedOn(String name, int bri, List<int> buses) => {
      'n': name,
      'on': true,
      'bri': bri,
      'seg': [
        for (final id in buses)
          {'id': id, 'on': true, 'fx': 0, 'col': baseLookColSlots()},
      ],
    };

Map<String, dynamic> _storedOff(List<int> buses) => {
      'n': 'NGL Off',
      'on': false,
      'seg': [
        for (final id in buses) {'id': id, 'on': false, 'fx': 0, 'col': _black()},
      ],
    };

/// Presets 1-5 saved for [buses].
Map<int, Map<String, dynamic>> _ladderFor(List<int> buses) => {
      1: _storedOn('NGL On', 200, buses),
      2: _storedOff(buses),
      3: _storedOn('NGL Dim', 51, buses),
      4: _storedOn('NGL Low', 102, buses),
      5: _storedOn('NGL Medium', 153, buses),
    };

/// What the repair must SEND for [presetId] on [buses] — the manual shape.
Map<String, dynamic> _wantSent(int presetId, List<int> buses) {
  if (presetId == 2) {
    return {
      'on': false,
      'ib': true,
      'seg': [
        for (final id in buses) {'id': id, 'on': false, 'fx': 0, 'col': _black()},
      ],
    };
  }
  const bri = {1: 200, 3: 51, 4: 102, 5: 153};
  return {
    'on': true,
    'bri': bri[presetId],
    'ib': true,
    'seg': [
      for (final id in buses)
        {'id': id, 'on': true, 'fx': 0, 'col': baseLookColSlots()},
    ],
  };
}

Map<String, dynamic> _live(List<int> segIds) => {
      'on': true,
      'bri': 90,
      'seg': [
        for (final id in segIds)
          {
            'id': id,
            'on': true,
            'fx': 12,
            'col': [
              [227, 24, 55, 0],
            ],
          },
      ],
    };

class _Ctl extends WledService {
  _Ctl({
    required this.presets,
    required this.hardware,
    required this.live,
    this.failSaves = const {},
    this.phantomSaves = const {},
  }) : super('http://mock');

  Map<int, Map<String, dynamic>> presets;
  WledHardwareConfig hardware;
  Map<String, dynamic> live;

  /// Saves that return false. Mutable so a test can clear the fault before
  /// the backup is put back.
  Set<int> failSaves;

  /// Saves that return TRUE but never persist (a 2xx that did not take).
  final Set<int> phantomSaves;

  final List<String> log = [];
  final Map<int, Map<String, dynamic>> savedStates = {};
  final List<Map<String, dynamic>> applied = [];

  int get saves => log.where((e) => e.startsWith('save:')).length;
  int get controllerWrites =>
      log.where((e) => e.startsWith('save:') || e == 'apply').length;

  @override
  Future<ControllerClockInfo?> fetchClockInfo() async {
    log.add('info');
    return ControllerClockInfo(
      deviceTime: _now,
      tzIndex: 5,
      tzOffsetSeconds: 0,
      latitude: 39.1,
      longitude: -94.6,
      ntpHost: kHealNtpHost,
      timerRows: const [],
      hardware: hardware,
    );
  }

  @override
  Future<PresetsRead> readPresets() async {
    log.add('presets');
    // A deep copy, as a real read is: the runner must not see later saves
    // through a shared body.
    return PresetsRead.available({
      for (final e in presets.entries)
        e.key: jsonDecode(jsonEncode(e.value)) as Map<String, dynamic>,
    });
  }

  @override
  Future<Map<String, dynamic>?> getState() async {
    log.add('state');
    return jsonDecode(jsonEncode(live)) as Map<String, dynamic>;
  }

  @override
  Future<WledHardwareConfig?> getConfig() async => null;

  @override
  Future<bool> savePreset({
    required int presetId,
    required Map<String, dynamic> state,
    String? presetName,
  }) async {
    log.add('save:$presetId');
    if (failSaves.contains(presetId)) return false;
    savedStates[presetId] = jsonDecode(jsonEncode(state)) as Map<String, dynamic>;
    if (phantomSaves.contains(presetId)) return true;
    presets = {
      ...presets,
      presetId: {'n': presetName, ...state}..remove('ib'),
    };
    return true;
  }

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    log.add('apply');
    applied.add(payload);
    return true;
  }
}

class _Store implements LadderRepairStore {
  _Store(this.log);
  final List<String> log;
  bool ran = false;
  String? backup;
  Map<String, Object?>? marker;
  LadderRepairStatus? status;

  @override
  Future<bool> hasRun(String controllerId) async => ran;
  @override
  Future<bool> markRan(String controllerId, Map<String, Object?> record) async {
    log.add('marker');
    marker = record;
    ran = true;
    return true;
  }

  @override
  Future<void> clearRan(String controllerId) async {
    ran = false;
    marker = null;
  }

  @override
  Future<bool> saveBackup(String controllerId, String backupJson) async {
    log.add('backup');
    backup = backupJson;
    return true;
  }

  @override
  Future<String?> readBackup(String controllerId) async => backup;
  @override
  Future<void> saveStatus(LadderRepairStatus s) async {
    log.add('status');
    status = s;
  }
}

class _Harness {
  _Harness({
    Map<int, Map<String, dynamic>>? presets,
    WledHardwareConfig hardware = _fourBuses,
    Map<String, dynamic>? live,
    Set<int> failSaves = const {},
    Set<int> phantomSaves = const {},
    this.mode = LadderRepairMode.dryRun, // the fleet flag ABSENT
    this.activity = const GameDayActivity.quiet(),
    this.participating = const [],
  }) {
    ctl = _Ctl(
      presets: presets ?? _ladderFor(_three),
      hardware: hardware,
      live: live ?? _live(_three),
      failSaves: failSaves,
      phantomSaves: phantomSaves,
    );
    store = _Store(ctl.log);
  }

  late final _Ctl ctl;
  late final _Store store;
  LadderRepairMode mode;
  GameDayActivity activity;
  List<int> participating;
  bool cancelled = false;
  final List<String> steps = [];
  final List<Map<String, Object?>> records = [];
  final List<({bool? asserts, LadderRestoreVerdict? v})> republished = [];
  void Function(String step)? onStep;

  BaseLadderRepairRunner runner() => BaseLadderRepairRunner(LadderRepairDeps(
        svc: ctl,
        controllerId: 'AA00000000A1',
        participating: participating,
        now: () => _now,
        phoneUtcOffset: _cdt,
        mode: () async => mode,
        gameDay: () async => activity,
        store: store,
        writeRecord: (r) async {
          ctl.log.add('record:${r['state']}');
          records.add(r);
          return true;
        },
        republish: (a, v) async => republished.add((asserts: a, v: v)),
        stillConnected: () => true,
        settle: Duration.zero,
        readinessTimeout: Duration.zero,
        readinessPoll: Duration.zero,
        cancelled: () => cancelled,
        onProgress: (s) {
          steps.add(s);
          onStep?.call(s);
        },
      ));

  List<int> get busIds =>
      [for (var i = 0; i < ctl.hardware.buses.length; i++) i];

  LadderRestoreVerdict verdict() => evaluateLadderRestore(
        presets: ctl.presets,
        participating: participating.isEmpty ? busIds : participating,
        deviceChannelIds: busIds,
      )!;

  bool? r2() =>
      ladderAssertsSegments(presets: ctl.presets, deviceChannelIds: busIds);
}

void main() {
  setUp(resetLadderRepairInFlight);

  group('the plan after a fourth bus (pure)', () {
    test('presets 1-5 saved for three buses: 1/3/4/5 leave bus 3 dark and 1 '
        'and 2 do not state it — all five are planned', () {
      final presets = _ladderFor(_three);
      final v = evaluateLadderRestore(
          presets: presets, participating: _four, deviceChannelIds: _four)!;
      final plan =
          planLadderRepair(v, presets: presets, deviceChannelIds: _four);
      expect(plan.map((s) => s.presetId), [1, 2, 3, 4, 5]);
      expect(plan.first.faults,
          [LadderFault.channelAbsent, LadderFault.channelUnstated]);
      expect(plan[1].faults, [LadderFault.channelUnstated],
          reason: 'OFF darkens via the master, so it is not a restore fault — '
              'it is the R2 fault the server gate reads');
      expect(plan[2].faults, [LadderFault.channelAbsent]);
    });

    test('without presets and bus ids the plan is the verdict\'s alone (the '
        'old behaviour): preset 2 is NOT planned', () {
      final presets = _ladderFor(_three);
      final v = evaluateLadderRestore(
          presets: presets, participating: _four, deviceChannelIds: _four)!;
      expect(planLadderRepair(v).map((s) => s.presetId), [1, 3, 4, 5]);
    });

    test('presets that already name every bus are not planned', () {
      final presets = _ladderFor(_four);
      final v = evaluateLadderRestore(
          presets: presets, participating: _four, deviceChannelIds: _four)!;
      expect(planLadderRepair(v, presets: presets, deviceChannelIds: _four),
          isEmpty);
    });

    test('the repair state is the manual shape, one entry per LIVE BUS — not '
        'per live segment', () {
      for (final id in const [1, 3, 4, 5]) {
        expect(ladderRepairState(id, _four), _wantSent(id, _four));
      }
      expect(ladderRepairState(2, _four), _wantSent(2, _four));
      // Unsorted input, same output.
      expect(ladderRepairState(1, const [3, 1, 0, 2]), _wantSent(1, _four));
    });

    test('ladderSlotStored: the read-back must hold what was sent', () {
      final sent = _wantSent(1, _four);
      final stored = {'n': 'NGL On', ...sent}..remove('ib');
      expect(ladderSlotStored(stored, sent), isTrue);
      expect(ladderSlotStored(null, sent), isFalse);
      expect(ladderSlotStored({...stored, 'bri': 199}, sent), isFalse);
      final missingBus = {...stored, 'seg': (stored['seg'] as List).sublist(0, 3)};
      expect(ladderSlotStored(missingBus, sent), isFalse);
      final black = jsonDecode(jsonEncode(stored)) as Map<String, dynamic>;
      ((black['seg'] as List).first as Map)['col'] = _black();
      expect(ladderSlotStored(black, sent), isFalse);
      // The OFF slot: segments off, nothing about colour is required.
      final off = _wantSent(2, _four);
      expect(ladderSlotStored({'n': 'NGL Off', ...off}..remove('ib'), off),
          isTrue);
    });
  });

  group('the customer\'s repair (repairNow) — fleet flag ABSENT', () {
    test('rewrites 1-5 for four channels in exactly the manual shape, in '
        'order, reading each back before the next; marker NOT set', () async {
      final h = _Harness();
      expect(h.r2(), isFalse, reason: 'the scene: R2 false after the 4th bus');
      final run = await h.runner().repairNow();

      expect(run.outcome, LadderRepairOutcome.repaired);
      expect(run.repairedIds, [1, 2, 3, 4, 5]);
      for (final id in const [1, 2, 3, 4, 5]) {
        expect(h.ctl.savedStates[id], _wantSent(id, _four), reason: 'p$id');
      }
      // save, read back, save, read back …
      final writes = h.ctl.log.where((e) => e.startsWith('save:')).toList();
      expect(writes, ['save:1', 'save:2', 'save:3', 'save:4', 'save:5']);
      for (var i = 0; i < h.ctl.log.length - 1; i++) {
        if (h.ctl.log[i].startsWith('save:')) {
          expect(h.ctl.log[i + 1], 'presets',
              reason: '${h.ctl.log[i]} must be read back before anything else');
        }
      }
      // Live look restored, facts republished at once, status says the
      // customer asked, no one-time marker for a user repair.
      expect(h.ctl.applied, isNotEmpty);
      expect(h.ctl.applied.last['transition'], 0);
      expect(h.republished.single.asserts, isTrue);
      expect(h.republished.single.v!.restoreLit, isTrue);
      expect(h.store.status!.userInitiated, isTrue);
      expect(h.store.marker, isNull);
      expect(h.store.ran, isFalse);
      expect(h.r2(), isTrue);
      expect(h.records.last['user_initiated'], true);
    });

    test('the backup holds the OLD three-bus bodies of 1-5', () async {
      final h = _Harness();
      await h.runner().repairNow();
      final backup = jsonDecode(h.store.backup!) as Map<String, dynamic>;
      final presets = backup['presets'] as Map<String, dynamic>;
      expect(presets.keys.toSet(), {'1', '2', '3', '4', '5'});
      expect((presets['1']['seg'] as List).length, 3);
      expect(h.records.first['state'], 'started');
      expect(h.records.first['backup_json'], h.store.backup);
    });

    test('presets that already name every bus are not rewritten: only the '
        'black Dim is', () async {
      final presets = _ladderFor(_four);
      ((presets[3]!['seg'] as List).first as Map)['col'] = _black();
      final h = _Harness(presets: presets, live: _live(_four));
      final run = await h.runner().repairNow();
      expect(run.outcome, LadderRepairOutcome.repaired);
      expect(run.repairedIds, [3]);
      expect(h.ctl.saves, 1);
      expect(h.ctl.savedStates.keys, [3]);
    });

    test('nothing is written when everything is already fine — not a single '
        'flash', () async {
      for (final h in [
        _Harness(presets: _ladderFor(_four), live: _live(_four)),
        // The three-bus controller its presets were saved for: fine too.
        _Harness(hardware: _threeBuses),
      ]) {
        final run = await h.runner().repairNow();
        expect(run.outcome, LadderRepairOutcome.notNeeded);
        expect(h.ctl.controllerWrites, 0);
        expect(h.store.backup, isNull);
        expect(h.records, isEmpty);
      }
    });

    test('a save that FAILS stops the run: nothing after it is touched, the '
        'house is put back, and the backup can be restored', () async {
      final h = _Harness(failSaves: {3});
      final run = await h.runner().repairNow();

      expect(run.outcome, LadderRepairOutcome.partial);
      expect(run.stoppedAtId, 3);
      expect(run.repairedIds, [1, 2]);
      expect(run.stillBadIds, [3, 4, 5]);
      expect(h.ctl.log.where((e) => e.startsWith('save:')),
          ['save:1', 'save:2', 'save:3']);
      expect(h.ctl.savedStates.containsKey(4), isFalse);
      expect(h.ctl.applied, isNotEmpty, reason: 'live look restored');
      expect(h.store.status!.stoppedAtId, 3);
      expect(h.records.last['stopped_at'], 3);
      // Presets 4 and 5 still hold the OLD three-bus bodies.
      expect((h.ctl.presets[4]!['seg'] as List).length, 3);

      // The restore path: every backed-up body goes back under its name
      // (the controller saves again now).
      h.ctl.failSaves = {};
      h.ctl.log.clear();
      final put = await h.runner().restoreFromBackup();
      expect(put.outcome, LadderRepairOutcome.repaired);
      expect(put.repairedIds, [1, 2, 3, 4, 5]);
      expect(h.ctl.presets[1], _ladderFor(_three)[1]);
      expect(h.ctl.presets[2], _ladderFor(_three)[2]);
      expect(h.ctl.savedStates[1]!['ib'], true,
          reason: 'a body with a root state is persisted with it');
      // Read back and the bus list re-read for the republished facts.
      expect(h.ctl.log.sublist(h.ctl.log.length - 2), ['presets', 'info']);
      expect(h.records.last['state'], 'backup_restored');
      expect(h.ctl.applied.length, greaterThanOrEqualTo(2),
          reason: 'the live look is restored after the put-back too');
    });

    test('a save that returns ok but does not PERSIST stops the run the same '
        'way', () async {
      final h = _Harness(phantomSaves: {2});
      final run = await h.runner().repairNow();
      expect(run.outcome, LadderRepairOutcome.partial);
      expect(run.stoppedAtId, 2);
      expect(run.repairedIds, [1]);
      expect(h.ctl.log.where((e) => e.startsWith('save:')),
          ['save:1', 'save:2']);
    });

    test('never during a live Game Day window — and never when Game Day '
        'state is unknown', () async {
      for (final a in const [
        GameDayActivity.live('a game is on'),
        GameDayActivity.unknown('calendar'),
      ]) {
        final h = _Harness(activity: a);
        final run = await h.runner().repairNow();
        expect(run.outcome, LadderRepairOutcome.deferred, reason: '$a');
        expect(run.reason, contains(a.known ? 'game_day_live' : 'game_day_unknown'));
        expect(h.ctl.controllerWrites, 0, reason: '$a');
        expect(h.store.backup, isNull);
      }
    });

    test('the kill switch (enabled:false) still stops the customer\'s repair',
        () async {
      final h = _Harness(mode: LadderRepairMode.off);
      final run = await h.runner().repairNow();
      expect(run.outcome, LadderRepairOutcome.modeOff);
      expect(h.ctl.controllerWrites, 0);
    });

    test('an account switch BEFORE the first write cancels: nothing saved',
        () async {
      final h = _Harness()..cancelled = true;
      final run = await h.runner().repairNow();
      expect(run.outcome, LadderRepairOutcome.cancelled);
      expect(h.ctl.saves, 0);
      expect(h.store.backup, isNull, reason: 'cancelled before the backup');
    });

    test('an account switch MID-repair stops after the save in flight and '
        'puts the house back', () async {
      final h = _Harness();
      h.onStep = (s) {
        if (s == 'verify:2') h.cancelled = true; // the account changes here
      };
      final run = await h.runner().repairNow();
      expect(h.ctl.log.where((e) => e.startsWith('save:')),
          ['save:1', 'save:2']);
      expect(run.outcome, LadderRepairOutcome.partial);
      expect(run.repairedIds, [1, 2]);
      expect(run.stillBadIds, [3, 4, 5]);
      expect(run.reason, contains('account changed'));
      expect(h.ctl.applied, isNotEmpty, reason: 'live look restored');
      expect(h.records.last['cancelled'], true);
    });

    test('progress is reported step by step', () async {
      final h = _Harness(presets: _ladderFor(_four)..[3] = _storedOn('NGL Dim', 51, _three),
          live: _live(_four));
      await h.runner().repairNow();
      expect(h.steps, [
        'backup',
        'capture',
        'save:3',
        'verify:3',
        'restore',
        'done',
      ]);
    });
  });

  group('the connect-time repair (consider) acts on R2 alone', () {
    test('restore_lit TRUE (participation narrower than the buses) but R2 '
        'false → presets 1 and 2 are repaired, 3/4/5 untouched', () async {
      // Participation resolved to the three original buses: every ON preset
      // lights every participating bus, OFF darkens via the master → lit.
      final h = _Harness(mode: LadderRepairMode.repair, participating: _three);
      final v = h.verdict();
      expect(v.restoreLit, isTrue);
      expect(h.r2(), isFalse);

      final run = await h.runner().consider(v, assertsSegments: false);
      expect(run.outcome, LadderRepairOutcome.repaired);
      expect(run.repairedIds, [1, 2]);
      expect(run.plan.map((s) => s.faults.single),
          [LadderFault.channelUnstated, LadderFault.channelUnstated]);
      expect(h.ctl.savedStates[1], _wantSent(1, _four));
      expect(h.ctl.savedStates[2], _wantSent(2, _four));
      expect(h.ctl.savedStates.containsKey(3), isFalse);
      expect(h.store.ran, isTrue, reason: 'a connect repair sets the marker');
      expect(h.republished.single.asserts, isTrue);
    });

    test('restore_lit true and R2 true (or unmeasured) → not even a read',
        () async {
      final h = _Harness(mode: LadderRepairMode.repair, participating: _three);
      final v = h.verdict();
      expect((await h.runner().consider(v, assertsSegments: true)).outcome,
          LadderRepairOutcome.notNeeded);
      expect((await h.runner().consider(v)).outcome,
          LadderRepairOutcome.notNeeded);
      expect(h.ctl.log, isEmpty);
    });

    test('with the fleet flag absent the connect-time repair only records a '
        'dry run; the customer\'s own tap is what writes', () async {
      final h = _Harness(mode: LadderRepairMode.dryRun);
      final auto = await h.runner().consider(h.verdict(), assertsSegments: false);
      expect(auto.outcome, LadderRepairOutcome.dryRun);
      expect(h.ctl.saves, 0);
      expect(h.records.single['state'], 'dry_run');
      expect((h.records.single['plan'] as List).length, 5);

      final user = await h.runner().repairNow();
      expect(user.outcome, LadderRepairOutcome.repaired);
      expect(h.ctl.saves, 5);
    });
  });

  group('a server start with no end since (the 8-hour refusal)', () {
    GameDayServerStatus started(DateTime at) => GameDayServerStatus(
          servedFlag: true,
          teams: const ['nfl_team'],
          checkedAt: _now,
          preflight: null,
          nextFire: null,
          lastFire: ServerLastFire(
            eventId: 'evt',
            seq: 'start',
            state: 'completed',
            completedAt: at,
            latencyMs: 2000,
          ),
        );

    test('inside kickoff + the hard cap → live', () {
      expect(
          serverLiveReasonAt(
              started(_now.subtract(const Duration(hours: 5, minutes: 59))),
              _now),
          isNotNull);
    });

    test('past kickoff + the hard cap with no end → treated as ENDED', () {
      expect(
          serverLiveReasonAt(
              started(_now.subtract(const Duration(hours: 6, minutes: 1))),
              _now),
          isNull);
      // The old rule held for eight hours.
      expect(
          serverLiveReasonAt(
              started(_now.subtract(const Duration(hours: 7))), _now),
          isNull);
    });

    test('the cap is six hours — the app\'s open-ended hard cap', () {
      expect(kGameDayStartHardCap, const Duration(hours: 6));
      expect(
          serverLiveReasonAt(started(_now.subtract(const Duration(hours: 3))),
              _now,
              startCap: const Duration(hours: 2)),
          isNull);
    });

    test('a pending END still means the game is on', () {
      final s = GameDayServerStatus(
        servedFlag: true,
        teams: const ['nfl_team'],
        checkedAt: _now,
        preflight: null,
        nextFire: ServerNextFire(
            eventId: 'evt',
            teamSlug: 'nfl_team',
            seq: 'end',
            fireAt: _now.add(const Duration(hours: 1))),
        lastFire: null,
      );
      expect(serverLiveReasonAt(s, _now), contains('end a game'));
    });
  });

  group('the bus-change watcher', () {
    test('busSetChanged: a first reading is not a change; count or ids are',
        () {
      expect(busSetChanged(null, _three), isFalse);
      expect(busSetChanged(_three, const [2, 1, 0]), isFalse);
      expect(busSetChanged(_three, _four), isTrue);
      expect(busSetChanged(_four, _three), isTrue);
      expect(busSetChanged(_three, const [0, 1, 3]), isTrue);
    });

    test('re-arms the marker and re-runs the heal ONLY on a real change of '
        'the same endpoint', () async {
      var reheals = 0;
      final cleared = <String>[];
      final w = LadderBusChangeWatcher(
        reheal: () async => reheals++,
        clearMarker: (id) async => cleared.add(id),
        controllerId: () => 'AA00000000A1',
      );
      expect(await w.onBuses('http://a', _three), isFalse,
          reason: 'first reading');
      expect(await w.onBuses('http://a', _three), isFalse,
          reason: 'provider churn re-reads the same config');
      expect(await w.onBuses('http://a', _four), isTrue, reason: '3 → 4');
      expect(reheals, 1);
      expect(cleared, ['AA00000000A1']);
      expect(await w.onBuses('http://a', _four), isFalse);
      // Another controller is a connect, which the healer already handles.
      expect(await w.onBuses('http://b', _three), isFalse);
      expect(reheals, 1);
      expect(w.lastIds, _three);
    });
  });

  group('why the customer\'s repair cannot run', () {
    test('impersonation, off-LAN, no record — in that order; else null', () {
      expect(
          ladderRepairBlockedReason(
              onLan: false, hasControllerId: false, impersonating: true),
          contains("homeowner's phone"));
      expect(
          ladderRepairBlockedReason(
              onLan: false, hasControllerId: true, impersonating: false),
          contains('home Wi-Fi'));
      expect(
          ladderRepairBlockedReason(
              onLan: true, hasControllerId: false, impersonating: false),
          contains('Choose your controller'));
      expect(
          ladderRepairBlockedReason(
              onLan: true, hasControllerId: true, impersonating: false),
          isNull);
    });
  });
}
