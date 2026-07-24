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
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/wled/wled_dow.dart';
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

  /// Expected dow bitmask for today, computed at runtime via the
  /// canonical [wledDowMaskForWeekday] helper (Mon=bit 0..Sun=bit 6
  /// per WLED firmware). Hardcoding breaks across days; reusing the
  /// helper guarantees the test asserts the same convention the
  /// production write path emits — and any future change to that
  /// convention fails fast at the source of truth.
  int todayDowMask() => wledDowMaskForWeekday(DateTime.now().weekday);

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

      // applyConfig captured the merged timers.ins. The payload is padded to
      // all 8 slots (slot reclaim); with zero ScheduleItems the lease is the
      // only REAL timer, at slot 0, followed by disabled stubs.
      expect(h.service.lastSimulatedConfigPayload, isNotNull);
      final ins = (h.service.lastSimulatedConfigPayload!['timers'] as Map)
          ['ins'] as List;
      expect(ins.length, ScheduleSyncService.kMaxWledTimers);
      // P0-3.1: lease timer `en` is int 1 (was bool true — WLED stores a bool
      // en as 0=disabled, so the pre-arm never fired). Padding stubs are en:0.
      expect(ins.where((t) => (t as Map)['en'] == 1).length, 1);
      expect(ins.skip(1).every((t) => (t as Map)['en'] == 0), isTrue);

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
      expect(timer['en'], 1, reason: 'P0-3.1: int 1, not bool true');
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
      // ScheduleItems, all 8 slots are disabled stubs — the vacated slot is
      // genuinely zeroed on the controller (this is the reclaim that clears
      // the accumulated dead dow:0 timers).
      expect(h.service.lastSimulatedConfigPayload, isNotNull);
      final ins = (h.service.lastSimulatedConfigPayload!['timers'] as Map)
          ['ins'] as List;
      expect(ins.length, ScheduleSyncService.kMaxWledTimers);
      expect(ins.every((t) => (t as Map)['en'] == 0), isTrue);
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
      // final captured payload must reflect the post-create state — padded to
      // all 8 slots with the single active lease as the only real timer.
      expect(h.service.lastSimulatedConfigPayload, isNotNull);
      final ins = (h.service.lastSimulatedConfigPayload!['timers'] as Map)
          ['ins'] as List;
      expect(ins.length, ScheduleSyncService.kMaxWledTimers);
      final real = ins.where((t) => (t as Map)['en'] == 1).toList(); // P0-3.1 int
      expect(real.length, 1);
      expect((real.first as Map)['macro'],
          h.manager.activeLeases.single.presetId);
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
        'cfg write NOT verified (P0-3.3): preset saved but timer absent → '
        'lease rolled back, surfaces writeFailed', () async {
      // Post-hardening contract (replaces the old fire-and-forget "orphan kept"
      // behavior): the cfg write is verified by readback. If it does not
      // confirm, the lease is NOT armed, so the registry must roll back — a
      // kept record would never re-arm (promotion skips registered dateKeys),
      // which was the days-of-presets / zero-timers silent-failure bug.
      final h = buildIntegrationHarness();
      await h.manager.initialize();
      // Drive the hardened cfg push to a non-confirmed outcome synchronously
      // (the stall / absent-timer case) — no real-time poll.
      h.manager.cfgPushFn = (_, __, ___) async => CfgPushOutcome.notConfirmed;
      h.service.lastSimulatedPresetSave = null;

      final entry = insideWindowEntry();
      final result = await h.manager.handleEntryCreated(entry);

      expect(result.outcome, LeaseOutcome.writeFailed,
          reason: 'an unverified cfg write must surface as writeFailed, not a '
              'silent leased');
      expect(h.manager.activeLeases, isEmpty,
          reason: 'registry MUST roll back when the timer is not verified so '
              'the next sweep re-promotes and re-arms it');
      // savePreset still ran — the preset is orphaned on the controller until
      // the re-arm overwrites it (expected, harmless).
      expect(h.service.lastSimulatedPresetSave, isNotNull);
    });
  });
}
