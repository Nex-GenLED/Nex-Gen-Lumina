// +114 (plan §3.2, D3) — engine OBSERVE mode for server-run teams.
//
// Driven through the REAL GameDayAutopilotService with fake ESPN readers (same
// harness shape as game_day_contention_test.dart). A served team is tracked
// through the whole phase machine but the phone never applies its design,
// never resumes the normal schedule for it, and never hands the house to it.
// Unserved teams are unchanged. Celebrations still come from the phone (D3)
// until the server runs them (step G).

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_service.dart';
import 'package:nexgen_command/features/sports_alerts/models/game_state.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';
import 'package:nexgen_command/features/sports_alerts/services/espn_api_service.dart';
import 'package:nexgen_command/features/sports_alerts/services/foreground_celebration_providers.dart';
import 'package:nexgen_command/features/sports_alerts/services/game_schedule_service.dart';

class _FakeSchedule extends GameScheduleService {
  final Set<String> soon = {};
  @override
  Future<DateTime?> fetchNextGameDate(String espnTeamId, SportType sport) async =>
      null;
  @override
  Future<bool> hasGameSoon(String espnTeamId, SportType sport,
          {int minutes = 30}) async =>
      soon.contains(espnTeamId);
}

class _FakeEspn extends EspnApiService {
  final Map<String, GameState> games = {};
  @override
  Future<GameState?> fetchTeamGame(SportType sport, String espnTeamId) async =>
      games[espnTeamId];
}

GameState _game(String teamId, GameStatus status) => GameState(
      gameId: 'g$teamId',
      homeTeam: 'Home',
      awayTeam: 'Away',
      homeTeamId: teamId,
      awayTeamId: 'opp',
      status: status,
      lastUpdated: DateTime(2026, 10, 11, 12),
    );

GameDayAutopilotConfig _cfg(String slug, String espnId, SportType sport) =>
    GameDayAutopilotConfig(
      teamSlug: slug,
      teamName: slug,
      espnTeamId: espnId,
      sport: sport,
      primaryColorValue: 0xFFE31837,
      secondaryColorValue: 0xFFFFB81C,
      enabled: true,
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );

class _Harness {
  final schedule = _FakeSchedule();
  final espn = _FakeEspn();
  late final GameDayAutopilotService svc;
  final List<Map<String, dynamic>> applied = [];
  int resumes = 0;
  Set<String> served = {};
  List<String> priority = const [];
  bool throwOnServed = false;

  _Harness() {
    svc = GameDayAutopilotService(espnApi: espn, scheduleService: schedule);
    svc.onGetTeamPriority = () => priority;
    svc.onApplyPayload = (p) async => applied.add(p);
    svc.onResumeNormalSchedule = () => resumes++;
    svc.onGetServedTeams = () {
      if (throwOnServed) throw StateError('status unreadable');
      return served;
    };
  }

  AutopilotSessionPhase? phase(String slug) => svc.getSession(slug)?.phase;
}

const _chiefsId = '12';
const _royalsId = '7';
final _chiefs = _cfg('nfl_chiefs', _chiefsId, SportType.nfl);
final _royals = _cfg('mlb_royals', _royalsId, SportType.mlb);

/// Pre-game → live → final → countdown elapsed, for one team.
Future<void> _wholeGame(_Harness h, GameDayAutopilotConfig c, String espnId,
    List<GameDayAutopilotConfig> configs) async {
  h.schedule.soon.add(espnId);
  await h.svc.evaluateConfigs(configs);
  expect(h.phase(c.teamSlug), AutopilotSessionPhase.preGame);
  h.espn.games[espnId] = _game(espnId, GameStatus.inProgress);
  await h.svc.evaluateConfigs(configs);
  expect(h.phase(c.teamSlug), AutopilotSessionPhase.liveGame);
  h.espn.games[espnId] = _game(espnId, GameStatus.final_);
  await h.svc.evaluateConfigs(configs);
  expect(h.phase(c.teamSlug), AutopilotSessionPhase.postGame);
  h.svc.debugSetCountdownEnd(c.teamSlug, DateTime(2020));
  await h.svc.evaluateConfigs(configs);
  expect(h.phase(c.teamSlug), AutopilotSessionPhase.completed);
}

