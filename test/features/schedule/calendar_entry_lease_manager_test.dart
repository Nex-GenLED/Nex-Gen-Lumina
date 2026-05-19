// test/features/schedule/calendar_entry_lease_manager_test.dart
//
// Unit tests for [CalendarEntryLeaseManager] (Item #61 Workstream B).
//
// Mock strategy: hand-rolled fake [WledRepository] (no mocktail in
// pubspec). SharedPreferences uses Flutter's
// [SharedPreferences.setMockInitialValues] helper. Riverpod test
// containers override the manager's testable indirection providers
// (`calendarLeaseScheduleSlotDemandProvider`,
// `calendarLeaseEntriesProvider`) so the real [SchedulesNotifier] +
// [CalendarScheduleNotifier] never construct in tests.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_lease_manager.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Fixed "now" anchor: Tuesday 2026-05-19 noon local. Tests that
  // exercise lease-window math pin the manager's clock to this moment
  // so assertions stay stable.
  final fixedNow = DateTime(2026, 5, 19, 12, 0);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  // ─── Helpers ────────────────────────────────────────────────────

  CalendarEntry buildEntry({
    required String dateKey,
    String? onTime = '18:00',
    String? offTime = '22:00',
    String patternName = 'Test Pattern',
    Color? color = const Color(0xFF00C2FF),
    int brightness = 80,
    CalendarEntryType type = CalendarEntryType.user,
  }) =>
      CalendarEntry(
        dateKey: dateKey,
        patternName: patternName,
        color: color,
        onTime: onTime,
        offTime: offTime,
        brightness: brightness,
        type: type,
        autopilot: false,
      );

  String dateKeyFor(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  ({_FakeWledRepository repo, ProviderContainer container, CalendarEntryLeaseManager manager})
      buildHarness({
    int scheduleSlotDemand = 0,
    List<CalendarEntry> entries = const [],
    DateTime? now,
  }) {
    final repo = _FakeWledRepository();
    final container = ProviderContainer(overrides: [
      calendarLeaseScheduleSlotDemandProvider
          .overrideWith((_) => scheduleSlotDemand),
      calendarLeaseEntriesProvider.overrideWith((_) => entries),
      wledRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    final manager = container.read(calendarEntryLeaseManagerProvider);
    if (now != null) {
      manager.nowProvider = () => now;
    }
    return (repo: repo, container: container, manager: manager);
  }

  // ────────────────────────────────────────────────────────────────
  // Group: lease window detection
  // ────────────────────────────────────────────────────────────────
  group('lease window detection', () {
    test('entry today within 48h returns true', () async {
      final h = buildHarness(now: fixedNow);
      await h.manager.initialize();
      final entry = buildEntry(
        dateKey: dateKeyFor(fixedNow),
        onTime: '18:00',
        offTime: '22:00',
      );
      expect(h.manager.isWithinLeaseWindowForTest(entry), isTrue);
    });

    test('entry tomorrow within 48h returns true', () async {
      final h = buildHarness(now: fixedNow);
      await h.manager.initialize();
      final entry = buildEntry(
        dateKey: dateKeyFor(fixedNow.add(const Duration(days: 1))),
        onTime: '18:00',
        offTime: '22:00',
      );
      expect(h.manager.isWithinLeaseWindowForTest(entry), isTrue);
    });

    test('entry 3 days out returns false', () async {
      final h = buildHarness(now: fixedNow);
      await h.manager.initialize();
      final entry = buildEntry(
        dateKey: dateKeyFor(fixedNow.add(const Duration(days: 3))),
        onTime: '18:00',
        offTime: '22:00',
      );
      expect(h.manager.isWithinLeaseWindowForTest(entry), isFalse);
    });

    test('entry 30 days out returns false', () async {
      final h = buildHarness(now: fixedNow);
      await h.manager.initialize();
      final entry = buildEntry(
        dateKey: dateKeyFor(fixedNow.add(const Duration(days: 30))),
        onTime: '18:00',
        offTime: '22:00',
      );
      expect(h.manager.isWithinLeaseWindowForTest(entry), isFalse);
    });

    test('entry yesterday returns false (already past)', () async {
      final h = buildHarness(now: fixedNow);
      await h.manager.initialize();
      final entry = buildEntry(
        dateKey: dateKeyFor(fixedNow.subtract(const Duration(days: 1))),
        onTime: '18:00',
        offTime: '22:00',
      );
      expect(h.manager.isWithinLeaseWindowForTest(entry), isFalse);
    });

    test('entry today but offTime already passed returns false', () async {
      final h = buildHarness(now: fixedNow);
      await h.manager.initialize();
      // fixedNow = 12:00; on=07:00, off=09:00 → already over.
      final entry = buildEntry(
        dateKey: dateKeyFor(fixedNow),
        onTime: '07:00',
        offTime: '09:00',
      );
      expect(h.manager.isWithinLeaseWindowForTest(entry), isFalse);
    });
  });

  // ────────────────────────────────────────────────────────────────
  // Group: _singleDateDowMask
  // ────────────────────────────────────────────────────────────────
  group('_singleDateDowMask', () {
    test('Sunday date returns 1 (bit 0)', () async {
      final h = buildHarness();
      await h.manager.initialize();
      // 2026-01-04 is a Sunday.
      expect(h.manager.singleDateDowMaskForTest('2026-01-04'), 1);
    });

    test('Monday date returns 2 (bit 1)', () async {
      final h = buildHarness();
      await h.manager.initialize();
      // 2026-01-05 is a Monday.
      expect(h.manager.singleDateDowMaskForTest('2026-01-05'), 2);
    });

    test('Saturday date returns 64 (bit 6)', () async {
      final h = buildHarness();
      await h.manager.initialize();
      // 2026-01-10 is a Saturday.
      expect(h.manager.singleDateDowMaskForTest('2026-01-10'), 64);
    });

    test('2026-05-19 (Tuesday) returns 4 (bit 2)', () async {
      final h = buildHarness();
      await h.manager.initialize();
      expect(h.manager.singleDateDowMaskForTest('2026-05-19'), 4);
    });

    test('weekday match is consistent with DateTime.weekday', () async {
      final h = buildHarness();
      await h.manager.initialize();
      // Cross-check every day of one week.
      final cases = <String, int>{
        '2026-01-04': 1, // Sun
        '2026-01-05': 2, // Mon
        '2026-01-06': 4, // Tue
        '2026-01-07': 8, // Wed
        '2026-01-08': 16, // Thu
        '2026-01-09': 32, // Fri
        '2026-01-10': 64, // Sat
      };
      cases.forEach((dateKey, expected) {
        expect(
          h.manager.singleDateDowMaskForTest(dateKey),
          expected,
          reason: dateKey,
        );
      });
    });
  });

  // ────────────────────────────────────────────────────────────────
  // Group: _timeStringToWledHourMin
  // ────────────────────────────────────────────────────────────────
  group('_timeStringToWledHourMin', () {
    test('07:00 returns (hour: 7, min: 0)', () async {
      final h = buildHarness();
      await h.manager.initialize();
      final r = h.manager.timeStringToWledHourMinForTest('07:00');
      expect(r, isNotNull);
      expect(r!.hour, 7);
      expect(r.min, 0);
    });

    test('23:59 returns (hour: 23, min: 59)', () async {
      final h = buildHarness();
      await h.manager.initialize();
      final r = h.manager.timeStringToWledHourMinForTest('23:59');
      expect(r!.hour, 23);
      expect(r.min, 59);
    });

    test('11:10 returns (hour: 11, min: 10)', () async {
      final h = buildHarness();
      await h.manager.initialize();
      final r = h.manager.timeStringToWledHourMinForTest('11:10');
      expect(r!.hour, 11);
      expect(r.min, 10);
    });

    test('Sunrise returns (hour: 24, min: 0)', () async {
      final h = buildHarness();
      await h.manager.initialize();
      final r = h.manager.timeStringToWledHourMinForTest('Sunrise');
      expect(r!.hour, 24);
      expect(r.min, 0);
    });

    test('Sunset returns (hour: 25, min: 0)', () async {
      final h = buildHarness();
      await h.manager.initialize();
      final r = h.manager.timeStringToWledHourMinForTest('Sunset');
      expect(r!.hour, 25);
      expect(r.min, 0);
    });

    test('null returns null', () async {
      final h = buildHarness();
      await h.manager.initialize();
      expect(h.manager.timeStringToWledHourMinForTest(null), isNull);
    });

    test('garbage returns null', () async {
      final h = buildHarness();
      await h.manager.initialize();
      expect(h.manager.timeStringToWledHourMinForTest('garbage'), isNull);
    });

    test('25:00 returns null (hour out of range)', () async {
      final h = buildHarness();
      await h.manager.initialize();
      expect(h.manager.timeStringToWledHourMinForTest('25:00'), isNull);
    });

    test('case-insensitive sunrise/sunset', () async {
      final h = buildHarness();
      await h.manager.initialize();
      expect(h.manager.timeStringToWledHourMinForTest('SUNRISE')!.hour, 24);
      expect(h.manager.timeStringToWledHourMinForTest('sunset')!.hour, 25);
    });
  });

  // ────────────────────────────────────────────────────────────────
  // Group: dateKey validation (CalendarEntry.fromAiJson)
  // ────────────────────────────────────────────────────────────────
  group('CalendarEntry.fromAiJson dateKey validation', () {
    test('"2026-05-19" accepted', () {
      final e = CalendarEntry.fromAiJson({'date': '2026-05-19'});
      expect(e, isNotNull);
      expect(e!.dateKey, '2026-05-19');
    });

    test('"2026-5-19" rejected (missing zero pad)', () {
      expect(CalendarEntry.fromAiJson({'date': '2026-5-19'}), isNull);
    });

    test('"2026-05-1" rejected (missing zero pad on day)', () {
      expect(CalendarEntry.fromAiJson({'date': '2026-05-1'}), isNull);
    });

    test('"26-05-19" rejected (truncated year)', () {
      expect(CalendarEntry.fromAiJson({'date': '26-05-19'}), isNull);
    });

    test('"2026-13-01" rejected (invalid month)', () {
      expect(CalendarEntry.fromAiJson({'date': '2026-13-01'}), isNull);
    });

    test('"2026-02-30" rejected (invalid day in February)', () {
      expect(CalendarEntry.fromAiJson({'date': '2026-02-30'}), isNull);
    });

    test('empty string rejected', () {
      expect(CalendarEntry.fromAiJson({'date': ''}), isNull);
    });

    test('null rejected', () {
      expect(CalendarEntry.fromAiJson({'date': null}), isNull);
    });

    test('valid leap-year date 2024-02-29 accepted', () {
      final e = CalendarEntry.fromAiJson({'date': '2024-02-29'});
      expect(e, isNotNull);
      expect(e!.dateKey, '2024-02-29');
    });

    test('non-leap-year 2025-02-29 rejected', () {
      expect(CalendarEntry.fromAiJson({'date': '2025-02-29'}), isNull);
    });
  });

  // ────────────────────────────────────────────────────────────────
  // Group: slot allocation
  // ────────────────────────────────────────────────────────────────
  group('slot allocation', () {
    test('zero schedules + zero leases allocates slot 0', () async {
      final h = buildHarness(scheduleSlotDemand: 0);
      await h.manager.initialize();
      expect(h.manager.allocateFreeSlotIndexForTest(), 0);
    });

    test('3 schedules occupying slots 0-2 allocates slot 3', () async {
      final h = buildHarness(scheduleSlotDemand: 3);
      await h.manager.initialize();
      expect(h.manager.allocateFreeSlotIndexForTest(), 3);
    });

    test('8 schedules + 0 leases returns null (noFreeSlots)', () async {
      final h = buildHarness(scheduleSlotDemand: 8);
      await h.manager.initialize();
      expect(h.manager.allocateFreeSlotIndexForTest(), isNull);
    });

    test('5 schedules + 2 existing leases allocates slot 7', () async {
      final h = buildHarness(scheduleSlotDemand: 5);
      await h.manager.initialize();
      // Inject leases occupying slots 5 and 6 → next free is 7.
      h.manager.injectLeaseForTest(_makeLease(
        dateKey: '2026-12-25',
        slotIndex: 5,
        presetId: 30,
      ));
      h.manager.injectLeaseForTest(_makeLease(
        dateKey: '2026-12-26',
        slotIndex: 6,
        presetId: 31,
      ));
      expect(h.manager.allocateFreeSlotIndexForTest(), 7);
    });

    test('4 schedules + 4 leases returns null', () async {
      final h = buildHarness(scheduleSlotDemand: 4);
      await h.manager.initialize();
      for (int i = 0; i < 4; i++) {
        h.manager.injectLeaseForTest(_makeLease(
          dateKey: '2026-12-2${i + 1}',
          slotIndex: 4 + i,
          presetId: 26 + i,
        ));
      }
      expect(h.manager.allocateFreeSlotIndexForTest(), isNull);
    });
  });

  // ────────────────────────────────────────────────────────────────
  // Group: preset ID allocation
  // ────────────────────────────────────────────────────────────────
  group('preset ID allocation', () {
    test('returns deterministic ID in range 26-41', () async {
      final h = buildHarness();
      await h.manager.initialize();
      final id = h.manager.allocatePresetIdForTest('2026-05-19');
      expect(id, greaterThanOrEqualTo(kFirstLeasePresetId));
      expect(id, lessThanOrEqualTo(kLastLeasePresetId));
    });

    test('same dateKey called twice returns same ID (no existing lease)',
        () async {
      final h = buildHarness();
      await h.manager.initialize();
      final a = h.manager.allocatePresetIdForTest('2026-05-19');
      final b = h.manager.allocatePresetIdForTest('2026-05-19');
      expect(a, b);
    });

    test('linear probe avoids collision when natural slot is taken',
        () async {
      final h = buildHarness();
      await h.manager.initialize();
      const dateKey = '2026-12-25';
      final naturalStart = kFirstLeasePresetId +
          (dateKey.hashCode.abs() % (kLastLeasePresetId - kFirstLeasePresetId + 1));
      // Block the natural slot under a DIFFERENT dateKey.
      h.manager.injectLeaseForTest(_makeLease(
        dateKey: 'BLOCKER-2099-01-01',
        slotIndex: 0,
        presetId: naturalStart,
      ));
      final result = h.manager.allocatePresetIdForTest(dateKey);
      expect(result, isNot(naturalStart));
      expect(result, greaterThanOrEqualTo(kFirstLeasePresetId));
      expect(result, lessThanOrEqualTo(kLastLeasePresetId));
    });

    test('16 simultaneous leases fill the entire 26-41 range', () async {
      final h = buildHarness();
      await h.manager.initialize();
      // Fill all 16 preset IDs with distinct dateKeys.
      for (int i = 0; i < 16; i++) {
        h.manager.injectLeaseForTest(_makeLease(
          dateKey: 'FILLER-$i',
          slotIndex: i % 8,
          presetId: kFirstLeasePresetId + i,
        ));
      }
      // Any new dateKey allocation must fail without infinite loop.
      final result = h.manager.allocatePresetIdForTest('FRESH-DATE');
      expect(result, -1);
    });

    test('17th lease attempt fails gracefully (no infinite loop)',
        () async {
      // Same as above but with a stopwatch guard. Allocation should
      // complete in milliseconds even when full.
      final h = buildHarness();
      await h.manager.initialize();
      for (int i = 0; i < 16; i++) {
        h.manager.injectLeaseForTest(_makeLease(
          dateKey: 'FILLER-$i',
          slotIndex: i % 8,
          presetId: kFirstLeasePresetId + i,
        ));
      }
      final sw = Stopwatch()..start();
      final result = h.manager.allocatePresetIdForTest('17TH');
      sw.stop();
      expect(result, -1);
      expect(sw.elapsedMilliseconds, lessThan(50));
    });
  });

  // ────────────────────────────────────────────────────────────────
  // Group: WLED payload synthesis
  // ────────────────────────────────────────────────────────────────
  group('WLED payload synthesis', () {
    test('Off entry produces {on: false, bri: 0}', () async {
      final h = buildHarness();
      await h.manager.initialize();
      final entry = buildEntry(
        dateKey: '2026-05-19',
        patternName: 'Off',
        color: null,
        brightness: 0,
      );
      final p = h.manager.synthesizeWledPayloadForTest(entry);
      expect(p['on'], isFalse);
      expect(p['bri'], 0);
      expect(p.containsKey('seg'), isFalse);
    });

    test('Color entry produces on:true with bri scaling and seg payload',
        () async {
      final h = buildHarness();
      await h.manager.initialize();
      final entry = buildEntry(
        dateKey: '2026-05-19',
        patternName: 'Ocean Pulse',
        color: const Color(0xFF00C2FF),
        brightness: 80,
      );
      final p = h.manager.synthesizeWledPayloadForTest(entry);
      expect(p['on'], isTrue);
      // 80 * 255 / 100 = 204
      expect(p['bri'], 204);
      expect(p['seg'], isA<List>());
      final seg0 = (p['seg'] as List).first as Map;
      expect(seg0['fx'], 0);
      expect(seg0['sx'], 128);
      expect(seg0['ix'], 128);
      expect(seg0['col'], isA<List>());
      final col0 = (seg0['col'] as List).first as List;
      expect(col0.length, 4); // RGBW
    });

    test('brightness 50 (CalendarEntry scale) produces bri 128 (WLED scale)',
        () async {
      final h = buildHarness();
      await h.manager.initialize();
      final entry = buildEntry(
        dateKey: '2026-05-19',
        brightness: 50,
      );
      final p = h.manager.synthesizeWledPayloadForTest(entry);
      // round(50 * 255 / 100) = round(127.5) = 128 in Dart's banker's
      // rounding via round() (.5 rounds away from zero).
      expect(p['bri'], 128);
    });

    test('named pattern entry contains synthesized seg payload', () async {
      final h = buildHarness();
      await h.manager.initialize();
      final entry = buildEntry(
        dateKey: '2026-10-15',
        patternName: 'Royals Chase',
        color: const Color(0xFF004687), // KC Royals royal blue
        brightness: 100,
      );
      final p = h.manager.synthesizeWledPayloadForTest(entry);
      expect(p['on'], isTrue);
      expect(p['bri'], 255);
      final seg0 = (p['seg'] as List).first as Map;
      expect(seg0['fx'], 0);
    });

    test('color hex (#0033A0) parses through CalendarEntry into payload',
        () async {
      final h = buildHarness();
      await h.manager.initialize();
      final entry = CalendarEntry.fromAiJson({
        'date': '2026-07-04',
        'pattern': 'Independence Blue',
        'color': '#0033A0',
        'onTime': '20:00',
        'offTime': '23:00',
        'brightness': 90,
      });
      expect(entry, isNotNull);
      final p = h.manager.synthesizeWledPayloadForTest(entry!);
      final col0 = ((p['seg'] as List).first as Map)['col'] as List;
      final rgbw = col0.first as List;
      // Hex #0033A0 → R=0x00, G=0x33 (51), B=0xA0 (160).
      expect(rgbw[0], 0x00);
      expect(rgbw[1], 0x33);
      expect(rgbw[2], 0xA0);
    });
  });

  // ────────────────────────────────────────────────────────────────
  // Group: handleEntryCreated outcomes
  // ────────────────────────────────────────────────────────────────
  group('handleEntryCreated outcomes', () {
    test('entry outside 48h window returns outsideWindow', () async {
      final h = buildHarness(now: fixedNow);
      await h.manager.initialize();
      final entry = buildEntry(
        dateKey: dateKeyFor(fixedNow.add(const Duration(days: 5))),
      );
      final r = await h.manager.handleEntryCreated(entry);
      expect(r.outcome, LeaseOutcome.outsideWindow);
    });

    test('entry inside window with free slot returns leased',
        () async {
      final h = buildHarness(now: fixedNow, scheduleSlotDemand: 0);
      await h.manager.initialize();
      final entry = buildEntry(
        dateKey: dateKeyFor(fixedNow),
        onTime: '18:00',
        offTime: '22:00',
      );
      final r = await h.manager.handleEntryCreated(entry);
      expect(r.outcome, LeaseOutcome.leased);
      expect(r.lease, isNotNull);
      expect(r.lease!.slotIndex, 0);
      expect(r.lease!.presetId, inInclusiveRange(
        kFirstLeasePresetId,
        kLastLeasePresetId,
      ));
      // Side-effects: preset saved + cfg pushed.
      expect(h.repo.savePresetCalls.length, 1);
      expect(h.repo.applyConfigCalls.length, 1);
    });

    test('entry inside window with no free slot returns noFreeSlots',
        () async {
      final h = buildHarness(now: fixedNow, scheduleSlotDemand: 8);
      await h.manager.initialize();
      final entry = buildEntry(
        dateKey: dateKeyFor(fixedNow),
      );
      final r = await h.manager.handleEntryCreated(entry);
      expect(r.outcome, LeaseOutcome.noFreeSlots);
      expect(r.lease, isNull);
    });

    test('entry with null onTime/offTime returns invalidEntry', () async {
      final h = buildHarness(now: fixedNow);
      await h.manager.initialize();
      final entry = buildEntry(
        dateKey: dateKeyFor(fixedNow),
        onTime: null,
        offTime: null,
      );
      final r = await h.manager.handleEntryCreated(entry);
      expect(r.outcome, LeaseOutcome.invalidEntry);
    });

    test('entry whose offTime is already past returns alreadyExpired',
        () async {
      final h = buildHarness(now: fixedNow);
      await h.manager.initialize();
      // fixedNow = 12:00; off at 09:00 same day.
      final entry = buildEntry(
        dateKey: dateKeyFor(fixedNow),
        onTime: '07:00',
        offTime: '09:00',
      );
      final r = await h.manager.handleEntryCreated(entry);
      expect(r.outcome, LeaseOutcome.alreadyExpired);
    });

    test(
        're-creating same dateKey updates existing lease '
        '(outcome=updated, same slot, same preset)', () async {
      final h = buildHarness(now: fixedNow);
      await h.manager.initialize();
      final entry1 = buildEntry(
        dateKey: dateKeyFor(fixedNow),
        onTime: '18:00',
        offTime: '22:00',
        brightness: 50,
      );
      final r1 = await h.manager.handleEntryCreated(entry1);
      expect(r1.outcome, LeaseOutcome.leased);
      final originalSlot = r1.lease!.slotIndex;
      final originalPreset = r1.lease!.presetId;

      final entry2 = buildEntry(
        dateKey: dateKeyFor(fixedNow),
        onTime: '18:00',
        offTime: '22:00',
        brightness: 100, // changed
      );
      final r2 = await h.manager.handleEntryCreated(entry2);
      expect(r2.outcome, LeaseOutcome.updated);
      expect(r2.lease!.slotIndex, originalSlot);
      expect(r2.lease!.presetId, originalPreset);
      // The new payload should have bri=255 (from brightness 100).
      expect(r2.lease!.wledPayload['bri'], 255);
    });

    test('holiday-typed entry returns outsideWindow (never leases)',
        () async {
      final h = buildHarness(now: fixedNow);
      await h.manager.initialize();
      final entry = buildEntry(
        dateKey: dateKeyFor(fixedNow),
        type: CalendarEntryType.holiday,
      );
      final r = await h.manager.handleEntryCreated(entry);
      expect(r.outcome, LeaseOutcome.outsideWindow);
    });
  });

  // ────────────────────────────────────────────────────────────────
  // Group: sweepExpiredLeases
  // ────────────────────────────────────────────────────────────────
  group('sweepExpiredLeases', () {
    test('lease whose expiresAt < now is removed from registry',
        () async {
      final h = buildHarness(now: fixedNow);
      await h.manager.initialize();
      h.manager.injectLeaseForTest(_makeLease(
        dateKey: '2026-05-18',
        slotIndex: 0,
        presetId: 26,
        expiresAt: fixedNow.subtract(const Duration(hours: 1)),
      ));
      expect(h.manager.activeLeases.length, 1);
      await h.manager.sweepExpiredLeases();
      expect(h.manager.activeLeases, isEmpty);
    });

    test('expired lease triggers applyConfig zero-write on mock repo',
        () async {
      final h = buildHarness(now: fixedNow);
      await h.manager.initialize();
      h.manager.injectLeaseForTest(_makeLease(
        dateKey: '2026-05-18',
        slotIndex: 0,
        presetId: 26,
        expiresAt: fixedNow.subtract(const Duration(hours: 1)),
      ));
      final callsBefore = h.repo.applyConfigCalls.length;
      await h.manager.sweepExpiredLeases();
      expect(h.repo.applyConfigCalls.length, greaterThan(callsBefore));
    });

    test('lease still active is not touched', () async {
      final h = buildHarness(now: fixedNow);
      await h.manager.initialize();
      h.manager.injectLeaseForTest(_makeLease(
        dateKey: '2026-05-20',
        slotIndex: 0,
        presetId: 26,
        expiresAt: fixedNow.add(const Duration(hours: 6)),
      ));
      await h.manager.sweepExpiredLeases();
      expect(h.manager.activeLeases.length, 1);
      expect(h.manager.activeLeases.single.dateKey, '2026-05-20');
    });

    test('sweep promotes entry that has entered the 48h window',
        () async {
      // Entry one day out — within window. No lease yet. Sweep
      // promotes it.
      final entry = buildEntry(
        dateKey: dateKeyFor(fixedNow.add(const Duration(days: 1))),
        onTime: '18:00',
        offTime: '22:00',
      );
      final h = buildHarness(now: fixedNow, entries: [entry]);
      await h.manager.initialize();
      // initialize() already ran one sweep — verify promotion landed.
      expect(h.manager.activeLeases.length, 1);
      expect(
        h.manager.activeLeases.single.dateKey,
        entry.dateKey,
      );
    });

    test('sweep handles empty registry without error', () async {
      final h = buildHarness(now: fixedNow);
      await h.manager.initialize();
      // No leases, no entries.
      await h.manager.sweepExpiredLeases();
      expect(h.manager.activeLeases, isEmpty);
    });
  });

  // ────────────────────────────────────────────────────────────────
  // Group: persistence
  // ────────────────────────────────────────────────────────────────
  group('persistence', () {
    test('leases persist across simulated app restart', () async {
      // Phase 1: create a lease, await persistence.
      {
        final h = buildHarness(now: fixedNow);
        await h.manager.initialize();
        final entry = buildEntry(
          dateKey: dateKeyFor(fixedNow),
          onTime: '18:00',
          offTime: '22:00',
        );
        final r = await h.manager.handleEntryCreated(entry);
        expect(r.outcome, LeaseOutcome.leased);
      }
      // Phase 2: same SharedPreferences mock instance, fresh container
      // + manager. Registry should rehydrate from disk.
      {
        final h = buildHarness(now: fixedNow);
        await h.manager.initialize();
        expect(h.manager.activeLeases.length, 1);
        expect(
          h.manager.activeLeases.single.dateKey,
          dateKeyFor(fixedNow),
        );
      }
    });

    test('corrupted SharedPreferences JSON is handled gracefully',
        () async {
      // Seed bad JSON into the mock.
      SharedPreferences.setMockInitialValues({
        'calendar_leases_v1': 'this is not json {{{',
      });
      final h = buildHarness(now: fixedNow);
      await h.manager.initialize();
      expect(h.manager.activeLeases, isEmpty);
      // Manager remains usable after corruption.
      final entry = buildEntry(
        dateKey: dateKeyFor(fixedNow),
        onTime: '18:00',
        offTime: '22:00',
      );
      final r = await h.manager.handleEntryCreated(entry);
      expect(r.outcome, LeaseOutcome.leased);
    });

    test('JSON that is valid but unexpected shape is handled', () async {
      SharedPreferences.setMockInitialValues({
        'calendar_leases_v1': '{"unexpected": "object"}',
      });
      final h = buildHarness(now: fixedNow);
      await h.manager.initialize();
      expect(h.manager.activeLeases, isEmpty);
    });

    test('individual malformed records are skipped, rest restored',
        () async {
      // One good lease + one broken record.
      SharedPreferences.setMockInitialValues({
        'calendar_leases_v1':
            '[{"dateKey":"2026-05-20","slotIndex":0,"presetId":26,'
            '"leasedAt":"2026-05-19T12:00:00.000",'
            '"expiresAt":"2026-05-20T22:00:00.000",'
            '"wledPayload":{"on":true},"patternName":"Good",'
            '"wledHour":18,"wledMin":0,"dowMask":8},'
            '{"bogus":"record"}]',
      });
      final h = buildHarness(now: fixedNow);
      await h.manager.initialize();
      // The good one survives the sweep (expiresAt > fixedNow).
      expect(h.manager.activeLeases.length, 1);
      expect(h.manager.activeLeases.single.dateKey, '2026-05-20');
    });
  });

  // ────────────────────────────────────────────────────────────────
  // Group: handleEntryDeleted
  // ────────────────────────────────────────────────────────────────
  group('handleEntryDeleted', () {
    test('removes active lease and triggers zero-write', () async {
      final h = buildHarness(now: fixedNow);
      await h.manager.initialize();
      h.manager.injectLeaseForTest(_makeLease(
        dateKey: '2026-05-20',
        slotIndex: 0,
        presetId: 26,
        expiresAt: fixedNow.add(const Duration(days: 1)),
      ));
      final callsBefore = h.repo.applyConfigCalls.length;
      await h.manager.handleEntryDeleted('2026-05-20');
      expect(h.manager.activeLeases, isEmpty);
      expect(h.repo.applyConfigCalls.length, greaterThan(callsBefore));
    });

    test('delete of unknown dateKey is a no-op (no repo call)', () async {
      final h = buildHarness(now: fixedNow);
      await h.manager.initialize();
      final callsBefore = h.repo.applyConfigCalls.length;
      await h.manager.handleEntryDeleted('9999-12-31');
      expect(h.repo.applyConfigCalls.length, callsBefore);
    });
  });
}

// ─── Test fixtures ──────────────────────────────────────────────────────────

CalendarEntryLease _makeLease({
  required String dateKey,
  required int slotIndex,
  required int presetId,
  DateTime? leasedAt,
  DateTime? expiresAt,
  Map<String, dynamic>? payload,
  String patternName = 'Fixture',
  int wledHour = 18,
  int wledMin = 0,
  int dowMask = 0,
}) =>
    CalendarEntryLease(
      dateKey: dateKey,
      slotIndex: slotIndex,
      presetId: presetId,
      leasedAt: leasedAt ?? DateTime(2026, 5, 19, 12, 0),
      expiresAt: expiresAt ?? DateTime(2026, 5, 20, 22, 0),
      wledPayload: payload ?? const {'on': true, 'bri': 128},
      patternName: patternName,
      wledHour: wledHour,
      wledMin: wledMin,
      dowMask: dowMask,
    );

class _SavePresetCall {
  final int presetId;
  final Map<String, dynamic> state;
  final String? presetName;
  _SavePresetCall(this.presetId, this.state, this.presetName);
}

class _FakeWledRepository extends WledRepository {
  final List<_SavePresetCall> savePresetCalls = [];
  final List<Map<String, dynamic>> applyConfigCalls = [];
  bool savePresetReturns = true;
  bool applyConfigReturns = true;

  @override
  Future<bool> savePreset({
    required int presetId,
    required Map<String, dynamic> state,
    String? presetName,
  }) async {
    savePresetCalls.add(
      _SavePresetCall(presetId, Map<String, dynamic>.from(state), presetName),
    );
    return savePresetReturns;
  }

  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async {
    applyConfigCalls.add(Map<String, dynamic>.from(cfg));
    return applyConfigReturns;
  }

  // ─── Abstract stubs (unused but required by interface) ─────────

  @override
  Future<Map<String, dynamic>?> getState() async => null;

  @override
  Future<bool> setState({
    bool? on,
    int? brightness,
    int? speed,
    Color? color,
    int? white,
    bool? forceRgbwZeroWhite,
  }) async =>
      true;

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async => true;

  @override
  Future<bool> uploadLedMapJson(String jsonContent) async => true;

  @override
  Future<bool> configureSyncReceiver() async => true;

  @override
  Future<bool> configureSyncSender({
    List<String> targets = const [],
    int ddpPort = 4048,
  }) async =>
      true;
}
