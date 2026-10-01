// +112 Policy B — a Game Day entry holds its date. A customer's dated entry
// onto that night is refused with one sentence; the Game Day timer is never
// displaced. Pure rule, pinned here; the notifier enforces the same function
// at the write.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_set.dart';
import 'package:nexgen_command/features/schedule/calendar_providers.dart';

CalendarEntry gameDay(String dateKey) => CalendarEntry(
      dateKey: dateKey,
      patternName: 'Kansas City Chiefs Colors',
      color: const Color(0xFFE31837),
      onTime: '14:55',
      offTime: '19:55',
      brightness: 78,
      type: CalendarEntryType.autopilot,
      autopilot: true,
      note: 'Kansas City Chiefs @ Las Vegas Raiders — Game Day autopilot',
      sourceTag: CalendarEntrySourceTag.gameDay,
      entryId: 'gd',
    );

CalendarEntry mine(String dateKey, {String? sourceTag, CalendarEntryType type = CalendarEntryType.user}) =>
    CalendarEntry(
      dateKey: dateKey,
      patternName: 'Warm White',
      color: const Color(0xFFFFE8C0),
      onTime: '19:00',
      offTime: '23:00',
      brightness: 80,
      type: type,
      autopilot: false,
      sourceTag: sourceTag,
      entryId: 'me',
    );

void main() {
  final state = CalendarEntrySet.fromEntries([gameDay('2026-10-04')]);

  test('a customer entry onto a Game Day night is refused and names the team', () {
    final r = gameDayRefusals(state, [mine('2026-10-04')]);
    expect(r.length, 1);
    expect(r.single.dateKey, '2026-10-04');
    expect(r.single.team, 'Kansas City Chiefs');
    expect(gameDayHoldsNightMessage(r.single.team),
        'The Kansas City Chiefs game already has that night.');
  });

  test('any other night passes', () {
    expect(gameDayRefusals(state, [mine('2026-10-05')]), isEmpty);
  });

  test('an edited Game Day row (type user, tag kept) passes — it IS the game', () {
    final edited = gameDay('2026-10-04').copyWith(type: CalendarEntryType.user, autopilot: false, brightness: 50);
    expect(gameDayRefusals(state, [edited]), isEmpty);
  });

  test('Lumina nights are refused like the customer\'s own', () {
    expect(gameDayRefusals(state, [mine('2026-10-04', sourceTag: CalendarEntrySourceTag.luminaAi)]).length, 1);
  });

  test('autopilot sources are not this guard\'s business', () {
    expect(gameDayRefusals(state, [mine('2026-10-04', type: CalendarEntryType.autopilot)]), isEmpty);
  });

  test('a batch reports each held date once', () {
    final two = CalendarEntrySet.fromEntries([gameDay('2026-10-04'), gameDay('2026-10-11')]);
    final r = gameDayRefusals(two, [mine('2026-10-04'), mine('2026-10-05'), mine('2026-10-11'), mine('2026-10-04')]);
    expect(r.map((x) => x.dateKey), ['2026-10-04', '2026-10-11']);
  });

  test('the message without a team name', () {
    expect(gameDayHoldsNightMessage(null), 'A Game Day already has that night.');
  });

  test('CalendarEntry.holdsGameDay covers both Game Day tags', () {
    expect(gameDay('2026-10-04').holdsGameDay, isTrue);
    expect(gameDay('2026-10-04').copyWith(sourceTag: CalendarEntrySourceTag.gameDayGroup).holdsGameDay, isTrue);
    expect(mine('2026-10-04').holdsGameDay, isFalse);
  });
}
