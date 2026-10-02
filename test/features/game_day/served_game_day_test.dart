// +114 — tying a Game Day calendar row to the team the server serves.
//
// Production Game Day rows carry entryId 'primary' (the autopilot writer never
// sets the gd_<slug> id the plan assumed); the team comes from the note through
// the account's configs. A row whose team cannot be recovered is NOT served.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/game_day/game_day_server_status.dart';
import 'package:nexgen_command/features/game_day/served_game_day.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';

const _names = {
  'Kansas City Chiefs': 'kansas_city_chiefs',
  'Kansas City Royals': 'kansas_city_royals',
};

CalendarEntry _row({
  String? note = 'Kansas City Chiefs vs Las Vegas Raiders — Game Day autopilot',
  String? tag = CalendarEntrySourceTag.gameDay,
  String entryId = CalendarEntryId.legacy,
  CalendarEntryType type = CalendarEntryType.autopilot,
}) =>
    CalendarEntry(
      entryId: entryId,
      dateKey: '2026-10-11',
      patternName: 'Team Night',
      color: const Color(0xFFE31837),
      onTime: '14:55',
      offTime: '19:55',
      type: type,
      note: note,
      sourceTag: tag,
    );

final DateTime _now = DateTime(2026, 10, 11, 12);

GameDayServerStatus _status({
  List<String> teams = const ['kansas_city_chiefs'],
  Duration age = const Duration(minutes: 3),
}) =>
    GameDayServerStatus.fromUserDoc({
      'served': true,
      'teams': teams,
      'checked_at': Timestamp.fromDate(_now.subtract(age)),
    });

void main() {
  group('gameDayEntryTeamSlug', () {
    test('a production row (entryId primary) maps through the note', () {
      expect(gameDayEntryTeamSlug(_row(), _names), 'kansas_city_chiefs');
    });

    test('an away game (@) maps too', () {
      expect(
          gameDayEntryTeamSlug(
              _row(note: 'Kansas City Chiefs @ Denver Broncos — Game Day '
                  'autopilot'),
              _names),
          'kansas_city_chiefs');
    });

    test('a gd_<slug> id is honoured first', () {
      expect(gameDayEntryTeamSlug(_row(entryId: 'gd_some_team', note: null),
              _names),
          'some_team');
    });

    test('a user-edited Game Day row (type user, tag kept) still maps', () {
      expect(gameDayEntryTeamSlug(_row(type: CalendarEntryType.user), _names),
          'kansas_city_chiefs');
    });

    test('crew rows, untagged rows, no note, unknown team → null', () {
      expect(
          gameDayEntryTeamSlug(
              _row(tag: CalendarEntrySourceTag.gameDayGroup), _names),
          isNull);
      expect(gameDayEntryTeamSlug(_row(tag: null), _names), isNull);
      expect(gameDayEntryTeamSlug(_row(note: null), _names), isNull);
      expect(
          gameDayEntryTeamSlug(
              _row(note: 'Somewhere FC vs Elsewhere — Game Day autopilot'),
              _names),
          isNull);
    });
  });

  group('isServedGameDayEntry', () {
    test('served team, fresh heartbeat → served', () {
      expect(isServedGameDayEntry(_row(), _status(), _names, _now), isTrue);
    });

    test('a different team on the same account → not served', () {
      expect(
          isServedGameDayEntry(
              _row(note: 'Kansas City Royals vs Detroit — Game Day autopilot'),
              _status(),
              _names,
              _now),
          isFalse);
    });

    test('stale heartbeat → not served (the phone leases again)', () {
      expect(
          isServedGameDayEntry(_row(),
              _status(age: const Duration(minutes: 45)), _names, _now),
          isFalse);
    });

    test('not served at all → not served', () {
      expect(
          isServedGameDayEntry(
              _row(), GameDayServerStatus.notServed, _names, _now),
          isFalse);
    });
  });
}
