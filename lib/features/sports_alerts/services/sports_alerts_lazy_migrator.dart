// lib/features/sports_alerts/services/sports_alerts_lazy_migrator.dart
//
// One-time adoption of the retired Sports Alerts store into Game Day.
//
// WHY THIS EXISTS. Sports Alerts kept its teams in a device-local
// SharedPreferences list (`sports_alert_configs`) that no Game Day write ever
// touched — see audit/SPORTS_ALERTS_SYNC_AUDIT.md §4.1-4.3. That disjoint store
// is what let a deleted team keep celebrating and a newly added team never
// appear. `migrationConfigsFor` (unified_monitoring.dart:141) was written and
// unit-tested to adopt those orphans into Game Day, but had NO production
// caller (audit §4.2, item 2), so the migration it describes never ran. This
// wires it.
//
// PATTERN. Deliberately a copy of ScheduleLazyMigrator
// (features/schedule/data/schedule_lazy_migrator.dart) — the codebase's
// established one-time-migration shape:
//   • a durable marker field on the user doc gates the run,
//   • a module-level in-flight map dedups concurrent same-session calls,
//   • it is triggered from the data-read provider, before the read,
//   • the marker is stamped LAST so a mid-migration crash retries next launch.
//
// ONE-WAY. prefs → Firestore. The prefs list is the source; it is cleared once
// adopted and never written back. After this runs, Game Day is the only store.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../autopilot/game_day_autopilot_config.dart';
import '../../autopilot/game_day_background_persistence.dart';
import '../../autopilot/unified_monitoring.dart';
import '../data/team_colors.dart';
import '../models/score_alert_config.dart';
import 'sports_background_service.dart';
import 'team_registration_service.dart';

/// Field marker (camelCase) stamped on the user doc once migrated. Matches the
/// naming of [kSchedulesMigratedAtField]. Migration is gated purely on this
/// field's PRESENCE; its value is never read for logic.
const String kSportsAlertsMigratedAtField = 'sportsAlertsMigratedAt';

// Per-uid in-flight guard, module-level so it survives provider rebuilds. The
// durable guard is the marker; this only dedups concurrent same-session calls.
final Map<String, Future<void>> _migrationInFlight = <String, Future<void>>{};

@visibleForTesting
void resetSportsAlertsMigrationLocks() => _migrationInFlight.clear();

class SportsAlertsLazyMigrator {
  SportsAlertsLazyMigrator({
    required FirebaseFirestore firestore,
    TeamRegistrationService? teamRegistration,
    Future<List<ScoreAlertConfig>> Function()? loadLegacy,
    Future<void> Function()? clearLegacy,
    DateTime Function()? clock,
    Object? markerValue,
  })  : _firestore = firestore,
        _teamRegistration =
            teamRegistration ?? TeamRegistrationService(firestore: firestore),
        _loadLegacy = loadLegacy ?? loadAlertConfigs,
        _clearLegacy = clearLegacy ?? clearAlertConfigs,
        _clock = clock ?? DateTime.now,
        _markerValue = markerValue ?? FieldValue.serverTimestamp();

  final FirebaseFirestore _firestore;
  final TeamRegistrationService _teamRegistration;

  /// Reads the retired prefs store. Injected so tests need no SharedPreferences
  /// and so this stays the ONLY remaining reader of that key.
  final Future<List<ScoreAlertConfig>> Function() _loadLegacy;

  /// Empties the retired prefs store once its contents are safely in Firestore.
  final Future<void> Function() _clearLegacy;

  final DateTime Function() _clock;

  /// Defaults to a server timestamp. Overridable ONLY as a test seam —
  /// fake_cloud_firestore deadlocks a read when a serverTimestamp write races a
  /// pending transaction. Same seam, and same reason, as ScheduleLazyMigrator.
  final Object _markerValue;

  /// Test-only: how many times the migration body actually ran.
  @visibleForTesting
  int migrationRunCount = 0;

  /// Adopt [uid]'s orphaned alert configs into Game Day exactly once.
  /// Idempotent: a no-op once the marker is set. Concurrent calls share one
  /// in-flight future.
  Future<void> ensureMigrated(String uid) {
    final existing = _migrationInFlight[uid];
    if (existing != null) return existing;
    // NB: block body — an arrow `=> _migrationInFlight.remove(uid)` would
    // RETURN this very future from whenComplete, making it await itself.
    final future = _run(uid).whenComplete(() {
      _migrationInFlight.remove(uid);
    });
    _migrationInFlight[uid] = future;
    return future;
  }