void main() {
  test('a SERVED team through a whole game: tracked every phase, ZERO applies, '
      'ZERO resumes', () async {
    final h = _Harness()..served = {'nfl_chiefs'};
    await _wholeGame(h, _chiefs, _chiefsId, [_chiefs]);
    expect(h.applied, isEmpty);
    expect(h.resumes, 0,
        reason: 'the server restores the ladder at the final; the phone '
            'turning the house off on top of it is the double-end');
  });

  test('the same team UNSERVED: one apply at pre-game, one resume at the end '
      '(112 behaviour, unchanged)', () async {
    final h = _Harness();
    await _wholeGame(h, _chiefs, _chiefsId, [_chiefs]);
    expect(h.applied, hasLength(1));
    expect(h.resumes, 1);
  });

  test('a served session still OWNS the house — priority and celebrations see '
      'it (D3: phone celebrations until step G)', () async {
    final h = _Harness()..served = {'nfl_chiefs'};
    h.schedule.soon.add(_chiefsId);
    await h.svc.evaluateConfigs([_chiefs]);
    h.espn.games[_chiefsId] = _game(_chiefsId, GameStatus.inProgress);
    await h.svc.evaluateConfigs([_chiefs]);

    final s = h.svc.getSession('nfl_chiefs')!;
    expect(s.ownsLights, isTrue);
    final teams = computeLiveCelebrationTeams(
      sessions: h.svc.activeSessions,
      ephemeralSessions: const [],
      configs: [_chiefs],
    );
    expect(teams.map((t) => t.teamSlug), ['nfl_chiefs']);
  });

  group('mixed served + unserved', () {
    test('served #1 owns (observed), unserved #2 deferred; #1 ends → the '
        'unserved survivor is applied by the phone, no resume', () async {
      final h = _Harness()
        ..served = {'nfl_chiefs'}
        ..priority = ['nfl_chiefs', 'mlb_royals'];
      final configs = [_royals, _chiefs];
      h.schedule.soon.addAll([_chiefsId, _royalsId]);
      await h.svc.evaluateConfigs(configs);
      expect(h.svc.getSession('nfl_chiefs')!.ownsLights, isTrue);
      expect(h.svc.getSession('mlb_royals')!.deferred, isTrue);
      expect(h.applied, isEmpty, reason: 'owner is server-run; #2 deferred');

      h.espn.games[_chiefsId] = _game(_chiefsId, GameStatus.inProgress);
      h.espn.games[_royalsId] = _game(_royalsId, GameStatus.inProgress);
      await h.svc.evaluateConfigs(configs);
      h.espn.games[_chiefsId] = _game(_chiefsId, GameStatus.final_);
      await h.svc.evaluateConfigs(configs);
      h.svc.debugSetCountdownEnd('nfl_chiefs', DateTime(2020));
      await h.svc.evaluateConfigs(configs);

      expect(h.svc.getSession('mlb_royals')!.ownsLights, isTrue);
      expect(h.applied, hasLength(1),
          reason: 'the unserved Royals take the house from the phone');
      expect(h.resumes, 0);
    });

    test('unserved #1 owns, served #2 deferred; #1 ends → hand-off to the '
        'server-run team applies NOTHING and does not resume', () async {
      final h = _Harness()
        ..served = {'nfl_chiefs'}
        ..priority = ['mlb_royals', 'nfl_chiefs'];
      final configs = [_royals, _chiefs];
      h.schedule.soon.addAll([_chiefsId, _royalsId]);
      await h.svc.evaluateConfigs(configs);
      expect(h.svc.getSession('mlb_royals')!.ownsLights, isTrue);
      expect(h.applied, hasLength(1), reason: 'Royals applied by the phone');

      h.espn.games[_chiefsId] = _game(_chiefsId, GameStatus.inProgress);
      h.espn.games[_royalsId] = _game(_royalsId, GameStatus.inProgress);
      await h.svc.evaluateConfigs(configs);
      h.espn.games[_royalsId] = _game(_royalsId, GameStatus.final_);
      await h.svc.evaluateConfigs(configs);
      h.svc.debugSetCountdownEnd('mlb_royals', DateTime(2020));
      await h.svc.evaluateConfigs(configs);

      expect(h.svc.getSession('nfl_chiefs')!.ownsLights, isTrue);
      expect(h.applied, hasLength(1), reason: 'no apply for the server-run '
          'survivor');
      expect(h.resumes, 0, reason: 'a team is still playing');
    });
  });

  group('degrading to the phone (D1)', () {
    test('the heartbeat goes stale mid-game → the phone owns the END', () async {
      final h = _Harness()..served = {'nfl_chiefs'};
      h.schedule.soon.add(_chiefsId);
      await h.svc.evaluateConfigs([_chiefs]);
      expect(h.applied, isEmpty);

      h.espn.games[_chiefsId] = _game(_chiefsId, GameStatus.inProgress);
      await h.svc.evaluateConfigs([_chiefs]);
      h.served = {}; // planner stopped writing; the reader ages it out
      h.espn.games[_chiefsId] = _game(_chiefsId, GameStatus.final_);
      await h.svc.evaluateConfigs([_chiefs]);
      h.svc.debugSetCountdownEnd('nfl_chiefs', DateTime(2020));
      await h.svc.evaluateConfigs([_chiefs]);

      expect(h.resumes, 1,
          reason: 'with no server to end it, the phone must — never dark, '
              'never stuck');
    });

    test('a throwing status read is the phone path', () async {
      final h = _Harness()
        ..served = {'nfl_chiefs'}
        ..throwOnServed = true;
      await _wholeGame(h, _chiefs, _chiefsId, [_chiefs]);
      expect(h.applied, hasLength(1));
      expect(h.resumes, 1);
    });

    test('unwired (null callback) is the phone path', () async {
      final h = _Harness();
      h.svc.onGetServedTeams = null;
      await _wholeGame(h, _chiefs, _chiefsId, [_chiefs]);
      expect(h.applied, hasLength(1));
      expect(h.resumes, 1);
    });
  });

  test('cancelling a served team mid-game does not turn the house off',
      () async {
    final h = _Harness()..served = {'nfl_chiefs'};
    h.schedule.soon.add(_chiefsId);
    await h.svc.evaluateConfigs([_chiefs]);
    await h.svc.cancelSession('nfl_chiefs');
    expect(h.resumes, 0);
    expect(h.applied, isEmpty);
  });

  test('forceActivate ("Light it up now") is the user\'s explicit choice and '
      'still applies for a served team', () async {
    final h = _Harness()..served = {'nfl_chiefs'};
    final design = h.svc.selectDesign(_chiefs);
    await h.svc.forceActivate(_chiefs, design);
    expect(h.applied, hasLength(1));
  });
}
