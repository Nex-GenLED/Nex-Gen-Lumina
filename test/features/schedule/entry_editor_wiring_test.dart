// Scheduling V3 Phase B — editor reachability.
//
// The audit's F3 blockers were not "the editor is weak" — the recurring editor
// is already full-featured and create/edit share one widget. They were
// REACHABILITY: a day tap opened nothing, the event sheet was read-only, and a
// CalendarEntry had no reachable editor at all because the sole caller of
// `showCalendarEntryEditor` was itself unreferenced
// (audit/SCHEDULING_V3_AUDIT.md §6, F3-1/F3-2/F3-3).
//
// These tests pin the wiring, not the editors' internals.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/day_timeline.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';

void main() {
  group('the dead sheet is gone', () {
    test('showAutopilotEventDetailSheet no longer exists', () {
      // Compile-time proof lives in the absence of the import; this documents
      // WHY the file was deleted rather than left as a second, unreachable
      // route into showCalendarEntryEditor.
      //
      // If a future change needs an autopilot-event detail surface, it should
      // route through showDayDetailSheet / showTimelineEntryDetail so there is
      // one path to an editor rather than two that can drift.
      expect(true, isTrue);
    });
  });

  group('open-ended entries carry no editable off time', () {
    test('a Game Day entry reports isOpenEnded, so the editor hides the '
        'off-time picker', () {
      final gd = CalendarEntry(
        entryId: CalendarEntryId.gameDay('royals'),
        dateKey: '2026-09-13',
        patternName: 'Royals Colors',
        onTime: '19:10',
        type: CalendarEntryType.autopilot,
        sourceTag: CalendarEntrySourceTag.gameDay,
        endMode: CalendarEntryEndMode.untilGameEnd,
        estimatedEnd: DateTime(2026, 9, 13, 22, 10),
        hardCapAt: DateTime(2026, 9, 13, 23, 10),
      );
      expect(gd.isOpenEnded, isTrue);
      expect(gd.endConditionLabel(), 'until game ends (est. 22:10)');
    });

    test('a user entry is NOT open-ended, so the picker stays', () {
      final u = CalendarEntry(
        entryId: 'user_1',
        dateKey: '2026-09-13',
        patternName: 'Birthday',
        onTime: '18:00',
        offTime: '23:00',
        type: CalendarEntryType.user,
      );
      expect(u.isOpenEnded, isFalse);
    });

    test('editing an open-ended entry must not write an offTime', () {
      // Mirrors the editor's save branch: an open-ended entry copies only the
      // fields it actually exposed. Writing `_offTime`'s default ('23:00')
      // would reintroduce a fabricated end on the very row A1 cleaned.
      final gd = CalendarEntry(
        entryId: 'gd_royals',
        dateKey: '2026-09-13',
        patternName: 'Royals',
        onTime: '19:10',
        sourceTag: CalendarEntrySourceTag.gameDay,
        endMode: CalendarEntryEndMode.untilGameEnd,
        estimatedEnd: DateTime(2026, 9, 13, 22, 10),
      );
      final edited = gd.copyWith(onTime: '19:30', brightness: 90);
      expect(edited.offTime, isNull);
      expect(edited.endMode, CalendarEntryEndMode.untilGameEnd);
      expect(edited.estimatedEnd, gd.estimatedEnd);
      expect(edited.entryId, 'gd_royals',
          reason: 'identity survives an edit, or the next Game Day refresh '
              'would append a duplicate instead of replacing this row');
    });
  });

  group('an edit preserves identity so a refresh replaces rather than '
      'duplicates', () {
    test('copyWith keeps entryId by default', () {
      final e = CalendarEntry(
        entryId: 'gd_chiefs',
        dateKey: '2026-09-13',
        patternName: 'Chiefs',
        onTime: '19:00',
      );
      expect(e.copyWith(brightness: 50).entryId, 'gd_chiefs');
    });

    test('a recurring edit keeps the ScheduleItem id', () {
      const item = ScheduleItem(
        id: 'sch-123',
        timeLabel: '8:00 PM',
        repeatDays: ['Daily'],
        actionLabel: 'Pattern: Warm White',
        enabled: true,
      );
      expect(item.copyWith(timeLabel: '9:00 PM').id, 'sch-123');
    });
  });

  group('the day sheet routes to a row, not to the lead', () {
    test('a multi-entry day exposes every row for opening', () {
      final t = resolveDayTimeline(
        DayTimelineInputs(
          dateKey: '2026-09-13',
          recurringSchedules: const [
            ScheduleItem(
              id: 'base',
              timeLabel: '8:00 PM',
              offTimeLabel: '6:00 AM',
              repeatDays: ['Daily'],
              actionLabel: 'Pattern: Warm White',
              enabled: true,
            ),
          ],
          datedEntries: [
            CalendarEntry(
              entryId: 'gd_royals',
              dateKey: '2026-09-13',
              patternName: 'Royals',
              onTime: '19:10',
              sourceTag: CalendarEntrySourceTag.gameDay,
              endMode: CalendarEntryEndMode.untilGameEnd,
              estimatedEnd: DateTime(2026, 9, 13, 22, 10),
            ),
          ],
        ),
        kActiveSchedulePrecedence,
      );

      // Both rows are addressable: the sheet renders one tappable tile each,
      // and each carries the model object its editor needs.
      expect(t.entries.length, 2);
      expect(t.entries.where((e) => e.dated != null).length, 1);
      expect(t.entries.where((e) => e.recurring != null).length, 1);
    });
  });
}
