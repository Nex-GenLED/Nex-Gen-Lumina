// #90 — the slot-meter budget must be driven by the lease RESERVATION, not by
// the number of calendar entries.
//
// The bug this locks down: `computeSlotUsage` subtracted
// `calendarLeaseEntriesProvider.length` — every date with a calendar entry,
// account-wide, no horizon filter, no expiry filter, plus the 12 holiday
// defaults seeded before Firestore loads. On Tyler's account that was 55, so
// the budget computed as `8 - 55`, clamped to 0, and the save guard refused
// EVERY new schedule with "This schedule needs 2 slots and 0 of 0 are already
// used. 55 held by calendar days."
//
// The firing path never used that number: ScheduleSyncService subtracts
// `leaseTimers.length` (schedule_sync.dart), the leases actually reserved on
// the device. These tests pin the meter to the same quantity.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_lease_manager.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/widgets/timer_slot_meter.dart';

ScheduleItem sched(String id, String on, {String? off = '11:00 PM'}) =>
    ScheduleItem(
      id: id,
      timeLabel: on,
      offTimeLabel: off,
      repeatDays: const ['Daily'],
      actionLabel: 'Warm White',
      enabled: true,
    );

/// A lease timer as the ledger carries it (macro 26-41, one general slot).
Map<String, dynamic> leaseTimer(int macro) =>
    {'en': 1, 'hour': 17, 'min': 30, 'macro': macro, 'dow': 127};

void main() {
  group('leaseReservationOf — the tri-state, not a count', () {
    test('Loading is UNKNOWN (null), never 0 — the P0-9 lesson', () {
      expect(leaseReservationOf(const LeaseLedgerLoading()), isNull);
    });

    test('Empty is a known zero', () {
      expect(leaseReservationOf(const LeaseLedgerEmpty()), 0);
    });

    test('Ready reports its timer count', () {
      expect(
        leaseReservationOf(LeaseLedgerReady([leaseTimer(26), leaseTimer(27)])),
        2,
      );
    });
  });

  group('(a) the reported failure — 55 entries but only 2 real leases', () {
    test('budget is 6, driven by the reservation and NOT the entry count', () {
      // Tyler's account: 43 stored calendar entries + 12 seeded holiday
      // defaults = 55 dates, of which exactly 2 fall inside the 48h lease
      // window and hold a device slot.
      const entryCountThatUsedToBeUsed = 55;
      final ledger = LeaseLedgerReady([leaseTimer(26), leaseTimer(27)]);

      final usage = computeSlotUsage(
        schedules: [sched('a', '7:00 PM')],
        leaseReservation: leaseReservationOf(ledger),
        solarEnabled: false,
      );

      expect(usage.budget, 6, reason: '8 general slots minus 2 real leases');
      expect(usage.used, 2, reason: 'one clock ON + one clock OFF');
      expect(usage.overCommitted, isFalse);
      expect(usage.ledgerUnknown, isFalse);

      // The old arithmetic, for contrast — this is what shipped.
      expect(kGeneralTimerSlots - entryCountThatUsedToBeUsed, -47);
    });

    test('a save that needs 2 slots now fits where it used to be refused', () {
      final usage = computeSlotUsage(
        schedules: [sched('a', '7:00 PM')],
        leaseReservation: 2,
        solarEnabled: false,
      );
      final want = slotsForSchedule(sched('new', '9:00 PM'),
          solarEnabled: false);
      expect(want, 2);
      expect(usage.used + want <= usage.budget, isTrue);
    });
  });

  group('(b) 12 seeded holidays, no active leases', () {
    test('budget is the full 8 — seeded holidays reserve nothing', () {
      // The 12 holiday defaults exist in CalendarScheduleNotifier's initial
      // state and are never persisted; none of them holds a device slot.
      final usage = computeSlotUsage(
        schedules: const [],
        leaseReservation: leaseReservationOf(const LeaseLedgerEmpty()),
        solarEnabled: false,
      );
      expect(usage.budget, kGeneralTimerSlots);
      expect(usage.budget, 8);
      expect(usage.overCommitted, isFalse);
    });
  });

  group('(c) ledger loading — unknown must not become zero', () {
    test('flagged unknown, budget is not fabricated as 0', () {
      final usage = computeSlotUsage(
        schedules: [sched('a', '7:00 PM')],
        leaseReservation: leaseReservationOf(const LeaseLedgerLoading()),
        solarEnabled: false,
      );
      expect(usage.ledgerUnknown, isTrue);
      expect(usage.overCommitted, isFalse,
          reason: 'unknown is not the same as full');
      expect(usage.budget, isNot(0));
    });
  });

  group('(d) 8 active leases — over-committed', () {
    test('budget 0 and flagged overCommitted', () {
      final ledger =
          LeaseLedgerReady(List.generate(8, (i) => leaseTimer(26 + i)));
      final usage = computeSlotUsage(
        schedules: const [],
        leaseReservation: leaseReservationOf(ledger),
        solarEnabled: false,
      );
      expect(usage.budget, 0);
      expect(usage.overCommitted, isTrue);
      expect(usage.ledgerUnknown, isFalse);
    });

    test('a negative budget is REPORTED, not clamped away', () {
      // Clamping is what made over-commitment indistinguishable from a
      // legitimately full pool. The raw value must survive.
      final usage = computeSlotUsage(
        schedules: const [],
        leaseReservation: 11,
        solarEnabled: false,
      );
      expect(usage.budget, -3);
      expect(usage.overCommitted, isTrue);
    });
  });

  group('the guard decides on flags, never on a clamped budget', () {
    // confirmSlotCapacity needs a BuildContext, so its decision rule is
    // asserted here in the form the widget applies it.
    bool wouldAllow(SlotUsage u, int want) =>
        u.ledgerUnknown || u.overCommitted || (u.used + want <= u.budget);

    test('(c) loading → allowed', () {
      final u = computeSlotUsage(
          schedules: [sched('a', '7:00 PM')],
          leaseReservation: null,
          solarEnabled: false);
      expect(wouldAllow(u, 2), isTrue);
    });

    test('(d) over-committed → allowed, NOT refused', () {
      final u = computeSlotUsage(
          schedules: const [], leaseReservation: 8, solarEnabled: false);
      expect(wouldAllow(u, 2), isTrue,
          reason: 'a save writes Firestore only; sync still refuses to arm');
    });

    test('a genuinely full pool with a known ledger still refuses', () {
      // Four two-slot schedules = 8 used, 0 leases, budget 8. One more cannot
      // fit and there is nothing unknown or over-committed about it.
      final u = computeSlotUsage(
        schedules: [
          sched('a', '1:00 PM'),
          sched('b', '2:00 PM'),
          sched('c', '3:00 PM'),
          sched('d', '4:00 PM'),
        ],
        leaseReservation: 0,
        solarEnabled: false,
      );
      expect(u.used, 8);
      expect(u.budget, 8);
      expect(u.overCommitted, isFalse);
      expect(u.ledgerUnknown, isFalse);
      expect(wouldAllow(u, 2), isFalse, reason: 'this refusal is correct');
    });
  });
}
