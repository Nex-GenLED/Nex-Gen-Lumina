import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../autopilot/game_day_autopilot_config.dart';
import '../autopilot/game_day_autopilot_providers.dart';
import '../site/user_profile_providers.dart';
import '../sports_alerts/data/team_colors.dart';
import '../sports_alerts/models/game_state.dart';
import '../sports_alerts/models/sport_type.dart';
import '../sports_alerts/providers/sports_alert_providers.dart';
import 'game_day_crew_models.dart';
import 'game_day_crew_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Service singleton
// ─────────────────────────────────────────────────────────────────────────────

final gameDayCrewServiceProvider = Provider<GameDayCrewService>((ref) {
  return GameDayCrewService();
});

// ─────────────────────────────────────────────────────────────────────────────
// Streams
// ─────────────────────────────────────────────────────────────────────────────

/// All crews the current user belongs to (as host or member).
final userCrewsProvider = StreamProvider<List<GameDayCrew>>((ref) {
  final service = ref.watch(gameDayCrewServiceProvider);
  return service.watchUserCrews();
});

/// Stream a single crew by ID.
final crewByIdProvider =
    StreamProvider.family<GameDayCrew?, String>((ref, crewId) {
  final service = ref.watch(gameDayCrewServiceProvider);
  return service.watchCrew(crewId);
});

// ─────────────────────────────────────────────────────────────────────────────
// Derived state
// ─────────────────────────────────────────────────────────────────────────────

/// Crew for a specific team (if user is in one).
final crewForTeamProvider =
    FutureProvider.family<GameDayCrew?, String>((ref, teamSlug) async {
  final service = ref.watch(gameDayCrewServiceProvider);
  return service.getCrewForTeam(teamSlug);
});

/// Whether the current user is host of a given crew.
final isCrewHostProvider = Provider.family<bool, String>((ref, crewId) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return false;
  final crews = ref.watch(userCrewsProvider).valueOrNull ?? [];
  final crew = crews.where((c) => c.id == crewId).firstOrNull;
  return crew?.isHost(uid) ?? false;
});

/// Combined view: user's individual Game Day autopilot configs + crew status.
/// This is the primary data source for the Game Day screen.
///
/// Source of truth: the authenticated user's Firestore profile document
/// (`sports_team_priority` / `sports_teams`). A Game Day autopilot config
/// is only surfaced if the user has explicitly selected that team in their
/// profile. No fallbacks, defaults, or geo-based suggestions — orphaned
/// subcollection docs from prior sessions are ignored.
final gameDayTeamsProvider =
    Provider<List<GameDayTeamEntry>>((ref) {
  final configs =
      ref.watch(gameDayAutopilotConfigsProvider).valueOrNull ?? [];
  final crews = ref.watch(userCrewsProvider).valueOrNull ?? [];
  final uid = FirebaseAuth.instance.currentUser?.uid;
  final profile = ref.watch(currentUserProfileProvider).valueOrNull;

  final selectedTokens = <String>{
    ...?profile?.sportsTeamPriority,
    ...?profile?.sportsTeams,
  }
      .map((s) => s.trim().toLowerCase())
      .where((s) => s.isNotEmpty)
      .toSet();

  if (selectedTokens.isEmpty) return const [];

  final entries = <GameDayTeamEntry>[];

  for (final config in configs) {
    final configName = config.teamName.toLowerCase();
    final configSlug = config.teamSlug.toLowerCase();
    final matches = selectedTokens.any((token) =>
        configName.contains(token) ||
        token.contains(configName) ||
        configSlug.endsWith(token.replaceAll(' ', '_')));
    if (!matches) continue;

    // Find if user is in a crew for this team.
    final crew = crews
        .where((c) => c.teamSlug == config.teamSlug)
        .firstOrNull;

    entries.add(GameDayTeamEntry(
      config: config,
      crew: crew,
      isHost: crew != null && uid != null && crew.isHost(uid),
    ));
  }

  return entries;
});

/// Check if a game exists within 24h for a given team slug.
/// Used by both the Game Day screen and the explore flow prompt.
final upcomingGameProvider =
    FutureProvider.family<GameState?, String>((ref, teamSlug) async {
  return ref.watch(activeGameProvider(teamSlug).future);
});

// ─────────────────────────────────────────────────────────────────────────────
// Team search for add-team flow
// ─────────────────────────────────────────────────────────────────────────────

final gameDayTeamSearchProvider = StateProvider<String>((ref) => '');

final gameDayFilteredTeamsProvider =
    Provider<List<MapEntry<String, TeamColors>>>((ref) {
  final query = ref.watch(gameDayTeamSearchProvider).toLowerCase();
  if (query.isEmpty) {
    return kTeamColors.entries.toList()
      ..sort((a, b) => a.value.teamName.compareTo(b.value.teamName));
  }
  return kTeamColors.entries
      .where((e) =>
          e.value.teamName.toLowerCase().contains(query) ||
          e.key.toLowerCase().contains(query) ||
          e.value.sport.displayName.toLowerCase().contains(query))
      .toList()
    ..sort((a, b) => a.value.teamName.compareTo(b.value.teamName));
});

// ─────────────────────────────────────────────────────────────────────────────
// View model
// ─────────────────────────────────────────────────────────────────────────────

/// Combined entry representing one team on the Game Day screen.
class GameDayTeamEntry {
  final GameDayAutopilotConfig config;
  final GameDayCrew? crew;
  final bool isHost;

  const GameDayTeamEntry({
    required this.config,
    this.crew,
    this.isHost = false,
  });

  bool get hasCrew => crew != null;
  bool get isCrewMember => hasCrew && !isHost;
}
