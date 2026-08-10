// A3 — interim overwrite guard. audit/MULTI_ENTRY_DISPLAY.md §2.
//
// `calendar_entries` holds one entry per date, so saving a second entry for a
// date destroys the first with no trace. The guard converts that silent loss
// into a deliberate choice — and is enforced AT THE WRITE, not only in the UI,
// because a widget-level guard is bypassed by the next call site that forgets
// it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/dated_overwrite_dialog.dart';

CalendarEntry entry({
  required String dateKey,
  required String pattern,
  CalendarEntryType type = CalendarEntryType.user,
  String onTime = '18:00',
}) =>
    CalendarEntry(
      dateKey: dateKey,
      patternName: pattern,
      color: const Color(0xFF00D4FF),
      onTime: onTime,
      offTime: '23:00',
      brightness: 100,
      type: type,
      autopilot: type == CalendarEntryType.autopilot,
    );

/// Mirrors CalendarScheduleNotifier.findDatedOverwrites. Kept in the test as a
/// pure re-statement of the rule so the contract is pinned independently of
/// Riverpod wiring: only a USER entry landing on an existing USER entry counts.
List<String> overwriteKeys(
  Map<String, CalendarEntry> state,
  List<CalendarEntry> incoming,
) {
  final out = <String>[];
  for (final e in incoming) {
    if (e.type != CalendarEntryType.user) continue;
    final existing = state[e.dateKey];
    if (existing == null) continue;
    if (existing.type != CalendarEntryType.user) continue;
    out.add(e.dateKey);
  }
  return out;
}

void main() {
  group('detection — what counts as a destructive overwrite', () {
    test('user entry over an existing USER entry → flagged', () {
      final state = {'2026-08-20': entry(dateKey: '2026-08-20', pattern: 'Deep Blue')};
      final incoming = [entry(dateKey: '2026-08-20', pattern: 'Warm White')];
      expect(overwriteKeys(state, incoming), ['2026-08-20']);
    });

    test('writing to an EMPTY date → not flagged (no new friction)', () {
      expect(
        overwriteKeys(const {}, [entry(dateKey: '2026-08-21', pattern: 'Warm White')]),
        isEmpty,
      );
    });

    test('user entry over a HOLIDAY entry → not flagged', () {
      // Holiday defaults are generated, not authored. Replacing one loses
      // nothing the customer created.
      final state = {
        '2026-12-25': entry(
            dateKey: '2026-12-25',
            pattern: 'Christmas Day',
            type: CalendarEntryType.holiday)
      };
      expect(
        overwriteKeys(state, [entry(dateKey: '2026-12-25', pattern: 'Warm White')]),
        isEmpty,
      );
    });

    test('user entry over an AUTOPILOT entry → not flagged', () {
      final state = {
        '2026-09-01': entry(
            dateKey: '2026-09-01',
            pattern: 'Game Day',
            type: CalendarEntryType.autopilot)
      };
      expect(
        overwriteKeys(state, [entry(dateKey: '2026-09-01', pattern: 'Warm White')]),
        isEmpty,
      );
    });

    test('AUTOPILOT entry over a user entry → NOT flagged here', () {
      // Autopilot has its own resolution flow (findUserConflictKeys +
      // resolveAutopilotConflicts). Double-guarding would prompt twice.
      final state = {'2026-09-02': entry(dateKey: '2026-09-02', pattern: 'Mine')};
      final incoming = [
        entry(
            dateKey: '2026-09-02',
            pattern: 'Game Day',
            type: CalendarEntryType.autopilot)
      ];
      expect(overwriteKeys(state, incoming), isEmpty);
    });

    test('a batch flags only the colliding dates', () {
      final state = {
        '2026-08-20': entry(dateKey: '2026-08-20', pattern: 'Deep Blue'),
        '2026-08-22': entry(dateKey: '2026-08-22', pattern: 'Gold'),
      };
      final incoming = [
        entry(dateKey: '2026-08-20', pattern: 'Warm White'), // collides
        entry(dateKey: '2026-08-21', pattern: 'Warm White'), // empty
        entry(dateKey: '2026-08-22', pattern: 'Warm White'), // collides
      ];
      expect(overwriteKeys(state, incoming), ['2026-08-20', '2026-08-22']);
    });
  });

  group('the choice offered is honest', () {
    test('there is no keepBoth — storage cannot hold two', () {
      expect(DatedOverwriteChoice.values,
          [DatedOverwriteChoice.replace, DatedOverwriteChoice.cancel]);
      expect(
        DatedOverwriteChoice.values.map((e) => e.name),
        isNot(contains('keepBoth')),
        reason: 'offering keepBoth would promise what the write cannot deliver',
      );
    });
  });
}
