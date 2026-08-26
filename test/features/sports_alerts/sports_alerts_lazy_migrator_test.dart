// One-time adoption of the retired Sports Alerts prefs store into Game Day.
//
// WHY THIS SUITE MATTERS: migrationConfigsFor was written and unit-tested but
// had NO production caller (audit/SPORTS_ALERTS_SYNC_AUDIT.md §4.2, item 2), so
// the migration it describes never ran. These lock the wiring — that orphans
// are adopted, that a team Game Day already knows is left alone, and that the
// user's own alerts switch is not flipped on for them.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/sports_alerts/models/score_alert_config.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';
import 'package:nexgen_command/features/sports_alerts/services/sports_alerts_lazy_migrator.dart';

const uid = 'u_test';

ScoreAlertConfig _legacy({
  String slug = 'nfl_chiefs',
  bool enabled = true,
  AlertSensitivity sensitivity = AlertSensitivity.clutchOnly,
}) =>
    ScoreAlertConfig(
      id: 'legacy-$slug',
      teamSlug: slug,
      sport: SportType.nfl,
      isEnabled: enabled,
      sensitivity: sensitivity,
    );

/// Migrator wired to a fake Firestore and an in-memory stand-in for the prefs
/// store, so no SharedPreferences binding is needed.
({SportsAlertsLazyMigrator migrator, List<ScoreAlertConfig> store})
    _migratorFor(
  FakeFirebaseFirestore fs, {
  List<ScoreAlertConfig> legacy = const [],
}) {
  final store = [...legacy];
  final migrator = SportsAlertsLazyMigrator(
    firestore: fs,
    loadLegacy: () async => [...store],
    clearLegacy: () async => store.clear(),
    clock: () => DateTime.utc(2026, 8, 24),
    // fake_cloud_firestore deadlocks on a serverTimestamp racing a pending
    // read — same seam ScheduleLazyMigrator uses.
    markerValue: Timestamp.now(),
  );
  return (migrator: migrator, store: store);
}

Future<void> _seedUser(
  FakeFirebaseFirestore fs, {
  List<String> sportsTeams = const [],
  Map<String, dynamic>? extra,
}) async {
  await fs.collection('users').doc(uid).set({
    'sports_teams': sportsTeams,
    'sports_team_priority': sportsTeams,
    ...?extra,
  });
}

Future<Map<String, dynamic>?> _gdDoc(
        FakeFirebaseFirestore fs, String slug) async =>
    (await fs
            .collection('users')
            .doc(uid)
            .collection('game_day_autopilot')
            .doc(slug)
            .get())
        .data();

