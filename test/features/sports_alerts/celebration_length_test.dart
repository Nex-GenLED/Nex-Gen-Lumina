// #169 — celebration length (owner values 2026-10-04): Short x0.5, Medium x1
// (today's lengths; absent = Medium), Long x2, every celebration clamped to
// 5-60 s. An NFL extra point plays NO celebration; a two-point conversion plays
// its +2 stages at Short length.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/sports_alerts/data/team_colors.dart';
import 'package:nexgen_command/features/sports_alerts/models/game_state.dart';
import 'package:nexgen_command/features/sports_alerts/models/score_alert_config.dart';
import 'package:nexgen_command/features/sports_alerts/models/score_alert_event.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';
import 'package:nexgen_command/features/sports_alerts/services/alert_trigger_service.dart';
import 'package:nexgen_command/features/sports_alerts/services/celebration_length.dart';
import 'package:nexgen_command/features/sports_alerts/services/espn_api_service.dart';
import 'package:nexgen_command/features/sports_alerts/services/score_monitor_service.dart';

const _short = CelebrationLength.short;
const _medium = CelebrationLength.medium;
const _long = CelebrationLength.long;

/// The owner-approved table: seconds per stage at Short / Medium / Long.
const _table = <AlertEventType, Map<CelebrationLength, List<int>>>{
  AlertEventType.touchdown: {
    _short: [1, 3, 4], _medium: [2, 5, 8], _long: [4, 10, 16],
  },
  AlertEventType.goal: {
    _short: [1, 3, 4], _medium: [2, 5, 8], _long: [4, 10, 16],
  },
  AlertEventType.soccerGoal: {
    _short: [3, 2, 3, 2], _medium: [6, 4, 6, 4], _long: [12, 8, 12, 8],
  },
  AlertEventType.fieldGoal: {_short: [5], _medium: [8], _long: [16]},
  AlertEventType.safety: {_short: [5], _medium: [6], _long: [12]},
  AlertEventType.run: {_short: [5], _medium: [6], _long: [12]},
  AlertEventType.quarterEndWinning: {
    _short: [5], _medium: [10], _long: [20],
  },
  AlertEventType.clutchBasket: {_short: [5], _medium: [5], _long: [10]},
  AlertEventType.win: {
    _short: [3, 5, 7], _medium: [5, 10, 15], _long: [10, 20, 30],
  },
  // Always Short, whatever the team chose.
  AlertEventType.twoPointConversion: {_short: [5], _medium: [5], _long: [5]},
  AlertEventType.turnover: {_short: [], _medium: [], _long: []},
};

final _team = kTeamColors['nfl_chiefs']!;

