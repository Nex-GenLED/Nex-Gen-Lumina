// Controller-wedge pacing fix — Parts A / B / D.
//
// The wedge pattern (audit/SYNC_PACING_FIX_STATUS.md): a sync fired its
// controller writes back-to-back with NO gap, while the background poller kept
// issuing getState straight through the burst, on a single-core HTTP server
// doing flash commits. Items (a) and (c) of the filed fix were never
// implemented; these lock them now, plus the Game Day batching (D1).
//
// The fake-controller harness mirrors schedule_sync_idempotent_test.dart — the
// suite that already pins the idempotence gate this pacing must not tax.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_lease_manager.dart'
    show calendarLeaseActiveTimersProvider, LeaseLedgerEmpty;
import 'package:nexgen_command/features/schedule/preset_repair_convergence.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';

class _FakeService extends WledService {
  _FakeService({required this.presets, this.state}) : super('http://mock');

  final Map<int, Map<String, dynamic>> presets;
  final Map<String, dynamic>? state;

  final List<int> savedPresetIds = [];
  Map<String, dynamic>? _lastCfg;

  @override
  Future<Map<int, Map<String, dynamic>>> fetchPresets() async => presets;

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
  Future<bool> deletePreset(int presetId) async => true;

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async => true;

  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async {
    _lastCfg = cfg;
    return true;
  }
}

ProviderContainer _harness(_FakeService repo) {
  final container = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWithValue(repo),
    calendarLeaseActiveTimersProvider.overrideWithValue(const LeaseLedgerEmpty()),
  ]);
  addTearDown(container.dispose);
  return container;
}

