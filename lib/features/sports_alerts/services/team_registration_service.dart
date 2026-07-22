// lib/features/sports_alerts/services/team_registration_service.dart
//
// Shared add/remove vehicle for a user's Game Day team selections.
//
// Owns the canonical write contract — every code path that adds or
// removes a team for a user (Game Day picker, Path 1 setup, installer
// handoff) should go through this service so the subcollection doc, the
// profile arrays, and the Explore "My Teams" cache stay in lockstep.
//
// Step 1 ships the service standalone. Callers continue to use the
// inline body in [GameDayAutopilotNotifier.toggleAutopilot] until
// Step 2 repoints them; no behavior change yet.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/team_color_resolver.dart';
import '../../autopilot/game_day_autopilot_config.dart';
import '../data/team_colors.dart';

class TeamRegistrationService {
  TeamRegistrationService({
    FirebaseFirestore? firestore,
    this.onTeamsChanged,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Cache-invalidation seam. Step 4 wires this from
  /// [patternRepositoryProvider] so adding/removing a team rebuilds the
  /// Explore "My Teams" folder without a profile-stream round-trip.
  /// Null in Step 1 (no caller yet); the service still works.
  void Function()? onTeamsChanged;

  /// Add a team for [uid]. Writes BOTH:
  ///   • /users/{uid}/game_day_autopilot/{teamSlug}  (enabled:false)
  ///   • /users/{uid}.sports_teams[]
  ///   • /users/{uid}.sports_team_priority[]
  ///
  /// `enabled:false` is intentional: the product decision is "adding a
  /// team does NOT auto-enable autopilot." Toggle ON happens through the
  /// notifier's enable path (Step 2 repoint), which can flip the field.
  ///
  /// If the team doc already exists this is a no-op for the subcollection
  /// (preserves any existing enabled/saved-design state) but still ensures
  /// the profile arrays carry the team name.
  ///
  /// Throws [ArgumentError] if [teamSlug] is not in [kTeamColors].
  /// Rethrows Firestore errors.
  Future<void> addTeam({
    required String uid,
    required String teamSlug,
  }) async {
    final team = kTeamColors[teamSlug];
    if (team == null) {
      throw ArgumentError.value(
        teamSlug,
        'teamSlug',
        'Unknown team — not in kTeamColors',
      );
    }

    final docRef = _firestore
        .collection('users')
        .doc(uid)
        .collection('game_day_autopilot')
        .doc(teamSlug);

    final existing = await docRef.get();
    final now = DateTime.now();

    if (!existing.exists) {
      final fresh = GameDayAutopilotConfig(
        teamSlug: teamSlug,
        teamName: team.teamName,
        espnTeamId: team.espnTeamId,
        sport: team.sport,
        primaryColorValue: team.primary.toARGB32(),
        secondaryColorValue: team.secondary.toARGB32(),
        enabled: false,
        createdAt: now,
        updatedAt: now,
      );
      await docRef.set(fresh.toFirestore());
    }

    await _appendTeamToProfile(uid, team.teamName);

    onTeamsChanged?.call();
  }

  /// Remove a team for [uid]. Inverts [addTeam]:
  ///   • strips [teamName] from sports_teams[] / sports_team_priority[]
  ///     (case-insensitive)
  ///   • deletes /users/{uid}/game_day_autopilot/{teamSlug}
  ///
  /// Does NOT cancel any live session or mutate notifier state — those
  /// are orchestration concerns that stay in the notifier wrapper.
  ///
  /// Profile writes propagate errors; subcollection delete is best-effort
  /// (logged on failure) — same posture as the canonical removeTeam.
  ///
  /// Throws [StateError] if [uid] is empty.
  Future<void> removeTeam({
    required String uid,
    required String teamSlug,
    required String teamName,
  }) async {
    if (uid.isEmpty) {
      throw StateError('TeamRegistrationService.removeTeam: empty uid');
    }

    await _stripTeamFromProfile(uid, teamName);

    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('game_day_autopilot')
          .doc(teamSlug)
          .delete();
    } catch (e) {
      debugPrint('[TeamRegistrationService] delete config $teamSlug failed: $e');
    }

    onTeamsChanged?.call();
  }

  /// Bridge free-text team input (installer handoff, chat, etc.) to a
  /// [kTeamColors] slug. Returns null when:
  ///   • the resolver finds no candidate
  ///   • the best candidate is below 0.8 confidence
  ///   • the resolved official name doesn't map to any kTeamColors entry
  ///
  /// The resolver is the [TeamColorDatabase] (155-team unified index with
  /// aliases + fuzzy matching). [kTeamColors] is a separate, slug-keyed
  /// map used by the autopilot subcollection. This bridge matches the
  /// resolver's `officialName` against `kTeamColors[*].teamName`
  /// (case-insensitive). Null results should be surfaced to telemetry by
  /// the caller — they're "custom teams" that the v1.0.1 local-discovery
  /// flow will handle.
  ///
  /// Pure static — no Firestore, no scaffold required to test.
  static String? resolveFreeTextToKTeamSlug(
    String raw, {
    List<String>? userTeams,
  }) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final result = TeamColorResolver.resolve(trimmed, userTeams: userTeams);
    if (result == null || !result.resolved) return null;
    if (!result.isHighConfidence) return null;

    final officialLower = result.team.officialName.toLowerCase();
    for (final entry in kTeamColors.entries) {
      if (entry.value.teamName.toLowerCase() == officialLower) {
        return entry.key;
      }
    }
    return null;
  }

