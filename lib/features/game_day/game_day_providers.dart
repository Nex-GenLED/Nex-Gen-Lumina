import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../autopilot/game_day_autopilot_config.dart';
import '../autopilot/game_day_autopilot_providers.dart';
import '../site/user_profile_providers.dart';
import '../../app_providers.dart' show appForegroundProvider;
import '../sports_alerts/data/team_colors.dart';
import '../sports_alerts/models/game_state.dart';
import '../sports_alerts/models/sport_type.dart';
import '../sports_alerts/services/espn_api_service.dart';
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

// ── Live score badge (Game Day card) ────────────────────────────────────────

/// Poll cadence for the Game Day card's live score badge while a game is live.
/// 30s matches the celebration coordinator's ESPN cadence.
const Duration kLiveScoreRefreshInterval = Duration(seconds: 30);

/// How long to wait before re-fetching the score badge, or null to STOP.
///
/// Pure + unit-tested. Polls ONLY while the game is actively live AND the app
/// is foregrounded — no orphaned timers pre/post game or in the background.
Duration? liveScoreRefreshInterval({
  required GameState? game,
  required bool appForeground,
}) {
  if (!appForeground || game == null) return null;
  final isLive = game.status == GameStatus.inProgress ||
      game.status == GameStatus.halftime;
  return isLive ? kLiveScoreRefreshInterval : null;
}

/// Test seam: how the badge fetches a team's current game. Defaults to a
/// one-shot ESPN scoreboard read (the same call the phase machine uses).
final liveScoreFetcherProvider =
    Provider<Future<GameState?> Function(String teamSlug)>((ref) {
  return (teamSlug) async {
    final teamInfo = kTeamColors[teamSlug];
    if (teamInfo == null) return null;
    final espnApi = EspnApiService();
    try {
      return await espnApi.fetchTeamGame(teamInfo.sport, teamInfo.espnTeamId);
    } finally {
      espnApi.dispose();
    }
  };
});

/// Overridable poll interval so tests don't wait 30s.
final liveScorePollIntervalProvider =
    Provider<Duration>((ref) => kLiveScoreRefreshInterval);

/// Live-updating game state for the Game Day card's score badge (also used for
/// the card's live/final treatment).
///
/// WAS a one-shot `FutureProvider` that snapshotted the score at card build and
/// never refreshed — the badge froze at whatever it read on load ("0 - 0" /
/// "Today") and never showed the live score. It is now a self-polling stream:
/// fetch → emit → re-fetch every [liveScorePollIntervalProvider], but ONLY
/// while the game is live AND the app is foregrounded ([liveScoreRefreshInterval]).
/// It stops otherwise, `autoDispose` stops it when the card scrolls off-screen,
/// and a background→foreground flip re-runs it (it watches [appForegroundProvider])
/// so polling resumes — no orphaned timers, no background ESPN traffic.
///
/// I chose this live-gated self-poll over pointing the badge at the celebration
/// coordinator's ScoreMonitorService: the coordinator only polls when
/// celebrations are ARMED (config enabled + `scoreCelebrationEnabled` +
/// foreground), so a user who turned celebrations OFF — or a team with no
/// autopilot config — would see a frozen badge again. The badge must show the
/// score independently of the celebration toggle, so it owns its own cadence.
final upcomingGameProvider =
    StreamProvider.autoDispose.family<GameState?, String>((ref, teamSlug) async* {
  final fetch = ref.watch(liveScoreFetcherProvider);
  final interval = ref.watch(liveScorePollIntervalProvider);
  // Watched at the top: a foreground flip re-runs the whole provider — background
  // ends the loop, resume restarts it.
  final foreground = ref.watch(appForegroundProvider);

  while (true) {
    GameState? game;
    try {
      game = await fetch(teamSlug);
    } catch (_) {
      game = null;
    }
    yield game;
    if (liveScoreRefreshInterval(game: game, appForeground: foreground) == null) {
      return; // not live or backgrounded → stop polling
    }
    await Future<void>.delayed(interval);
  }
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