void main() {
  group('seconds per event and preset', () {
    test('the table covers every event type', () {
      expect(_table.keys.toSet(), AlertEventType.values.toSet());
    });

    for (final entry in _table.entries) {
      for (final p in entry.value.entries) {
        test('${entry.key.name} at ${p.key.label}: ${p.value}', () {
          final steps = AlertTriggerService.buildAnimationStepsAt(
              entry.key, _team, null,
              length: p.key);
          expect([for (final s in steps) s.hold.inSeconds], p.value);
          expect(
              AlertTriggerService.animationDuration(entry.key, length: p.key)
                  .inSeconds,
              p.value.fold<int>(0, (a, b) => a + b),
              reason: 'the override window equals what plays');
        });
      }
    }

    test('Medium is exactly today: buildAnimationSteps is unchanged', () {
      for (final t in AlertEventType.values) {
        final legacy = AlertTriggerService.buildAnimationSteps(t, _team);
        expect([for (final s in legacy) s.hold.inSeconds], _table[t]![_medium],
            reason: t.name);
      }
    });

    test('the helper names a touchdown at each setting', () {
      expect(celebrationLengthHelper(),
          'A touchdown plays 8 seconds on Short, 15 on Medium and 30 on Long. '
          'Every celebration ends on its own.');
    });
  });

  group('every celebration is held between 5 and 60 seconds', () {
    for (final m in [0.0, 0.01, 0.2, 3.0, 10.0, 1000.0]) {
      test('multiplier $m', () {
        for (final t in AlertEventType.values) {
          final legacy = AlertTriggerService.buildAnimationSteps(t, _team);
          if (legacy.isEmpty) continue;
          final holds = scaleCelebrationHolds(
              [for (final s in legacy) s.hold], _medium,
              multiplier: m);
          final total = totalOf(holds);
          expect(total, greaterThanOrEqualTo(kCelebrationMinLength),
              reason: '${t.name} x$m');
          expect(total, lessThanOrEqualTo(kCelebrationMaxLength),
              reason: '${t.name} x$m');
          for (final h in holds) {
            expect(h.inSeconds, greaterThanOrEqualTo(1));
          }
        }
      });
    }

    test('the limits are 5 s and 60 s', () {
      expect(kCelebrationMinLength, const Duration(seconds: 5));
      expect(kCelebrationMaxLength, const Duration(seconds: 60));
    });
  });

  group('absent = Medium', () {
    test('an unset, unknown or malformed value reads as Medium', () {
      for (final v in [null, '', 'MEDIUM', 'extra-long', 2, true]) {
        expect(CelebrationLength.fromWire(v), _medium, reason: '$v');
      }
      expect(CelebrationLength.fromWire('short'), _short);
      expect(CelebrationLength.fromWire('long'), _long);
    });

    test('a team doc without the field is Medium, and Medium is not written',
        () {
      final base = {
        'team_slug': 'nfl_chiefs',
        'team_name': 'Kansas City Chiefs',
        'espn_team_id': '12',
        'sport': 'nfl',
        'primary_color': 0xFFE31837,
        'secondary_color': 0xFFFFB81C,
      };
      final c = GameDayAutopilotConfig.fromFirestore(base);
      expect(c.celebrationLength, _medium);
      expect(c.toFirestore().containsKey('celebration_length'), isFalse,
          reason: 'an untouched config stays byte-identical');
      final long = GameDayAutopilotConfig.fromFirestore(
          {...base, 'celebration_length': 'long'});
      expect(long.celebrationLength, _long);
      expect(long.toFirestore()['celebration_length'], 'long');
    });
  });

  group('football scoring', () {
    Future<List<ScoreAlertEvent>> run(List<(int, int)> scores) async {
      final espn = _ScriptedEspn([
        for (final (us, them) in scores)
          [
            GameState(
              gameId: 'g1',
              homeTeamId: '12', // the Chiefs' ESPN id: they are HOME
              awayTeamId: '99',
              homeTeam: 'Kansas City Chiefs',
              awayTeam: 'Opponent',
              homeScore: us,
              awayScore: them,
              status: GameStatus.inProgress,
              period: '2',
              clock: '5:00',
              lastUpdated: DateTime.utc(2026, 10, 4),
            ),
          ],
      ]);
      final monitor = ScoreMonitorService(espnApi: espn);
      final events = <ScoreAlertEvent>[];
      final sub = monitor.alertStream.listen(events.add);
      for (var i = 0; i < scores.length; i++) {
        await monitor.checkScores([
          const ScoreAlertConfig(
            id: 'nfl_chiefs',
            teamSlug: 'nfl_chiefs',
            sport: SportType.nfl,
            sensitivity: AlertSensitivity.allEvents,
          ),
        ]);
      }
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      monitor.dispose();
      return events;
    }

    List<AlertEventType> types(List<ScoreAlertEvent> e) =>
        [for (final x in e) x.eventType];

    test('touchdown then extra point → ONE celebration (the PAT plays none)',
        () async {
      final e = await run([(0, 0), (6, 0), (7, 0)]);
      expect(types(e), [AlertEventType.touchdown]);
    });

    test('touchdown then two-point conversion → the conversion celebrates, '
        'at Short length', () async {
      final e = await run([(0, 0), (6, 0), (8, 0)]);
      expect(types(e),
          [AlertEventType.touchdown, AlertEventType.twoPointConversion]);
      expect(
          AlertTriggerService.animationDuration(
              AlertEventType.twoPointConversion,
              length: _long),
          const Duration(seconds: 5),
          reason: 'always Short, whatever the team chose');
    });

    test('a +2 with no touchdown before it is a safety', () async {
      final e = await run([(0, 0), (2, 0)]);
      expect(types(e), [AlertEventType.safety]);
    });

    test('a +1 on its own plays nothing', () async {
      final e = await run([(0, 0), (1, 0)]);
      expect(e, isEmpty);
    });

    test('a +2 after the extra point is a safety, not a conversion', () async {
      final e = await run([(0, 0), (6, 0), (7, 0), (9, 0)]);
      expect(types(e), [AlertEventType.touchdown, AlertEventType.safety]);
    });
  });
}

/// Hands out one scoreboard per call, in order.
class _ScriptedEspn extends EspnApiService {
  _ScriptedEspn(this.script);
  final List<List<GameState>> script;
  int calls = 0;

  @override
  Future<List<GameState>> fetchLiveGames(SportType sport) async {
    final i = calls < script.length ? calls : script.length - 1;
    calls++;
    return script[i];
  }

  @override
  void dispose() {}
}
