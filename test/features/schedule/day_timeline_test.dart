// Scheduling V3 A2 — the day timeline, both precedence policies.
//
// Written BEFORE the implementation, per the brief. Each group maps to a
// lettered case (a)-(g).
//
// What these tests are actually asserting: that the DISPLAY tells the truth
// about the firing layer as it exists today. `lastWriteWins` is not a rule this
// code invents — it is a description of what a WLED controller does when a base
// timer fires in the middle of a Game Day, which nothing prevents
// (audit/SCHEDULING_V3_AUDIT.md §4.3). `holdUntilEnd` is Policy B, implemented
// and tested but NOT selected.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/day_timeline.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';

const _date = '2026-09-13'; // a Sunday

ScheduleItem _recurring({
  String id = 'base',
  String on = '8:00 PM',
  String? off = '6:00 AM',
  String action = 'Pattern: Warm White',
  List<String> days = const ['Daily'],
  bool enabled = true,
  int sortKey = 1,
}) =>
    ScheduleItem(
      id: id,
      timeLabel: on,
      offTimeLabel: off,
      repeatDays: days,
      actionLabel: action,
      enabled: enabled,
      sortKey: sortKey,
    );

CalendarEntry _gameDay({
  String entryId = 'gd_royals',
  String on = '19:10',
  DateTime? estimatedEnd,
  DateTime? hardCapAt,
  List<int>? channels,
}) =>
    CalendarEntry(
      entryId: entryId,
      dateKey: _date,
      patternName: 'Kansas City Royals Colors',
      onTime: on,
      type: CalendarEntryType.autopilot,
      sourceTag: CalendarEntrySourceTag.gameDay,
      endMode: CalendarEntryEndMode.untilGameEnd,
      estimatedEnd: estimatedEnd ?? DateTime(2026, 9, 13, 22, 10),
      hardCapAt: hardCapAt ?? DateTime(2026, 9, 13, 23, 10),
      channels: channels,
    );

CalendarEntry _dated({
  String entryId = 'user_1',
  String on = '18:00',
  String? off = '23:00',
  String pattern = 'Halloween',
  List<int>? channels,
}) =>
    CalendarEntry(
      entryId: entryId,
      dateKey: _date,
      patternName: pattern,
      onTime: on,
      offTime: off,
      type: CalendarEntryType.user,
      channels: channels,
    );

DayTimeline _build({
  List<ScheduleItem> recurring = const [],
  List<CalendarEntry> dated = const [],
  required PrecedencePolicy policy,
}) =>
    resolveDayTimeline(
      DayTimelineInputs(
        dateKey: _date,
        recurringSchedules: recurring,
        datedEntries: dated,
      ),
      policy,
    );

