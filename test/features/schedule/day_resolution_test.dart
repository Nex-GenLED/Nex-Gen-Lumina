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
}
