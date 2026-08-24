// Unified score-monitoring model — the arming logic that decides whether score
// polling happens at all.
//
// WHY THIS SUITE IS THE ONE THAT MATTERS: celebrations had never fired for
// anyone, fleet-wide, and the largest of the three reasons was that arming keyed
// off the SPORTS-ALERT config list rather than the Game Day teams the user had
// actually selected. Nothing in test/ pinned that, so the gate could be — and
// was — silently wrong for the entire life of the feature. These lock the
// predicate so it cannot re-narrow.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_background_persistence.dart';
import 'package:nexgen_command/features/autopilot/unified_monitoring.dart';
import 'package:nexgen_command/features/sports_alerts/models/score_alert_config.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';

BackgroundGameDayAutopilotConfig _gd({
  String slug = 'mlb_royals',
  bool enabled = true,
  bool liveScoring = true,
  String sensitivity = 'majorOnly',
  bool celebration = true,
}) =>
    BackgroundGameDayAutopilotConfig(
      teamSlug: slug,
      teamName: slug,
      espnTeamId: '1',
      sport: 'mlb',
      primaryColorValue: 0xFF0000FF,
      secondaryColorValue: 0xFFFFFFFF,
      enabled: enabled,
      designMode: 'fallback',
      effectId: 0,
      speed: 128,
      intensity: 128,
      brightness: 200,
      skipDayGames: true,
      designVariety: 'rotating',
      scoreCelebrationEnabled: celebration,
      liveScoringEnabled: liveScoring,
      alertSensitivity: sensitivity,
    );

ScoreAlertConfig _legacy({
  String slug = 'nfl_chiefs',
  bool enabled = true,
  AlertSensitivity sensitivity = AlertSensitivity.allEvents,
}) =>
    ScoreAlertConfig(
      id: 'legacy-$slug',
      teamSlug: slug,
      sport: SportType.nfl,
      isEnabled: enabled,
      sensitivity: sensitivity,
    );

