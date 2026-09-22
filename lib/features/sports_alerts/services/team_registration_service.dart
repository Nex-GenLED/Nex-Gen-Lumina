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
import '../../autopilot/team_priority.dart';
import '../data/team_colors.dart';

/// Why [TeamRegistrationService.onTeamsChanged] fired.
///
/// A listener that repopulates the Game Day calendar must react to exactly one
/// of these. Adding a team already triggers its own populate at the call site;
/// reordering triggers nothing at all, which is the gap this enum closes.
enum TeamsChangedReason {
  /// A team was added or removed. The team SET changed.
  membership,

  /// The user rearranged the hierarchy. The set is identical; only the order
  /// — and therefore which team owns a shared night — changed.
  priorityReordered,
}

class TeamRegistrationService {
  TeamRegistrationService({
    FirebaseFirestore? firestore,
    this.onTeamsChanged,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Change notification for everything downstream of a team write.
  ///
  /// Originally a cache-invalidation seam for the Explore "My Teams" folder,
  /// and it still serves that. It now also carries a [TeamsChangedReason],
  /// because the Game Day screen needs to repopulate the calendar when the
  /// PRIORITY ORDER changes and must NOT repopulate when a team is merely
  /// added — `GameDayAutopilotNotifier.toggleAutopilot` already kicks off its
  /// own populate right after `addTeam`, so a reason-blind listener would run
  /// two concurrent clear-and-rewrite cycles over one calendar.
  ///
  /// Distinguishing the reason here, at the one place that knows which write
  /// just happened, is what lets a single listener be correct for all of them.
  void Function(TeamsChangedReason reason)? onTeamsChanged;

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

    await _appendTeamToProfile(uid, team.teamName, teamSlug);

    onTeamsChanged?.call(TeamsChangedReason.membership);
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

    await _stripTeamFromProfile(uid, teamName, teamSlug: teamSlug);

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

    onTeamsChanged?.call(TeamsChangedReason.membership);
  }

  /// Strip a team from the profile arrays ONLY, with no config to delete.
  ///
  /// TEAM CONSOLIDATION: for legacy free-text entries that match no catalogue
  /// team — `sports_teams[]` was unvalidated, so the fleet carries values like
  /// `"Kansas City Sporting Kansas City"` — there is no `game_day_autopilot`
  /// document and never could have been. Removing one must still clear both
  /// arrays rather than silently doing nothing.
  ///
  /// Deliberately narrow: it cannot delete a config, so it can never be used to
  /// remove a real team by the wrong route.
  Future<void> removeTeamByNameOnly({
    required String uid,
    required String teamName,
  }) async {
    if (uid.isEmpty) {
      throw StateError('TeamRegistrationService.removeTeamByNameOnly: empty uid');
    }
    await _stripTeamFromProfile(uid, teamName);
    onTeamsChanged?.call(TeamsChangedReason.membership);
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

  /// Persist a reordered hierarchy — the ONE write path both reorder
  /// surfaces use.
  ///
  /// Game Day and Edit Profile render the same control and both land here, so
  /// the display-name array and the slug array are always written from the
  /// same gesture, in the same order, in one `set(merge)`. Two separate write
  /// paths is exactly how the two screens would come to disagree about who
  /// the user's #1 team is.
  ///
  /// [entries] is the full ordered list as the user just arranged it; the two
  /// field values are derived by [alignPriorityLists].
  Future<void> setTeamPriority({
    required String uid,
    required List<TeamPriorityEntry> entries,
  }) async {
    if (uid.isEmpty) {
      throw StateError('TeamRegistrationService.setTeamPriority: empty uid');
    }
    final aligned = alignPriorityLists(entries);
    await _firestore.collection('users').doc(uid).set({
      'sports_team_priority': aligned.names,
      'game_day_team_priority': aligned.slugs,
      'updated_at': Timestamp.fromDate(DateTime.now()),
    }, SetOptions(merge: true));
    // The ONLY fire site that means "who wins tonight just changed".
    onTeamsChanged?.call(TeamsChangedReason.priorityReordered);
  }

  /// Persist a healed slug ordering WITHOUT touching the display-name array.
  ///
  /// This is the heal-on-read write, and it is deliberately narrower than
  /// [setTeamPriority]: the heal derives the slug list FROM the name list, so
  /// it has nothing new to say about names, and rewriting them would turn a
  /// read into an edit of data the user did arrange by hand.
  ///
  /// Writes only the signed-in user's own document — the caller passes their
  /// own uid. There is no bulk path and no cross-account write.
  Future<void> writeHealedGameDayPriority({
    required String uid,
    required List<String> slugs,
  }) async {
    if (uid.isEmpty) {
      throw StateError(
          'TeamRegistrationService.writeHealedGameDayPriority: empty uid');
    }
    await _firestore.collection('users').doc(uid).set({
      'game_day_team_priority': slugs,
      'updated_at': Timestamp.fromDate(DateTime.now()),
    }, SetOptions(merge: true));
  }

  /// Appends [teamName] to sports_team_priority and sports_teams arrays
  /// (case-insensitive dedupe), and [teamSlug] to game_day_team_priority.
  /// Mirrors the canonical [GameDayAutopilotNotifier._addTeamToProfile].
  ///
  /// A new team lands at the END of both lists: adding a team must never
  /// silently promote it over the one the user already ranked first.
  Future<void> _appendTeamToProfile(
    String uid,
    String teamName,
    String teamSlug,
  ) async {
    final profileRef = _firestore.collection('users').doc(uid);
    final snap = await profileRef.get();
    final data = snap.data() ?? const <String, dynamic>{};
    final priority = _asStringList(data['sports_team_priority']);
    final teams = _asStringList(data['sports_teams']);
    final slugPriority = _asStringList(data['game_day_team_priority']);
    final key = teamName.trim().toLowerCase();

    final updates = <String, dynamic>{};
    if (!priority.any((t) => t.trim().toLowerCase() == key)) {
      updates['sports_team_priority'] = [...priority, teamName];
    }
    if (!teams.any((t) => t.trim().toLowerCase() == key)) {
      updates['sports_teams'] = [...teams, teamName];
    }
    if (!slugPriority.contains(teamSlug)) {
      updates['game_day_team_priority'] = [...slugPriority, teamSlug];
    }
    if (updates.isEmpty) return;
    updates['updated_at'] = Timestamp.fromDate(DateTime.now());
    await profileRef.set(updates, SetOptions(merge: true));
  }

  /// Removes [teamName] from sports_team_priority and sports_teams arrays
  /// (case-insensitive match), and [teamSlug] from game_day_team_priority.
  /// No-op if absent. Mirrors the canonical
  /// [GameDayAutopilotNotifier._removeTeamFromProfile].
  ///
  /// [teamSlug] is null for [removeTeamByNameOnly], whose whole purpose is
  /// legacy free-text entries that never had a slug. When it is null the
  /// name is still resolved through the catalogue, so a removal that DOES
  /// correspond to a real team still cleans the slug list.
  Future<void> _stripTeamFromProfile(
    String uid,
    String teamName, {
    String? teamSlug,
  }) async {
    final profileRef = _firestore.collection('users').doc(uid);
    final snap = await profileRef.get();
    final data = snap.data() ?? const <String, dynamic>{};
    final priority = _asStringList(data['sports_team_priority']);
    final teams = _asStringList(data['sports_teams']);
    final slugPriority = _asStringList(data['game_day_team_priority']);
    final key = teamName.trim().toLowerCase();
    final slug = teamSlug ?? slugForTeamName(teamName);

    final newPriority =
        priority.where((t) => t.trim().toLowerCase() != key).toList();
    final newTeams = teams.where((t) => t.trim().toLowerCase() != key).toList();
    final newSlugPriority =
        slug == null ? slugPriority : slugPriority.where((s) => s != slug).toList();

    final updates = <String, dynamic>{};
    if (newPriority.length != priority.length) {
      updates['sports_team_priority'] = newPriority;
    }
    if (newTeams.length != teams.length) {
      updates['sports_teams'] = newTeams;
    }
    if (newSlugPriority.length != slugPriority.length) {
      updates['game_day_team_priority'] = newSlugPriority;
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
