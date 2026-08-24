// Live game state for a team.
//
// WHAT USED TO BE HERE. This file also held `sportsAlertConfigsProvider` (the
// SharedPreferences-backed alert list), `sportsAlertActiveProvider`, and the
// team-picker search providers. All of them served the retired Sports Alerts
// screen — a surface backed by a device-local store that no Game Day write ever
// touched, which is what let a deleted team keep celebrating and a newly added
// team never appear (audit/SPORTS_ALERTS_SYNC_AUDIT.md §4.1-4.3). Alert
// settings now live on the Game Day team card, backed by the
// `game_day_autopilot` Firestore doc, and Game Day is the only store.
//
// `activeGameProvider` survives because it is not part of that store: it is a
// live ESPN fetch keyed by team slug, used by the post-apply Live Scoring
// prompt.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/team_colors.dart';
import '../models/game_state.dart';
import '../services/espn_api_service.dart';

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
