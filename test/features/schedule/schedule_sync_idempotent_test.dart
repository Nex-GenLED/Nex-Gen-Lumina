// test/features/schedule/schedule_sync_idempotent_test.dart
//
// Regression coverage for the schedule-sync apply-mechanism fix.
//
// Root cause (bench-confirmed on WLED 0.15.1): savePreset POSTs its inline
// state with `psave`, which WLED applies to the live strip before snapshotting
// it. The old syncAll re-psaved the whole 1-5 system block on every mutation,
// so saving a schedule and navigating away left the lights solid-on.
//
// The fix: (1) only psave a preset whose stored definition doesn't already
// match (idempotent), and (2) capture live /json/state before any write and
// re-apply it after, so the strip ends where it started. These tests lock both
// guarantees by counting the fake controller's savePreset / applyJson calls.

import 'package:nexgen_command/features/schedule/preset_repair_convergence.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_lease_manager.dart'
    show calendarLeaseActiveTimersProvider, LeaseLedgerEmpty;
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';

/// Fake controller that records the writes syncAll performs. Subclasses
/// [WledService] (not just the interface) because syncAll reads presets only
/// when `repo is WledService` — the preset read is the on-LAN-only capability.
/// The 'mock' host puts the base service in simulation mode so the overridden
/// methods are the only network surface. Returns configurable preset defs (for
/// idempotence) and a live state (for capture/restore).
class _FakeService extends WledService {
  _FakeService({required this.presets, this.state}) : super('http://mock');

  final Map<int, Map<String, dynamic>> presets;
  final Map<String, dynamic>? state;

  final List<int> savedPresetIds = [];
  final List<int> deletedPresetIds = [];
  final Map<int, Map<String, dynamic>> savedStates = {};
  final List<String> callLog = []; // ordered: 'save:N' / 'delete:N' / 'applyJson'
  int applyJsonCalls = 0;
  int applyConfigCalls = 0;
  Map<String, dynamic>? _lastCfg;

  @override
  Future<Map<int, Map<String, dynamic>>> fetchPresets() async => presets;

  // Model a healthy controller's readback: echo the timers we last wrote so the
  // 2xx-path content-match confirms (no patient-verify poll). Without this the
  // fake returns a null readback, which — post trust-2xx-close — drops syncAll
  // into the real-time verify poll and hangs the test.
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
  }) async {
    savedPresetIds.add(presetId);
    savedStates[presetId] = Map<String, dynamic>.from(state);
    callLog.add('save:$presetId');
    return true;
  }

  @override
  Future<bool> deletePreset(int presetId) async {
    deletedPresetIds.add(presetId);
    callLog.add('delete:$presetId');
    return true;
  }

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    applyJsonCalls++;
    callLog.add('applyJson');
    return true;
  }

  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async {
    applyConfigCalls++;
    _lastCfg = cfg;
    return true;
  }
}

// Exposes the container's Ref so syncAll (which takes a Ref) can be driven
// from a test.
final _refProvider = Provider<Ref>((ref) => ref);

({ProviderContainer container, _FakeService repo}) _harness(_FakeService repo) {
  final container = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWithValue(repo),
    // P0-9 (part a): syncAll now refuses to write cfg while the lease ledger is
    // UNKNOWN, and an un-overridden provider resolves to LOADING (the flag's
    // Firestore stream has not emitted in a unit-test container). These tests
    // exercise PRESET idempotency, not lease behaviour, so they declare the
    // loaded-and-empty state explicitly. Previously they relied on the flag's
    // sync adapter collapsing its loading window to `false` — an accidental
    // resolution of exactly the race this guard closes.
    calendarLeaseActiveTimersProvider.overrideWithValue(const LeaseLedgerEmpty()),
  ]);
  addTearDown(container.dispose);
  return (container: container, repo: repo);
}