void main() {
  group('resolveMonitoring — Game Day is the single source of truth', () {
    test('a Game Day team with Live Scoring ON is monitored', () {
      final plan = resolveMonitoring(
        gameDayConfigs: [_gd()],
        legacyAlertConfigs: const [],
        profileTeamNames: const [],
      );
      expect(plan.monitored.map((c) => c.teamSlug), ['mlb_royals']);
    });

    test('Live Scoring OFF means NOT monitored', () {
      final plan = resolveMonitoring(
        gameDayConfigs: [_gd(liveScoring: false)],
        legacyAlertConfigs: const [],
        profileTeamNames: const [],
      );
      expect(plan.monitored, isEmpty);
    });

    // The point of the split: an alerts-only team is invisible to the server
    // planner (enabled:false) yet still monitored.
    test('enabled:false + liveScoring:true is still monitored', () {
      final plan = resolveMonitoring(
        gameDayConfigs: [_gd(enabled: false, liveScoring: true)],
        legacyAlertConfigs: const [],
        profileTeamNames: const [],
      );
      expect(plan.monitored.map((c) => c.teamSlug), ['mlb_royals']);
    });

    test('sensitivity is carried onto the derived monitoring config', () {
      final plan = resolveMonitoring(
        gameDayConfigs: [_gd(sensitivity: 'clutchOnly')],
        legacyAlertConfigs: const [],
        profileTeamNames: const [],
      );
      expect(plan.monitored.single.sensitivity, AlertSensitivity.clutchOnly);
    });

    test('an unknown sensitivity degrades to majorOnly, it does not throw', () {
      final plan = resolveMonitoring(
        gameDayConfigs: [_gd(sensitivity: 'nonsense')],
        legacyAlertConfigs: const [],
        profileTeamNames: const [],
      );
      expect(plan.monitored.single.sensitivity, AlertSensitivity.majorOnly);
    });

    test('derived id is the team slug, so it is stable across runs', () {
      final a = resolveMonitoring(
          gameDayConfigs: [_gd()], legacyAlertConfigs: const [], profileTeamNames: const []);
      final b = resolveMonitoring(
          gameDayConfigs: [_gd()], legacyAlertConfigs: const [], profileTeamNames: const []);
      expect(a.monitored.single.id, b.monitored.single.id);
      expect(a.monitored.single.id, 'mlb_royals');
    });
  });

  group('resolveMonitoring — legacy configs are a safety net, not an authority',
      () {
    test(
        'a legacy config with no Game Day team is still monitored while the '
        'profile arrays corroborate it', () {
      final plan = resolveMonitoring(
        gameDayConfigs: const [],
        legacyAlertConfigs: [_legacy()],
        profileTeamNames: const ['Kansas City Chiefs'],
      );
      expect(plan.monitored.map((c) => c.teamSlug), ['nfl_chiefs']);
      expect(plan.orphanedLegacy.map((c) => c.teamSlug), ['nfl_chiefs']);
    });

    // ── ORPHAN SAFETY GATE (audit/SPORTS_ALERTS_SYNC_AUDIT.md §4.4) ────────
    //
    // The bug this closes: Game Day's delete writes ONLY to Firestore
    // (team_registration_service.dart:118-122 deletes the doc, :214-235 strips
    // the arrays) and never to the prefs store, so a deleted team's prefs
    // config survived and kept arming monitoring. Deleting the Game Day doc
    // removed the one record that would have suppressed it.
    group('orphan safety gate', () {
      test(
          'an orphan with NO Game Day doc and NO profile entry is excluded '
          'from monitored', () {
        final plan = resolveMonitoring(
          gameDayConfigs: const [],
          legacyAlertConfigs: [_legacy(slug: 'nfl_chiefs')],
          profileTeamNames: const [],
        );
        expect(plan.monitored, isEmpty);
      });

      test('...but is still REPORTED as orphaned, so migration can adopt it',
          () {
        final plan = resolveMonitoring(
          gameDayConfigs: const [],
          legacyAlertConfigs: [_legacy(slug: 'nfl_chiefs')],
          profileTeamNames: const [],
        );
        expect(plan.orphanedLegacy.map((c) => c.teamSlug), ['nfl_chiefs']);
      });

      // The exact reported scenario: three teams deleted from Game Day, whose
      // prefs configs were left behind and kept celebrating.
      test('the three deleted teams all disarm together', () {
        final plan = resolveMonitoring(
          gameDayConfigs: const [],
          legacyAlertConfigs: [
            _legacy(slug: 'nfl_chiefs'),
            _legacy(slug: 'mlb_royals'),
            _legacy(slug: 'mlb_dodgers'),
          ],
          profileTeamNames: const [],
        );
        expect(plan.monitored, isEmpty);
        expect(plan.orphanedLegacy, hasLength(3));
      });

      // DON'T BREAK ACCOUNTS THAT ARE FINE — a legacy entry whose team is
      // still on the profile arrays keeps working exactly as before.
      test('an orphan still on the profile arrays is NOT disarmed', () {
        final plan = resolveMonitoring(
          gameDayConfigs: const [],
          legacyAlertConfigs: [
            _legacy(slug: 'nfl_chiefs'),
            _legacy(slug: 'mlb_royals'),
          ],
          profileTeamNames: const ['Kansas City Royals'],
        );
        expect(plan.monitored.map((c) => c.teamSlug), ['mlb_royals']);
      });

      // A legacy entry backed by a Game Day doc never reaches the gate:
      // Game Day wins outright, profile arrays are irrelevant.
      test('a legacy entry with a matching Game Day doc is unaffected', () {
        final plan = resolveMonitoring(
          gameDayConfigs: [_gd(slug: 'nfl_chiefs', liveScoring: true)],
          legacyAlertConfigs: [_legacy(slug: 'nfl_chiefs')],
          profileTeamNames: const [],
        );
        expect(plan.monitored.map((c) => c.teamSlug), ['nfl_chiefs']);
      });

      // Matches TeamRegistrationService._stripTeamFromProfile's normalisation,
      // so "carried on the profile" means the same thing on both sides.
      test('profile matching is case- and whitespace-insensitive', () {
        final plan = resolveMonitoring(
          gameDayConfigs: const [],
          legacyAlertConfigs: [_legacy(slug: 'nfl_chiefs')],
          profileTeamNames: const ['  kansas city CHIEFS '],
        );
        expect(plan.monitored.map((c) => c.teamSlug), ['nfl_chiefs']);
      });

      // Both writers of the prefs store pick from kTeamColors, so a slug that
      // is not in it cannot be mapped to a profile name and must not arm.
      test('a slug absent from kTeamColors never arms', () {
        final plan = resolveMonitoring(
          gameDayConfigs: const [],
          legacyAlertConfigs: [_legacy(slug: 'not_a_real_team')],
          profileTeamNames: const ['Kansas City Chiefs'],
        );
        expect(plan.monitored, isEmpty);
      });
    });

    // THE REDUNDANCY FIX. A stale legacy config must not resurrect monitoring
    // the user turned off in Game Day — otherwise there are still two switches.
    test('Game Day OFF beats a stale legacy config that is ON', () {
      final plan = resolveMonitoring(
        gameDayConfigs: [_gd(slug: 'nfl_chiefs', liveScoring: false)],
        legacyAlertConfigs: [_legacy(slug: 'nfl_chiefs', enabled: true)],
        profileTeamNames: const [],
      );
      expect(plan.monitored, isEmpty);
      expect(plan.orphanedLegacy, isEmpty); // covered, not orphaned
    });

    test('a disabled legacy orphan is reported but not monitored', () {
      final plan = resolveMonitoring(
        gameDayConfigs: const [],
        legacyAlertConfigs: [_legacy(enabled: false)],
        profileTeamNames: const [],
      );
      expect(plan.monitored, isEmpty);
      expect(plan.orphanedLegacy, hasLength(1));
    });

    test('no duplicate when both sources name the same team', () {
      final plan = resolveMonitoring(
        gameDayConfigs: [_gd(slug: 'nfl_chiefs')],
        legacyAlertConfigs: [_legacy(slug: 'nfl_chiefs')],
        profileTeamNames: const [],
      );
      expect(plan.monitored, hasLength(1));
    });
  });

  group('shouldPollScores — the gate that was wrong', () {
    test('polls when a team is monitored', () {
      final plan = resolveMonitoring(
          gameDayConfigs: [_gd()], legacyAlertConfigs: const [], profileTeamNames: const []);
      expect(
        shouldPollScores(plan: plan, hasActiveGameDaySession: false),
        isTrue,
      );
    });

    // THE MID-GAME JOIN. "Light It Up Now" can produce an active session for a
    // team with no enabled config at all; the old gate polled nothing here.
    test('polls on an active session even with NOTHING monitored', () {
      const empty = MonitoringPlan(monitored: []);
      expect(
        shouldPollScores(plan: empty, hasActiveGameDaySession: true),
        isTrue,
      );
    });

    test('does not poll when nothing is monitored and no session is active', () {
      const empty = MonitoringPlan(monitored: []);
      expect(
        shouldPollScores(plan: empty, hasActiveGameDaySession: false),
        isFalse,
      );
    });

    // The regression this whole change exists to prevent.
    test('Game Day teams alone arm polling with ZERO legacy alert configs', () {
      final plan = resolveMonitoring(
        gameDayConfigs: [_gd()],
        legacyAlertConfigs: const [], // the old gate would have been empty here
        profileTeamNames: const [],
      );
      expect(
        shouldPollScores(plan: plan, hasActiveGameDaySession: false),
        isTrue,
      );
    });
  });

  group('monitoringPollInterval', () {
    test('an active session polls at 30s', () {
      expect(monitoringPollInterval(hasActiveGameDaySession: true),
          const Duration(seconds: 30));
    });
    test('idle polls at 5 minutes', () {
      expect(monitoringPollInterval(hasActiveGameDaySession: false),
          const Duration(minutes: 5));
    });
  });

  group('migrationConfigsFor — nobody loses monitoring, nobody gains lighting',
      () {
    final now = DateTime.utc(2026, 8, 14);

    test('adopts an orphan as monitoring-only', () {
      final out = migrationConfigsFor([_legacy()], now: now);
      expect(out, hasLength(1));
      // Monitored...
      expect(out.single.liveScoringEnabled, isTrue);
      // ...but INVISIBLE TO THE PLANNER, which queries enabled == true. This is
      // the assertion that stops a migrated alerts-only team from getting a
      // first-pitch fire the user never asked for.
      expect(out.single.enabled, isFalse);
    });

    test('carries the user\'s sensitivity across rather than resetting it', () {
      final out = migrationConfigsFor(
        [_legacy(sensitivity: AlertSensitivity.clutchOnly)],
        now: now,
      );
      expect(out.single.alertSensitivity, AlertSensitivity.clutchOnly);
    });

    test('celebrations are on for migrated teams', () {
      final out = migrationConfigsFor([_legacy()], now: now);
      expect(out.single.scoreCelebrationEnabled, isTrue);
    });

    test('an empty orphan list migrates nothing', () {
      expect(migrationConfigsFor(const [], now: now), isEmpty);
    });

    test('round-trips through the plan: orphans in, adoptions out', () {
      final plan = resolveMonitoring(
        gameDayConfigs: [_gd(slug: 'mlb_royals')],
        legacyAlertConfigs: [_legacy(slug: 'nfl_chiefs')],
        profileTeamNames: const [],
      );
      final out = migrationConfigsFor(plan.orphanedLegacy, now: now);
      // Only the uncovered team is adopted; the Game Day team is left alone.
      expect(out.map((c) => c.teamSlug), ['nfl_chiefs']);
    });
  });

  group('celebration default — blocker (3)', () {
    // The live Twins config carries no scoreCelebrationEnabled key at all. The
    // background mirror read `?? false`, so the worker saw "celebrations off"
    // for a config the Firestore layer considered on. Absent must mean TRUE.
    test('absent scoreCelebrationEnabled reads TRUE from the mirror', () {
      final c = BackgroundGameDayAutopilotConfig.fromJson({
        'teamSlug': 'mlb_twins',
        'teamName': 'Minnesota Twins',
        'sport': 'mlb',
        'enabled': true,
        // scoreCelebrationEnabled deliberately absent
      });
      expect(c.scoreCelebrationEnabled, isTrue);
    });

    test('an explicit false is still honoured — the toggle still works', () {
      final c = BackgroundGameDayAutopilotConfig.fromJson({
        'teamSlug': 'mlb_twins',
        'scoreCelebrationEnabled': false,
      });
      expect(c.scoreCelebrationEnabled, isFalse);
    });

    test('absent liveScoringEnabled reads TRUE, so upgrades keep monitoring',
        () {
      final c = BackgroundGameDayAutopilotConfig.fromJson({
        'teamSlug': 'mlb_twins',
        'enabled': true,
      });
      expect(c.liveScoringEnabled, isTrue);
      expect(c.isMonitored, isTrue);
    });

    // THE PREMISE CORRECTION. This branch assumed score_celebration_enabled was
    // absent fleet-wide; measurement says 49 of 50 live configs carry it, and
    // the switch that writes it is the one LABELLED "Live Scoring". So an
    // absent liveScoringEnabled must inherit that switch, not default to true —
    // otherwise a user who deliberately turned Live Scoring OFF gets monitored,
    // polled and celebrated at anyway, having used the only control they have.
    test('absent liveScoringEnabled inherits an explicit celebration OFF', () {
      final c = BackgroundGameDayAutopilotConfig.fromJson({
        'teamSlug': 'mlb_twins',
        'enabled': true,
        'scoreCelebrationEnabled': false,
        // liveScoringEnabled deliberately absent — pre-upgrade mirror
      });
      expect(c.liveScoringEnabled, isFalse);
      expect(c.isMonitored, isFalse,
          reason: 'the user turned the only Live Scoring switch off');
    });

    test('an explicit liveScoringEnabled still wins over the fallback', () {
      final c = BackgroundGameDayAutopilotConfig.fromJson({
        'teamSlug': 'mlb_twins',
        'liveScoringEnabled': true,
        'scoreCelebrationEnabled': false,
      });
      expect(c.isMonitored, isTrue);
      // Monitored, but the last celebration gate still refuses the apply.
      expect(c.scoreCelebrationEnabled, isFalse);
    });

    test('round-trips the new fields through toJson/fromJson', () {
      final original = _gd(liveScoring: false, sensitivity: 'clutchOnly');
      final back =
          BackgroundGameDayAutopilotConfig.fromJson(original.toJson());
      expect(back.liveScoringEnabled, isFalse);
      expect(back.alertSensitivity, 'clutchOnly');
      expect(back.isMonitored, isFalse);
    });
  });
}
