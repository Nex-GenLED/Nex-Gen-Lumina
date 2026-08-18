// test/features/schedule/schedule_sync_capture_replay_test.dart
//
// COVERAGE OWED BY a356b5f — the SECOND instance of the capture-replay shape,
// §2 of audit/ORIENTATION_ON_THE_WIRE.md.
//
// `schedule_sync.dart:892` captures the full `/json/state` before the preset
// batch, and `:1279` replays `capturedLiveState['seg']` VERBATIM afterwards so
// the strip ends exactly where it started. Structurally identical to
// `WledCelebrationDelivery.revert`: a stored state snapshot trusted at
// use-time. The controller's readback carries `start`/`stop`/`rev`/`len`/`mi`
// on every segment, so the non-disruptive restore re-provisions geometry from
// a snapshot unless the wire fence takes it back off.
//
// Unlike the celebration site this one fires on EVERY Sync — pressing Sync,
// saving a schedule, editing one — under the always-psave policy. It had zero
// geometry assertions before this file.
//
// Structure mirrors celebration_revert_capture_replay_test.dart exactly; see
// that file's header for why the tap point (A), the wire (B) and the real exit
// (C) are all three needed and why A is asserted fence-independently.
//
// PROVEN ABLE TO FAIL — verified by temporarily reverting the fix:
//   `kGeometryKeys = ['start', 'stop']`  (the pre-a356b5f fence)
//     → B fails: the restore still carries `rev: false` at the wire.
//     → C fails: the pin's report enumerates only `start+stop`.
// Both were re-greened by restoring `['start', 'stop', 'rev', 'mi']`.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_lease_manager.dart'
    show calendarLeaseActiveTimersProvider, LeaseLedgerEmpty;
import 'package:nexgen_command/features/schedule/preset_repair_convergence.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/wled/geometry_wire_pin.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The bench `/json/state` shape (.150, 2026-08-18): two channels, `rev:
/// false` on seg 1 — the incident value — and `len` present so over-fencing is
/// detectable.
///
/// BOUNDS ARE THE SIMULATOR'S BUS LAYOUT (0–100 / 100–200), not the bench's
/// 0–291 / 291–441, and that is deliberate. syncAll runs the #76 layer-4
/// geometry gate before every psave: a readback that disagrees with the
/// controller's OWN buses is drift, the gate refuses the batch,
/// `didWriteAnyPreset` stays false and the restore at :1274 never arms — so a
/// bench-literal bounds pair would make this file assert nothing. A controller
/// whose readback matches its own buses is the healthy case, which is exactly
/// the case where the capture-replay path runs. The value under test is `rev`,
/// which the gate does not look at.
///
/// `ps` is deliberately absent: schedule sync has no preset short-circuit, it
/// always takes the on/bri/seg restore branch.
Map<String, dynamic> benchState({bool seg1Reversed = false}) => {
      'on': true,
      'bri': 128,
      'seg': [
        {
          'id': 0,
          'start': 0,
          'stop': 100,
          'len': 100,
          'grp': 1,
          'spc': 0,
          'of': 0,
          'on': true,
          'bri': 255,
          'col': [
            [255, 160, 0, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0],
          ],
          'fx': 0,
          'sx': 128,
          'ix': 128,
          'pal': 0,
          'rev': false,
          'mi': false,
        },
        {
          'id': 1,
          'start': 100,
          'stop': 200,
          'len': 100,
          'grp': 1,
          'spc': 0,
          'of': 0,
          'on': true,
          'bri': 255,
          'col': [
            [0, 128, 255, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0],
          ],
          'fx': 63,
          'sx': 200,
          'ix': 96,
          'pal': 11,
          'rev': seg1Reversed,
          'mi': false,
        },
      ],
    };

/// Fake controller for `syncAll`. Subclasses [WledService] (not the bare
/// interface) because syncAll reads presets only when `repo is WledService`,
/// and because with [routeToWire] the un-stubbed `applyJson` is the REAL wire
/// chain — normalize → expand → `_postJson` → `pinNoGeometryOnWire`. Nothing
/// about the fence is re-implemented here.
class _BenchService extends WledService {
  _BenchService(this.state, {this.routeToWire = false}) : super('http://mock');

  final Map<String, dynamic> state;

  /// false → record the payload and stop (the pre-strip TAP POINT).
  /// true  → record it and hand it to the real wire (the real EXIT).
  final bool routeToWire;

  final List<Map<String, dynamic>> applied = [];
  Map<String, dynamic>? _lastCfg;

