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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
    return true;
  }

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    applyJsonCalls++;
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
  const svc = ScheduleSyncService();

  test('idempotent: presets already current → zero writes, no restore', () async {
    // Controller already holds every preset the sync would write, named
    // correctly, preset 2 genuinely off, and slot 10 matching the design.
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
          'seg': [
            {'on': true}
          ]
        },
        2: {
          'n': 'NGL Off',
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
    expect(repo.savedPresetIds, isEmpty,
        reason: 'no preset should be re-psaved when all already match');
    expect(repo.applyJsonCalls, 0,
        reason: 'no write happened, so live output must not be restored/touched');
    expect(repo.applyConfigCalls, 1, reason: 'timers are still pushed');
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
    // Field corruption: slot 2 has the right name but an ON segment, so an
    // OFF timer firing macro:2 would turn lights ON. Sync must rewrite it.
    final repo = _FakeService(
      state: {'on': true, 'bri': 128, 'seg': []},
      presets: {
        1: {
          'n': 'NGL On',
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
    expect(repo.applyJsonCalls, 1, reason: 'the single repair write is restored');
  });
}
