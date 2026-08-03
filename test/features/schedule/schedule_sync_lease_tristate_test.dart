// test/features/schedule/schedule_sync_lease_tristate_test.dart
//
// P0-9 (part a) — the lease ledger is a TRI-STATE and syncAll must REFUSE to
// write cfg while it is loading.
//
// The defect: `activeLeaseTimers()` returned a bare list, so "this account has
// no leases" and "the ledger hasn't loaded yet" were both `[]`. `initialize()`
// is fire-and-forget from `calendarEntryLeaseManagerProvider`, so a sync racing
// the load merged ZERO lease timers, `padTimersToMax` stubbed their slots, and
// every live lease was wiped off the controller — silently, and self-concealing
// (gone from the device AND from the ledger that would have restored it).
//
// The two cases that matter are opposites and both are asserted here:
//   • LOADING            → must NOT write at all
//   • EMPTY (loaded)     → MUST write (a hydrated user with zero leases still
//                          needs the device cleared) — the regression risk
//
// Note the guard sits BELOW the off-LAN check, so `_FakeService` (a WledService,
// which supports cfg writes) is required for the refusal to be reachable.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_lease_manager.dart'
    show
        calendarLeaseActiveTimersProvider,
        LeaseLedgerEmpty,
        LeaseLedgerLoading,
        LeaseLedgerReady,
        LeaseLedgerState;
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';

/// Captures whether a cfg write was attempted at all. `applyConfig` staying
/// null is the assertion that matters — a refusal that still POSTs is not a
/// refusal.
class _FakeService extends WledService {
  _FakeService() : super('http://mock');

  Map<String, dynamic>? lastCfg;
  int applyConfigCalls = 0;
  final List<int> savedPresetIds = [];

  @override
  Future<Map<int, Map<String, dynamic>>> fetchPresets() async => const {};

  @override
  Future<List<Map<String, dynamic>>?> fetchTimerInstances() async {
    final ins = (lastCfg?['timers'] as Map?)?['ins'];
    if (ins is List) {
      return ins
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>?> getState() async => {
        'on': true,
        'seg': [
          {'id': 0}
        ]
      };

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
    applyConfigCalls++;
    lastCfg = cfg;
    return true;
  }

  List<Map<String, dynamic>> get lastIns =>
      ((lastCfg?['timers'] as Map?)?['ins'] as List?)
          ?.cast<Map<String, dynamic>>() ??
      const [];

  Set<int> get realMacros => lastIns
      .where((t) => t['en'] == 1)
      .map((t) => (t['macro'] as num).toInt())
      .toSet();
}

final _refProvider = Provider<Ref>((ref) => ref);

Map<String, dynamic> _leaseTimer(int macro) =>
    {'en': 1, 'hour': 18, 'min': 0, 'macro': macro, 'dow': 8};

ScheduleItem _sched(String id, int presetId, String time) => ScheduleItem(
      id: id,
      timeLabel: time,
      repeatDays: const ['Mon'],
      actionLabel: 'Pattern: $id',
      enabled: true,
      presetId: presetId,
      wledPayload: const {
        'on': true,
        'seg': [
          {
            'fx': 0,
            'col': [
              [10, 20, 30, 0]
            ]
          }
        ]
      },
    );

({ProviderContainer container, _FakeService repo}) _harness(
    LeaseLedgerState leaseState) {
  final repo = _FakeService();
  final container = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWithValue(repo),
    calendarLeaseActiveTimersProvider.overrideWithValue(leaseState),
  ]);
  addTearDown(container.dispose);
  return (container: container, repo: repo);
}

