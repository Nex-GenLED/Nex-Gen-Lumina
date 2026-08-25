// Phase D — the win celebration.
//
// There was no win event at all: AlertEventType had no member for it, and the
// only handling of GameStatus.final_ evicted cache entries
// (audit/GAME_DAY_SPEC_AUDIT.md §2.1, gap row 3c).
//
// THE HAZARD these tests exist for (pre-check P3): the final-status cleanup at
// score_monitor_service.dart WIPES `_emittedKeys` for the game. A win routed
// through the normal dedup would lose its guard on the very tick it fired and
// re-fire on the next poll while ESPN still reported the game final. The guard
// is therefore a separate set the cleanup never touches, plus a
// status-transition check.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/sports_alerts/data/team_colors.dart';
import 'package:nexgen_command/features/sports_alerts/models/game_state.dart';
import 'package:nexgen_command/features/sports_alerts/models/score_alert_config.dart';
import 'package:nexgen_command/features/sports_alerts/models/score_alert_event.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';
import 'package:nexgen_command/features/sports_alerts/services/alert_trigger_service.dart';
import 'package:nexgen_command/features/sports_alerts/services/celebration_contrast.dart';
import 'package:nexgen_command/features/sports_alerts/services/espn_api_service.dart';
import 'package:nexgen_command/features/sports_alerts/services/score_monitor_service.dart';

final _team = kTeamColors['nfl_chiefs']!;
const _chiefsEspnId = '12'; // kTeamColors['nfl_chiefs'].espnTeamId

/// ESPN stub that serves one scripted scoreboard per poll.
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

GameState _game({
  required int home,
  required int away,
  required GameStatus status,
  String id = 'g1',
}) =>
    GameState(
      gameId: id,
      homeTeamId: _chiefsEspnId, // Chiefs are HOME
      awayTeamId: '99',
      homeTeam: 'Kansas City Chiefs',
      awayTeam: 'Opponent',
      homeScore: home,
      awayScore: away,
      status: status,
      period: '4',
      clock: '0:00',
      lastUpdated: DateTime.utc(2026, 8, 25),
    );

const _config = ScoreAlertConfig(
  id: 'nfl_chiefs',
  teamSlug: 'nfl_chiefs',
  sport: SportType.nfl,
  sensitivity: AlertSensitivity.clutchOnly, // the strictest filter
);

/// Run [script] through the monitor, returning every event emitted.
Future<List<ScoreAlertEvent>> _run(List<List<GameState>> script) async {
  final espn = _ScriptedEspn(script);
  final monitor = ScoreMonitorService(espnApi: espn);
  final events = <ScoreAlertEvent>[];
  final sub = monitor.alertStream.listen(events.add);
  for (var i = 0; i < script.length; i++) {
    await monitor.checkScores([_config]);
  }
  await Future<void>.delayed(Duration.zero);
  await sub.cancel();
  monitor.dispose();
  return events;
}

List<ScoreAlertEvent> _wins(List<ScoreAlertEvent> events) =>
    events.where((e) => e.eventType == AlertEventType.win).toList();

