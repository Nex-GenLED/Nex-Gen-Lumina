// +114 item 1c — the one-time, guarded on-connect ladder repair.
//
// The guarantees pinned here, in the order a reviewer should ask about them:
//   1. It NEVER writes during a live or imminent Game Day, near ANY armed
//      device timer (lease rows named), with the clock unhealthy, or when it
//      cannot tell (Game Day state not loaded, timer table unreadable).
//   2. When it does write: dry run → local backup (required) → record →
//      live capture (required) → ONE psave per bad preset → restore → read
//      back → one-time marker. Nothing else touches the controller.
//   3. Mode off / dry_run / already-ran write nothing to the controller.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_service.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/wled/base_boundary_denormalizer.dart';
import 'package:nexgen_command/features/wled/base_ladder_repair.dart';
import 'package:nexgen_command/features/wled/base_ladder_repair_providers.dart';
import 'package:nexgen_command/features/wled/base_ladder_restore.dart';
import 'package:nexgen_command/features/wled/base_look.dart';
import 'package:nexgen_command/features/wled/clock_health.dart';
import 'package:nexgen_command/features/wled/controller_defaults_healer.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/utils/sun_utils.dart';

// A Friday afternoon, well clear of every timer below unless a test moves it.
final DateTime _now = DateTime(2026, 10, 2, 13, 0);
const Duration _cdt = Duration(hours: -5);
const List<int> _buses = [0, 1, 2];

const WledHardwareConfig _threeBuses = WledHardwareConfig(
  totalLeds: 390,
  buses: [
    WledLedBus(pin: [2], start: 0, len: 162),
    WledLedBus(pin: [14], start: 162, len: 128),
    WledLedBus(pin: [16], start: 290, len: 100),
  ],
);

