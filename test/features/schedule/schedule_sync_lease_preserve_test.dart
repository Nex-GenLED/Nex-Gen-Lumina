// test/features/schedule/schedule_sync_lease_preserve_test.dart
//
// P0-3.2 — schedule sync must PRESERVE active lease timers (macro 26-41) instead
// of stub-clobbering them (defect d). syncAll built timers.ins from ScheduleItems
// only and padTimersToMax stubbed all 8 slots, wiping any lease-range entry the
// lease manager had armed. These tests inject active lease timers via
// [calendarLeaseActiveTimersProvider] and assert the emitted cfg keeps them, with
// LEASE-PRIORITY slot exhaustion.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_lease_manager.dart'
    show
        calendarLeaseActiveTimersProvider,
        LeaseLedgerEmpty,
        LeaseLedgerReady;
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';

/// Fake controller that captures the cfg syncAll pushes. Extends [WledService]
/// because syncAll reads presets/timers only when `repo is WledService`. Echoes
/// the last-written timers so the hardened readback verify confirms (no poll).
class _FakeService extends WledService {
  _FakeService() : super('http://mock');

  Map<String, dynamic>? lastCfg;
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
    List<Map<String, dynamic>> leases) {
  final repo = _FakeService();
  final container = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWithValue(repo),
    // P0-9 (part a): the provider is now a tri-state. These P0-3.2 cases are all
    // "ledger LOADED" — an empty list here means genuinely zero leases, which
    // must still write. The loading case has its own suite
    // (schedule_sync_lease_tristate_test.dart).
    calendarLeaseActiveTimersProvider.overrideWithValue(
      leases.isEmpty ? const LeaseLedgerEmpty() : LeaseLedgerReady(leases),
    ),
  ]);
  addTearDown(container.dispose);
  return (container: container, repo: repo);
}

void main() {
  const svc = ScheduleSyncService();

  test('schedule sync during an active lease PRESERVES the lease timer '
      '(macro 26-41) in the emitted cfg', () async {
    final h = _harness([_leaseTimer(30)]); // lease preset 30
    final ref = h.container.read(_refProvider);

    final result = await svc.syncAll(ref, [_sched('s1', 10, '7:00 PM')]);

    expect(result.success, isTrue);
    expect(h.repo.realMacros, contains(30),
        reason: 'lease timer (macro 30) must survive the schedule sync — '
            'not stub-clobbered (defect d)');
    expect(h.repo.realMacros, contains(10),
        reason: 'the schedule timer is written alongside the lease');
  });

  test('LEASE-PRIORITY when schedules + leases exceed 8 slots: all leases '
      'preserved, schedules capped at 8-leaseCount, overflow warned', () async {
    // 6 leases (macros 26-31) → schedule budget = 8-6 = 2.
    final leases = [for (var m = 26; m <= 31; m++) _leaseTimer(m)];
    final h = _harness(leases);
    final ref = h.container.read(_refProvider);

    // 3 ON-only schedules (1 slot each) → 2 arm, 1 overflows.
    final result = await svc.syncAll(ref, [
      _sched('a', 10, '6:00 PM'),
      _sched('b', 11, '6:30 PM'),
      _sched('c', 12, '7:00 PM'),
    ]);

    final macros = h.repo.realMacros;
    for (var m = 26; m <= 31; m++) {
      expect(macros, contains(m),
          reason: 'lease $m must be preserved (lease priority)');
    }
    final schedMacros = macros.where((m) => m >= 10 && m <= 25).toList();
    expect(schedMacros.length, 2,
        reason: 'schedules capped at 8-6=2 general slots');
    expect(result.presetErrors.any((e) => e.contains('slots are full')), isTrue,
        reason: 'schedule overflow surfaces the existing 8/8 warning');
    expect(h.repo.lastIns.where((t) => t['en'] == 1).length, lessThanOrEqualTo(8),
        reason: 'never more than 8 real timers on the controller');
  });

  test('no active leases → emitted cfg unchanged (schedule-only + stubs, no '
      'macro 26-41): existing behavior preserved', () async {
    final h = _harness(const []);
    final ref = h.container.read(_refProvider);

    final result = await svc.syncAll(ref, [_sched('s1', 10, '7:00 PM')]);

    expect(result.success, isTrue);
    expect(h.repo.realMacros.where((m) => m >= 26 && m <= 41), isEmpty,
        reason: 'no lease timers when none active — schedule-only path unchanged');
    expect(h.repo.realMacros, contains(10));
  });
}