  /// Empty → nothing matches → every system preset is written → the batch
  /// trips `didWriteAnyPreset`, which is what arms the restore at :1274.
  @override
  Future<Map<int, Map<String, dynamic>>> fetchPresets() async => const {};

  // Echo the timers we last wrote so the 2xx content-match confirms and the
  // sync does not drop into the real-time verify poll (which hangs a test).
  @override
  Future<List<Map<String, dynamic>>?> fetchTimerInstances() async {
    final ins = (_lastCfg?['timers'] as Map?)?['ins'];
    if (ins is List) {
      return ins.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>?> getState() async => state;

  @override
  Future<bool> savePreset({
    required int presetId,
    required Map<String, dynamic> state,
    String? presetName,
  }) async =>
      true;

  @override
  Future<bool> deletePreset(int presetId) async => true;

  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async {
    _lastCfg = cfg;
    return true;
  }

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    applied.add(payload);
    if (routeToWire) return super.applyJson(payload);
    return true;
  }

  /// The non-disruptive live-state restore at schedule_sync.dart:1274-1287.
  /// Identified by `transition: 0` (its snap-back marker), so the assertions
  /// stay pinned to that write even if another applyJson lands in the sync.
  Map<String, dynamic> get restorePayload => applied.singleWhere(
        (p) => p['transition'] == 0,
        orElse: () => throw StateError(
            'no live-state restore was issued — the capture-replay path did '
            'not run, so this test proves nothing. Applied: $applied'),
      );
}

/// Exposes the container's Ref so syncAll (which takes a Ref) can be driven.
final _refProvider = Provider<Ref>((ref) => ref);

ProviderContainer _harness(_BenchService repo) {
  final container = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWithValue(repo),
    // P0-9 (part a): syncAll refuses to write cfg while the lease ledger is
    // UNKNOWN, and an un-overridden provider resolves to LOADING in a unit
    // container. This file exercises the RESTORE, not lease behaviour.
    calendarLeaseActiveTimersProvider.overrideWithValue(const LeaseLedgerEmpty()),
  ]);
  addTearDown(container.dispose);
  return container;
}

ScheduleItem _item() => const ScheduleItem(
      id: 'cr1',
      timeLabel: '7:00 PM',
      offTimeLabel: '11:00 PM',
      repeatDays: ['Mon'],
      actionLabel: 'Turn On',
      enabled: true,
    );

