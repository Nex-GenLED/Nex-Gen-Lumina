// Scheduling V3 A4 — widget tests for the timeline surfaces.
//
// These drive the REAL shared components (`DayTimelineList`,
// `TimelineCountBadge`), which is why the Tonight card and the day hero were
// refactored onto them rather than each keeping its own row loop. A test that
// re-implemented "take 2, then +N" would pass while the shipped card did
// something else — the failure mode this repo has been bitten by before.
//
// Budgets under test:
//   Tonight card → maxRows: 2 + "+N more"
//   Day hero     → maxRows: null (every row)
//   Week cell    → TimelineCountBadge

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/day_timeline.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/widgets/timeline_row.dart';

const _date = '2026-09-13'; // Sunday

ScheduleItem _rec(String id, String on, String action) => ScheduleItem(
      id: id,
      timeLabel: on,
      offTimeLabel: '6:00 AM',
      repeatDays: const ['Daily'],
      actionLabel: action,
      enabled: true,
    );

CalendarEntry _gd() => CalendarEntry(
      entryId: 'gd_royals',
      dateKey: _date,
      patternName: 'Royals Colors',
      onTime: '19:10',
      type: CalendarEntryType.autopilot,
      sourceTag: CalendarEntrySourceTag.gameDay,
      endMode: CalendarEntryEndMode.untilGameEnd,
      estimatedEnd: DateTime(2026, 9, 13, 22, 10),
      hardCapAt: DateTime(2026, 9, 13, 23, 10),
    );

CalendarEntry _user(String id, String on, String name) => CalendarEntry(
      entryId: id,
      dateKey: _date,
      patternName: name,
      onTime: on,
      offTime: '23:00',
      type: CalendarEntryType.user,
    );

DayTimeline _timeline({
  List<ScheduleItem> recurring = const [],
  List<CalendarEntry> dated = const [],
  PrecedencePolicy policy = kActiveSchedulePrecedence,
}) =>
    resolveDayTimeline(
      DayTimelineInputs(
        dateKey: _date,
        recurringSchedules: recurring,
        datedEntries: dated,
      ),
      policy,
    );

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: child),
        ),
      ),
    );

