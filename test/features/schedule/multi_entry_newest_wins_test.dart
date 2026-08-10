// B3 — newest-wins single pick. audit/MULTI_ENTRY_DISPLAY.md §2.
//
// A day with several recurring schedules can only render one today. It used to
// render `.first`, which is the OLDEST-created (sortKey is stamped max+1 per
// insert and both backends deliver ascending order). So a customer adding a
// schedule to an already-covered day saw NOTHING change — it sorted last and
// was the one dropped, which reads as "the app didn't save it".
//
// This pins the ordering contract the four display surfaces depend on. It does
// NOT fix multi-entry display, and it deliberately does not touch the
// dated-vs-recurring precedence (calEntry ?? recurring) — that is B2's question.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';

ScheduleItem item({
  required String id,
  required String label,
  required int sortKey,
  String time = '8:00 PM',
  List<String> days = const ['Mon'],
}) =>
    ScheduleItem(
      id: id,
      timeLabel: time,
      actionLabel: label,
      repeatDays: days,
      enabled: true,
      sortKey: sortKey,
    );

/// The pick the display surfaces make. Mirrors the shape at
/// my_schedule_page.dart (_DayHeroCard, _WeekDayCell) and
/// wled_dashboard_page.dart (_buildTonightCard).
ScheduleItem? newestOf(List<ScheduleItem> items) =>
    items.isNotEmpty ? items.last : null;

void main() {
  group('newest-wins single pick', () {
    test('two schedules on a day → the NEWER one shows', () {
      final items = [
        item(id: 'a', label: 'Warm White', sortKey: 1),
        item(id: 'b', label: 'Deep Blue', sortKey: 2), // added second
      ];
      expect(newestOf(items)!.id, 'b');
      expect(newestOf(items)!.actionLabel, 'Deep Blue');
    });

    test('adding a THIRD displaces the second', () {
      final items = [
        item(id: 'a', label: 'Warm White', sortKey: 1),
        item(id: 'b', label: 'Deep Blue', sortKey: 2),
        item(id: 'c', label: 'Royal Gold', sortKey: 3), // added third
      ];
      expect(newestOf(items)!.id, 'c');
    });

    test('REGRESSION: the old .first behaviour would have shown the oldest', () {
      final items = [
        item(id: 'a', label: 'Warm White', sortKey: 1),
        item(id: 'b', label: 'Deep Blue', sortKey: 2),
      ];
      expect(items.first.id, 'a', reason: 'documents what was shown before');
      expect(newestOf(items)!.id, isNot(items.first.id));
    });

    test('single schedule is unaffected', () {
      final items = [item(id: 'only', label: 'Warm White', sortKey: 1)];
      expect(newestOf(items)!.id, 'only');
    });

    test('empty day yields null, not a throw', () {
      expect(newestOf(const []), isNull);
    });
  });

  group('the ordering contract this relies on', () {
    test('sortKey ascending means newest is LAST', () {
      final items = [
        item(id: 'a', label: 'A', sortKey: 1),
        item(id: 'b', label: 'B', sortKey: 2),
        item(id: 'c', label: 'C', sortKey: 3),
      ];
      for (var i = 1; i < items.length; i++) {
        expect(items[i].sortKey, greaterThan(items[i - 1].sortKey));
      }
      expect(newestOf(items)!.sortKey,
          items.map((e) => e.sortKey).reduce((a, b) => a > b ? a : b));
    });

    test('TIED sortKeys fall back to list position — later still wins', () {
      // Fleet data shows several stored schedules carrying sortKey:1, so ties
      // are real. Positional .last degrades correctly; a max-by-sortKey pick
      // would be ambiguous here.
      final items = [
        item(id: 'a', label: 'A', sortKey: 1),
        item(id: 'b', label: 'B', sortKey: 1),
      ];
      expect(newestOf(items)!.id, 'b');
    });

    test('filtering to a weekday preserves relative order', () {
      final all = [
        item(id: 'a', label: 'A', sortKey: 1, days: ['Mon']),
        item(id: 'x', label: 'X', sortKey: 2, days: ['Tue']),
        item(id: 'b', label: 'B', sortKey: 3, days: ['Mon']),
      ];
      final mon =
          all.where((s) => s.repeatDays.contains('Mon')).toList();
      expect(newestOf(mon)!.id, 'b',
          reason: 'the weekday filter must not reorder');
    });
  });
}
