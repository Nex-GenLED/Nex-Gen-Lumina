// "Light It Up Now" must start the COMPLETE Game Day experience, not just apply
// a pattern — celebration blocker (2).
//
// The worker looks for a team's session in its in-memory `_sessions` map, and
// that map was only ever written by the scheduled `evaluate()` path. A manual
// tap lit the house and armed nothing: every scoring event that followed found
// no session and returned silently.
//
// The phase assertions here are the ones that matter. The first cut of this
// feature registered `phase: 'inGame'`, which is not a phase this system has,
// and three things followed silently — the session read as INACTIVE
// (`isActive` is `preGame || liveGame || postGame`), so it never armed polling;
// `onScoreAlertEvent` refused it; and `_updateActiveSession`'s switch has no
// such case, so it could never reach postGame → completed and the show would
// have run forever. These tests exist so that cannot recur.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/autopilot/game_day_background_persistence.dart';
import 'package:nexgen_command/features/game_day/light_it_up_now.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';
import 'package:shared_preferences/shared_preferences.dart';

GameDayAutopilotConfig _config() {
  final created = DateTime.utc(2026, 8, 1);
  return GameDayAutopilotConfig(
    teamSlug: 'mlb_dodgers',
    teamName: 'Los Angeles Dodgers',
    espnTeamId: '19',
    sport: SportType.mlb,
    primaryColorValue: 0xFF005A9C,
    secondaryColorValue: 0xFFFFFFFF,
    effectId: 52,
    speed: 200,
    intensity: 180,
    brightness: 220,
    createdAt: created,
    updatedAt: created,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('registerManualGameDaySession — the isolate crossing', () {
    test('registers a session the worker will adopt', () async {
      await registerManualGameDaySession(teamSlug: 'mlb_dodgers');

      final sessions = await loadGameDaySessions();
      expect(sessions.containsKey('mlb_dodgers'), isTrue);
    });

    // THE ARMING PROPERTY. If this is false, hasActiveSession is false and the
    // background service never polls scores for the manual session.
    test('the registered session is ACTIVE', () async {
      await registerManualGameDaySession(teamSlug: 'mlb_dodgers');
      final s = (await loadGameDaySessions())['mlb_dodgers']!;
      expect(s.isActive, isTrue,
          reason: 'an inactive session arms nothing — this was the inGame bug');
    });

    // THE END-CARRY PROPERTY (B8). 'liveGame' is the only phase that is both
    // active AND handled by the phase machine, so it is the only one that can
    // reach the end contract.
    test('phase is liveGame — active AND handled by the phase machine', () async {
      await registerManualGameDaySession(teamSlug: 'mlb_dodgers');
      final s = (await loadGameDaySessions())['mlb_dodgers']!;
      expect(s.phase, 'liveGame');
    });

    test('phase is one the machine can advance (not an invented one)', () async {
      await registerManualGameDaySession(teamSlug: 'mlb_dodgers');
      final s = (await loadGameDaySessions())['mlb_dodgers']!;
      // The phases _updateActiveSession switches on. A phase outside this set
      // strands the session: no transition, no postGame, no end.
      expect(['preGame', 'liveGame', 'postGame'], contains(s.phase));
    });

    test('carries gameStart and gameId when known', () async {
      final start = DateTime.utc(2026, 8, 14, 2, 10);
      await registerManualGameDaySession(
        teamSlug: 'mlb_dodgers',
        gameStart: start,
        activeGameId: '401816515',
      );
      final s = (await loadGameDaySessions())['mlb_dodgers']!;
      expect(s.gameStart, start);
      expect(s.activeGameId, '401816515');
    });

    test('is idempotent — re-tapping does not restart a running show', () async {
      final first = DateTime.utc(2026, 8, 14, 2, 0);
      await registerManualGameDaySession(teamSlug: 'mlb_dodgers', now: first);
      await registerManualGameDaySession(
        teamSlug: 'mlb_dodgers',
        now: DateTime.utc(2026, 8, 14, 3, 0),
      );
      final sessions = await loadGameDaySessions();
      expect(sessions.length, 1);
      expect(sessions['mlb_dodgers']!.activatedAt, first,
          reason: 'the original activation must survive a second tap');
    });

    test('does not disturb another team\'s session', () async {
      await registerManualGameDaySession(teamSlug: 'mlb_dodgers');
      await registerManualGameDaySession(teamSlug: 'mlb_twins');
      final sessions = await loadGameDaySessions();
      expect(sessions.keys, containsAll(['mlb_dodgers', 'mlb_twins']));
    });
  });

  group('lightItUpNow — the tap arms monitoring', () {
    test('a successful apply registers the session', () async {
      String? registered;
      final outcome = await lightItUpNow(
        applyPayloadWithLabel: (payload, {labelHint}) async => true,
        configureForTeam: ({required groupId, required sourceConfig, now}) async =>
            throw StateError('not broadcasting in this test'),
        config: _config(),
        broadcastToGroup: false,
        groupId: null,
        participatingChannels: const [0],
        deviceChannels: const [],
        registerSession: ({
          required String teamSlug,
          DateTime? gameStart,
          String? activeGameId,
        }) {
          registered = teamSlug;
        },
      );

      expect(outcome, isA<LightItUpApplied>());
      expect(registered, 'mlb_dodgers');
    });

    // A failed apply means no show — so there is nothing to monitor and nothing
    // to end. Arming here would leave a session with no lights behind it.
    test('a FAILED apply registers nothing', () async {
      var registered = false;
      final outcome = await lightItUpNow(
        applyPayloadWithLabel: (payload, {labelHint}) async => false,
        configureForTeam: ({required groupId, required sourceConfig, now}) async =>
            throw StateError('unreachable'),
        config: _config(),
        broadcastToGroup: false,
        groupId: null,
        participatingChannels: const [0],
        deviceChannels: const [],
        registerSession: ({
          required String teamSlug,
          DateTime? gameStart,
          String? activeGameId,
        }) {
          registered = true;
        },
      );

      expect(outcome, isA<LightItUpApplyFailed>());
      expect(registered, isFalse);
    });

    // Omitting the callback must stay legal so existing callers and tests
    // compile — but a caller that omits it gets no monitoring, which is exactly
    // the bug, so production call sites must pass it.
    test('registerSession is optional', () async {
      final outcome = await lightItUpNow(
        applyPayloadWithLabel: (payload, {labelHint}) async => true,
        configureForTeam: ({required groupId, required sourceConfig, now}) async =>
            throw StateError('unreachable'),
        config: _config(),
        broadcastToGroup: false,
        groupId: null,
        participatingChannels: const [0],
        deviceChannels: const [],
      );
      expect(outcome, isA<LightItUpApplied>());
    });
  });
}