void main() {
  group('Tonight card budget — DayTimelineList(maxRows: 2)', () {
    testWidgets('renders TWO entries when the day holds two', (tester) async {
      final t = _timeline(
        recurring: [_rec('base', '8:00 PM', 'Pattern: Warm White')],
        dated: [_gd()],
      );
      expect(t.count, 2);

      await _pump(tester,
          DayTimelineList(timeline: t, maxRows: 2, compact: true));

      expect(find.text('Royals Colors'), findsOneWidget);
      expect(find.text('Warm White'), findsOneWidget);
      expect(find.byType(TimelineRowTile), findsNWidgets(2));
      // Nothing hidden ⇒ no "+N more".
      expect(find.byType(TimelineMoreRow), findsNothing);
    });

    testWidgets('shows the Game Day as open-ended with an estimate, and names '
        'what takes over', (tester) async {
      final t = _timeline(
        recurring: [_rec('base', '8:00 PM', 'Pattern: Warm White')],
        dated: [_gd()],
      );
      await _pump(tester,
          DayTimelineList(timeline: t, maxRows: 2, compact: true));

      // The honest end — NOT the fabricated clock time.
      expect(
        find.textContaining('until game ends (est. 10:10 PM)'),
        findsOneWidget,
      );
      // And today's firing truth: the base timer fires anyway.
      expect(
        find.textContaining('Warm White takes over at 8:00 PM'),
        findsOneWidget,
      );
    });

    testWidgets('truncates to two rows and offers "+N more"', (tester) async {
      final t = _timeline(
        recurring: [_rec('base', '11:00 PM', 'Pattern: Warm White')],
        dated: [
          _gd(),
          _user('u1', '18:00', 'Halloween'),
        ],
      );
      expect(t.count, 3);

      await _pump(tester,
          DayTimelineList(timeline: t, maxRows: 2, compact: true));

      expect(find.byType(TimelineRowTile), findsNWidgets(2));
      expect(find.byType(TimelineMoreRow), findsOneWidget);
      expect(find.text('+1 more schedule'), findsOneWidget);
    });

    testWidgets('"+N more" pluralises and is tappable', (tester) async {
      var tapped = 0;
      final t = _timeline(
        recurring: [_rec('base', '11:00 PM', 'Pattern: Warm White')],
        dated: [
          _gd(),
          _user('u1', '18:00', 'Halloween'),
          _user('u2', '18:30', 'Extra'),
        ],
      );
      await _pump(
        tester,
        DayTimelineList(
          timeline: t,
          maxRows: 2,
          compact: true,
          onMoreTap: () => tapped++,
        ),
      );

      expect(find.text('+2 more schedules'), findsOneWidget);
      await tester.tap(find.byType(TimelineMoreRow));
      await tester.pump();
      expect(tapped, 1);
    });
  });

  group('Day hero budget — DayTimelineList(maxRows: null)', () {
    testWidgets('renders THREE entries with no truncation', (tester) async {
      final t = _timeline(
        recurring: [_rec('base', '11:00 PM', 'Pattern: Warm White')],
        dated: [
          _gd(),
          _user('u1', '18:00', 'Halloween'),
        ],
      );
      expect(t.count, 3);

      await _pump(tester, DayTimelineList(timeline: t));

      expect(find.byType(TimelineRowTile), findsNWidgets(3));
      expect(find.byType(TimelineMoreRow), findsNothing);
      expect(find.text('Halloween'), findsOneWidget);
      expect(find.text('Royals Colors'), findsOneWidget);
      expect(find.text('Warm White'), findsOneWidget);
    });

    testWidgets('rows appear in clock order', (tester) async {
      final t = _timeline(
        recurring: [_rec('base', '11:00 PM', 'Pattern: Warm White')],
        dated: [_gd(), _user('u1', '18:00', 'Halloween')],
      );
      await _pump(tester, DayTimelineList(timeline: t));

      final labels = tester
          .widgetList<TimelineRowTile>(find.byType(TimelineRowTile))
          .map((w) => w.entry.label)
          .toList();
      expect(labels, ['Halloween', 'Royals Colors', 'Warm White']);
    });

    testWidgets('a non-compact row shows its provenance chip', (tester) async {
      final t = _timeline(dated: [_gd()]);
      await _pump(tester, DayTimelineList(timeline: t));
      expect(find.text('⚡ Game Day'), findsOneWidget);
    });

    testWidgets('a same-minute overlap is surfaced as unpredictable, not '
        'silently resolved', (tester) async {
      final t = _timeline(
        recurring: [_rec('base', '8:00 PM', 'Pattern: Warm White')],
        dated: [_user('u1', '20:00', 'Halloween')],
      );
      expect(t.hasConflict, isTrue);

      await _pump(tester, DayTimelineList(timeline: t));

      expect(find.byType(TimelineRowTile), findsNWidgets(2));
      expect(
        find.textContaining('which one runs is not predictable'),
        findsNWidgets(2),
      );
      // And neither claims a takeover.
      expect(find.textContaining('takes over'), findsNothing);
    });
  });

  group('Week cell — TimelineCountBadge', () {
    testWidgets('shows the count when a day holds more than one', (tester) async {
      final t = _timeline(
        recurring: [_rec('base', '8:00 PM', 'Pattern: Warm White')],
        dated: [_gd()],
      );
      await _pump(tester,
          TimelineCountBadge(count: t.count, hasConflict: t.hasConflict));
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('renders nothing for 0 or 1 — a "1" badge is noise',
        (tester) async {
      for (final n in [0, 1]) {
        await _pump(tester, TimelineCountBadge(count: n));
        expect(find.text('$n'), findsNothing, reason: 'count=$n');
      }
    });

    testWidgets('counts three', (tester) async {
      final t = _timeline(
        recurring: [_rec('base', '11:00 PM', 'Pattern: Warm White')],
        dated: [_gd(), _user('u1', '18:00', 'Halloween')],
      );
      await _pump(tester, TimelineCountBadge(count: t.count));
      expect(find.text('3'), findsOneWidget);
    });
  });

  group('Policy B rendering (implemented, not selected)', () {
    testWidgets('a suppressed base row is SHOWN and says when it resumes',
        (tester) async {
      final t = _timeline(
        recurring: [_rec('base', '8:00 PM', 'Pattern: Warm White')],
        dated: [_gd()],
        policy: PrecedencePolicy.holdUntilEnd,
      );
      await _pump(tester, DayTimelineList(timeline: t));

      expect(find.byType(TimelineRowTile), findsNWidgets(2),
          reason: 'suppressed is dimmed, never hidden');
      expect(find.textContaining('Paused while the game runs — resumes at '
          '11:10 PM'), findsOneWidget);
      expect(find.textContaining('takes over'), findsNothing);
    });
  });
}
