// test/features/schedule/calendar_entry_lease_manager_integration_test.dart
//
// Item #61 Workstream B Prompt 5 — end-to-end coverage of the lease
// manager talking to a simulated WLED endpoint via WledService's
// mock-host path. Distinct from the unit-test file
// (calendar_entry_lease_manager_test.dart) — these tests exercise the
// full savePreset + applyConfig roundtrip through a real WledService
// instance with no hand-rolled fakes.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_lease_manager.dart';
import 'package:nexgen_command/features/schedule/calendar_lease_feature_flag.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ─── Helpers ────────────────────────────────────────────────────

  /// Today's dateKey ('YYYY-MM-DD'), local time.
  String todayDateKey() {
    final d = DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  /// Expected dow bitmask for today (must be computed at runtime —
  /// hardcoding breaks the test the next time it runs on a different
  /// weekday).
  int todayDowMask() {
    final wd = DateTime.now().weekday;
    if (wd == DateTime.sunday) return 1; // bit 0
    return 1 << wd;
  }

  /// CalendarEntry guaranteed to land within the 48 h lease window.
  /// Uses 30 min from now → 90 min from now so window math holds
  /// regardless of test-run wall-clock.
  CalendarEntry insideWindowEntry({
    String patternName = 'Warm White',
    Color color = const Color(0xFFFFCC88),
    int brightness = 75,
  }) {
    final now = DateTime.now();
    final on = now.add(const Duration(minutes: 30));
    final off = now.add(const Duration(minutes: 90));
    String hhmm(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
    return CalendarEntry(
      dateKey: todayDateKey(),
      patternName: patternName,
      color: color,
      onTime: hhmm(on),
      offTime: hhmm(off),
      brightness: brightness,
      type: CalendarEntryType.user,
      autopilot: false,
    );
  }

  ({WledService service, ProviderContainer container,
      CalendarEntryLeaseManager manager}) buildIntegrationHarness({
    bool liveWritesEnabled = true,
    int scheduleSlotDemand = 0,
    List<CalendarEntry> entries = const [],
  }) {
    final service = WledService('http://mock');
    final container = ProviderContainer(overrides: [
      wledRepositoryProvider.overrideWithValue(service),
      // Override the sync adapter directly so flag reads inside the
      // manager are deterministic (no AsyncLoading→AsyncData race
      // against initialize() running before the stream emits).
      calendarLeaseLiveWritesEnabledSyncProvider
          .overrideWithValue(liveWritesEnabled),
      // Also override the underlying StreamProvider so any code that
      // reads the stream directly (e.g. UI consumers) sees the same
      // value. Matches the prompt's specified override pattern.
      calendarLeaseLiveWritesEnabledProvider
          .overrideWith((_) => Stream.value(liveWritesEnabled)),
      calendarLeaseScheduleSlotDemandProvider
          .overrideWith((_) => scheduleSlotDemand),
      calendarLeaseEntriesProvider.overrideWithValue(entries),
      calendarLeaseSchedulesProvider.overrideWithValue(const []),
      calendarLeaseScheduleUpdaterProvider
          .overrideWith((_) => (_) async {}),
      calendarLeaseScheduleSyncTriggerProvider
          .overrideWith((_) => () async {}),
    ]);
    addTearDown(container.dispose);
    final manager = container.read(calendarEntryLeaseManagerProvider);
    return (service: service, container: container, manager: manager);
  }

  // ────────────────────────────────────────────────────────────────
  group('end-to-end (flag ON)', () {
    test(
        'lease created → savePreset + applyConfig reach mock WLED with '
        'correct shape', () async {
      final h = buildIntegrationHarness();
      await h.manager.initialize();

      final entry = insideWindowEntry();
      final result = await h.manager.handleEntryCreated(entry);

      expect(result.outcome, LeaseOutcome.leased);
      expect(result.lease, isNotNull);
      expect(result.lease!.slotIndex, 0);
      expect(
        result.lease!.presetId,
        inInclusiveRange(kFirstLeasePresetId, kLastLeasePresetId),
      );

      // savePreset reached the controller with matching preset ID +
      // a non-empty WLED state payload.
      expect(h.service.lastSimulatedPresetSave, isNotNull);
      expect(h.service.lastSimulatedPresetSave!.presetId,
          result.lease!.presetId);
      expect(h.service.lastSimulatedPresetSave!.state.containsKey('on'),
          isTrue);

      // applyConfig captured the merged timers.ins. With zero
      // ScheduleItems, the lease's timer is the only entry.
      expect(h.service.lastSimulatedConfigPayload, isNotNull);
      final ins = (h.service.lastSimulatedConfigPayload!['timers'] as Map)
          ['ins'] as List;
      expect(ins.length, 1);

      // Pull onTime back out of the entry to verify hour/min mapping.
      final onParts = entry.onTime!.split(':');
      final expectedHour = int.parse(onParts[0]);
      final expectedMin = int.parse(onParts[1]);
      final timer = ins.first as Map;
      expect(timer['macro'], result.lease!.presetId);
      expect(timer['hour'], expectedHour);
      expect(timer['min'], expectedMin);
      // dow MUST be computed from today's weekday at runtime — a
      // hardcoded value would break the test on every other day of
      // the week.
      expect(timer['dow'], todayDowMask());
      expect(timer['en'], isTrue);
    });
  });

  group('feature flag OFF', () {
    test('no savePreset or applyConfig reaches mock WLED', () async {
      final h = buildIntegrationHarness(liveWritesEnabled: false);
      await h.manager.initialize();

      final entry = insideWindowEntry();
      final result = await h.manager.handleEntryCreated(entry);

      // Registry still records the lease — entry is in-memory
      // visible even when the controller hasn't been touched.
      expect(result.outcome, LeaseOutcome.leased);
      expect(h.manager.activeLeases.length, 1);

      // No controller traffic occurred.
      expect(h.service.lastSimulatedPresetSave, isNull);
      expect(h.service.lastSimulatedConfigPayload, isNull);
    });
  });

  group('lease expiry sweep', () {
    test('expired lease → zeroed cfg.timers reaches mock WLED', () async {
      final h = buildIntegrationHarness();
      await h.manager.initialize();

      // Inject a synthesized lease that's already expired, then
      // sweep. The manager should write an empty timers.ins to the
      // controller (since the expired lease was the only entry).
      h.manager.injectLeaseForTest(CalendarEntryLease(
        dateKey: todayDateKey(),
        slotIndex: 0,
        presetId: kFirstLeasePresetId,
        leasedAt: DateTime.now().subtract(const Duration(hours: 2)),
        expiresAt: DateTime.now().subtract(const Duration(minutes: 5)),
        wledPayload: const {'on': true, 'bri': 128},
        patternName: 'expired',
        wledHour: 18,
        wledMin: 0,
        dowMask: todayDowMask(),
      ));
      expect(h.manager.activeLeases.length, 1);

      // Clear the capture so the assertion below targets the
      // sweep-induced write, not anything from initialize().
      h.service.lastSimulatedConfigPayload = null;

      await h.manager.sweepExpiredLeases();
      expect(h.manager.activeLeases, isEmpty);

      // The zero-write happened. With the expired lease gone and no
      // ScheduleItems, the timers.ins array is empty.
      expect(h.service.lastSimulatedConfigPayload, isNotNull);
      final ins = (h.service.lastSimulatedConfigPayload!['timers'] as Map)
          ['ins'] as List;
      expect(ins, isEmpty);
    });
  });

  group('write lock serializes sweep + create', () {
    test('concurrent sweep + create complete without crash; '
        'final state reflects both', () async {
      final h = buildIntegrationHarness();
      await h.manager.initialize();

      // Seed two leases: one expired (the sweep will remove it) and
      // one fresh (handleEntryCreated will add it). Run both
      // operations concurrently — without the lock, their
      // applyConfig calls could interleave and produce a corrupted
      // device-side timer array.
      h.manager.injectLeaseForTest(CalendarEntryLease(
        dateKey: '2026-01-01',
        slotIndex: 0,
        presetId: kFirstLeasePresetId,
        leasedAt: DateTime.now().subtract(const Duration(hours: 2)),
        expiresAt: DateTime.now().subtract(const Duration(minutes: 5)),
        wledPayload: const {'on': true, 'bri': 100},
        patternName: 'expired',
        wledHour: 18,
        wledMin: 0,
        dowMask: 0,
      ));

      final entry = insideWindowEntry(patternName: 'concurrent');
      final futures = await Future.wait<Object?>([
        h.manager.sweepExpiredLeases().then((_) => 'sweep'),
        h.manager.handleEntryCreated(entry).then((r) => r),
      ]);
      // Both completed.
      expect(futures.length, 2);
      // Final state: expired removed, new lease added.
      expect(h.manager.activeLeases.length, 1);
      expect(h.manager.activeLeases.single.dateKey, entry.dateKey);

      // applyConfig was called multiple times (sweep + create); the
      // final captured payload must reflect the post-create state.
      expect(h.service.lastSimulatedConfigPayload, isNotNull);
      final ins = (h.service.lastSimulatedConfigPayload!['timers'] as Map)
          ['ins'] as List;
      expect(ins.length, 1);
      expect((ins.first as Map)['macro'], h.manager.activeLeases.single.presetId);
    });
  });

  group('partial failure modes', () {
    test(
        'savePreset failure: applyConfig NOT attempted, '
        'lease registry rolled back', () async {
      final h = buildIntegrationHarness();
      h.service.simulateSavePresetReturns = false;
      await h.manager.initialize();

      // Clear any captures from initialize().
      h.service.lastSimulatedConfigPayload = null;
      h.service.lastSimulatedPresetSave = null;

      final entry = insideWindowEntry();
      final result = await h.manager.handleEntryCreated(entry);

      expect(result.outcome, LeaseOutcome.writeFailed,
          reason: 'savePreset failure must surface as writeFailed');
      // Registry rolled back — no lease for this dateKey.
      expect(h.manager.activeLeases, isEmpty);
      // savePreset was attempted.
      expect(h.service.lastSimulatedPresetSave, isNotNull);
      // applyConfig was NOT attempted (savePreset failure short-circuits).
      expect(h.service.lastSimulatedConfigPayload, isNull);
    });

    test(
        'applyConfig failure: savePreset preset still on controller '
        '(orphan), lease registry NOT rolled back', () async {
      final h = buildIntegrationHarness();
      h.service.simulateApplyConfigReturns = false;
      await h.manager.initialize();

      h.service.lastSimulatedConfigPayload = null;
      h.service.lastSimulatedPresetSave = null;

      final entry = insideWindowEntry();
      final result = await h.manager.handleEntryCreated(entry);

      // Outcome is `leased` so caller can surface "saved" UX while
      // the sweep retries the timer write in the background.
      expect(result.outcome, LeaseOutcome.leased);
      expect(h.manager.activeLeases.length, 1,
          reason: 'Registry must NOT be rolled back on applyConfig '
              'failure — preset is orphaned on controller, sweep retries');
      // savePreset succeeded — the preset record landed.
      expect(h.service.lastSimulatedPresetSave, isNotNull);
      expect(h.service.lastSimulatedPresetSave!.presetId,
          h.manager.activeLeases.single.presetId);
      // applyConfig was attempted (and failed per the injection).
      expect(h.service.lastSimulatedConfigPayload, isNotNull);
    });
  });
}