void main() {
  setUp(resetSportsAlertsMigrationLocks);

  group('adoption — an orphan with no Game Day doc', () {
    test('is ADOPTED as a Game Day team, not dropped', () async {
      final fs = FakeFirebaseFirestore();
      await _seedUser(fs);
      final h = _migratorFor(fs, legacy: [_legacy()]);

      await h.migrator.ensureMigrated(uid);

      expect(await _gdDoc(fs, 'nfl_chiefs'), isNotNull);
    });

    // The shape migrationConfigsFor produces: monitored, but invisible to the
    // server planner, so adoption can never light a house on its own.
    test('is adopted MONITORING-ONLY — autopilot off, live scoring on',
        () async {
      final fs = FakeFirebaseFirestore();
      await _seedUser(fs);
      final h = _migratorFor(fs, legacy: [_legacy()]);

      await h.migrator.ensureMigrated(uid);

      final doc = await _gdDoc(fs, 'nfl_chiefs');
      expect(doc!['enabled'], isFalse, reason: 'no lighting the user did not ask for');
      expect(doc['live_scoring_enabled'], isTrue);
      expect(doc['score_celebration_enabled'], isTrue);
    });

    test('carries the sensitivity the user had tuned', () async {
      final fs = FakeFirebaseFirestore();
      await _seedUser(fs);
      final h = _migratorFor(
          fs, legacy: [_legacy(sensitivity: AlertSensitivity.clutchOnly)]);

      await h.migrator.ensureMigrated(uid);

      expect((await _gdDoc(fs, 'nfl_chiefs'))!['alert_sensitivity'],
          'clutchOnly');
    });

    test('gets real team metadata, not the slug as a name', () async {
      final fs = FakeFirebaseFirestore();
      await _seedUser(fs);
      final h = _migratorFor(fs, legacy: [_legacy()]);

      await h.migrator.ensureMigrated(uid);

      final doc = await _gdDoc(fs, 'nfl_chiefs');
      expect(doc!['team_name'], 'Kansas City Chiefs');
      expect(doc['espn_team_id'], isNot(''));
    });

    // STEP F: the adopted team must be VISIBLE, not a doc nothing lists. The
    // profile arrays are what My Teams renders from.
    test('lands on the profile arrays so a team card renders', () async {
      final fs = FakeFirebaseFirestore();
      await _seedUser(fs);
      final h = _migratorFor(fs, legacy: [_legacy()]);

      await h.migrator.ensureMigrated(uid);

      final profile = (await fs.collection('users').doc(uid).get()).data()!;
      expect(profile['sports_teams'], contains('Kansas City Chiefs'));
      expect(profile['sports_team_priority'], contains('Kansas City Chiefs'));
    });

    // migrationConfigsFor hardcodes liveScoringEnabled:true for EVERY orphan,
    // including ones the user had switched off. Adopting that verbatim would
    // silently re-arm alerts they turned off.
    test('a DISABLED orphan is still surfaced, but with alerts left off',
        () async {
      final fs = FakeFirebaseFirestore();
      await _seedUser(fs);
      final h = _migratorFor(fs, legacy: [_legacy(enabled: false)]);

      await h.migrator.ensureMigrated(uid);

      final doc = await _gdDoc(fs, 'nfl_chiefs');
      expect(doc, isNotNull, reason: 'surfaced, not silently dropped');
      expect(doc!['live_scoring_enabled'], isFalse);
    });

    test('a slug absent from kTeamColors is skipped, not written', () async {
      final fs = FakeFirebaseFirestore();
      await _seedUser(fs);
      final h = _migratorFor(fs, legacy: [_legacy(slug: 'not_a_real_team')]);

      await h.migrator.ensureMigrated(uid);

      expect(await _gdDoc(fs, 'not_a_real_team'), isNull);
    });
  });

  group('reconciliation — an orphan WITH a matching Game Day doc', () {
    test('leaves the existing config untouched', () async {
      final fs = FakeFirebaseFirestore();
      await _seedUser(fs, sportsTeams: ['Kansas City Chiefs']);
      // The user's real Game Day config: autopilot ON, alerts deliberately OFF.
      await fs
          .collection('users')
          .doc(uid)
          .collection('game_day_autopilot')
          .doc('nfl_chiefs')
          .set(GameDayAutopilotConfig(
            teamSlug: 'nfl_chiefs',
            teamName: 'Kansas City Chiefs',
            espnTeamId: '12',
            sport: SportType.nfl,
            primaryColorValue: 0xFFE31837,
            secondaryColorValue: 0xFFFFB81C,
            enabled: true,
            liveScoringEnabled: false,
            scoreCelebrationEnabled: false,
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ).toFirestore());

      final h = _migratorFor(fs, legacy: [_legacy(enabled: true)]);
      await h.migrator.ensureMigrated(uid);

      final doc = await _gdDoc(fs, 'nfl_chiefs');
      // Game Day wins: the stale prefs entry does NOT resurrect alerts.
      expect(doc!['enabled'], isTrue);
      expect(doc['live_scoring_enabled'], isFalse);
    });

    test('adopts only the uncovered team when the list is mixed', () async {
      final fs = FakeFirebaseFirestore();
      await _seedUser(fs, sportsTeams: ['Kansas City Royals']);
      await fs
          .collection('users')
          .doc(uid)
          .collection('game_day_autopilot')
          .doc('mlb_royals')
          .set(GameDayAutopilotConfig(
            teamSlug: 'mlb_royals',
            teamName: 'Kansas City Royals',
            espnTeamId: '7',
            sport: SportType.mlb,
            primaryColorValue: 0xFF004687,
            secondaryColorValue: 0xFFC09A5B,
            enabled: true,
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ).toFirestore());

      final h = _migratorFor(fs, legacy: [
        _legacy(slug: 'mlb_royals'),
        _legacy(slug: 'nfl_chiefs'),
      ]);
      await h.migrator.ensureMigrated(uid);

      expect(await _gdDoc(fs, 'nfl_chiefs'), isNotNull, reason: 'adopted');
      // Untouched — still the user's own enabled:true config.
      expect((await _gdDoc(fs, 'mlb_royals'))!['enabled'], isTrue);
    });
  });

  group('run-once semantics', () {
    test('stamps the marker so it never runs twice', () async {
      final fs = FakeFirebaseFirestore();
      await _seedUser(fs);
      final h = _migratorFor(fs, legacy: [_legacy()]);

      await h.migrator.ensureMigrated(uid);
      final profile = (await fs.collection('users').doc(uid).get()).data()!;
      expect(profile[kSportsAlertsMigratedAtField], isNotNull);

      resetSportsAlertsMigrationLocks();
      await h.migrator.ensureMigrated(uid);
      expect(h.migrator.migrationRunCount, 2, reason: 'entered twice');
      // ...but the second entry returned at the marker check.
      expect(h.store, isEmpty);
    });

    test('an already-marked account is a no-op — legacy store left alone',
        () async {
      final fs = FakeFirebaseFirestore();
      await _seedUser(fs, extra: {kSportsAlertsMigratedAtField: Timestamp.now()});
      final h = _migratorFor(fs, legacy: [_legacy()]);

      await h.migrator.ensureMigrated(uid);

      expect(await _gdDoc(fs, 'nfl_chiefs'), isNull);
      expect(h.store, hasLength(1), reason: 'not cleared — already migrated');
    });

    test('the retired store is emptied once its contents are in Firestore',
        () async {
      final fs = FakeFirebaseFirestore();
      await _seedUser(fs);
      final h = _migratorFor(fs, legacy: [_legacy()]);

      await h.migrator.ensureMigrated(uid);

      expect(h.store, isEmpty);
    });

    test('concurrent calls share ONE run', () async {
      final fs = FakeFirebaseFirestore();
      await _seedUser(fs);
      final h = _migratorFor(fs, legacy: [_legacy()]);

      await Future.wait([
        h.migrator.ensureMigrated(uid),
        h.migrator.ensureMigrated(uid),
        h.migrator.ensureMigrated(uid),
      ]);

      expect(h.migrator.migrationRunCount, 1);
    });

    test('a missing user doc is a no-op, not a crash', () async {
      final fs = FakeFirebaseFirestore();
      final h = _migratorFor(fs, legacy: [_legacy()]);

      await h.migrator.ensureMigrated('nobody');

      expect(h.store, hasLength(1));
    });

    test('an empty legacy store still marks the account migrated', () async {
      final fs = FakeFirebaseFirestore();
      await _seedUser(fs);
      final h = _migratorFor(fs);

      await h.migrator.ensureMigrated(uid);

      final profile = (await fs.collection('users').doc(uid).get()).data()!;
      expect(profile[kSportsAlertsMigratedAtField], isNotNull);
    });
  });
}