  // ── Internal: profile-array writes ────────────────────────────────────

  /// Appends [teamName] to sports_team_priority and sports_teams arrays
  /// (case-insensitive dedupe). Mirrors the canonical
  /// [GameDayAutopilotNotifier._addTeamToProfile].
  Future<void> _appendTeamToProfile(String uid, String teamName) async {
    final profileRef = _firestore.collection('users').doc(uid);
    final snap = await profileRef.get();
    final data = snap.data() ?? const <String, dynamic>{};
    final priority = _asStringList(data['sports_team_priority']);
    final teams = _asStringList(data['sports_teams']);
    final key = teamName.trim().toLowerCase();

    final updates = <String, dynamic>{};
    if (!priority.any((t) => t.trim().toLowerCase() == key)) {
      updates['sports_team_priority'] = [...priority, teamName];
    }
    if (!teams.any((t) => t.trim().toLowerCase() == key)) {
      updates['sports_teams'] = [...teams, teamName];
    }
    if (updates.isEmpty) return;
    updates['updated_at'] = Timestamp.fromDate(DateTime.now());
    await profileRef.set(updates, SetOptions(merge: true));
  }

  /// Removes [teamName] from sports_team_priority and sports_teams arrays
  /// (case-insensitive match). No-op if absent. Mirrors the canonical
  /// [GameDayAutopilotNotifier._removeTeamFromProfile].
  Future<void> _stripTeamFromProfile(String uid, String teamName) async {
    final profileRef = _firestore.collection('users').doc(uid);
    final snap = await profileRef.get();
    final data = snap.data() ?? const <String, dynamic>{};
    final priority = _asStringList(data['sports_team_priority']);
    final teams = _asStringList(data['sports_teams']);
    final key = teamName.trim().toLowerCase();

    final newPriority =
        priority.where((t) => t.trim().toLowerCase() != key).toList();
    final newTeams = teams.where((t) => t.trim().toLowerCase() != key).toList();

    final updates = <String, dynamic>{};
    if (newPriority.length != priority.length) {
      updates['sports_team_priority'] = newPriority;
    }
    if (newTeams.length != teams.length) {
      updates['sports_teams'] = newTeams;
    }
    if (updates.isEmpty) return;
    updates['updated_at'] = Timestamp.fromDate(DateTime.now());
    await profileRef.set(updates, SetOptions(merge: true));
  }

  static List<String> _asStringList(dynamic raw) =>
      (raw as List?)?.map((e) => e.toString()).toList() ?? <String>[];
}

/// Riverpod provider for [TeamRegistrationService]. Default-constructed
/// against the live Firestore instance; tests can override the provider
/// with a service backed by FakeFirebaseFirestore.
final teamRegistrationServiceProvider =
    Provider<TeamRegistrationService>((ref) => TeamRegistrationService());
