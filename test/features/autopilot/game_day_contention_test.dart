// test/features/autopilot/game_day_contention_test.dart
//
// The behaviour a user actually sees when two of their teams play at once,
// driven through the REAL GameDayAutopilotService with fake ESPN inputs.
//
// The four scenarios below are the ones the 2026-09-21 audit measured as
// broken, expressed as assertions:
//   1. two teams overlapping        → only the #1 team's design reaches the wire
//   2. reverse the hierarchy        → the other team wins (proves priority, not slug order)
//   3. the LOWER team's game ends   → the house does NOT go dark
//   4. the WINNER's game ends       → hand-off; the survivor's design is applied
//
// Scenario 3 is the dark-mid-game bug. Before the fix, the first game to
// finish called onResumeNormalSchedule → togglePower(false) and the house
// went out part-way through the other game.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_service.dart';
import 'package:nexgen_command/features/sports_alerts/models/game_state.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';
import 'package:nexgen_command/features/sports_alerts/services/espn_api_service.dart';
import 'package:nexgen_command/features/sports_alerts/services/game_schedule_service.dart';

// ── Fakes: the only things stubbed are the two ESPN readers ───────────────

class _FakeSchedule extends GameScheduleService {
  /// slug-independent: keyed by espnTeamId, like the real calls.
  final Map<String, DateTime> nextGame = {};
  final Set<String> soon = {};

