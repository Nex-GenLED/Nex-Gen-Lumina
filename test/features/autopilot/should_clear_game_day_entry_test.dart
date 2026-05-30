// Tests for [shouldClearGameDayEntry] — the predicate that gates which
// CalendarEntry rows _clearFutureGameDayCalendarEntries deletes during
// a Game Day calendar regen.
//
// #63 Sub-Change A (the LOCKED filter) added the
// sourceTag == CalendarEntrySourceTag.gameDay condition so neighborhood-
// sync entries (type:autopilot, sourceTag:neighborhoodSync) survive
// game-day populate/teardown. Pre-fix the predicate filtered only by
// type and would collateral-wipe the neighborhood entries.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_providers.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';

CalendarEntry _entry({
  CalendarEntryType type = CalendarEntryType.autopilot,
  String? sourceTag,
  String dateKey = '2026-06-15',
}) =>
    CalendarEntry(
      dateKey: dateKey,
      patternName: 'test',
      type: type,
      sourceTag: sourceTag,
    );

void main() {
  final todayStart = DateTime(2026, 5, 29);

  group('shouldClearGameDayEntry — positive cases', () {
    test('game-day autopilot entry in the future is cleared', () {
      final entry = _entry(
        sourceTag: CalendarEntrySourceTag.gameDay,
        dateKey: '2026-06-15',
      );
      expect(
        shouldClearGameDayEntry(
            dateKey: '2026-06-15', entry: entry, todayStart: todayStart),
        isTrue,
      );
    });

    test('game-day autopilot entry on today is cleared (boundary)', () {
      // todayStart is 2026-05-29 00:00; an entry on 2026-05-29 is NOT
      // before todayStart → cleared.
      final entry = _entry(
        sourceTag: CalendarEntrySourceTag.gameDay,
        dateKey: '2026-05-29',
      );
      expect(
        shouldClearGameDayEntry(
            dateKey: '2026-05-29', entry: entry, todayStart: todayStart),
        isTrue,
      );
    });
  });

  group(
      'shouldClearGameDayEntry — negative cases (the protections #63 ships)',
      () {
    test(
      'neighborhood-sync autopilot entry is PRESERVED '
      '(#63 Sub-Change A — the neighborhood-sync collateral-wipe fix)',
      () {
        final entry = _entry(
          sourceTag: CalendarEntrySourceTag.neighborhoodSync,
          dateKey: '2026-06-15',
        );
        expect(
          shouldClearGameDayEntry(
              dateKey: '2026-06-15', entry: entry, todayStart: todayStart),
          isFalse,
          reason:
              'Neighborhood-sync entries share CalendarEntryType.autopilot '
              'but carry sourceTag.neighborhoodSync. The locked filter must '
              'leave them untouched during Game Day regen.',
        );
      },
    );

    test('user-authored entry (non-autopilot type) is preserved', () {
      final entry = _entry(type: CalendarEntryType.user);
      expect(
        shouldClearGameDayEntry(
            dateKey: '2026-06-15', entry: entry, todayStart: todayStart),
        isFalse,
      );
    });

    test('holiday entry is preserved', () {
      final entry = _entry(type: CalendarEntryType.holiday);
      expect(
        shouldClearGameDayEntry(
            dateKey: '2026-06-15', entry: entry, todayStart: todayStart),
        isFalse,
      );
    });

    test('past game-day entry is preserved (history)', () {
      final entry = _entry(
        sourceTag: CalendarEntrySourceTag.gameDay,
        dateKey: '2025-12-01',
      );
      expect(
        shouldClearGameDayEntry(
            dateKey: '2025-12-01', entry: entry, todayStart: todayStart),
        isFalse,
      );
    });

    test('autopilot entry with null sourceTag is preserved '
        '(legacy in-flight entries — acceptable per #63 spike)', () {
      // Future-window entries pre-dating the sourceTag write will be
      // stranded but age out; past entries are already preserved by
      // the date guard. Acceptable trade-off for the schema-free fix.
      final entry = _entry(sourceTag: null, dateKey: '2026-06-15');
      expect(
        shouldClearGameDayEntry(
            dateKey: '2026-06-15', entry: entry, todayStart: todayStart),
        isFalse,
      );
    });

    test('unparsable dateKey is preserved (defensive)', () {
      final entry = _entry(sourceTag: CalendarEntrySourceTag.gameDay);
      expect(
        shouldClearGameDayEntry(
            dateKey: 'not-a-date', entry: entry, todayStart: todayStart),
        isFalse,
      );
    });
  });
}