Map<String, dynamic> _live() => {
      'on': true,
      'bri': 77,
      'seg': [
        for (final id in _buses)
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

Map<int, Map<String, dynamic>> _healthy() => {
      for (final e in ScheduleSyncService.kOnPresetSpecs.entries)
        e.key: {
          'n': e.value.name,
          ...ScheduleSyncService.buildNglOnPresetState(e.value.bri, _live()),
        }..remove('ib'),
      2: {'n': 'NGL Off', ...ScheduleSyncService.buildNglOffPresetState(_live())}
        ..remove('ib'),
    };

Map<String, dynamic> _black(String name, int bri) => {
      'n': name,
      'on': true,
      'bri': bri,
      'seg': [
        for (final id in _buses)
          {
            'id': id,
            'on': true,
            'fx': 0,
            'col': [
              [0, 0, 0, 0],
              [0, 0, 0, 0],
              [0, 0, 0, 0],
            ],
          },
      ],
    };

/// Presets 1 and 4 captured black; 2, 3, 5 healthy.
Map<int, Map<String, dynamic>> _broken() => _healthy()
  ..[1] = _black('NGL On', 200)
  ..[4] = _black('NGL Low', 102);

class _Ctl extends WledService {
  _Ctl({
    required this.presets,
    List<Map<String, dynamic>>? timers,
    this.live,
    this.failSaves = const {},
  })  : timers = timers ?? const [],
        super('http://mock');

  Map<int, Map<String, dynamic>> presets;
  List<Map<String, dynamic>> timers;
  Map<String, dynamic>? live;
  final Set<int> failSaves;
  bool presetsReadable = true;

  final List<String> log = [];
  final List<Map<String, dynamic>> applied = [];
  final Map<int, Map<String, dynamic>> savedStates = {};

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
      timerRows: timers,
      hardware: _threeBuses,
    );
  }

  @override
  Future<PresetsRead> readPresets() async {
    log.add('presets');
    return presetsReadable
        ? PresetsRead.available(presets)
        : const PresetsRead.unreadable('io');
  }

  @override
  Future<Map<String, dynamic>?> getState() async {
    log.add('state');
    return live;
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
    savedStates[presetId] = state;
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

/// A controller that behaves like WLED for the parts the restore touches: a
/// psave APPLIES its inline state live before persisting; an apply merges into
/// live state by segment id; an apply carrying geometry fails like the wire
/// pin does in debug.
class _Device extends _Ctl {
  _Device({
    required super.presets,
    required Map<String, dynamic> state,
    super.failSaves,
    this.applyOnFail = false,
    this.refuseApplies = 0,
  }) : state = jsonDecode(jsonEncode(state)) as Map<String, dynamic>;

  Map<String, dynamic> state;
  final bool applyOnFail;
  int refuseApplies;
  int psaveCount = 0;
  bool sawRepairLookLive = false;

  void _merge(Map<String, dynamic> payload) {
    if (payload['on'] != null) state['on'] = payload['on'];
    if (payload['bri'] != null) state['bri'] = payload['bri'];
    final segs = payload['seg'];
    if (segs is! List) return;
    final live = (state['seg'] as List).cast<Map<String, dynamic>>();
    for (final raw in segs.cast<Map>()) {
      final id = raw['id'];
      final target = live.firstWhere((x) => x['id'] == id,
          orElse: () => <String, dynamic>{});
      if (target.isEmpty) continue;
      raw.forEach((k, v) {
        if (k != 'id') target['$k'] = jsonDecode(jsonEncode(v));
      });
    }
  }

  @override
  Future<Map<String, dynamic>?> getState() async {
    log.add('state');
    return jsonDecode(jsonEncode(state)) as Map<String, dynamic>;
  }

  @override
  Future<bool> savePreset({
    required int presetId,
    required Map<String, dynamic> state,
    String? presetName,
  }) async {
    final ok = await super.savePreset(
        presetId: presetId, state: state, presetName: presetName);
    if (ok || applyOnFail) {
      psaveCount++;
      _merge(state);
      final seg0 = (this.state['seg'] as List).first as Map;
      if (this.state['on'] == true && seg0['fx'] == 0) {
        sawRepairLookLive = true;
      }
    }
    return ok;
  }

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    log.add('apply');
    applied.add(payload);
    for (final sg in (payload['seg'] as List? ?? const []).cast<Map>()) {
      for (final k in const ['start', 'stop', 'rev', 'mi']) {
        if (sg.containsKey(k)) {
          throw AssertionError('GEOMETRY ON THE WIRE: $k');
        }
      }
    }
    if (refuseApplies > 0) {
      refuseApplies--;
      return false;
    }
    _merge(payload);
    return true;
  }
}

class _Store implements LadderRepairStore {
  bool ran;
  final bool backupWorks;
  String? backup;
  Map<String, Object?>? marker;
  LadderRepairStatus? status;
  final List<String> log;

  _Store.withLog(this.log, {this.ran = false, this.backupWorks = true});

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
  Future<bool> saveBackup(String controllerId, String backupJson) async {
    log.add('backup');
    if (!backupWorks) return false;
    backup = backupJson;
    return true;
  }

  @override
  Future<void> saveStatus(LadderRepairStatus s) async {
    log.add('status');
    status = s;
  }
}

class _Harness {
  _Harness({
    Map<int, Map<String, dynamic>>? presets,
    List<Map<String, dynamic>>? timers,
    Map<String, dynamic>? live,
    Set<int> failSaves = const {},
    this.mode = LadderRepairMode.repair,
    bool ran = false,
    bool backupWorks = true,
    this.activity = const GameDayActivity.quiet(),
    this.connected = true,
    DateTime? now,
  }) : now = now ?? _now {
    ctl = _Ctl(
      presets: presets ?? _broken(),
      timers: timers,
      live: live ?? _live(),
      failSaves: failSaves,
    );
    store = _Store.withLog(ctl.log, ran: ran, backupWorks: backupWorks);
  }

  late _Ctl ctl;
  late _Store store;

  /// Swap in a stateful controller, keeping the same store/record wiring.
  void useDevice(_Device d) {
    ctl = d;
    store = _Store.withLog(d.log, ran: store.ran);
  }
  LadderRepairMode mode;
  GameDayActivity activity;
  bool connected;
  DateTime now;
  final List<Map<String, Object?>> records = [];
  final List<({bool? asserts, LadderRestoreVerdict? v})> republished = [];

  /// Runs inside the record write — i.e. between the first fresh read and the
  /// final check. Tests use it to change the world mid-repair.
  void Function(Map<String, Object?> record)? onRecord;

  /// Replaces the record write's result (e.g. a future that never completes).
  Future<bool> Function()? recordResult;
  Duration recordTimeout = const Duration(seconds: 10);

  BaseLadderRepairRunner runner() => BaseLadderRepairRunner(LadderRepairDeps(
        svc: ctl,
        controllerId: 'AA00000000A1',
        participating: _buses,
        now: () => now,
        phoneUtcOffset: _cdt,
        mode: () async => mode,
        gameDay: () async => activity,
        store: store,
        writeRecord: (r) {
          ctl.log.add('record:${r['state']}');
          records.add(r);
          onRecord?.call(r);
          return recordResult?.call() ?? Future.value(true);
        },
        republish: (a, v) async => republished.add((asserts: a, v: v)),
        stillConnected: () => connected,
        settle: Duration.zero,
        readinessTimeout: Duration.zero,
        readinessPoll: Duration.zero,
        recordTimeout: recordTimeout,
      ));

  LadderRestoreVerdict connectVerdict() => evaluateLadderRestore(
        presets: ctl.presets,
        participating: _buses,
        deviceChannelIds: _buses,
      )!;

  Future<LadderRepairRun> run() => runner().consider(connectVerdict());
}

ClockHealth _healthyClock() => const ClockHealth.healthy();

BaseBoundaryRow _clockRow(int hour, int minute,
        {int macro = 1, int dow = 127, String role = 'system_on'}) =>
    BaseBoundaryRow(
      index: 0,
      kind: kBoundaryKindClock,
      hour: hour,
      minute: minute,
      dow: dow,
      macro: macro,
      role: role,
    );

void main() {
  setUp(resetLadderRepairInFlight);

  group('guards (pure)', () {
    LadderRepairGate gate({
      DateTime? now,
      List<BaseBoundaryRow>? rows = const [],
      ClockHealth? clock,
      GameDayActivity activity = const GameDayActivity.quiet(),
      double? lat = 39.1,
      double? lon = -94.6,
      Duration offset = Duration.zero,
    }) =>
        evaluateLadderRepairGuards(
          now: now ?? _now,
          timerRows: rows,
          clockHealth: clock ?? _healthyClock(),
          gameDay: activity,
          latitude: lat,
          longitude: lon,
          clockOffset: offset,
        );

    test('a quiet afternoon passes', () {
      expect(gate().allowed, isTrue);
    });

    test('a LEASE timer 5 min ahead refuses, and is named as a lease', () {
      final g = gate(rows: [
        _clockRow(13, 5, macro: 39, role: 'lease', dow: 16), // Friday
      ]);
      expect(g.allowed, isFalse);
      expect(g.code, 'lease_timer_near');
      expect(g.reason, contains('13:05'));
    });

    test('a lease timer on another weekday does not refuse', () {
      expect(
          gate(rows: [_clockRow(13, 5, macro: 39, role: 'lease', dow: 64)])
              .allowed,
          isTrue);
    });

    test('just outside the window (11 min) passes', () {
      expect(gate(rows: [_clockRow(13, 11)]).allowed, isTrue);
    });

    test('a timer that fired 8 min AGO refuses — the restore would undo it',
        () {
      final g = gate(rows: [_clockRow(12, 52)]);
      expect(g.code, 'timer_near');
    });

    test('ANY armed timer counts, not only leases (the sunset ON row)', () {
      expect(gate(rows: [_clockRow(13, 3, macro: 1)]).code, 'timer_near');
    });

    test('across midnight: a 00:05 timer refuses at 23:58 the night before',
        () {
      expect(
          gate(
            now: DateTime(2026, 10, 2, 23, 58),
            rows: [_clockRow(0, 5, macro: 2, role: 'system_off')],
          ).code,
          'timer_near');
    });

    test('a solar row near sunset refuses; hours away it does not', () {
      // Anchored on the computed sunset itself, not on a clock-face hour or a
      // day number: KC sunset is ~00:00 UTC, so under TZ=UTC0 (Codemagic) the
      // local day boundary sits right next to it.
      final sunset = SunUtils.sunsetLocal(39.1, -94.6, DateTime(2026, 10, 2))!;
      final row = BaseBoundaryRow(
        index: 0,
        kind: kBoundaryKindSunset,
        hour: 255,
        minute: 0,
        dow: 127,
        macro: 1,
        role: 'system_on',
      );
      expect(gate(now: sunset.add(const Duration(minutes: 4)), rows: [row]).code,
          'timer_near');
      expect(
          gate(now: sunset.subtract(const Duration(hours: 3)), rows: [row])
              .allowed,
          isTrue);
    });

    test('a solar row on a controller with 0,0 coordinates cannot fire — '
        'ignored', () {
      final row = BaseBoundaryRow(
        index: 0,
        kind: kBoundaryKindSolarUnknown,
        hour: 255,
        minute: 0,
        dow: 127,
        macro: 1,
        role: 'system_on',
      );
      expect(timerFiresAround(row, _now, latitude: 0, longitude: 0), isEmpty);
    });

    test('a controller one zone EAST: its 14:05 row is 13:05 here — refuses',
        () {
      // Controller wall clock is one hour ahead of the phone. Compared in the
      // phone's frame this row would look an hour away.
      expect(
          gate(rows: [_clockRow(14, 5)], offset: const Duration(hours: 1)).code,
          'timer_near');
    });

    test('deviceClockOffset rounds drift away and keeps the zone', () {
      expect(
          deviceClockOffset(
              _now.add(const Duration(hours: 1, seconds: 40)), _now),
          const Duration(hours: 1));
      expect(deviceClockOffset(_now.add(const Duration(minutes: 3)), _now),
          Duration.zero);
      expect(deviceClockOffset(null, _now), Duration.zero);
    });

    test('timer table unreadable refuses (cannot see the leases)', () {
      expect(gate(rows: null).code, 'timers_unreadable');
    });

    test('clock unset / tz suspect / unreadable refuse', () {
      expect(gate(clock: const ClockHealth({ClockHealthIssue.clockUnset})).code,
          'clock_unhealthy');
      expect(gate(clock: const ClockHealth({ClockHealthIssue.tzSuspect})).code,
          'clock_unhealthy');
      expect(
          evaluateLadderRepairGuards(
            now: _now,
            timerRows: const [],
            clockHealth: null,
            gameDay: const GameDayActivity.quiet(),
          ).code,
          'clock_unknown');
    });

    test('a live Game Day refuses; an UNKNOWN Game Day refuses too', () {
      expect(gate(activity: const GameDayActivity.live('KC game in progress')).code,
          'game_day_live');
      expect(gate(activity: const GameDayActivity.unknown('calendar')).code,
          'game_day_unknown');
    });
  });

  group('Game Day activity (pure)', () {
    CalendarEntry gd(String date, String on, String? off,
            {CalendarEntryEndMode end = CalendarEntryEndMode.fixedTime,
            DateTime? cap,
            String tag = CalendarEntrySourceTag.gameDay}) =>
        CalendarEntry(
          dateKey: date,
          patternName: 'Team Night',
          color: const Color(0xFFE31837),
          onTime: on,
          offTime: off,
          type: CalendarEntryType.autopilot,
          sourceTag: tag,
          note: 'Home Team vs Away Team — Game Day autopilot',
          endMode: end,
          hardCapAt: cap,
        );

    GameDayActivity act({
      DateTime? now,
      List<CalendarEntry> entries = const [],
      List<AutopilotSession> sessions = const [],
      bool configs = true,
      bool calendar = true,
      bool ephemeral = true,
      String? espn,
      String? server,
    }) =>
        gameDayActivityFrom(
          now: now ?? _now,
          configsLoaded: configs,
          calendarLoaded: calendar,
          calendarEntries: entries,
          autopilotSessions: sessions,
          ephemeralKnown: ephemeral,
          ephemeralSessions: const [],
          espnLiveReason: espn,
          serverLiveReason: server,
        );

    test('nothing on → quiet', () {
      expect(act().known, isTrue);
      expect(act().liveReason, isNull);
    });

    test('an active autopilot session (any phase) → live', () {
      for (final p in [
        AutopilotSessionPhase.preGame,
        AutopilotSessionPhase.liveGame,
        AutopilotSessionPhase.postGame,
      ]) {
        expect(
            act(sessions: [AutopilotSession(teamSlug: 'kc', phase: p)])
                .liveReason,
            isNotNull);
      }
      expect(
          act(sessions: [
            const AutopilotSession(
                teamSlug: 'kc', phase: AutopilotSessionPhase.completed)
          ]).liveReason,
          isNull);
    });

    test('ESPN or server reasons → live', () {
      expect(act(espn: 'KC game in progress').liveReason, 'KC game in progress');
      expect(act(server: 'server start fires in 4 min').liveReason, isNotNull);
    });

    test('a Game Day window containing now (with its 10 min margins) → live',
        () {
      final e = gd('2026-10-02', '13:09', '17:00');
      expect(act(entries: [e]).liveReason, isNotNull, reason: '9 min before on');
      final later = gd('2026-10-02', '13:11', '17:00');
      expect(act(entries: [later]).liveReason, isNull, reason: '11 min before');
    });

    test('an overnight window from yesterday still holds today', () {
      final e = gd('2026-10-01', '19:00', '00:30');
      expect(act(now: DateTime(2026, 10, 2, 0, 20), entries: [e]).liveReason,
          isNotNull);
    });

    test('an open-ended Game Day runs to its hard cap', () {
      final e = gd('2026-10-02', '12:00', null,
          end: CalendarEntryEndMode.untilGameEnd,
          cap: DateTime(2026, 10, 2, 16, 30));
      expect(act(entries: [e]).liveReason, isNotNull);
      expect(act(now: DateTime(2026, 10, 2, 16, 45), entries: [e]).liveReason,
          isNull);
    });

    test('a crew (group) Game Day counts; a plain dated entry does not', () {
      expect(
          act(entries: [
            gd('2026-10-02', '12:30', '16:00',
                tag: CalendarEntrySourceTag.gameDayGroup)
          ]).liveReason,
          isNotNull);
      expect(act(entries: [gd('2026-10-02', '12:30', '16:00', tag: 'x')]).liveReason,
          isNull);
    });

    test('anything not loaded → UNKNOWN (a refusal), unless already live', () {
      expect(act(configs: false).known, isFalse);
      expect(act(calendar: false).known, isFalse);
      expect(act(ephemeral: false).known, isFalse);
      expect(act(calendar: false, espn: 'live').liveReason, 'live');
    });
  });

  group('plan (pure)', () {
    test('one step per PRESENT bad slot, named as the builders name them', () {
      final v = evaluateLadderRestore(
          presets: _broken()..remove(3),
          participating: _buses,
          deviceChannelIds: _buses)!;
      final plan = planLadderRepair(v);
      expect(plan.map((s) => s.presetId), [1, 4]);
      expect(plan.map((s) => s.name), ['NGL On', 'NGL Low']);
      expect(plan.first.faults, [LadderFault.channelBlack]);
    });

    test('repair state is the builders\' output — ON in the base look, OFF '
        'all-off', () {
      final on = ladderRepairState(1, _live());
      expect(on, ScheduleSyncService.buildNglOnPresetState(200, _live()));
      for (final seg in (on['seg'] as List).cast<Map>()) {
        expect(seg['col'], baseLookColSlots());
      }
      expect(ladderRepairState(2, _live()),
          ScheduleSyncService.buildNglOffPresetState(_live()));
    });
  });

  group('runner — when it writes', () {
    test('the full sequence, in order, one psave per bad preset', () async {
      final h = _Harness();
      final run = await h.run();

      expect(run.outcome, LadderRepairOutcome.repaired);
      expect(run.repairedIds, [1, 4]);
      expect(h.ctl.saves, 2, reason: 'one psave per bad preset, no retry');

      // Order: fresh reads → backup → record → capture → saves → restore →
      // readback → record → marker.
      final log = h.ctl.log;
      int at(String e) => log.indexOf(e);
      expect(at('backup'), lessThan(at('record:started')));
      expect(at('record:started'), lessThan(log.lastIndexOf('state')));
      expect(log.lastIndexOf('state'), lessThan(at('save:1')));
      expect(at('save:1'), lessThan(at('save:4')));
      expect(at('save:4'), lessThan(at('apply')));
      expect(at('apply'), lessThan(log.lastIndexOf('presets')));
      expect(log.lastIndexOf('presets'), lessThan(at('record:repaired')));
      expect(at('record:repaired'), lessThan(at('marker')));
    });

    test('saved states are the base look; the restore puts back the captured '
        'live look', () async {
      final h = _Harness();
      await h.run();
      expect(h.ctl.savedStates[1],
          ScheduleSyncService.buildNglOnPresetState(200, _live()));
      final restore = h.ctl.applied.single;
      expect(restore['transition'], 0);
      expect(restore['on'], true);
      expect(restore['bri'], 77);
      expect(restore['seg'], _live()['seg']);
    });

    test('the backup holds the OLD bodies of presets 1-5 and goes out on the '
        'record as a JSON string', () async {
      final h = _Harness();
      final before = h.ctl.presets;
      await h.run();
      expect(h.store.backup, contains('"1":'));
      expect(h.store.backup, contains('"5":'));
      expect(h.store.backup, contains('[0,0,0,0]'),
          reason: 'the black body that was replaced');
      final started =
          h.records.firstWhere((r) => r['state'] == 'started');
      expect(started['backup_json'], h.store.backup);
      expect(started['backup_json'], isA<String>(),
          reason: '#84: arrays of arrays must not reach Firestore');
      expect(before[1]!['seg'], isNotNull);
    });

    test('republishes the ladder facts and shows the banner status', () async {
      final h = _Harness();
      await h.run();
      expect(h.republished.single.v!.restoreLit, isTrue);
      expect(h.republished.single.asserts, isTrue);
      expect(h.store.status!.outcome, LadderRepairOutcome.repaired);
      expect(h.store.status!.repairedIds, [1, 4]);
    });

    test('a Firestore record write that never completes does not hold the '
        'repair (bounded, best effort)', () async {
      final h = _Harness()
        ..recordResult = (() => Completer<bool>().future)
        ..recordTimeout = const Duration(milliseconds: 20);
      final run = await h.run();
      expect(run.outcome, LadderRepairOutcome.repaired);
      expect(h.store.ran, isTrue);
    });

    test('a save that fails → partial, still one-time (no retry loop)',
        () async {
      final h = _Harness(failSaves: {4});
      final run = await h.run();
      expect(run.outcome, LadderRepairOutcome.partial);
      expect(run.stillBadIds, [4]);
      expect(h.ctl.saves, 2);
      expect(h.store.ran, isTrue);
      expect(h.store.status!.outcome, LadderRepairOutcome.partial);
    });

    test('a second consideration after it ran writes nothing', () async {
      final h = _Harness();
      await h.run();
      final writes = h.ctl.controllerWrites;
      h.ctl.presets = _broken(); // regressed somehow
      final again = await h.run();
      expect(again.outcome, LadderRepairOutcome.alreadyRan);
      expect(h.ctl.controllerWrites, writes);
    });

    test('the OFF preset is repaired with the OFF builder', () async {
      final h = _Harness(
        presets: _healthy()
          ..[2] = {
            'n': 'NGL Off',
            'seg': [
              {'id': 0, 'on': false},
              {'id': 1, 'on': true},
              {'id': 2, 'on': false},
            ],
          },
      );
      final run = await h.run();
      expect(run.outcome, LadderRepairOutcome.repaired);
      expect(h.ctl.savedStates[2],
          ScheduleSyncService.buildNglOffPresetState(_live()));
    });
  });

  group('runner — when it does NOT write a single byte to the controller', () {
    Future<void> expectNoControllerWrite(_Harness h, LadderRepairOutcome want,
        {bool marker = false}) async {
      final run = await h.run();
      expect(run.outcome, want, reason: run.reason);
      expect(h.ctl.controllerWrites, 0, reason: h.ctl.log.join(' '));
      expect(h.store.ran, marker);
    }

    test('a lease timer 4 min away', () async {
      await expectNoControllerWrite(
        _Harness(timers: [
          {'en': 1, 'hour': 13, 'min': 4, 'macro': 39, 'dow': 16},
        ]),
        LadderRepairOutcome.deferred,
      );
    });

    test('the base ON timer fired 6 min ago', () async {
      await expectNoControllerWrite(
        _Harness(timers: [
          {'en': 1, 'hour': 12, 'min': 54, 'macro': 1, 'dow': 127},
        ]),
        LadderRepairOutcome.deferred,
      );
    });

    test('a Game Day is live', () async {
      await expectNoControllerWrite(
        _Harness(activity: const GameDayActivity.live('KC game in progress')),
        LadderRepairOutcome.deferred,
      );
    });

    test('Game Day state never loaded', () async {
      await expectNoControllerWrite(
        _Harness(activity: const GameDayActivity.unknown('calendar')),
        LadderRepairOutcome.deferred,
      );
    });

    test('mode off', () async {
      await expectNoControllerWrite(
          _Harness(mode: LadderRepairMode.off), LadderRepairOutcome.modeOff);
    });

    test('mode dry_run records the plan and the gate, marker NOT set',
        () async {
      final h = _Harness(mode: LadderRepairMode.dryRun);
      await expectNoControllerWrite(h, LadderRepairOutcome.dryRun);
      final r = h.records.single;
      expect(r['state'], 'dry_run');
      expect((r['plan'] as List).length, 2);
      expect(r['gate'], 'ok');
      expect(h.store.backup, isNull, reason: 'dry run backs nothing up');
    });

    test('dry run still records when a guard would refuse', () async {
      final h = _Harness(
          mode: LadderRepairMode.dryRun,
          activity: const GameDayActivity.live('live'));
      await expectNoControllerWrite(h, LadderRepairOutcome.dryRun);
      expect(h.records.single['gate'], 'game_day_live');
    });

    test('already ran on this phone', () async {
      await expectNoControllerWrite(
          _Harness(ran: true), LadderRepairOutcome.alreadyRan,
          marker: true);
    });

    test('the local backup fails', () async {
      final h = _Harness(backupWorks: false);
      await expectNoControllerWrite(h, LadderRepairOutcome.aborted);
      expect(h.records, isEmpty, reason: 'no record before a backup exists');
    });

    test('the live state cannot be captured', () async {
      final h = _Harness();
      h.ctl.live = null;
      await expectNoControllerWrite(h, LadderRepairOutcome.aborted);
    });

    test('the app switched controllers before the first write', () async {
      await expectNoControllerWrite(
          _Harness(connected: false), LadderRepairOutcome.deferred);
    });

    test('a LEASE armed while the record write was in flight is caught by the '
        'final fresh read', () async {
      final h = _Harness();
      h.onRecord = (r) {
        if (r['state'] == 'started') {
          h.ctl.timers = [
            {'en': 1, 'hour': 13, 'min': 3, 'macro': 40, 'dow': 16},
          ];
        }
      };
      final run = await h.run();
      expect(run.outcome, LadderRepairOutcome.deferred);
      expect(run.reason, contains('lease_timer_near'));
      expect(h.ctl.controllerWrites, 0);
      expect(h.store.ran, isFalse);
    });

    test('a planned preset rewritten during the repair is NOT overwritten',
        () async {
      final h = _Harness();
      h.onRecord = (r) {
        if (r['state'] == 'started') {
          h.ctl.presets = {...h.ctl.presets, 4: _black('Someone Else', 90)};
        }
      };
      final run = await h.run();
      expect(run.outcome, LadderRepairOutcome.deferred);
      expect(run.reason, contains('preset 4 changed'));
      expect(h.ctl.controllerWrites, 0);
    });

    test('the fresh read finds the ladder already lit', () async {
      final h = _Harness();
      final atConnect = h.connectVerdict();
      h.ctl.presets = _healthy();
      final run = await h.runner().consider(atConnect);
      expect(run.outcome, LadderRepairOutcome.notNeeded);
      expect(h.ctl.controllerWrites, 0);
    });

    test('presets unreadable on the fresh read', () async {
      final h = _Harness();
      final atConnect = h.connectVerdict();
      h.ctl.presetsReadable = false;
      final run = await h.runner().consider(atConnect);
      expect(run.outcome, LadderRepairOutcome.aborted);
      expect(h.ctl.controllerWrites, 0);
    });

    test('restore_lit true, unmeasured, or only MISSING slots → not even '
        'considered', () async {
      final h = _Harness(presets: _healthy());
      expect((await h.run()).outcome, LadderRepairOutcome.notNeeded);
      expect((await h.runner().consider(null)).outcome,
          LadderRepairOutcome.notNeeded);
      final missing = _Harness(presets: _healthy()..remove(1));
      expect((await missing.run()).outcome, LadderRepairOutcome.notNeeded);
      expect(missing.ctl.log, isEmpty, reason: 'not a single read');
    });

    test('a concurrent consideration for the same controller is refused',
        () async {
      final h = _Harness(activity: const GameDayActivity.unknown('slow'));
      final slow = BaseLadderRepairRunner(LadderRepairDeps(
        svc: h.ctl,
        controllerId: 'AA00000000A1',
        participating: _buses,
        now: () => _now,
        phoneUtcOffset: _cdt,
        mode: () async => LadderRepairMode.repair,
        gameDay: () async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return const GameDayActivity.unknown('slow');
        },
        store: h.store,
        writeRecord: (_) async => true,
        republish: (_, __) async {},
        stillConnected: () => true,
        readinessTimeout: Duration.zero,
      ));
      final first = slow.consider(h.connectVerdict());
      final second = await h.run();
      expect(second.outcome, LadderRepairOutcome.inFlight);
      expect((await first).outcome, LadderRepairOutcome.deferred);
    });
  });

  group('mode — writes need an explicit "repair" (owner decision 2026-10-02)',
      () {
    Future<LadderRepairMode> read(Future<Map<String, dynamic>?> Function() r) =>
        readLadderRepairMode(r, timeout: const Duration(milliseconds: 50));

    test('ABSENT document → dry run (never repair)', () async {
      expect(ladderRepairModeFrom(null), LadderRepairMode.dryRun);
      expect(await read(() async => null), LadderRepairMode.dryRun);
    });

    test('UNREADABLE document (read throws: 403, offline) → dry run', () async {
      expect(
          await read(() async => throw StateError('permission-denied')),
          LadderRepairMode.dryRun);
    });

    test('UNREADABLE document (no answer within the bound) → dry run',
        () async {
      expect(await read(() => Completer<Map<String, dynamic>?>().future),
          LadderRepairMode.dryRun);
    });

    test('"dry_run" → dry run', () async {
      expect(await read(() async => {'connect_repair': 'dry_run'}),
          LadderRepairMode.dryRun);
    });

    test('"repair" → repair — the ONLY value that writes', () async {
      expect(await read(() async => {'connect_repair': 'repair'}),
          LadderRepairMode.repair);
    });

    test('"off" → off', () async {
      expect(await read(() async => {'connect_repair': 'off'}),
          LadderRepairMode.off);
    });

    test('document present without the field, or any other value → dry run',
        () {
      expect(ladderRepairModeFrom({}), LadderRepairMode.dryRun);
      expect(ladderRepairModeFrom({'enabled': true}), LadderRepairMode.dryRun);
      for (final v in ['REPAIR', 'Repair', 'repair ', 'yes', true, 1, null]) {
        expect(ladderRepairModeFrom({'connect_repair': v}),
            LadderRepairMode.dryRun,
            reason: '$v must not enable writes');
      }
    });

    test('the old kill switch enabled:false wins over "repair"', () {
      expect(
          ladderRepairModeFrom({'enabled': false, 'connect_repair': 'repair'}),
          LadderRepairMode.off);
    });

    test('end to end: with no config at all, a bad ladder is PLANNED and '
        'RECORDED, and the controller is not written', () async {
      final h = _Harness(mode: await read(() async => null));
      final run = await h.run();
      expect(run.outcome, LadderRepairOutcome.dryRun);
      expect(h.ctl.controllerWrites, 0);
      expect(h.records.single['state'], 'dry_run');
      expect(h.store.ran, isFalse,
          reason: 'a later explicit "repair" must still run');
    });
  });

  group('healer step (e) is gone', () {
    test('a connect never psaves a ladder preset from the healer itself',
        () async {
      // Root `on` missing on every ON slot — exactly what step (e) used to
      // rewrite on every connect, unguarded.
      final presets = _healthy();
      for (final id in const [1, 3, 4, 5]) {
        presets[id] = Map<String, dynamic>.from(presets[id]!)..remove('on');
      }
      final ctl = _Ctl(presets: presets, live: _live());
      final healer = ControllerDefaultsHealer(
        repo: ctl,
        isLan: true,
        controllerIp: '192.0.2.10',
        ctx: ControllerHealContext(
          profileLat: 39.1,
          profileLon: -94.6,
          ianaTimezone: 'America/Chicago',
          resolvePhonePosition: () async => null,
          now: () => _now,
          phoneUtcOffset: _cdt,
        ),
        gammaAction: (_) async => throw StateError('no gamma in this test'),
      );
      await healer.run();
      expect(ctl.saves, 0);
    });
  });

  group('the restore leaves the house EXACTLY as it was (owner decision '
      '2026-10-02)', () {
    Map<String, dynamic> offHouse() => {
          'on': false,
          'bri': 90,
          'transition': 7,
          'seg': [
            for (final id in _buses)
              {
                'id': id,
                'start': id * 100,
                'stop': id * 100 + 100,
                'rev': id == 1,
                'on': true,
                'fx': 0,
                'pal': 0,
                'bri': 255,
                'frz': false,
                'col': [
                  [255, 160, 40, 0],
                  [0, 0, 0, 0],
                  [0, 0, 0, 0],
                ],
              },
          ],
        };

    Map<String, dynamic> litTeamLook() => {
          'on': true,
          'bri': 140,
          'transition': 7,
          'seg': [
            for (final id in _buses)
              {
                'id': id,
                'start': id * 100,
                'stop': id * 100 + 100,
                'rev': false,
                'on': id != 2, // one channel deliberately dark tonight
                'fx': 12,
                'sx': 40,
                'ix': 180,
                'pal': 5,
                'bri': id == 0 ? 200 : 255,
                'frz': id == 1,
                'col': [
                  [227, 24, 55, 0],
                  [255, 184, 28, 0],
                  [0, 0, 0, 0],
                ],
              },
          ],
        };

    /// What the house shows: master power + brightness and each segment's look
    /// and on/off — everything a restore must put back. (`ps`/`transition` are
    /// bookkeeping, not light.)
    Map<String, dynamic> visible(Map<String, dynamic> st) => {
          'on': st['on'],
          'bri': st['bri'],
          'seg': [
            for (final sg in (st['seg'] as List).cast<Map>())
              {
                for (final k in const [
                  'id', 'start', 'stop', 'rev', 'on', 'fx', 'sx', 'ix', 'pal',
                  'bri', 'frz', 'col'
                ])
                  if (sg.containsKey(k)) k: sg[k],
              },
          ],
        };

    for (final (label, house) in [
      ('an OFF house stays OFF', offHouse),
      ('a LIT house gets its exact look back (team design, one channel dark, '
          'a frozen segment, per-segment opacity)', litTeamLook),
    ]) {
      test(label, () async {
        final start = house();
        final h = _Harness();
        final dev = _Device(presets: _broken(), state: start);
        h.useDevice(dev);

        final run = await h.run();

        expect(run.outcome, LadderRepairOutcome.repaired);
        expect(dev.psaveCount, 2, reason: 'presets 1 and 4 were rewritten');
        expect(dev.sawRepairLookLive, isTrue,
            reason: 'the psave really did change the house mid-repair');
        expect(visible(dev.state), visible(start),
            reason: 'after the restore the house is exactly as captured');
        expect(h.records.last['restore'], 'ok');
      });
    }

    test('the restore never states geometry (the wire pin asserts in debug)',
        () {
      final p = BaseLadderRepairRunner.restorePayloadFor(litTeamLook());
      for (final sg in (p['seg'] as List).cast<Map>()) {
        for (final k in const ['start', 'stop', 'rev', 'mi']) {
          expect(sg.containsKey(k), isFalse, reason: '$k must be stripped');
        }
      }
      expect(p['on'], true);
      expect(p['transition'], 0);
    });

    test('a save that FAILED still triggers the restore (it may have applied)',
        () async {
      final start = offHouse();
      final h = _Harness(failSaves: {1, 4});
      final dev = _Device(
          presets: _broken(), state: start, failSaves: {1, 4}, applyOnFail: true);
      h.useDevice(dev);
      final run = await h.run();
      expect(run.outcome, LadderRepairOutcome.failed);
      expect(visible(dev.state), visible(start));
      expect(h.records.last['restore'], 'ok');
    });

    test('a controller that refuses the first restore gets a second one',
        () async {
      final start = offHouse();
      final h = _Harness();
      final dev = _Device(presets: _broken(), state: start, refuseApplies: 1);
      h.useDevice(dev);
      await h.run();
      expect(visible(dev.state), visible(start));
      expect(h.records.last['restore'], 'ok');
    });

    test('a restore that fails twice is RECORDED as failed (support can see '
        'it)', () async {
      final h = _Harness();
      final dev = _Device(presets: _broken(), state: offHouse(), refuseApplies: 2);
      h.useDevice(dev);
      await h.run();
      expect(h.records.last['restore'], 'failed');
    });
  });
}