void main() {
  // ── (a) Game Day + base nightly ─────────────────────────────────────────
  group('(a) Game Day + base nightly', () {
    test('lastWriteWins: both shown; base takes over at its own clock time', () {
      final t = _build(
        recurring: [_recurring(on: '8:00 PM')],
        dated: [_gameDay(on: '19:10')],
        policy: PrecedencePolicy.lastWriteWins,
      );

      expect(t.entries.length, 2, reason: 'a dated entry must not mask recurring');

      final gd = t.entries.first;
      final base = t.entries.last;
      expect(gd.source, TimelineSource.gameDay);
      expect(base.source, TimelineSource.recurring);
      expect(gd.startsAt, DateTime(2026, 9, 13, 19, 10));
      expect(base.startsAt, DateTime(2026, 9, 13, 20, 0));

      // THE POINT: the base timer fires on the controller mid-game and nothing
      // stops it, so the display says so.
      expect(gd.takenOverAt, DateTime(2026, 9, 13, 20, 0));
      expect(gd.takenOverByLabel, contains('Warm White'));
      expect(gd.suppressedUntil, isNull);

      // Open-ended, with the estimate carried but never stated as the end.
      expect(gd.isOpenEnded, isTrue);
      expect(gd.endsAt, isNull);
      expect(gd.estimatedEnd, DateTime(2026, 9, 13, 22, 10));
    });

    test('holdUntilEnd: base is suppressed and resumes at the cap', () {
      final t = _build(
        recurring: [_recurring(on: '8:00 PM')],
        dated: [_gameDay(on: '19:10')],
        policy: PrecedencePolicy.holdUntilEnd,
      );

      expect(t.entries.length, 2, reason: 'suppressed is still SHOWN');

      final gd = t.entries.first;
      final base = t.entries.last;

      expect(gd.takenOverAt, isNull, reason: 'Game Day holds under Policy B');
      expect(gd.holdsUntil, DateTime(2026, 9, 13, 23, 10),
          reason: 'hardCapAt, the fail-safe end');

      expect(base.suppressed, isTrue);
      expect(base.suppressedUntil, DateTime(2026, 9, 13, 23, 10),
          reason: 'the base resumes when the hold ends');
    });
  });

  // ── (b) two dated entries on one date ───────────────────────────────────
  test('(b) two dated entries are both shown, ordered by start', () {
    for (final policy in PrecedencePolicy.values) {
      final t = _build(
        dated: [
          _dated(entryId: 'user_late', on: '21:00', off: '23:00', pattern: 'Late'),
          _dated(entryId: 'user_early', on: '18:00', off: '20:00', pattern: 'Early'),
        ],
        policy: policy,
      );
      expect(t.entries.length, 2, reason: '$policy');
      expect(t.entries[0].label, contains('Early'), reason: '$policy');
      expect(t.entries[1].label, contains('Late'), reason: '$policy');
      expect(t.hasConflict, isFalse, reason: '$policy — they do not overlap');
    }
  });

  // ── (c) dated + recurring on the same date ──────────────────────────────
  test('(c) a dated entry no longer masks a recurring one', () {
    final t = _build(
      recurring: [_recurring(on: '8:00 PM')],
      dated: [_dated(on: '18:00', off: '23:00')],
      policy: PrecedencePolicy.lastWriteWins,
    );
    expect(t.entries.length, 2);
    expect(t.entries.map((e) => e.source),
        containsAll([TimelineSource.dated, TimelineSource.recurring]));
  });

  // ── (d) same-minute overlap → CONFLICT, unresolved ──────────────────────
  group('(d) same-minute overlap', () {
    test('is marked CONFLICT under both policies and is NOT resolved', () {
      for (final policy in PrecedencePolicy.values) {
        final t = _build(
          recurring: [_recurring(on: '8:00 PM')],
          dated: [_dated(on: '20:00', off: '23:00')],
          policy: policy,
        );
        expect(t.entries.length, 2, reason: '$policy — both survive');
        expect(t.hasConflict, isTrue, reason: '$policy');
        expect(t.entries.every((e) => e.conflict), isTrue, reason: '$policy');
        // Not resolved: neither is dropped, and neither claims to take over the
        // other, because today's firing order genuinely is indeterminate.
        expect(t.entries.every((e) => e.takenOverAt == null), isTrue,
            reason: '$policy');
      }
    });

    test('disjoint channels at the same minute are NOT a conflict', () {
      final t = _build(
        dated: [
          _dated(entryId: 'a', on: '20:00', channels: const [0]),
          _dated(entryId: 'b', on: '20:00', channels: const [1]),
        ],
        policy: PrecedencePolicy.lastWriteWins,
      );
      expect(t.hasConflict, isFalse);
    });

    test('null channels means ALL, so it conflicts with anything', () {
      final t = _build(
        dated: [
          _dated(entryId: 'a', on: '20:00', channels: null),
          _dated(entryId: 'b', on: '20:00', channels: const [1]),
        ],
        policy: PrecedencePolicy.lastWriteWins,
      );
      expect(t.hasConflict, isTrue);
    });
  });

  // ── (e) recurring-only day is unchanged from today ──────────────────────
  group('(e) a date with only recurring schedules', () {
    test('single recurring: one entry, no takeover, no conflict', () {
      final t = _build(
        recurring: [_recurring(on: '8:00 PM')],
        policy: PrecedencePolicy.lastWriteWins,
      );
      expect(t.entries.length, 1);
      expect(t.entries.single.takenOverAt, isNull);
      expect(t.hasConflict, isFalse);
      expect(t.entries.single.endsAt, DateTime(2026, 9, 14, 6, 0),
          reason: 'off before on ⇒ next morning');
    });

    test('disabled and evicted items are excluded, as resolveDay did', () {
      final t = _build(
        recurring: [
          _recurring(id: 'off', enabled: false),
          _recurring(
            id: 'evicted',
            // disabledUntil in the future ⇒ isCurrentlyEvicted
          ).copyWith(disabledUntil: DateTime.now().add(const Duration(days: 1))),
          _recurring(id: 'live', on: '7:00 PM'),
        ],
        policy: PrecedencePolicy.lastWriteWins,
      );
      expect(t.entries.length, 1);
      expect(t.entries.single.id, contains('live'));
    });

    test('weekday filtering matches the pre-V3 surfaces', () {
      // 2026-09-13 is a Sunday.
      final sundayOnly = _build(
        recurring: [_recurring(days: const ['Sun'])],
        policy: PrecedencePolicy.lastWriteWins,
      );
      expect(sundayOnly.entries.length, 1);

      final mondayOnly = _build(
        recurring: [_recurring(days: const ['Mon'])],
        policy: PrecedencePolicy.lastWriteWins,
      );
      expect(mondayOnly.entries, isEmpty);
    });
  });

  // ── (f) channels do not affect ordering in this prompt ──────────────────
  test('(f) channels present on one entry and null on another does not '
      'change ordering', () {
    final withChannels = _build(
      dated: [
        _dated(entryId: 'a', on: '18:00', channels: const [0, 1]),
        _dated(entryId: 'b', on: '21:00', channels: null),
      ],
      policy: PrecedencePolicy.lastWriteWins,
    );
    final withoutChannels = _build(
      dated: [
        _dated(entryId: 'a', on: '18:00'),
        _dated(entryId: 'b', on: '21:00'),
      ],
      policy: PrecedencePolicy.lastWriteWins,
    );

    // DOCUMENTED: `channels` is inert for ordering and takeover here. Its ONLY
    // effect anywhere in this prompt is conflict detection (case d) — deciding
    // whether two same-minute entries actually contend for the same pixels.
    expect(
      withChannels.entries.map((e) => e.id).toList(),
      withoutChannels.entries.map((e) => e.id).toList(),
    );
    expect(
      withChannels.entries.map((e) => e.takenOverAt).toList(),
      withoutChannels.entries.map((e) => e.takenOverAt).toList(),
    );
  });

  // ── (g) hardCapAt earlier than estimatedEnd ─────────────────────────────
  test('(g) holdUntilEnd ends at hardCapAt when it precedes estimatedEnd', () {
    final t = _build(
      recurring: [_recurring(on: '11:00 PM')],
      dated: [
        _gameDay(
          on: '19:10',
          estimatedEnd: DateTime(2026, 9, 13, 23, 30),
          hardCapAt: DateTime(2026, 9, 13, 22, 0), // EARLIER
        ),
      ],
      policy: PrecedencePolicy.holdUntilEnd,
    );

    final gd = t.entries.first;
    expect(gd.holdsUntil, DateTime(2026, 9, 13, 22, 0),
        reason: 'the cap is a fail-safe: whichever comes first');

    // The 23:00 base starts AFTER the hold ends, so it is not suppressed.
    final base = t.entries.last;
    expect(base.suppressed, isFalse);
  });

  // ── legacy read path (brief item 3) ─────────────────────────────────────
  group('legacy Game Day offTime is reinterpreted, not trusted', () {
    test('a pre-V3 game_day row becomes untilGameEnd with an estimate', () {
      final legacy = CalendarEntry.fromJson({
        'dateKey': '2026-05-31',
        'patternName': 'Kansas City Royals Colors',
        'onTime': '13:05',
        'offTime': '17:35', // the fabricated one, live on 159 rows
        'brightness': 78,
        'type': 'autopilot',
        'autopilot': true,
        'sourceTag': 'game_day',
        // no entryId, no endMode — this is what production holds
      });

      expect(legacy.entryId, CalendarEntryId.legacy);
      expect(legacy.endMode, CalendarEntryEndMode.untilGameEnd);
      expect(legacy.estimatedEnd, DateTime(2026, 5, 31, 17, 35));
      expect(legacy.isOpenEnded, isTrue);
      expect(legacy.timeRangeLabel, '13:05 → until game ends (est. 17:35)');
      expect(legacy.offTime, '17:35',
          reason: 'the raw field is preserved; only its MEANING changed');
    });

    test('a user entry keeps its offTime as a real boundary', () {
      final user = CalendarEntry.fromJson({
        'dateKey': '2026-05-31',
        'patternName': 'Birthday',
        'onTime': '18:00',
        'offTime': '23:00',
        'type': 'user',
        'autopilot': false,
      });
      expect(user.endMode, CalendarEntryEndMode.fixedTime);
      expect(user.isOpenEnded, isFalse);
      expect(user.timeRangeLabel, '18:00 → 23:00');
    });

    test('an explicit stored endMode always wins over inference', () {
      final e = CalendarEntry.fromJson({
        'dateKey': '2026-05-31',
        'patternName': 'X',
        'onTime': '18:00',
        'offTime': '23:00',
        'sourceTag': 'game_day',
        'endMode': 'fixedTime',
      });
      expect(e.endMode, CalendarEntryEndMode.fixedTime);
    });

    test('a game_day row with no offTime is open-ended with no estimate', () {
      final e = CalendarEntry.fromJson({
        'dateKey': '2026-05-31',
        'patternName': 'X',
        'onTime': '18:00',
        'sourceTag': 'game_day',
      });
      // No offTime ⇒ nothing to infer from ⇒ stays fixedTime, and the display
      // simply shows the start. We do NOT invent an end.
      expect(e.endMode, CalendarEntryEndMode.fixedTime);
      expect(e.estimatedEnd, isNull);
      expect(e.timeRangeLabel, '18:00');
    });

    test('an overnight legacy estimate rolls to the next day', () {
      final e = CalendarEntry.fromJson({
        'dateKey': '2026-05-31',
        'patternName': 'X',
        'onTime': '22:00',
        'offTime': '01:30',
        'sourceTag': 'game_day',
      });
      expect(e.estimatedEnd, DateTime(2026, 6, 1, 1, 30));
    });
  });
}