ScheduleItem _patternItem() => const ScheduleItem(
      id: 's1',
      timeLabel: '7:00 PM',
      repeatDays: ['Mon'],
      actionLabel: 'Pattern: Test',
      enabled: true,
      presetId: 10,
      wledPayload: {
        'on': true,
        'seg': [
          {
            'fx': 57,
            'col': [
              [10, 20, 30, 0]
            ]
          }
        ]
      },
    );

void main() {
  // The non-convergence guard's counters are process-scoped ON PURPOSE — that
  // is what lets it see a repair failing across syncs. Several tests here each
  // drive a sync in the same process, so without this the fourth test is
  // refused for the third one's attempts.
  setUp(resetRepairAttempts);
  const svc = ScheduleSyncService();

  test('Option A: pattern preset ALWAYS re-saved (even when it matches); '
      'system presets skip; save is non-disruptive', () async {
    // Controller already holds every preset the sync would write in its
    // HEALTHY shape: named correctly AND asserting root master state (ON
    // presets on:true, preset 2 on:false), with slot 10 matching the design.
    final repo = _FakeService(
      state: {
        'on': true,
        'bri': 128,
        'seg': [
          {
            'id': 0,
            'col': [
              [255, 160, 0, 0]
            ]
          }
        ]
      },
      presets: {
        1: {
          'n': 'NGL On',
          // HEALED shape: root `on: true` is what asserts MASTER power.
          // Segment-level `on` does NOT — see the broken-shape test below.
          'on': true,
          'seg': [
            {'on': true}
          ]
        },
        2: {
          'n': 'NGL Off',
          // Already healed: carries root on:false (the ib-persisted master-off),
          // so the OFF-preset self-heal skips it.
          'on': false,
          'seg': [
            {'on': false}
          ]
        },
        3: {
          'n': 'NGL Dim',
          // HEALED shape: root `on: true` is what asserts MASTER power.
          // Segment-level `on` does NOT — see the broken-shape test below.
          'on': true,
          'seg': [
            {'on': true}
          ]
        },
        4: {
          'n': 'NGL Low',
          // HEALED shape: root `on: true` is what asserts MASTER power.
          // Segment-level `on` does NOT — see the broken-shape test below.
          'on': true,
          'seg': [
            {'on': true}
          ]
        },
        5: {
          'n': 'NGL Medium',
          // HEALED shape: root `on: true` is what asserts MASTER power.
          // Segment-level `on` does NOT — see the broken-shape test below.
          'on': true,
          'seg': [
            {'on': true}
          ]
        },
        10: {
          'n': 'Pattern: Test',
          'seg': [
            {
              'fx': 57,
              'col': [
                [10, 20, 30, 0]
              ]
            }
          ]
        },
      },
    );
    final h = _harness(repo);
    final ref = h.container.read(_refProvider);

    final result = await svc.syncAll(ref, [_patternItem()]);

    expect(result.success, isTrue);
    // Option A: the schedule's pattern preset is ALWAYS re-saved (no fx+color
    // skip), so a stale on:false / wrong-field preset can never survive.
    // System presets 1-5 skip because they satisfy name AND root master state
    // — NOT by name alone. The name-only predicate was the defect that made
    // 9158c00 inert on every pre-existing controller.
    expect(repo.savedPresetIds, [10],
        reason: 'pattern preset always re-psaved; healthy system presets skip');
    // on:true is forced into the saved pattern preset so it can never be dark,
    // and ib:true makes WLED persist that master state (bench-proven: without
    // ib the preset is segments-only and fires DARK from a master-off state).
    expect(repo.savedStates[10]?['on'], true,
        reason: 'schedule ON-preset must be saved on:true');
    expect(repo.savedStates[10]?['ib'], true,
        reason: 'ON-preset asserts master power via ib (persists root on/bri)');
    // Non-disruptive: exactly one restore, and it runs AFTER the psave.
    expect(repo.applyJsonCalls, 1);
    expect(repo.callLog.last, 'applyJson',
        reason: 'live-state restore is the last live-output touch (after psave)');
    expect(repo.applyConfigCalls, 1, reason: 'timers are still pushed');
  });

  // ── REGRESSION GUARD (P3-57) ────────────────────────────────────────────
  //
  // THE test that must fail if anyone reinstates a name-only skip predicate.
  //
  // Fixtures presets 1/3/4/5 in the shape found on every controller
  // commissioned before 9158c00 and bench-confirmed on vid 2507300 on
  // 2026-07-30: right NAME, segments on, but NO root `on`. WLED writes root
  // `on`/`bri` into a preset only when the psave carried `ib: true`, so these
  // store segments only — a timer firing macro:1 loads the design and leaves
  // the MASTER off, i.e. the strip stays DARK.
  //
  // The old predicate (`_presetNamed`) was satisfied by the name alone, so the
  // sync skipped these forever and the ib fix was inert on the entire
  // installed fleet. They MUST be re-saved.
  test('ON presets named correctly but WITHOUT root on are re-saved '
      '(P3-57 regression guard: name-only skip must never come back)',
      () async {
    final repo = _FakeService(
      state: {'on': true, 'bri': 128, 'seg': []},
      presets: {
        // BROKEN shape — deliberately no root `on`. Do NOT "fix" these
        // fixtures: they are the defect this test exists to catch.
        1: {
          'n': 'NGL On',
          'seg': [
            {'on': true}
          ]
        },
        2: {
          'n': 'NGL Off',
          'on': false, // healthy — isolates the ON presets
          'seg': [
            {'on': false}
          ]
        },
        3: {
          'n': 'NGL Dim',
          'seg': [
            {'on': true}
          ]
        },
        4: {
          'n': 'NGL Low',
          'seg': [
            {'on': true}
          ]
        },
        5: {
          'n': 'NGL Medium',
          'seg': [
            {'on': true}
          ]
        },
      },
    );
    final h = _harness(repo);
    final ref = h.container.read(_refProvider);

    // Payload-less schedule so no slot 10+ write muddies the assertion.
    final result = await svc.syncAll(ref, [
      const ScheduleItem(
        id: 'guard1',
        timeLabel: '7:00 PM',
        offTimeLabel: '11:00 PM',
        repeatDays: ['Mon'],
        actionLabel: 'Turn On',
        enabled: true,
      ),
    ]);

    expect(result.success, isTrue);
    expect(repo.savedPresetIds, [1, 3, 4, 5],
        reason: 'every ON preset lacking root on MUST be re-saved; the healthy '
            'OFF preset 2 must NOT be touched');

    for (final id in [1, 3, 4, 5]) {
      expect(repo.savedStates[id]?['on'], true,
          reason: 'preset $id must be re-saved asserting root master power');
      expect(repo.savedStates[id]?['ib'], true,
          reason: 'ib is what makes WLED persist root on/bri — without it the '
              'rewrite would store segments only and stay dark');
    }
    // Brightness must survive the repair, per ScheduleSyncService.kOnPresetSpecs.
    expect(repo.savedStates[1]?['bri'], 200);
    expect(repo.savedStates[3]?['bri'], 51);
    expect(repo.savedStates[4]?['bri'], 102);
    expect(repo.savedStates[5]?['bri'], 153);
  });

  test('corrupted/absent presets → writes happen AND live state is restored',
      () async {
    // Empty preset map = nothing matches → every system + schedule preset is
    // written, and because a write occurred the captured live state is
    // re-applied exactly once.
    final repo = _FakeService(
      state: {
        'on': true,
        'bri': 128,
        'seg': [
          {
            'id': 0,
            'col': [
              [255, 160, 0, 0]
            ]
          }
        ]
      },
      presets: const {},
    );
    final h = _harness(repo);
    final ref = h.container.read(_refProvider);

    final result = await svc.syncAll(ref, [_patternItem()]);

    expect(result.success, isTrue);
    // System presets 1-5 + the schedule's slot 10.
    expect(repo.savedPresetIds..sort(), containsAll(<int>[1, 2, 3, 4, 5, 10]));
    expect(repo.applyJsonCalls, 1,
        reason: 'exactly one capture→restore after the write batch');
    expect(repo.applyConfigCalls, 1);
  });

  test('preset 2 named NGL Off but left ON is repaired (off-timer safety)',
      () async {
    // Field corruption: slot 2 has the right name but an ON segment and no
    // root on:false, so an OFF timer firing macro:2 would turn lights ON. Sync
    // must rewrite it. Presets 1/3/4/5 are HEALTHY here so the assertion
    // isolates the preset-2 repair.
    final repo = _FakeService(
      state: {'on': true, 'bri': 128, 'seg': []},
      presets: {
        1: {
          'n': 'NGL On',
          // HEALED shape: root `on: true` is what asserts MASTER power.
          // Segment-level `on` does NOT — see the broken-shape test below.
          'on': true,
          'seg': [
            {'on': true}
          ]
        },
        2: {
          'n': 'NGL Off',
          'seg': [
            {'on': true} // ← corrupted: should be off
          ]
        },
        3: {
          'n': 'NGL Dim',
          // HEALED shape: root `on: true` is what asserts MASTER power.
          // Segment-level `on` does NOT — see the broken-shape test below.
          'on': true,
          'seg': [
            {'on': true}
          ]
        },
        4: {
          'n': 'NGL Low',
          // HEALED shape: root `on: true` is what asserts MASTER power.
          // Segment-level `on` does NOT — see the broken-shape test below.
          'on': true,
          'seg': [
            {'on': true}
          ]
        },
        5: {
          'n': 'NGL Medium',
          // HEALED shape: root `on: true` is what asserts MASTER power.
          // Segment-level `on` does NOT — see the broken-shape test below.
          'on': true,
          'seg': [
            {'on': true}
          ]
        },
      },
    );
    final h = _harness(repo);
    final ref = h.container.read(_refProvider);

    // Payload-less schedule (the reported repro): no slot 10+ write.
    final result = await svc.syncAll(ref, [
      const ScheduleItem(
        id: 'off1',
        timeLabel: '7:00 PM',
        offTimeLabel: '11:00 PM',
        repeatDays: ['Mon'],
        actionLabel: 'Turn On',
        enabled: true,
      ),
    ]);

    expect(result.success, isTrue);
    expect(repo.savedPresetIds, [2],
        reason: 'only the corrupted off-preset is rewritten');
    expect(repo.savedStates[2]?['on'], false,
        reason: 'OFF preset keeps its intended on:false — intent-based, not '
            'blanket true');
    expect(repo.savedStates[2]?['ib'], true,
        reason: 'OFF preset asserts master-OFF via ib (root on:false persisted), '
            'so loading it kills master power even for a multi-segment pattern — '
            'the symmetric counterpart to the ON-preset ib master-assert');
    expect(repo.applyJsonCalls, 1, reason: 'the single repair write is restored');
  });

  test('on:true is INJECTED even when a pattern payload is dark/absent (BUG-1)',
      () async {
    // The reported repro: a schedule whose stored wledPayload is on:false (or
    // omits on) was saved into a DARK preset, so firing the timer left the strip
    // off. The pattern preset must be forced on:true (+ explicit bri).
    final repo = _FakeService(
      presets: const {},
      state: {'on': true, 'bri': 100, 'seg': const []},
    );
    final h = _harness(repo);
    final ref = h.container.read(_refProvider);

    await svc.syncAll(ref, [
      const ScheduleItem(
        id: 'dark1',
        timeLabel: '7:00 PM',
        repeatDays: ['Mon'],
        actionLabel: 'Pattern: Dark',
        enabled: true,
        presetId: 10,
        wledPayload: {
          'on': false, // ← dark design
          'seg': [
            {
              'fx': 57,
              'col': [
                [10, 20, 30, 0]
              ]
            }
          ]
        },
      ),
    ]);

    expect(repo.savedStates[10]?['on'], true,
        reason: 'a dark design payload must be saved on:true so it lights up');
    expect(repo.savedStates[10]?['bri'], isNotNull,
        reason: 'an explicit bri is injected');
    expect(repo.savedStates[10]?['ib'], true,
        reason: 'ib persists the master on/bri so the ON-timer powers the strip');
  });

  test('OFF preset save asserts master-OFF: root on:false + ib:true, one off '
      'segment per live segment (belt-and-braces for multi-segment)', () async {
    // Live strip is a 2-segment pattern (the bench repro). The OFF preset must
    // carry root on:false + ib (deterministic master kill) AND an off segment
    // per live segment so a firmware that ignored root on still blanks the
    // whole strip. Empty preset map → preset 2 is written this sync.
    final repo = _FakeService(
      state: {
        'on': true,
        'bri': 200,
        'seg': [
          {'id': 0, 'on': true},
          {'id': 1, 'on': true},
        ],
      },
      presets: const {},
    );
    final h = _harness(repo);
    final ref = h.container.read(_refProvider);

    await svc.syncAll(ref, [
      const ScheduleItem(
        id: 'off1',
        timeLabel: '7:00 PM',
        offTimeLabel: '11:00 PM',
        repeatDays: ['Mon'],
        actionLabel: 'Turn On',
        enabled: true,
      ),
    ]);

    expect(repo.savedStates[2]?['on'], false,
        reason: 'OFF preset persists root on:false');
    expect(repo.savedStates[2]?['ib'], true,
        reason: 'ib persists that root master-off so loading kills master power');
    final offSeg = repo.savedStates[2]?['seg'];
    expect(offSeg, isA<List>());
    expect((offSeg as List).length, 2,
        reason: 'one off segment per live segment covers the full strip');
    expect(offSeg.every((s) => (s as Map)['on'] == false), isTrue,
        reason: 'every segment in the OFF preset is off');
  });

  test('slot hygiene: orphaned managed-range presets are deleted; owned and '
      'out-of-range slots are never touched', () async {
    // Device holds pattern presets from deleted schedules (11, 12, 25) plus a
    // lease/user preset at 26 (outside the 10–25 managed range). Only slot 10
    // is owned by a current schedule.
    final repo = _FakeService(
      state: {'on': true, 'bri': 128, 'seg': const []},
      presets: {
        10: {
          'n': 'Pattern: Test',
          'seg': [
            {
              'fx': 57,
              'col': [
                [10, 20, 30, 0]
              ]
            }
          ]
        },
        11: {
          'n': 'Evening Glow',
          'seg': [
            {'fx': 1}
          ]
        },
        12: {
          'n': 'Ghost',
          'seg': [
            {'fx': 2}
          ]
        },
        25: {
          'n': 'Old Pattern',
          'seg': [
            {'fx': 3}
          ]
        },
        26: {
          'n': 'Lease Slot', // unmanaged — must survive
          'seg': [
            {'fx': 4}
          ]
        },
      },
    );
    final h = _harness(repo);
    final ref = h.container.read(_refProvider);

    await svc.syncAll(ref, [_patternItem()]); // owns slot 10

    expect(repo.deletedPresetIds..sort(), [11, 12, 25],
        reason: 'every managed-range (10–25) preset no current schedule owns is '
            'purged so a stale macro cannot fire a ghost pattern');
    expect(repo.deletedPresetIds, isNot(contains(10)),
        reason: 'slot 10 is owned by a live schedule — never deleted');
    expect(repo.deletedPresetIds, isNot(contains(26)),
        reason: 'slot 26 is outside the app-managed range (lease/user) — '
            'never touched');
  });
}
