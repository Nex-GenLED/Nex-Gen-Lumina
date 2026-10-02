// +114 (plan §3.4) — the three-state "who runs this home's Game Day" surfaces:
// the banner, the team-card badge, and the day-timeline tag.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_providers.dart';
import 'package:nexgen_command/features/game_day/game_day_run_mode.dart';
import 'package:nexgen_command/features/game_day/game_day_server_status.dart';
import 'package:nexgen_command/features/game_day/game_day_server_status_provider.dart';
import 'package:nexgen_command/features/game_day/gate_status.dart';
import 'package:nexgen_command/features/game_day/gate_status_banner.dart';
import 'package:nexgen_command/features/game_day/gate_status_provider.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/day_timeline.dart';
import 'package:nexgen_command/features/schedule/widgets/timeline_row.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';
import 'package:nexgen_command/utils/time_format.dart';

import '../../helpers/text_scale_harness.dart';

final DateTime _now = DateTime(2026, 10, 10, 12, 0); // Saturday noon
const _chiefs = 'kansas_city_chiefs';
const _royals = 'kansas_city_royals';
String _name(String slug) => const {
      _chiefs: 'Kansas City Chiefs',
      _royals: 'Kansas City Royals',
    }[slug] ??
    slug;

GameDayServerStatus _status({
  bool served = true,
  List<String> teams = const [_chiefs],
  Duration age = const Duration(minutes: 3),
  Map<String, Object?>? preflight = const {
    'ok': true,
    'reasons': <String>[],
    'info': <String>[],
    'mode': 'enforce',
  },
  Map<String, Object?>? next,
  Map<String, Object?>? last,
}) =>
    GameDayServerStatus.fromUserDoc({
      'served': served,
      'teams': teams,
      'checked_at': Timestamp.fromDate(_now.subtract(age)),
      'preflight': preflight,
      'next_fire': next,
      'last_fire': last,
    });

final _nextStart = {
  'event_id': 'gd_kansas_city_chiefs_401772',
  'team_slug': _chiefs,
  'seq': 'start',
  'fire_at': Timestamp.fromDate(DateTime(2026, 10, 11, 14, 55)),
};

final _lastStart = {
  'event_id': 'gd_kansas_city_chiefs_401771',
  'seq': 'end',
  'state': 'completed',
  'completed_at': Timestamp.fromDate(DateTime(2026, 10, 4, 18, 52)),
  'latency_ms': 2400,
};

GameDayAutopilotConfig _cfg(String slug) => GameDayAutopilotConfig(
      teamSlug: slug,
      teamName: _name(slug),
      espnTeamId: slug.hashCode.toString(),
      sport: SportType.nfl,
      primaryColorValue: 0xFFE31837,
      secondaryColorValue: 0xFFFFB81C,
      enabled: true,
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );

