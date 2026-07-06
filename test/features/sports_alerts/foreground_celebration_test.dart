// test/features/sports_alerts/foreground_celebration_test.dart
//
// Foreground score celebrations (next release). Covers the NEW coordinator
// logic — lifecycle, capture→flash→revert delivery, coalescing under rapid
// scores, toggle-off gating — plus the reused ScoreMonitorService baseline
// guard (no celebration on app-open mid-game / no missed-score replay).

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_service.dart';
import 'package:nexgen_command/features/sports_alerts/data/team_colors.dart';
import 'package:nexgen_command/features/sports_alerts/models/game_state.dart';
import 'package:nexgen_command/features/sports_alerts/models/score_alert_config.dart';
import 'package:nexgen_command/features/sports_alerts/models/score_alert_event.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';
import 'package:nexgen_command/features/sports_alerts/services/alert_trigger_service.dart'
    show AlertAnimationStep;
import 'package:nexgen_command/features/sports_alerts/services/espn_api_service.dart';
import 'package:nexgen_command/features/sports_alerts/services/foreground_celebration_coordinator.dart';
import 'package:nexgen_command/features/sports_alerts/services/foreground_celebration_providers.dart';
import 'package:nexgen_command/features/sports_alerts/services/score_monitor_service.dart';

// ── Fakes ──────────────────────────────────────────────────────────────────

class _FakeMonitor implements ScoreMonitor {
  final _controller = StreamController<ScoreAlertEvent>.broadcast();
  final List<List<ScoreAlertConfig>> checkCalls = [];
  int resetCount = 0;

  @override
  Stream<ScoreAlertEvent> get alertStream => _controller.stream;
  @override
  Future<void> checkScores(List<ScoreAlertConfig> c) async => checkCalls.add(c);
  @override
  void reset() => resetCount++;

  void emit(ScoreAlertEvent e) => _controller.add(e);
  void close() => _controller.close();
}

class _FakeDelivery implements CelebrationDelivery {
  final List<String> log = [];
  Map<String, dynamic>? captureReturn = {
    'on': true,
    'bri': 120,
    'seg': [
      {'fx': 5, 'col': [[1, 2, 3, 0]]}
    ],
  };
  Map<String, dynamic>? revertedWith;
  int captureCount = 0, playCount = 0, revertCount = 0;
  Completer<void>? blockPlay;

  @override
  Future<Map<String, dynamic>?> capture() async {
    captureCount++;
    log.add('capture');
    return captureReturn;
  }

  @override
  Future<void> play(List<AlertAnimationStep> steps) async {
    playCount++;
    log.add('play(${steps.length})');
    if (blockPlay != null) await blockPlay!.future;
  }

  @override
  Future<void> revert(Map<String, dynamic> captured) async {
    revertCount++;
    revertedWith = captured;
    log.add('revert');
  }
}

class _FakeEspn extends EspnApiService {
  List<GameState> games = [];
  @override
  Future<List<GameState>> fetchLiveGames(SportType sport) async => games;
  @override
  void dispose() {}
}

Future<void> _settle() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

ScoreAlertEvent _event(String slug, {AlertEventType type = AlertEventType.touchdown}) =>
    ScoreAlertEvent(
      teamSlug: slug,
      sport: SportType.nfl,
      eventType: type,
      pointsScored: 7,
      gameId: 'g1',
      timestamp: DateTime(2026, 1, 1),
    );