  Future<void> _run(String uid) async {
    migrationRunCount++;
    final userRef = _firestore.collection('users').doc(uid);
    final snap = await userRef.get();
    if (!snap.exists) return;
    final data = snap.data()!;

    if (data[kSportsAlertsMigratedAtField] != null) return; // already migrated

    final legacy = await _loadLegacy();
    if (legacy.isNotEmpty) {
      await _adopt(uid, userRef, data, legacy);
    }

    // Clear the retired store BEFORE stamping the marker: if the clear fails we
    // have not marked the account migrated, so the next launch retries. Adoption
    // itself is idempotent (addTeam no-ops on an existing doc), so a retry
    // cannot duplicate anything.
    await _clearLegacy();
    await userRef.update({kSportsAlertsMigratedAtField: _markerValue});
    debugPrint('SportsAlertsLazyMigrator: migrated $uid onto Game Day');
  }

  Future<void> _adopt(
    String uid,
    DocumentReference<Map<String, dynamic>> userRef,
    Map<String, dynamic> profile,
    List<ScoreAlertConfig> legacy,
  ) async {
    // Reconcile against what Game Day already holds, using the SAME definition
    // of "orphan" the runtime arming path uses — resolveMonitoring — so there
    // is exactly one place that decides whether a legacy entry is covered.
    final gdSnap = await userRef.collection('game_day_autopilot').get();
    final gameDayConfigs = gdSnap.docs
        .map((d) => BackgroundGameDayAutopilotConfig.fromConfig(
              GameDayAutopilotConfig.fromFirestore(d.data()),
            ))
        .toList();

    final plan = resolveMonitoring(
      gameDayConfigs: gameDayConfigs,
      legacyAlertConfigs: legacy,
      profileTeamNames: _asStringList(profile['sports_teams']),
    );

    // An orphan WITH a matching Game Day doc never reaches here:
    // resolveMonitoring drops it from orphanedLegacy because Game Day wins, so
    // the existing doc is left exactly as the user configured it.
    if (plan.orphanedLegacy.isEmpty) return;

    final adoptions = migrationConfigsFor(
      plan.orphanedLegacy,
      now: _clock(),
      teamMetadata: _metadataFor(plan.orphanedLegacy),
    );

    // migrationConfigsFor hardcodes liveScoringEnabled:true for every orphan.
    // That is right for an orphan the user had alerts ON for, but it would
    // silently re-arm one they had turned OFF. Preserve the user's own switch.
    final wasEnabled = {
      for (final o in plan.orphanedLegacy) o.teamSlug: o.isEnabled,
    };

    for (final cfg in adoptions) {
      if (!kTeamColors.containsKey(cfg.teamSlug)) {
        // Not in the catalogue, so it has no colors, no ESPN id, and cannot be
        // rendered or polled. Both writers of the prefs store picked from
        // kTeamColors, so this is a dead entry, not a custom team.
        debugPrint('SportsAlertsLazyMigrator: skipping unknown slug '
            '"${cfg.teamSlug}" — not in kTeamColors');
        continue;
      }
      try {
        // Canonical add: creates the subcollection doc (enabled:false) AND puts
        // the team on the profile arrays, so the migrated team shows up as a
        // real Game Day team card rather than a doc nothing lists.
        await _teamRegistration.addTeam(uid: uid, teamSlug: cfg.teamSlug);

        // Then layer on the migration-specific fields addTeam does not set.
        // enabled stays false — adoption must never hand the server planner a
        // team the user did not ask to have lit.
        await userRef
            .collection('game_day_autopilot')
            .doc(cfg.teamSlug)
            .update({
          'live_scoring_enabled': wasEnabled[cfg.teamSlug] ?? true,
          'score_celebration_enabled': cfg.scoreCelebrationEnabled,
          'alert_sensitivity': cfg.alertSensitivity.toJson(),
          'updated_at': Timestamp.fromDate(_clock()),
        });
      } catch (e) {
        // Best-effort per team: one bad slug must not strand the rest, and must
        // not block the marker (a retry would re-run the whole set anyway).
        debugPrint(
            'SportsAlertsLazyMigrator: adopt ${cfg.teamSlug} failed — $e');
      }
    }
  }

  /// Colors + names for the adopted teams, so a migrated card renders properly
  /// instead of falling back to migrationConfigsFor's slug-as-name default.
  Map<String,
          ({String teamName, String espnTeamId, int primary, int secondary})>
      _metadataFor(List<ScoreAlertConfig> orphans) {
    final out = <String,
        ({
      String teamName,
      String espnTeamId,
      int primary,
      int secondary
    })>{};
    for (final o in orphans) {
      final t = kTeamColors[o.teamSlug];
      if (t == null) continue;
      out[o.teamSlug] = (
        teamName: t.teamName,
        espnTeamId: t.espnTeamId,
        primary: t.primary.toARGB32(),
        secondary: t.secondary.toARGB32(),
      );
    }
    return out;
  }

  static List<String> _asStringList(dynamic raw) =>
      (raw as List?)?.map((e) => e.toString()).toList() ?? <String>[];
}

/// Injects the migrator with the app Firestore.
final sportsAlertsLazyMigratorProvider =
    Provider<SportsAlertsLazyMigrator>((ref) {
  return SportsAlertsLazyMigrator(firestore: FirebaseFirestore.instance);
});