  @override
  Future<DateTime?> fetchNextGameDate(String espnTeamId, SportType sport) async =>
      nextGame[espnTeamId];

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

GameState _game(String id, String teamId, GameStatus status) => GameState(
      gameId: id,
      homeTeam: 'Home',
      awayTeam: 'Away',
      homeTeamId: teamId,
      awayTeamId: 'opp',
      status: status,
      lastUpdated: DateTime(2026, 9, 22, 12),
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

/// Harness: real service, fake ESPN, recording apply + resume.
class _Harness {
  late final _FakeSchedule schedule;
  late final _FakeEspn espn;
  late final GameDayAutopilotService svc;

  /// Effect ids applied, in order — a proxy for "what is on the wire".
  final List<int> applied = [];
  final List<String> appliedNames = [];
  int resumeCalls = 0;
  List<String> priority = const [];

  _Harness() {
    schedule = _FakeSchedule();
    espn = _FakeEspn();
    svc = GameDayAutopilotService(espnApi: espn, scheduleService: schedule);
    svc.onGetTeamPriority = () => priority;
    svc.onApplyPayload = (payload) async {
      final seg = (payload['seg'] as List).cast<Map<String, dynamic>>();
      applied.add(seg.isEmpty ? -1 : seg.first['fx'] as int);
    };
    svc.onResumeNormalSchedule = () => resumeCalls++;
  }

  /// Record which TEAM each apply belonged to, by tagging through the design
  /// name the service logs. Simpler: infer from the session that is not
  /// deferred at apply time.
  String? get owner => svc.activeSessions.values
      .where((s) => s.ownsLights)
      .map((s) => s.teamSlug)
      .firstOrNull;

  Set<String> get deferredTeams => svc.activeSessions.values
      .where((s) => s.deferred)
      .map((s) => s.teamSlug)
      .toSet();
}

void main() {
  const chiefsId = '12';
  const royalsId = '7';
  final chiefs = _cfg('nfl_chiefs', chiefsId, SportType.nfl);
  final royals = _cfg('mlb_royals', royalsId, SportType.mlb);

  // Configs are handed to evaluateConfigs in Firestore document-id order,
  // which is lexicographic: mlb_royals BEFORE nfl_chiefs. That ordering is
  // what used to decide the winner, so every test below feeds it deliberately.
  final docIdOrder = [royals, chiefs];

  group('two teams overlapping', () {
    test('only the #1 team owns the lights; the other is tracked, not lit',
        () async {
      final h = _Harness()..priority = ['nfl_chiefs', 'mlb_royals'];
      h.schedule.soon.addAll([chiefsId, royalsId]);

      await h.svc.evaluateConfigs(docIdOrder);

      expect(h.owner, 'nfl_chiefs',
          reason: 'Royals sorts first by document id and used to win on that '
              'alone; the hierarchy must override it.');
      expect(h.deferredTeams, {'mlb_royals'});
      // Exactly one design reached the wire, not two.
      expect(h.applied, hasLength(1));
    });

    test('REVERSING the hierarchy reverses the winner, same game times — the '
        'proof that priority is doing the work, not slug order', () async {
      final h = _Harness()..priority = ['mlb_royals', 'nfl_chiefs'];
      h.schedule.soon.addAll([chiefsId, royalsId]);

      await h.svc.evaluateConfigs(docIdOrder);

      expect(h.owner, 'mlb_royals');
      expect(h.deferredTeams, {'nfl_chiefs'});
      expect(h.applied, hasLength(1));
    });

    test('the lower team activating FIRST is preempted, not left in place',
        () async {
      final h = _Harness()..priority = ['nfl_chiefs', 'mlb_royals'];
      // Royals' window opens on an earlier tick.
      h.schedule.soon.add(royalsId);
      await h.svc.evaluateConfigs(docIdOrder);
      expect(h.owner, 'mlb_royals');

      // Chiefs' window opens on a later tick.
      h.schedule.soon.add(chiefsId);
      await h.svc.evaluateConfigs(docIdOrder);

      expect(h.owner, 'nfl_chiefs');
      expect(h.deferredTeams, {'mlb_royals'});
      expect(h.resumeCalls, 0, reason: 'preemption is not a reason to go dark');
    });

    test('with no hierarchy set, first-come-first-served still holds and the '
        'second team defers rather than stomping', () async {
      final h = _Harness()..priority = const [];
      h.schedule.soon.add(royalsId);
      await h.svc.evaluateConfigs(docIdOrder);
      h.schedule.soon.add(chiefsId);
      await h.svc.evaluateConfigs(docIdOrder);

      expect(h.owner, 'mlb_royals');
      expect(h.deferredTeams, {'nfl_chiefs'});
    });
  });

  group('the dark-mid-game bug', () {
    test('the LOWER-priority game ending does NOT turn the house off, and '
        'does not disturb the winner', () async {
      final h = _Harness()..priority = ['nfl_chiefs', 'mlb_royals'];
      h.schedule.soon.addAll([chiefsId, royalsId]);
      await h.svc.evaluateConfigs(docIdOrder);
      expect(h.owner, 'nfl_chiefs');
      final appliedBefore = h.applied.length;

      // Both games go live, then the deferred Royals game ends and its
      // 30-minute countdown elapses.
      h.espn.games[chiefsId] = _game('g1', chiefsId, GameStatus.inProgress);
      h.espn.games[royalsId] = _game('g2', royalsId, GameStatus.inProgress);
      await h.svc.evaluateConfigs(docIdOrder);

      h.espn.games[royalsId] = _game('g2', royalsId, GameStatus.final_);
      await h.svc.evaluateConfigs(docIdOrder);
      // Fast-forward past the Royals countdown.
      h.svc.debugSetCountdownEnd('mlb_royals', DateTime(2020));
      await h.svc.evaluateConfigs(docIdOrder);

      expect(h.resumeCalls, 0,
          reason: 'THE BUG: the first game to finish used to power the house '
              'off while the other game was still live.');
      expect(h.owner, 'nfl_chiefs');
      expect(h.applied.length, appliedBefore,
          reason: 'a deferred team completing must not repaint the house');
    });

    test('the LAST game ending DOES resume the normal schedule', () async {
      final h = _Harness()..priority = ['nfl_chiefs'];
      h.schedule.soon.add(chiefsId);
      await h.svc.evaluateConfigs([chiefs]);

      h.espn.games[chiefsId] = _game('g1', chiefsId, GameStatus.inProgress);
      await h.svc.evaluateConfigs([chiefs]);
      h.espn.games[chiefsId] = _game('g1', chiefsId, GameStatus.final_);
      await h.svc.evaluateConfigs([chiefs]);
      h.svc.debugSetCountdownEnd('nfl_chiefs', DateTime(2020));
      await h.svc.evaluateConfigs([chiefs]);

      expect(h.resumeCalls, 1,
          reason: 'with nothing left to hand off to, resuming is correct');
    });
  });

  group('hand-off on end', () {
    test("the winner's game ends while the other is still live — the second "
        "team takes over and its design is applied", () async {
      final h = _Harness()..priority = ['nfl_chiefs', 'mlb_royals'];
      h.schedule.soon.addAll([chiefsId, royalsId]);
      await h.svc.evaluateConfigs(docIdOrder);
      expect(h.owner, 'nfl_chiefs');
      final appliedBefore = h.applied.length;

      // Both live.
      h.espn.games[chiefsId] = _game('g1', chiefsId, GameStatus.inProgress);
      h.espn.games[royalsId] = _game('g2', royalsId, GameStatus.inProgress);
      await h.svc.evaluateConfigs(docIdOrder);

      // Chiefs finish; Royals still playing.
      h.espn.games[chiefsId] = _game('g1', chiefsId, GameStatus.final_);
      await h.svc.evaluateConfigs(docIdOrder);
      h.svc.debugSetCountdownEnd('nfl_chiefs', DateTime(2020));
      await h.svc.evaluateConfigs(docIdOrder);

      expect(h.resumeCalls, 0, reason: 'hand off, do not go dark');
      expect(h.owner, 'mlb_royals', reason: 'the survivor takes the house');
      expect(h.deferredTeams, isEmpty,
          reason: 'taking over IS un-deferring — which is also what starts '
              "the new owner's score alerts");
      expect(h.applied.length, appliedBefore + 1,
          reason: "the survivor's design must actually reach the wire");
    });

    test('hand-off picks the HIGHEST-priority survivor, not the next one in '
        'document order', () async {
      final blues = _cfg('nhl_blues', '19', SportType.nhl);
      final h = _Harness()
        ..priority = ['nfl_chiefs', 'mlb_royals', 'nhl_blues'];
      final all = [royals, blues, chiefs]; // doc-id order
      h.schedule.soon.addAll([chiefsId, royalsId, '19']);
      await h.svc.evaluateConfigs(all);
      expect(h.owner, 'nfl_chiefs');

      for (final id in [chiefsId, royalsId, '19']) {
        h.espn.games[id] = _game('g$id', id, GameStatus.inProgress);
      }
      await h.svc.evaluateConfigs(all);

      h.espn.games[chiefsId] = _game('g$chiefsId', chiefsId, GameStatus.final_);
      await h.svc.evaluateConfigs(all);
      h.svc.debugSetCountdownEnd('nfl_chiefs', DateTime(2020));
      await h.svc.evaluateConfigs(all);

      expect(h.owner, 'mlb_royals',
          reason: 'nhl_blues sorts first by document id but ranks third');
    });

    test('cancelling the owning team hands off instead of going dark',
        () async {
      final h = _Harness()..priority = ['nfl_chiefs', 'mlb_royals'];
      h.schedule.soon.addAll([chiefsId, royalsId]);
      await h.svc.evaluateConfigs(docIdOrder);
      expect(h.owner, 'nfl_chiefs');

      await h.svc.cancelSession('nfl_chiefs');

      expect(h.resumeCalls, 0);
      expect(h.owner, 'mlb_royals');
    });

    test('cancelling a DEFERRED team touches nothing — it never had the '
        'lights', () async {
      final h = _Harness()..priority = ['nfl_chiefs', 'mlb_royals'];
      h.schedule.soon.addAll([chiefsId, royalsId]);
      await h.svc.evaluateConfigs(docIdOrder);
      final appliedBefore = h.applied.length;

      await h.svc.cancelSession('mlb_royals');

      expect(h.resumeCalls, 0);
      expect(h.owner, 'nfl_chiefs');
      expect(h.applied.length, appliedBefore);
    });

    test('cancelling the only team resumes, as before', () async {
      final h = _Harness()..priority = ['nfl_chiefs'];
      h.schedule.soon.add(chiefsId);
      await h.svc.evaluateConfigs([chiefs]);

      await h.svc.cancelSession('nfl_chiefs');

      expect(h.resumeCalls, 1);
    });
  });

  group('single-team accounts are unaffected', () {
    test('one team activates exactly as it always did', () async {
      final h = _Harness()..priority = ['nfl_chiefs'];
      h.schedule.soon.add(chiefsId);
      await h.svc.evaluateConfigs([chiefs]);

      expect(h.owner, 'nfl_chiefs');
      expect(h.deferredTeams, isEmpty);
      expect(h.applied, hasLength(1));
    });
  });
}