Map<String, dynamic> _seg(Map<String, dynamic> payload, int index) =>
    Map<String, dynamic>.from((payload['seg'] as List)[index] as Map);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const svc = ScheduleSyncService();

  setUp(() {
    // The non-convergence guard's counters are process-scoped on purpose.
    resetRepairAttempts();
    // `applyJson` warms the participation cache from SharedPreferences. Empty
    // → null → `expandForParticipation` passes the payload through unchanged.
    SharedPreferences.setMockInitialValues({});
  });

  group('ScheduleSyncService live-state restore: the payload that reaches the '
      'wire is geometry-free (a356b5f §2, schedule_sync.dart:1279)', () {
    test('A+B — the bench snapshot is replayed verbatim, the wire strips '
        'geometry, and the LOOK survives intact', () async {
      final repo = _BenchService(benchState());

      final result = await svc.syncAll(_harness(repo).read(_refProvider), [_item()]);
      expect(result.success, isTrue);

      final raw = repo.restorePayload;

      // ── A. THE TAP POINT (pre-strip) ─────────────────────────────────────
      // Fence-independent by design: raw `containsKey`, never
      // `findGeometryViolations`. A narrowed `kGeometryKeys` must fail at B,
      // where the regression actually lives — not here, masking it.
      for (final i in [0, 1]) {
        final s = _seg(raw, i);
        expect(
          ['start', 'stop', 'rev', 'mi'].where(s.containsKey).toList(),
          ['start', 'stop', 'rev', 'mi'],
          reason: 'seg[$i]: capturedLiveState["seg"] is replayed VERBATIM — '
              'every geometry key the controller echoed is handed to applyJson',
        );
      }
      expect(_seg(raw, 1)['rev'], false, reason: 'the incident value');

      // ── B. THE WIRE (post-strip) ─────────────────────────────────────────
      final wire = stripGeometry(raw);
      expect(findGeometryViolations(wire), isEmpty,
          reason: 'nothing stating segment geometry reaches the controller');

      for (final i in [0, 1]) {
        final s = _seg(wire, i);
        expect(s.containsKey('start'), isFalse, reason: 'seg[$i] start');
        expect(s.containsKey('stop'), isFalse, reason: 'seg[$i] stop');
        expect(s.containsKey('rev'), isFalse,
            reason: 'seg[$i] rev — a Sync must not re-assert DIRECTION');
        expect(s.containsKey('mi'), isFalse, reason: 'seg[$i] mi');
        // The whole point of the restore: the strip ends where it started.
        expect(s['id'], i);
        expect(s['on'], isTrue);
        expect(s['col'], _seg(benchState(), i)['col']);
        expect(s['fx'], _seg(benchState(), i)['fx']);
        expect(s['pal'], _seg(benchState(), i)['pal']);
        expect(s['sx'], _seg(benchState(), i)['sx']);
        expect(s['ix'], _seg(benchState(), i)['ix']);
        // NOT over-fenced: len stays exempt.
        expect(s['len'], _seg(benchState(), i)['len']);
      }

      expect(wire['on'], isTrue);
      expect(wire['bri'], 128);
      expect(wire['transition'], 0,
          reason: 'the snap-back marker survives — no visible fade');
    });

    test('A+B — the MIRRORED case: a genuinely reversed channel is not '
        're-asserted either', () async {
      final repo = _BenchService(benchState(seg1Reversed: true));

      await svc.syncAll(_harness(repo).read(_refProvider), [_item()]);

      final raw = repo.restorePayload;
      expect(_seg(raw, 1)['rev'], true,
          reason: 'pre-strip tap point — fence-independent');

      final wire = stripGeometry(raw);
      expect(_seg(wire, 1).containsKey('rev'), isFalse,
          reason: 'orientation is provisioning\'s in EITHER direction (#76)');
      expect(_seg(wire, 1)['fx'], 63, reason: 'the LOOK still survives');
    });

    test('C — driven against the REAL wire exit, the pin fires and enumerates '
        'rev + mi', () async {
      // No applyJson stub: the restore takes normalizeWledPayload →
      // expandForParticipation → _postJson → pinNoGeometryOnWire, the real
      // chain. In debug/test the pin asserts; in release it strips (which is
      // what B measures). Proof that B is the behaviour on the actual path.
      //
      // Nothing between syncAll's restore call and here catches — the
      // AssertionError propagates straight out of syncAll, which is itself
      // worth knowing: on a debug build this write is fatal, not degraded.
      final repo = _BenchService(benchState(), routeToWire: true);

      await expectLater(
        svc.syncAll(_harness(repo).read(_refProvider), [_item()]),
        throwsA(isA<AssertionError>().having(
          (e) => e.message.toString(),
          'message',
          allOf(
            contains('GEOMETRY ON THE WIRE (local)'),
            // The ENUMERATED keys, not the report's static prose — the
            // boilerplate names start/stop/rev/mi regardless of what the
            // fence caught, so `contains('rev')` alone would pass against a
            // fence that had never looked at rev.
            contains('seg[0](id=0):start+stop+rev+mi'),
            contains('seg[1](id=1):start+stop+rev+mi'),
          ),
        )),
        reason: 'the schedule-sync restore reaches the real wire pin carrying '
            'orientation, on EVERY Sync',
      );
    });

    test('no preset was written → no restore → nothing to fence', () async {
      // The negative control. If the batch writes nothing, :1274 is not armed
      // and no snapshot is replayed at all. Guards against the restore
      // becoming unconditional, which would put a stale snapshot on the wire
      // on every Sync including the no-op ones.
      final repo = _HealthyPresetsService(benchState());

      await svc.syncAll(_harness(repo).read(_refProvider), [_item()]);

      expect(repo.applied.where((p) => p['transition'] == 0), isEmpty,
          reason: 'nothing was written, so the strip never moved');
    });
  });
}

/// Controller already holding every system preset in its HEALTHY shape, so the
/// batch writes nothing and `didWriteAnyPreset` stays false.
class _HealthyPresetsService extends _BenchService {
  _HealthyPresetsService(super.state);

  @override
  Future<Map<int, Map<String, dynamic>>> fetchPresets() async => {
        1: {
          'n': 'NGL On',
          'on': true,
          'seg': [
            {'on': true}
          ]
        },
        2: {
          'n': 'NGL Off',
          'on': false,
          'seg': [
            {'on': false}
          ]
        },
        3: {
          'n': 'NGL Dim',
          'on': true,
          'seg': [
            {'on': true}
          ]
        },
        4: {
          'n': 'NGL Low',
          'on': true,
          'seg': [
            {'on': true}
          ]
        },
        5: {
          'n': 'NGL Medium',
          'on': true,
          'seg': [
            {'on': true}
          ]
        },
      };
}
