// Shared day resolution — audit/MULTI_ENTRY_DISPLAY.md §2 B1.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/day_resolution.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';

ScheduleItem sched({
  required String id,
  int sortKey = 1,
  bool enabled = true,
  String label = 'Warm White',
}) =>
    ScheduleItem(
      id: id,
      timeLabel: '8:00 PM',
      actionLabel: label,
      repeatDays: const ['Mon'],
      enabled: enabled,
      sortKey: sortKey,
    );

CalendarEntry dated({String pattern = 'Deep Blue'}) => CalendarEntry(
      dateKey: '2026-08-20',
      patternName: pattern,
      color: const Color(0xFF00D4FF),
      onTime: '18:00',
      offTime: '23:00',
      brightness: 100,
      type: CalendarEntryType.user,
      autopilot: false,
    );

void main() {
  group('precedence — UNCHANGED, a dated entry masks recurring', () {
    test('dated entry wins over recurring', () {
      final r = resolveDay(
        datedEntry: dated(),
        recurringForDay: [sched(id: 'a'), sched(id: 'b', sortKey: 2)],
      );
      expect(r.source, DaySource.dated);
      expect(r.datedEntry!.patternName, 'Deep Blue');
      expect(r.recurringPrimary, isNull);
    });

    test('masked recurring items are COUNTED, not discarded', () {
      final r = resolveDay(
        datedEntry: dated(),
        recurringForDay: [sched(id: 'a'), sched(id: 'b', sortKey: 2)],
      );
      expect(r.totalCount, 3, reason: '1 dated + 2 recurring');
      expect(r.others.length, 2, reason: 'a +N badge must be able to count them');
      expect(r.hasMore, isTrue);
    });
  });

  group('ordering — newest wins (B3)', () {
    test('the NEWEST recurring item is primary', () {
      final r = resolveDay(datedEntry: null, recurringForDay: [
        sched(id: 'old', sortKey: 1),
        sched(id: 'new', sortKey: 2),
      ]);
      expect(r.source, DaySource.recurring);
      expect(r.recurringPrimary!.id, 'new');
    });

    test('a third schedule displaces the second', () {
      final r = resolveDay(datedEntry: null, recurringForDay: [
        sched(id: 'a', sortKey: 1),
        sched(id: 'b', sortKey: 2),
        sched(id: 'c', sortKey: 3),
      ]);
      expect(r.recurringPrimary!.id, 'c');
      expect(r.others.map((e) => e.id), ['b', 'a'], reason: 'newest-first');
    });

    test('REGRESSION: .first would have shown the oldest', () {
      final items = [sched(id: 'old', sortKey: 1), sched(id: 'new', sortKey: 2)];
      final r = resolveDay(datedEntry: null, recurringForDay: items);
      expect(r.recurringPrimary!.id, isNot(items.first.id));
    });

    test('tied sortKeys fall back to list position — later still wins', () {
      final r = resolveDay(datedEntry: null, recurringForDay: [
        sched(id: 'a', sortKey: 1),
        sched(id: 'b', sortKey: 1),
      ]);
      expect(r.recurringPrimary!.id, 'b');
    });
  });

  group('what does not count as coverage', () {
    test('disabled schedules are excluded', () {
      final r = resolveDay(datedEntry: null, recurringForDay: [
        sched(id: 'off', enabled: false, sortKey: 2),
        sched(id: 'on', sortKey: 1),
      ]);
      expect(r.recurringPrimary!.id, 'on');
      expect(r.totalCount, 1);
    });

    test('a day with only disabled schedules is EMPTY', () {
      final r = resolveDay(
        datedEntry: null,
        recurringForDay: [sched(id: 'x', enabled: false)],
      );
      expect(r.source, DaySource.none);
      expect(r.isEmpty, isTrue);
    });
  });

  group('the empty case', () {
    test('nothing at all', () {
      final r = resolveDay(datedEntry: null, recurringForDay: const []);
      expect(r.source, DaySource.none);
      expect(r.totalCount, 0);
      expect(r.hasMore, isFalse);
      expect(r.recurringPrimary, isNull);
      expect(r.datedEntry, isNull);
    });
  });

  group('defect C — a recurring-only day is NOT empty', () {
    test('resolves to recurring, so the month grid can render it', () {
      // _CalDayCell received only calEntry and never saw recurring schedules,
      // so a day covered solely by a recurring schedule rendered as nothing.
      final r = resolveDay(datedEntry: null, recurringForDay: [sched(id: 'a')]);
      expect(r.isEmpty, isFalse);
      expect(r.source, DaySource.recurring);
    });
  });

  group('all four surfaces resolve identically', () {
    test('the same inputs give the same answer regardless of caller', () {
      final entry = dated();
      final items = [sched(id: 'a', sortKey: 1), sched(id: 'b', sortKey: 2)];
      final a = resolveDay(datedEntry: entry, recurringForDay: items);
      final b = resolveDay(datedEntry: entry, recurringForDay: items);
      expect(a.source, b.source);
      expect(a.totalCount, b.totalCount);
      expect(a.datedEntry?.patternName, b.datedEntry?.patternName);
    });
  });

  // The three migrated surfaces (_DayHeroCard, _WeekDayCell, _buildTonightCard)
  // do NOT read `recurringPrimary` directly — they fall through a dated entry
  // field-by-field, so they need the newest recurring item even on a day a
  // dated entry masks. That is what `newestRecurring` is, and these pin it.
  group('newestRecurring — the masked fall-through accessor', () {
    test('with no dated entry it IS the primary', () {
      final r = resolveDay(datedEntry: null, recurringForDay: [
        sched(id: 'old', sortKey: 1),
        sched(id: 'new', sortKey: 2),
      ]);
      expect(r.newestRecurring!.id, 'new');
      expect(r.newestRecurring, same(r.recurringPrimary));
    });

    test('a dated entry does NOT hide it — the newest is still reachable', () {
      final r = resolveDay(datedEntry: dated(), recurringForDay: [
        sched(id: 'old', sortKey: 1),
        sched(id: 'new', sortKey: 2),
      ]);
      // Precedence is intact: nothing renders the recurring item as content.
      expect(r.source, DaySource.dated);
      expect(r.recurringPrimary, isNull);
      // But onTime/offTime fall-through and the Tonight card's tap target
      // both still resolve to the newest recurring schedule, as before B1.
      expect(r.newestRecurring!.id, 'new');
    });

    test('null when nothing recurring covers the day, dated or not', () {
      expect(
        resolveDay(datedEntry: null, recurringForDay: const []).newestRecurring,
        isNull,
      );
      expect(
        resolveDay(datedEntry: dated(), recurringForDay: const [])
            .newestRecurring,
        isNull,
      );
    });

    test('a disabled schedule is not a fall-through target either', () {
      final r = resolveDay(
        datedEntry: dated(),
        recurringForDay: [sched(id: 'off', enabled: false)],
      );
      expect(r.newestRecurring, isNull);
      expect(r.totalCount, 1, reason: 'the dated entry only');
    });
  });

  // BEHAVIOUR CHANGE at the three migrated surfaces, recorded deliberately:
  // none of them filtered soft-evicted schedules before B1, so a schedule the
  // lease manager had evicted still showed as the day's plan while the device
  // was never going to run it. resolveDay uses the same predicate as
  // cfg_payload_builder.dart:183, so display now matches what actually arms.
  group('soft-evicted schedules do not cover a day', () {
    ScheduleItem evicted(String id, {int sortKey = 1}) => ScheduleItem(
          id: id,
          timeLabel: '8:00 PM',
          actionLabel: 'Warm White',
          repeatDays: const ['Mon'],
          enabled: true,
          sortKey: sortKey,
          disabledUntil: DateTime.now().add(const Duration(days: 1)),
        );

    test('an evicted schedule cannot be the primary', () {
      final r = resolveDay(datedEntry: null, recurringForDay: [
        sched(id: 'live', sortKey: 1),
        evicted('evicted', sortKey: 2),
      ]);
      expect(r.recurringPrimary!.id, 'live',
          reason: 'newest-wins must not promote a schedule that will not arm');
      expect(r.totalCount, 1);
    });

    test('a day covered only by an evicted schedule is EMPTY', () {
      final r = resolveDay(
        datedEntry: null,
        recurringForDay: [evicted('x')],
      );
      expect(r.source, DaySource.none);
    });

    test('an expired eviction is live again', () {
      final r = resolveDay(datedEntry: null, recurringForDay: [
        ScheduleItem(
          id: 'expired',
          timeLabel: '8:00 PM',
          actionLabel: 'Warm White',
          repeatDays: const ['Mon'],
          enabled: true,
          sortKey: 1,
          disabledUntil: DateTime.now().subtract(const Duration(days: 1)),
        ),
      ]);
      expect(r.recurringPrimary!.id, 'expired');
    });
  });
}
