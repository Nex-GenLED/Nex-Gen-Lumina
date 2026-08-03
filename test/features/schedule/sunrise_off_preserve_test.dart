// test/features/schedule/sunrise_off_preserve_test.dart
//
// The make-or-break test for the global sunrise-off: a foreground schedule sync
// must PRESERVE the reserved sunrise slot instead of stub-clobbering it.
//
// This is the P0-3 clobber class with a new victim. assembleSolarAwareIns writes
// a DISABLED STUB into slot 8 whenever no solar schedule supplies one, so before
// the merge was wired, the very next schedule sync (any app-open) silently
// disarmed the user's daily sunrise-off. Mirrors
// schedule_sync_lease_preserve_test.dart deliberately — same harness, same
// shape, because it is the same defect.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_lease_manager.dart'
    show
        calendarLeaseActiveTimersProvider,
        LeaseLedgerEmpty,
        LeaseLedgerReady;
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/schedule/sunrise_off_service.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';

class _FakeService extends WledService {
  _FakeService() : super('http://mock');

  Map<String, dynamic>? lastCfg;

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
  }) async =>
      true;

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

ScheduleItem _sched(String id, int presetId, String time, {String? off}) =>
    ScheduleItem(
      id: id,
      timeLabel: time,
      offTimeLabel: off,
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

({ProviderContainer container, _FakeService repo}) _harness({
  bool sunriseOff = false,
  List<Map<String, dynamic>> leases = const [],
}) {
  final repo = _FakeService();
  final container = ProviderContainer(overrides: [
    wledRepositoryProvider.overrideWithValue(repo),
    // P0-9 (part a): the provider is a tri-state. These cases are all
    // "ledger LOADED"; empty here means genuinely zero leases, which writes.
    calendarLeaseActiveTimersProvider.overrideWithValue(
      leases.isEmpty ? const LeaseLedgerEmpty() : LeaseLedgerReady(leases),
    ),
    globalSunriseOffTimerProvider
        .overrideWithValue(sunriseOff ? buildSunriseOffTimerEntry() : null),
  ]);
  addTearDown(container.dispose);
  return (container: container, repo: repo);
}

void main() {
  const svc = ScheduleSyncService();

  test('schedule sync PRESERVES the reserved sunrise-off slot (does not '
      'stub-clobber it)', () async {
    final h = _harness(sunriseOff: true);
    final ref = h.container.read(_refProvider);

    final result = await svc.syncAll(ref, [_sched('s1', 10, '7:00 PM')]);

    expect(result.success, isTrue);
    expect(h.repo.lastIns.length, ScheduleSyncService.kWledTotalTimerSlots,
        reason: 'the sunrise-off forces the 10-slot solar-aware assembly');

    final slot8 = h.repo.lastIns[ScheduleSyncService.kWledSunriseSlot];
    expect(slot8['en'], 1,
        reason: 'the sunrise-off must survive the sync ENABLED — a disabled '
            'stub here is the clobber this test exists to catch');
    expect(slot8['macro'], kSunriseOffMacro);
    expect(slot8['hour'], ScheduleSyncService.kWledSolarHourMarker);
    expect(slot8['dow'], kSunriseOffDow);
    expect(h.repo.realMacros, contains(10),
        reason: 'the schedule timer still arms alongside it');
  });

  test('sunrise-off + active lease + schedule all coexist in one sync',
      () async {
    final h = _harness(sunriseOff: true, leases: [_leaseTimer(30)]);
    final ref = h.container.read(_refProvider);

    final result = await svc.syncAll(ref, [_sched('s1', 10, '7:00 PM')]);

    expect(result.success, isTrue);
    expect(h.repo.lastIns[ScheduleSyncService.kWledSunriseSlot]['en'], 1,
        reason: 'sunrise-off preserved');
    expect(h.repo.realMacros, contains(30), reason: 'lease preserved (P0-3.2)');
    expect(h.repo.realMacros, contains(10), reason: 'schedule armed');
  });

  test('toggle OFF → sync writes an 8-slot payload and never re-arms slot 8',
      () async {
    final h = _harness(sunriseOff: false);
    final ref = h.container.read(_refProvider);

    final result = await svc.syncAll(ref, [_sched('s1', 10, '7:00 PM')]);

    expect(result.success, isTrue);
    expect(h.repo.lastIns.length, 8,
        reason: 'no dedicated-slot owner → the existing 8-slot path is '
            'unchanged (no behavior change for users who never opt in)');
    expect(h.repo.realMacros, contains(10));
  });

  test('a schedule that turns lights ON at sunrise is refused-and-warned '
      'while the sunrise-off owns the slot (no on/off race)', () async {
    final h = _harness(sunriseOff: true);
    final ref = h.container.read(_refProvider);

    final result = await svc.syncAll(ref, [_sched('dawn', 11, 'Sunrise')]);

    expect(result.presetErrors.any((e) => e.contains('conflicts')), isTrue,
        reason: 'the user must be told, not silently dropped');
    expect(h.repo.realMacros, isNot(contains(11)),
        reason: 'never arm an ON at the same instant as the master-OFF');
    expect(h.repo.lastIns[ScheduleSyncService.kWledSunriseSlot]['macro'],
        kSunriseOffMacro,
        reason: 'the slot still resolves to OFF');
  });

  test('DOUBLE SUNRISE TARGET resolves to OFF, never ON — a sunset→sunrise '
      'schedule keeps its sunset ON and its redundant sunrise OFF is '
      'superseded by the identical global one', () async {
    // Solar is refused unless the flag+coords gate opens, so this exercises the
    // contention path that matters here: both boundaries want to mean "off at
    // sunrise", and macro 2 is an absolute master-OFF preset load, never a
    // toggle — so whichever fires, the strip ends dark.
    final h = _harness(sunriseOff: true);
    final ref = h.container.read(_refProvider);

    await svc.syncAll(ref, [_sched('dusk', 12, '7:00 PM', off: 'Sunrise')]);

    final slot8 = h.repo.lastIns[ScheduleSyncService.kWledSunriseSlot];
    expect(slot8['macro'], kSunriseOffMacro,
        reason: 'macro 2 = NGL Off = explicit master off, not a toggle');
    expect(slot8['en'], 1);
    // Exactly one sunrise timer exists — the firmware has one sunrise slot, so
    // a duplicate is structurally impossible.
    final sunriseTimers = h.repo.lastIns
        .where((t) =>
            t['hour'] == ScheduleSyncService.kWledSolarHourMarker &&
            t['en'] == 1)
        .toList();
    expect(sunriseTimers.length, 1);
  });
}
