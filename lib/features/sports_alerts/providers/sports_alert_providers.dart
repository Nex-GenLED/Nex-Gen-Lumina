import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/team_colors.dart';
import '../models/game_state.dart';
import '../models/score_alert_config.dart';
import '../models/sport_type.dart';
import '../services/espn_api_service.dart';
import 'sports_alert_notifier.dart';

// ---------------------------------------------------------------------------
// 1. Alert configs — CRUD via StateNotifier, persisted to SharedPreferences.
// ---------------------------------------------------------------------------

/// Provides the list of [ScoreAlertConfig]s and exposes mutation methods
/// via [SportsAlertNotifier].
final sportsAlertConfigsProvider =
    StateNotifierProvider<SportsAlertNotifier, List<ScoreAlertConfig>>(
  (ref) => SportsAlertNotifier(),
);

// ---------------------------------------------------------------------------
// 2. Active game state — fetch the current game for a given team slug.
// ---------------------------------------------------------------------------

/// Fetches the current / next [GameState] for the team identified by
/// [teamSlug].  Returns `null` when no game is found.
///
/// Usage: `ref.watch(activeGameProvider('chiefs'))`.
final activeGameProvider =
    FutureProvider.family<GameState?, String>((ref, teamSlug) async {
  final teamInfo = kTeamColors[teamSlug];
  if (teamInfo == null) return null;

  final espnApi = EspnApiService();
  try {
    return await espnApi.fetchTeamGame(
      teamInfo.sport,
      teamInfo.espnTeamId,
    );
  } finally {
    espnApi.dispose();
  }
});

// ---------------------------------------------------------------------------
// 3. Background service indicator.
// ---------------------------------------------------------------------------

/// `true` when at least one alert config is enabled (i.e. the background
/// service should be running).
final sportsAlertActiveProvider = Provider<bool>((ref) {
  final configs = ref.watch(sportsAlertConfigsProvider);
  return configs.any((c) => c.isEnabled);
});

// ---------------------------------------------------------------------------
// 4. Team search query for the team-picker UI.
// ---------------------------------------------------------------------------

/// Current search query entered in the team-picker search bar.
final teamSearchProvider = StateProvider<String>((ref) => '');

// ---------------------------------------------------------------------------
// 5. Filtered teams based on search query.
// ---------------------------------------------------------------------------

/// Filters [kTeamColors] entries by the current [teamSearchProvider] query.
///
/// Returns a list of `MapEntry<String, TeamColors>` sorted by team name,
/// matching against team name, slug, or sport display name.
final filteredTeamsProvider =
    Provider<List<MapEntry<String, TeamColors>>>((ref) {
  final query = ref.watch(teamSearchProvider).toLowerCase().trim();

  final entries = kTeamColors.entries.toList()
    ..sort((a, b) => a.value.teamName.compareTo(b.value.teamName));

  if (query.isEmpty) return entries;

  return entries.where((entry) {
    final slug = entry.key.toLowerCase();
    final name = entry.value.teamName.toLowerCase();
    final sport = entry.value.sport.displayName.toLowerCase();
    return slug.contains(query) ||
        name.contains(query) ||
        sport.contains(query);
  }).toList();
});