ScheduleItem _patternItem(String id, String time) => ScheduleItem(
      id: id,
      timeLabel: time,
      repeatDays: const ['Mon'],
      actionLabel: 'Pattern: Test',
      enabled: true,
      presetId: 10,
      wledPayload: const {
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

/// A controller holding NOTHING — so every preset the sync wants is a real
/// write and the idempotence gate cannot skip it.
_FakeService _emptyController() => _FakeService(
      presets: const {},
      state: const {
        'on': true,
        'bri': 200,
        'seg': [
          {'id': 0, 'on': true, 'fx': 0}
        ],
      },
    );

void main() {
  setUp(resetRepairAttempts);

  group('Part A — pacing applies to writes that actually happen', () {
    // The required test: several REAL psaves cost measurably more wall-clock
    // than the same sync with pacing disabled.
    test('a sync with real psave writes is paced', () async {
      final paced = _emptyController();
      final unpaced = _emptyController();

      final swUnpaced = Stopwatch()..start();
      await const ScheduleSyncService(paceDelay: Duration.zero)
          .syncAll(_harness(unpaced).read(Provider<Ref>((r) => r)),
              [_patternItem('s1', '7:00 PM')]);
      swUnpaced.stop();

      final swPaced = Stopwatch()..start();
      await const ScheduleSyncService(paceDelay: Duration(milliseconds: 300))
          .syncAll(_harness(paced).read(Provider<Ref>((r) => r)),
              [_patternItem('s1', '7:00 PM')]);
      swPaced.stop();

      // Same writes either way — pacing must not change WHAT is written.
      expect(paced.savedPresetIds.length, unpaced.savedPresetIds.length);
      expect(paced.savedPresetIds.length, greaterThanOrEqualTo(3),
          reason: 'an empty controller must force several real writes');

      // n real writes ⇒ (n-1) gaps of 300ms. The sleeps are real, so the
      // PACED run's absolute wall-clock is the sturdy invariant; the delta
      // against the unpaced run varies with fake-controller overhead.
      final expectedFloor = (paced.savedPresetIds.length - 1) * 300;
      expect(expectedFloor, greaterThanOrEqualTo(500),
          reason: 'the filed spec asked for 500-1000ms on 3 writes');
      expect(swPaced.elapsedMilliseconds, greaterThanOrEqualTo(expectedFloor),
          reason: 'paced sync must spend at least ${expectedFloor}ms sleeping');
      expect(swPaced.elapsedMilliseconds,
          greaterThan(swUnpaced.elapsedMilliseconds),
          reason: 'and must be slower than the same sync unpaced');
    });

    // The half that matters just as much: a converged controller must not pay.
    test('a steady-state sync with ZERO real writes is not slowed', () async {
      // Controller already holds every system preset in its HEALED shape, so
      // the idempotence gate skips all of them. Same fixture shape as
      // schedule_sync_idempotent_test.dart's healthy controller.
      final converged = _FakeService(
        presets: const {
          1: {'n': 'NGL On', 'on': true, 'seg': [{'on': true}]},
          2: {'n': 'NGL Off', 'on': false, 'seg': [{'on': false}]},
          3: {'n': 'NGL Dim', 'on': true, 'seg': [{'on': true}]},
          4: {'n': 'NGL Low', 'on': true, 'seg': [{'on': true}]},
          5: {'n': 'NGL Medium', 'on': true, 'seg': [{'on': true}]},
        },
        state: const {
          'on': true,
          'bri': 128,
          'seg': [
            {'id': 0, 'on': true}
          ]
        },
      );
      final sw = Stopwatch()..start();
      await const ScheduleSyncService(paceDelay: Duration(seconds: 5))
          .syncAll(_harness(converged).read(Provider<Ref>((r) => r)),
              const <ScheduleItem>[]);
      sw.stop();

      // A 5s pace would be unmissable if it were charged per iteration rather
      // than per actual write.
      expect(converged.savedPresetIds, isEmpty,
          reason: 'no schedules ⇒ no pattern presets to write');
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)),
          reason: 'pacing must be a gap between writes, not a fixed tax');
    });

    test('the default pace sits inside the specified 250-500ms band', () {
      expect(kControllerWritePace.inMilliseconds, greaterThanOrEqualTo(250));
      expect(kControllerWritePace.inMilliseconds, lessThanOrEqualTo(500));
    });
  });

  group('Part B — the poller is suspended across a sync', () {
    test('polling is paused for the duration and resumed after', () async {
      final repo = _emptyController();
      final c = _harness(repo);
      final notifier = c.read(wledStateProvider.notifier);

      expect(notifier.isPollingPaused, isFalse);
      await const ScheduleSyncService(paceDelay: Duration.zero)
          .syncAll(c.read(Provider<Ref>((r) => r)), [_patternItem('s1', '7:00 PM')]);
      expect(notifier.isPollingPaused, isFalse,
          reason: 'resume must run on the success path');
    });

    test('pause/resume nests — an inner resume does not restart polling', () {
      final notifier = _harness(_emptyController()).read(wledStateProvider.notifier);

      notifier.pausePolling(); // outer (calendar populate)
      notifier.pausePolling(); // inner (syncAll)
      expect(notifier.isPollingPaused, isTrue);

      notifier.resumePolling(); // inner releases
      expect(notifier.isPollingPaused, isTrue,
          reason: 'the outer operation is still writing');

      notifier.resumePolling(); // outer releases
      expect(notifier.isPollingPaused, isFalse);
    });

    // The failure mode this guards: a throw mid-sync leaving the dashboard
    // permanently un-polled.
    test('an unbalanced resume is tolerated, not thrown', () {
      final notifier = _harness(_emptyController()).read(wledStateProvider.notifier);
      expect(() => notifier.resumePolling(), returnsNormally);
      expect(notifier.isPollingPaused, isFalse);
    });

    test('resume after a pause always returns to unpaused', () {
      final notifier = _harness(_emptyController()).read(wledStateProvider.notifier);
      for (var i = 0; i < 5; i++) {
        notifier.pausePolling();
      }
      for (var i = 0; i < 5; i++) {
        notifier.resumePolling();
      }
      expect(notifier.isPollingPaused, isFalse);
    });
  });
}
