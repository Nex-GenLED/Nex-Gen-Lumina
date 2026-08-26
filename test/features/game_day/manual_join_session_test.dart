// Phase E — "Light Up Now" arms a mid-game join WITHOUT arming the schedule.
//
// It used to flip config.enabled:true, because the background worker's session
// map is what onScoreAlertEvent looks in and only the scheduled path wrote it.
// But `enabled` is the field the SERVER planner queries, so joining ONE live
// game silently opted the team into every future scheduled show
// (audit/GAME_DAY_SPEC_AUDIT.md §3.5).
//
// The screen itself has no widget-test harness in this repo, so these pin the
// two mechanisms it now uses instead: the prefs-backed isolate crossing that
// arms celebrations, and the worker's adoption of a session registered while
// it was already running.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_background_worker.dart';
import 'package:nexgen_command/features/autopilot/game_day_background_persistence.dart';
import 'package:nexgen_command/features/sports_alerts/services/espn_api_service.dart';
import 'package:nexgen_command/features/sports_alerts/services/game_schedule_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

GameDayAutopilotBackgroundWorker _worker() =>
    GameDayAutopilotBackgroundWorker(
      espnApi: EspnApiService(),
      scheduleService: GameScheduleService(),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('arming a manual join', () {
    test('registers an ACTIVE session for the team', () async {
      await registerManualGameDaySession(teamSlug: 'mlb_royals');

      final sessions = await loadGameDaySessions();
      expect(sessions.containsKey('mlb_royals'), isTrue);
      expect(sessions['mlb_royals']!.isActive, isTrue);
    });

    // 'liveGame' is the only in-progress phase that is BOTH active and handled
    // by the phase machine's switch — an invented phase reads as inactive and
    // never advances, stranding the show on forever.
    test('the phase is liveGame, so the show can also END', () async {
      await registerManualGameDaySession(teamSlug: 'mlb_royals');
      expect((await loadGameDaySessions())['mlb_royals']!.phase, 'liveGame');
    });

    test('it binds the game id when one is known', () async {
      await registerManualGameDaySession(
          teamSlug: 'mlb_royals', activeGameId: 'g1');
      expect(
          (await loadGameDaySessions())['mlb_royals']!.activeGameId, 'g1');
    });

    // THE POINT OF THE PHASE. Arming must not write the planner's field.
    test('arming writes NO Game Day config at all', () async {
      await registerManualGameDaySession(teamSlug: 'mlb_royals');
      expect(await loadGameDayConfigsForBackground(), isEmpty,
          reason: 'config.enabled must be untouched by a manual join');
    });

    test('re-tapping does not stack or restart the session', () async {
      await registerManualGameDaySession(
          teamSlug: 'mlb_royals', activeGameId: 'g1');
      final first = (await loadGameDaySessions())['mlb_royals']!;
      await registerManualGameDaySession(
          teamSlug: 'mlb_royals', activeGameId: 'g2');
      final second = (await loadGameDaySessions())['mlb_royals']!;

      expect((await loadGameDaySessions()).length, 1);
      expect(second.activatedAt, first.activatedAt);
    });
  });

  // Without this the whole phase is inert in the field: `_sessions` was loaded
  // ONCE at startMonitoring, so a join made while the service was already up
  // armed nothing until the service happened to restart.
  group('the worker adopts a session registered while it was running', () {
    test('an externally-registered session is picked up on evaluate', () async {
      final worker = _worker();
      await worker.startMonitoring();
      expect(worker.hasActiveSession, isFalse);

      await registerManualGameDaySession(teamSlug: 'mlb_royals');
      await worker.evaluate();

      expect(worker.hasActiveSession, isTrue,
          reason: 'celebrations arm off exactly this');
      worker.dispose();
    });

    test('a session already present at startup is loaded as before', () async {
      await registerManualGameDaySession(teamSlug: 'mlb_royals');
      final worker = _worker();
      await worker.startMonitoring();
      expect(worker.hasActiveSession, isTrue);
      worker.dispose();
    });

    test('a COMPLETED persisted session is not resurrected', () async {
      await registerManualGameDaySession(teamSlug: 'mlb_royals');
      await clearGameDaySession('mlb_royals');

      final worker = _worker();
      await worker.startMonitoring();
      await worker.evaluate();

      expect(worker.hasActiveSession, isFalse);
      worker.dispose();
    });
  });

  // The session's own end must take the arming with it, or a score in a LATER
  // game would celebrate over whatever the house had gone back to.
  group('disarming', () {
    test('clearing the session removes it from the store', () async {
      await registerManualGameDaySession(teamSlug: 'mlb_royals');
      await clearGameDaySession('mlb_royals');
      expect((await loadGameDaySessions()).containsKey('mlb_royals'), isFalse);
    });

    test('a cleared team no longer arms a freshly started worker', () async {
      await registerManualGameDaySession(teamSlug: 'mlb_royals');
      await clearGameDaySession('mlb_royals');

      final worker = _worker();
      await worker.startMonitoring();
      expect(worker.hasActiveSession, isFalse);
      worker.dispose();
    });

    test('clearing one team leaves another armed', () async {
      await registerManualGameDaySession(teamSlug: 'mlb_royals');
      await registerManualGameDaySession(teamSlug: 'nfl_chiefs');
      await clearGameDaySession('mlb_royals');

      final sessions = await loadGameDaySessions();
      expect(sessions.containsKey('mlb_royals'), isFalse);
      expect(sessions.containsKey('nfl_chiefs'), isTrue);
    });
  });
}