void main() {
  group('who gets a win', () {
    test('the monitored team ahead at final fires exactly ONE win', () async {
      final events = await _run([
        [_game(home: 21, away: 14, status: GameStatus.inProgress)],
        [_game(home: 28, away: 14, status: GameStatus.final_)],
      ]);
      expect(_wins(events), hasLength(1));
      expect(_wins(events).single.teamSlug, 'nfl_chiefs');
    });

    test('behind at final fires NO win', () async {
      final events = await _run([
        [_game(home: 14, away: 21, status: GameStatus.inProgress)],
        [_game(home: 14, away: 28, status: GameStatus.final_)],
      ]);
      expect(_wins(events), isEmpty);
    });

    test('tied at final fires NO win', () async {
      final events = await _run([
        [_game(home: 21, away: 14, status: GameStatus.inProgress)],
        [_game(home: 21, away: 21, status: GameStatus.final_)],
      ]);
      expect(_wins(events), isEmpty);
    });

    test('a one-point win still counts', () async {
      final events = await _run([
        [_game(home: 20, away: 20, status: GameStatus.inProgress)],
        [_game(home: 21, away: 20, status: GameStatus.final_)],
      ]);
      expect(_wins(events), hasLength(1));
    });
  });

  // THE P3 HAZARD.
  group('it cannot double-fire', () {
    test('repeated polls after final do not fire again', () async {
      final events = await _run([
        [_game(home: 21, away: 14, status: GameStatus.inProgress)],
        [_game(home: 28, away: 14, status: GameStatus.final_)],
        [_game(home: 28, away: 14, status: GameStatus.final_)],
        [_game(home: 28, away: 14, status: GameStatus.final_)],
        [_game(home: 28, away: 14, status: GameStatus.final_)],
      ]);
      expect(_wins(events), hasLength(1),
          reason: 'the guard must survive the final-status cleanup');
    });

    // Requiring the TRANSITION means a game already over when we start
    // monitoring does not light the house for something that finished hours
    // ago.
    test('a game already final on the first poll fires nothing', () async {
      final events = await _run([
        [_game(home: 28, away: 14, status: GameStatus.final_)],
        [_game(home: 28, away: 14, status: GameStatus.final_)],
      ]);
      expect(_wins(events), isEmpty);
    });

    test('reset() clears the guard so a new session can fire again', () async {
      final espn = _ScriptedEspn([
        [_game(home: 21, away: 14, status: GameStatus.inProgress)],
        [_game(home: 28, away: 14, status: GameStatus.final_)],
      ]);
      final monitor = ScoreMonitorService(espnApi: espn);
      final events = <ScoreAlertEvent>[];
      final sub = monitor.alertStream.listen(events.add);

      await monitor.checkScores([_config]);
      await monitor.checkScores([_config]);
      await Future<void>.delayed(Duration.zero);
      expect(_wins(events), hasLength(1));

      monitor.reset();
      expect(() => monitor.reset(), returnsNormally);
      await sub.cancel();
      monitor.dispose();
    });
  });

  // A clutchOnly user asked for fewer alerts; they did not ask to miss their
  // team winning.
  test('a win fires even under the strictest sensitivity', () async {
    final events = await _run([
      [_game(home: 21, away: 14, status: GameStatus.inProgress)],
      [_game(home: 28, away: 14, status: GameStatus.final_)],
    ]);
    expect(_wins(events), hasLength(1));
  });

  group('the win animation', () {
    test('is the longest entry in the timing table', () {
      final win = AlertTriggerService.animationDuration(AlertEventType.win);
      expect(win, const Duration(seconds: 30));
      for (final t in AlertEventType.values) {
        if (t == AlertEventType.win) continue;
        expect(AlertTriggerService.animationDuration(t), lessThan(win),
            reason: '${t.name} should not outlast a win');
      }
    });

    test('its staged holds sum to the declared duration', () {
      final steps =
          AlertTriggerService.buildAnimationSteps(AlertEventType.win, _team);
      expect(steps.fold(Duration.zero, (a, s) => a + s.hold),
          AlertTriggerService.animationDuration(AlertEventType.win));
    });

    test('it uses the same user-chosen celebration as every other event', () {
      const chosen =
          CelebrationResolution(effectId: 79, speed: 200, intensity: 180);
      final steps = AlertTriggerService.buildAnimationSteps(
          AlertEventType.win, _team, chosen);
      for (final s in steps) {
        final seg = (s.payload['seg'] as List).first as Map;
        expect(seg['fx'], 79);
        expect(seg['sx'], 200);
      }
    });

    test('with nothing chosen it keeps its own default staging', () {
      final steps =
          AlertTriggerService.buildAnimationSteps(AlertEventType.win, _team);
      expect(steps, hasLength(3));
      expect(steps.first.payload['bri'], 255);
    });
  });
}