void main() {
  // A guaranteed-valid team slug (buildAnimationSteps needs team colors).
  final anySlug = kTeamColors.keys.first;
  final anySport = kTeamColors[anySlug]!.sport;

  ForegroundCelebrationCoordinator build(
    _FakeMonitor monitor,
    _FakeDelivery delivery,
  ) =>
      ForegroundCelebrationCoordinator(
        monitor: monitor,
        delivery: delivery,
        minGap: Duration.zero, // no real delay in tests
      );

  group('celebration delivery (capture → flash → revert)', () {
    test('a score fires capture, play, then revert with the captured state',
        () async {
      final m = _FakeMonitor();
      final d = _FakeDelivery();
      final c = build(m, d);
      addTearDown(c.dispose);

      c.handleAlert(_event(anySlug));
      await _settle();

      expect(d.log, ['capture', 'play(3)', 'revert']);
      expect(d.captureCount, 1);
      expect(d.revertCount, 1);
      // Revert restores exactly what was captured (lands back on the active
      // team design if the phase machine had one on).
      expect(d.revertedWith, d.captureReturn);
    });

    test('no revert when capture returns null (can\'t read state)', () async {
      final m = _FakeMonitor();
      final d = _FakeDelivery()..captureReturn = null;
      final c = build(m, d);
      addTearDown(c.dispose);

      c.handleAlert(_event(anySlug));
      await _settle();

      expect(d.log, ['capture', 'play(3)']);
      expect(d.revertCount, 0);
    });
  });

  group('coalescing under rapid scores', () {
    test('scores during a celebration collapse to ONE follow-up (no strobe)',
        () async {
      final m = _FakeMonitor();
      final d = _FakeDelivery();
      final c = build(m, d);
      addTearDown(c.dispose);

      // Block the first celebration mid-play.
      final block = Completer<void>();
      d.blockPlay = block;

      c.handleAlert(_event(anySlug)); // starts celebration #1
      await _settle();
      expect(c.isCelebrating, isTrue);
      expect(d.captureCount, 1);

      // Two more scores arrive WHILE celebrating — must coalesce to one.
      c.handleAlert(_event(anySlug));
      c.handleAlert(_event(anySlug));
      expect(d.captureCount, 1, reason: 'no new celebration starts mid-flight');

      block.complete(); // finish celebration #1
      await _settle();

      // Exactly ONE follow-up ran (the coalesced slot), not two.
      expect(d.captureCount, 2);
      expect(d.revertCount, 2);
      expect(c.isCelebrating, isFalse);
    });
  });

  group('lifecycle — poll only during live game + foreground', () {
    test('polling starts on live teams, stops on empty / background', () async {
      final m = _FakeMonitor();
      final d = _FakeDelivery();
      final c = build(m, d);
      addTearDown(c.dispose);

      expect(c.isPolling, isFalse);

      c.syncLiveTeams([CelebrationTeam(teamSlug: anySlug, sport: anySport)]);
      expect(c.isPolling, isTrue);
      await _settle();
      expect(m.checkCalls, isNotEmpty, reason: 'first poll ran immediately');

      // App backgrounded → stop.
      c.setForeground(false);
      expect(c.isPolling, isFalse);

      // Foregrounded again → resume.
      c.setForeground(true);
      expect(c.isPolling, isTrue);

      // No live games → stop.
      c.syncLiveTeams(const []);
      expect(c.isPolling, isFalse);
    });

    test('no polling while backgrounded even with live teams', () async {
      final m = _FakeMonitor();
      final c = build(m, _FakeDelivery());
      addTearDown(c.dispose);

      c.setForeground(false);
      c.syncLiveTeams([CelebrationTeam(teamSlug: anySlug, sport: anySport)]);
      expect(c.isPolling, isFalse);
    });
  });

  group('config gating — computeLiveCelebrationTeams', () {
    GameDayAutopilotConfig cfg(String slug,
            {bool enabled = true, bool celebrate = true}) =>
        GameDayAutopilotConfig(
          teamSlug: slug,
          teamName: slug,
          espnTeamId: '1',
          sport: SportType.nfl,
          primaryColorValue: 0xFFFF0000,
          secondaryColorValue: 0xFFFFFFFF,
          enabled: enabled,
          scoreCelebrationEnabled: celebrate,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        );

    AutopilotSession session(String slug, AutopilotSessionPhase phase) =>
        AutopilotSession(teamSlug: slug, phase: phase);

    test('liveGame + celebrate ON → included', () {
      final teams = computeLiveCelebrationTeams(
        sessions: {'a': session('a', AutopilotSessionPhase.liveGame)},
        configs: [cfg('a')],
      );
      expect(teams.map((t) => t.teamSlug), ['a']);
    });

    test('toggle OFF (scoreCelebrationEnabled=false) → excluded', () {
      final teams = computeLiveCelebrationTeams(
        sessions: {'a': session('a', AutopilotSessionPhase.liveGame)},
        configs: [cfg('a', celebrate: false)],
      );
      expect(teams, isEmpty);
    });

    test('not in liveGame phase (preGame) → excluded', () {
      final teams = computeLiveCelebrationTeams(
        sessions: {'a': session('a', AutopilotSessionPhase.preGame)},
        configs: [cfg('a')],
      );
      expect(teams, isEmpty);
    });

    test('config disabled → excluded even if live', () {
      final teams = computeLiveCelebrationTeams(
        sessions: {'a': session('a', AutopilotSessionPhase.liveGame)},
        configs: [cfg('a', enabled: false)],
      );
      expect(teams, isEmpty);
    });
  });

  group('baseline guard (reused ScoreMonitorService) — no replay', () {
    test('first poll baselines silently; only a NEW delta celebrates', () async {
      final espn = _FakeEspn();
      final monitor = ScoreMonitorService(espnApi: espn);
      addTearDown(monitor.dispose);

      final alerts = <ScoreAlertEvent>[];
      final sub = monitor.alertStream.listen(alerts.add);
      addTearDown(sub.cancel);

      // A real NFL team so the diff engine's TD logic + team lookup work.
      final nfl = kTeamColors.entries
          .firstWhere((e) => e.value.sport == SportType.nfl);
      final config = ScoreAlertConfig(
        id: 'c',
        teamSlug: nfl.key,
        sport: SportType.nfl,
        sensitivity: AlertSensitivity.allEvents,
      );

      GameState game(int home) => GameState(
            gameId: 'g1',
            homeTeam: 'H',
            awayTeam: 'A',
            homeTeamId: nfl.value.espnTeamId,
            awayTeamId: 'other',
            homeScore: home,
            awayScore: 0,
            status: GameStatus.inProgress,
            period: '2',
            lastUpdated: DateTime(2026, 1, 1),
          );

      // App opens mid-game at 7-0 — must NOT replay the existing score.
      espn.games = [game(7)];
      await monitor.checkScores([config]);
      await _settle();
      expect(alerts, isEmpty, reason: 'baseline poll must not celebrate 7-0');

      // A touchdown lands (7 → 14) — NEW delta celebrates.
      espn.games = [game(14)];
      await monitor.checkScores([config]);
      await _settle();
      expect(alerts, hasLength(1));
      expect(alerts.first.eventType, AlertEventType.touchdown);
    });
  });
}