void main() {
  const svc = ScheduleSyncService();

  group('LOADING — the ledger is cold, the lease set is unknown', () {
    test('sync racing an uninitialized lease manager REFUSES to write cfg',
        () async {
      final h = _harness(const LeaseLedgerLoading());
      final ref = h.container.read(_refProvider);

      final result = await svc.syncAll(ref, [_sched('s1', 10, '7:00 PM')]);

      expect(h.repo.applyConfigCalls, 0,
          reason: 'THE assertion: no cfg write may be attempted while the lease '
              'set is unknown — a write here stub-clobbers every live lease');
      expect(h.repo.lastCfg, isNull);
      expect(result.deferredLeaseLedger, isTrue);
      expect(result.success, isFalse,
          reason: 'nothing was armed, so this is not a success');
    });

    test('the refusal is legible — carries the neutral notice, not a raw error',
        () async {
      final h = _harness(const LeaseLedgerLoading());
      final ref = h.container.read(_refProvider);

      final result = await svc.syncAll(ref, [_sched('s1', 10, '7:00 PM')]);

      expect(result.summaryMessage, kScheduleLeaseLedgerNotice);
      expect(result.error, kScheduleLeaseLedgerNotice,
          reason: 'a deferral the user cannot see is indistinguishable from the '
              'silent no-op this guard exists to prevent');
    });

    test('refuses even when the schedule set would otherwise arm cleanly — the '
        'all-stub clobber guard cannot catch this case', () async {
      // Two perfectly good schedules: `ins` carries REAL timers, so
      // shouldSkipClobberingWrite correctly does not fire. Only the tri-state
      // gate stops the write. This is the partial-arm case P0-9 is about.
      final h = _harness(const LeaseLedgerLoading());
      final ref = h.container.read(_refProvider);

      final result = await svc.syncAll(
          ref, [_sched('a', 10, '6:00 PM'), _sched('b', 11, '7:00 PM')]);

      expect(h.repo.applyConfigCalls, 0);
      expect(result.deferredLeaseLedger, isTrue);
    });
  });

  group('EMPTY — the ledger LOADED and this account has no leases', () {
    test('sync DOES write (the case most likely to regress)', () async {
      final h = _harness(const LeaseLedgerEmpty());
      final ref = h.container.read(_refProvider);

      final result = await svc.syncAll(ref, [_sched('s1', 10, '7:00 PM')]);

      expect(result.success, isTrue,
          reason: 'a loaded-but-empty ledger must NOT be treated as loading — '
              'conflating them is the original bug, mirrored');
      expect(result.deferredLeaseLedger, isFalse);
      expect(h.repo.applyConfigCalls, 1);
      expect(h.repo.realMacros, contains(10));
    });

    test('an empty ledger still lets a CLEARING write through (slot reclaim)',
        () async {
      // No schedules and no leases: the payload is all stubs and the write must
      // still go out to clear the device. If the gate keyed on "no lease timers"
      // instead of "ledger loading", this would be refused and stale timers
      // would strand on the controller forever.
      final h = _harness(const LeaseLedgerEmpty());
      final ref = h.container.read(_refProvider);

      final result = await svc.syncAll(ref, const []);

      expect(h.repo.applyConfigCalls, 1,
          reason: 'a hydrated user with zero schedules AND zero leases must '
              'still push, exactly as before this change');
      expect(result.deferredLeaseLedger, isFalse);
    });
  });

  group('READY — loaded with live leases', () {
    test('writes and preserves the lease timer (P0-3.2 unchanged)', () async {
      final h = _harness(LeaseLedgerReady([_leaseTimer(30)]));
      final ref = h.container.read(_refProvider);

      final result = await svc.syncAll(ref, [_sched('s1', 10, '7:00 PM')]);

      expect(result.success, isTrue);
      expect(result.deferredLeaseLedger, isFalse);
      expect(h.repo.realMacros, containsAll(<int>[10, 30]));
    });
  });

  group('the tri-state itself', () {
    test('Loading and Empty are distinct types that both expose no timers',
        () {
      const loading = LeaseLedgerLoading();
      const empty = LeaseLedgerEmpty();

      expect(loading.timers, isEmpty);
      expect(empty.timers, isEmpty);
      expect(loading, isNot(isA<LeaseLedgerEmpty>()),
          reason: 'the whole point: an empty timer list no longer tells you '
              'which state you are in — the TYPE does');
    });

    test('Ready carries its timers', () {
      final ready = LeaseLedgerReady([_leaseTimer(27)]);
      expect(ready.timers.single['macro'], 27);
    });
  });
}
