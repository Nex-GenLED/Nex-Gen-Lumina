// +114 — tying a Game Day calendar row to the team the server serves.
//
// Production Game Day rows carry entryId 'primary' (the autopilot writer never
// sets the gd_<slug> id the plan assumed); the team comes from the note through
// the account's configs. A row whose team cannot be recovered is NOT served.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_providers.dart';
import 'package:nexgen_command/features/game_day/game_day_server_status.dart';
import 'package:nexgen_command/features/game_day/game_day_server_status_provider.dart';
import 'package:nexgen_command/features/game_day/served_game_day.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';

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

  group('servedGameDayEntryTestProvider — tri-state (the launch race)', () {
    late StreamController<GameDayServerStatus> status;
    late StreamController<List<GameDayAutopilotConfig>> configs;
    late ProviderContainer c;

    GameDayAutopilotConfig chiefs() => GameDayAutopilotConfig(
          teamSlug: 'kansas_city_chiefs',
          teamName: 'Kansas City Chiefs',
          espnTeamId: '12',
          sport: SportType.nfl,
          primaryColorValue: 0xFFE31837,
          secondaryColorValue: 0xFFFFB81C,
          enabled: true,
          createdAt: DateTime(2026, 9, 1),
          updatedAt: DateTime(2026, 9, 1),
        );

    setUp(() {
      status = StreamController<GameDayServerStatus>();
      configs = StreamController<List<GameDayAutopilotConfig>>();
      c = ProviderContainer(overrides: [
        gameDayServerStatusProvider.overrideWith((_) => status.stream),
        gameDayAutopilotConfigsProvider.overrideWith((_) => configs.stream),
      ]);
      // Keep both streams subscribed, as the app's widgets do.
      c.listen(gameDayServerStatusProvider, (_, __) {});
      c.listen(gameDayAutopilotConfigsProvider, (_, __) {});
    });
    tearDown(() {
      c.dispose();
      status.close();
      configs.close();
    });

    ServedVerdict verdict(CalendarEntry e) =>
        c.read(servedGameDayEntryTestProvider)(e, _now);

    Future<void> flush() => Future<void>.delayed(Duration.zero);

    test('nothing loaded → UNKNOWN for a Game Day row', () {
      expect(verdict(_row()), ServedVerdict.unknown);
    });

    test('a non-Game-Day row is decided at once, never unknown', () {
      expect(verdict(_row(tag: null, type: CalendarEntryType.user)),
          ServedVerdict.notServed);
    });

    test('status loaded NOT served → notServed without waiting on teams',
        () async {
      status.add(GameDayServerStatus.notServed);
      await flush();
      expect(verdict(_row()), ServedVerdict.notServed);
    });

    test('status served, teams still loading → UNKNOWN', () async {
      status.add(_status());
      await flush();
      expect(verdict(_row()), ServedVerdict.unknown);
    });

    test('status served, teams loaded → SERVED for the mapped team', () async {
      status.add(_status());
      configs.add([chiefs()]);
      await flush();
      expect(verdict(_row()), ServedVerdict.served);
      expect(
          verdict(_row(
              note: 'Kansas City Royals vs Detroit — Game Day autopilot')),
          ServedVerdict.notServed);
    });

    test('a status stream error is an answer (not served), not a wait',
        () async {
      status.addError(StateError('permission-denied'));
      await flush();
      expect(verdict(_row()), ServedVerdict.notServed);
    });
  });
}