void main() {
  group('run mode (pure)', () {
    test('served + fresh → SERVER', () {
      expect(
          gameDayRunModeFor(
              status: _status(), gate: GateStatus.unknown, now: _now),
          GameDayRunMode.server);
    });

    test('stale heartbeat → PHONE (D1)', () {
      expect(
          gameDayRunModeFor(
              status: _status(age: const Duration(minutes: 31)),
              gate: GateStatus.unknown,
              now: _now),
          GameDayRunMode.phone);
    });

    test('not allowlisted, gate blocking → PHONE (the gate changes nothing '
        'for a phone-run home)', () {
      expect(
          gameDayRunModeFor(
              status: _status(served: false, preflight: null),
              gate: const GateStatus([kGateNoFacts]),
              now: _now),
          GameDayRunMode.phone);
    });

    test('allowlisted, gate blocking → BLOCKED', () {
      expect(
          gameDayRunModeFor(
              status: _status(served: false),
              gate: const GateStatus([kGateNoFacts]),
              now: _now),
          GameDayRunMode.blocked);
    });

    test('per team (D2): the served team is SERVER, the other PHONE', () {
      final s = _status();
      expect(
          gameDayRunModeFor(
              status: s, gate: GateStatus.unknown, now: _now, teamSlug: _chiefs),
          GameDayRunMode.server);
      expect(
          gameDayRunModeFor(
              status: s, gate: GateStatus.unknown, now: _now, teamSlug: _royals),
          GameDayRunMode.phone);
    });

    test('absent status → PHONE', () {
      expect(
          gameDayRunModeFor(
              status: GameDayServerStatus.notServed,
              gate: GateStatus.unknown,
              now: _now),
          GameDayRunMode.phone);
    });
  });

  group('copy (pure)', () {
    GameDayRunCopy copy(GameDayRunMode m, GameDayServerStatus s,
            {GateStatus gate = GateStatus.unknown,
            List<String> teams = const [_chiefs],
            String tf = '12h'}) =>
        gameDayRunCopy(
          mode: m,
          status: s,
          gate: gate,
          now: _now,
          teamName: _name,
          enabledTeamSlugs: teams,
          timeFormat: tf,
        );

    test('SERVER says the app can be closed and names the next fire', () {
      final c = copy(GameDayRunMode.server,
          _status(next: _nextStart, last: _lastStart));
      expect(c.title, 'Game Day runs from our servers');
      expect(c.lines, contains('Your lights change for the game even with the '
          'app closed.'));
      expect(c.lines, contains('Next: Kansas City Chiefs, tomorrow 2:55 PM.'));
      expect(c.lines.last, 'Last change: Sun 6:52 PM, 2 s after it was due.');
    });

    test('SERVER with a team the server does not run names that team', () {
      final c =
          copy(GameDayRunMode.server, _status(), teams: [_chiefs, _royals]);
      expect(
          c.lines,
          contains('Kansas City Royals still runs from this phone: keep the '
              'app open at home for that game.'));
    });

    test('SERVER mid-game (end pending)', () {
      final c = copy(
          GameDayRunMode.server,
          _status(next: {
            ..._nextStart,
            'seq': 'end',
          }));
      expect(
          c.lines,
          contains("Kansas City Chiefs's game is on. Your lights go back to "
              'normal after the final.'));
    });

    test('24-hour preference is honoured', () {
      final c = copy(GameDayRunMode.server, _status(next: _nextStart), tf: '24h');
      expect(c.lines, contains('Next: Kansas City Chiefs, tomorrow 14:55.'));
    });

    test('PHONE names the pre-flight reason for an allowlisted home', () {
      final c = copy(
          GameDayRunMode.phone,
          _status(served: false, preflight: {
            'ok': false,
            'reasons': ['preflight_bridge_stale', 'preflight_gated'],
            'info': [],
            'mode': 'enforce',
          }));
      expect(c.title, 'Game Day runs from this phone');
      expect(c.lines.first, 'Your lights change for the game when the Lumina '
          'app is open at home.');
      expect(c.lines, hasLength(2), reason: 'gated has no phone sentence');
      expect(c.lines[1], contains('Lumina Bridge has not checked in'));
    });

    test('PHONE in observe mode shows no reasons (the server still serves)', () {
      final c = copy(
          GameDayRunMode.phone,
          _status(served: false, preflight: {
            'ok': false,
            'reasons': ['preflight_bridge_stale'],
            'info': [],
            'mode': 'observe',
          }));
      expect(c.lines, hasLength(1));
    });

    test('PHONE because the server went quiet says so', () {
      final c =
          copy(GameDayRunMode.phone, _status(age: const Duration(hours: 2)));
      expect(c.lines.join(' '), contains('have not checked in for a while'));
    });

    test('BLOCKED is the gate\'s own headline and reasons', () {
      const gate = GateStatus([kGateLadderBad]);
      final c = copy(GameDayRunMode.blocked, _status(served: false), gate: gate);
      expect(c.title, gate.headline);
      expect(c.lines, gate.reasons);
    });

    test('no copy promises a show the server will not run', () {
      for (final c in [
        copy(GameDayRunMode.phone, _status(served: false, preflight: null)),
        copy(GameDayRunMode.blocked, _status(served: false),
            gate: const GateStatus([kGateNoFacts])),
      ]) {
        expect([c.title, ...c.lines].join(' '),
            isNot(contains('will fire for upcoming games')));
      }
    });

    test('gameDayWhen: today / tomorrow / weekday', () {
      expect(gameDayWhen(DateTime(2026, 10, 10, 19, 15), _now), 'today 7:15 PM');
      expect(gameDayWhen(DateTime(2026, 10, 11, 12, 0), _now),
          'tomorrow 12:00 PM');
      expect(gameDayWhen(DateTime(2026, 10, 15, 19, 15), _now), 'Thu 7:15 PM');
    });
  });

  group('GameDayRunBanner (providers)', () {
    Widget banner(GameDayServerStatus s,
            {List<GameDayAutopilotConfig> configs = const [],
            GateStatus gate = GateStatus.unknown}) =>
        ProviderScope(
          overrides: [
            gameDayServerStatusSyncProvider.overrideWithValue(s),
            gateStatusProvider.overrideWith((_) => Stream.value(gate)),
            gameDayNowProvider.overrideWithValue(() => _now),
            enabledAutopilotConfigsProvider.overrideWithValue(configs),
            timeFormatPreferenceProvider.overrideWithValue('12h'),
          ],
          child: const MaterialApp(home: Scaffold(body: GameDayRunBanner())),
        );

    testWidgets('no teams and not served → renders nothing', (tester) async {
      await tester.pumpWidget(banner(GameDayServerStatus.notServed));
      await tester.pump();
      expect(find.text('Game Day runs from this phone'), findsNothing);
    });

    testWidgets('a team, not served → PHONE', (tester) async {
      await tester.pumpWidget(
          banner(GameDayServerStatus.notServed, configs: [_cfg(_chiefs)]));
      await tester.pump();
      expect(find.text('Game Day runs from this phone'), findsOneWidget);
    });

    testWidgets('served → SERVER with the next fire', (tester) async {
      await tester.pumpWidget(banner(_status(next: _nextStart),
          configs: [_cfg(_chiefs)]));
      await tester.pump();
      expect(find.text('Game Day runs from our servers'), findsOneWidget);
      expect(find.text('Next: Kansas City Chiefs, tomorrow 2:55 PM.'),
          findsOneWidget);
    });

    testWidgets('served but the heartbeat is stale → PHONE', (tester) async {
      await tester.pumpWidget(banner(_status(age: const Duration(hours: 1)),
          configs: [_cfg(_chiefs)]));
      await tester.pump();
      expect(find.text('Game Day runs from this phone'), findsOneWidget);
    });

    testWidgets('allowlisted and gated → BLOCKED', (tester) async {
      await tester.pumpWidget(banner(_status(served: false),
          configs: [_cfg(_chiefs)], gate: const GateStatus([kGateNoFacts])));
      await tester.pump();
      expect(find.text('Game Day is on — not firing yet'), findsOneWidget);
    });
  });

  group('accessibility — 1.0 / 1.75 / 2.0 with Bold Text', () {
    final views = <String, Widget>{
      'server (longest copy)': GameDayRunBannerView(
        mode: GameDayRunMode.server,
        copy: gameDayRunCopy(
          mode: GameDayRunMode.server,
          status: _status(next: _nextStart, last: _lastStart),
          gate: GateStatus.unknown,
          now: _now,
          teamName: _name,
          enabledTeamSlugs: const [_chiefs, _royals],
        ),
      ),
      'phone with two reasons': GameDayRunBannerView(
        mode: GameDayRunMode.phone,
        copy: gameDayRunCopy(
          mode: GameDayRunMode.phone,
          status: _status(served: false, preflight: {
            'ok': false,
            'reasons': ['preflight_no_bridge', 'preflight_ladder_bad'],
            'info': [],
            'mode': 'enforce',
          }),
          gate: GateStatus.unknown,
          now: _now,
          teamName: _name,
        ),
      ),
      'blocked': GameDayRunBannerView(
        mode: GameDayRunMode.blocked,
        copy: gameDayRunCopy(
          mode: GameDayRunMode.blocked,
          status: _status(served: false),
          gate: const GateStatus([kGateNoFacts, kGateLadderBad]),
          now: _now,
          teamName: _name,
        ),
      ),
    };
    for (final e in views.entries) {
      testWidgets('banner: ${e.key}', (tester) async {
        await expectNoTextScaleDefectsAcrossMatrix(tester, e.value);
      });
    }

    for (final mode in GameDayRunMode.values) {
      testWidgets('team-card header with the ${mode.name} badge', (tester) async {
        await expectNoTextScaleDefectsAcrossMatrix(
          tester,
          SizedBox(
            width: 358, // a team card inside the screen's 16 pt gutters
            child: Row(
              children: [
                const Expanded(
                  child: Text('🏈 Kansas City Chiefs',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                GameDayStatusBadge(
                  isLive: false,
                  isFinal: false,
                  liveText: '0 - 0',
                  finalText: 'Final 0-0',
                  mode: mode,
                ),
                const SizedBox(width: 4),
                const Icon(Icons.delete_outline, size: 20),
              ],
            ),
          ),
        );
      });
    }
  });

  group('day-timeline tag', () {
    final gdEntry = CalendarEntry(
      dateKey: '2026-10-11',
      patternName: 'Team Night',
      color: const Color(0xFFE31837),
      onTime: '14:55',
      offTime: '19:55',
      type: CalendarEntryType.autopilot,
      sourceTag: CalendarEntrySourceTag.gameDay,
      note: 'Kansas City Chiefs vs Las Vegas Raiders — Game Day autopilot',
    );
    final row = TimelineEntry(
      id: 'gd',
      source: TimelineSource.gameDay,
      dated: gdEntry,
      startsAt: DateTime(2026, 10, 11, 14, 55),
      endsAt: DateTime(2026, 10, 11, 19, 55),
      endMode: CalendarEntryEndMode.fixedTime,
      label: 'Team Night',
    );

    testWidgets('full row: the tag rides on the time line; the chip and title '
        'row are unchanged', (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: TimelineRowTile(entry: row, runnerTag: 'server'))));
      expect(find.text('2:55 PM → 7:55 PM · server'), findsOneWidget);
      expect(find.text('⚡ Game Day'), findsOneWidget);
    });

    testWidgets('compact row: the tag rides on the time line', (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: TimelineRowTile(
                  entry: row, runnerTag: 'phone', compact: true))));
      expect(find.text('2:55 PM → 7:55 PM · phone'), findsOneWidget);
    });

    testWidgets('no tag → unchanged', (tester) async {
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: TimelineRowTile(entry: row))));
      expect(find.text('⚡ Game Day'), findsOneWidget);
      expect(find.text('2:55 PM → 7:55 PM'), findsOneWidget);
    });

    for (final compact in [false, true]) {
      testWidgets('tagged row survives the text-scale matrix '
          '(compact: $compact)', (tester) async {
        await expectNoTextScaleDefectsAcrossMatrix(
          tester,
          SizedBox(
            width: 358,
            child: TimelineRowTile(
                entry: row, runnerTag: 'setup needed', compact: compact),
          ),
        );
      });
    }
  });
}
