// lib/features/sports_alerts/services/foreground_celebration_providers.dart
//
// Wiring for FOREGROUND score celebrations. Delivery goes through the modern
// apply chokepoint (wledRepositoryProvider) — LAN and relay, multi-bus correct
// via applyChannelFilter — NOT the dead direct-IP AlertTriggerService path.
//
// The driver derives "live celebration teams" from the Game Day phase machine
// (teams in liveGame) ∩ their GameDayAutopilotConfig (enabled &&
// scoreCelebrationEnabled). Kept alive + fed the foreground signal by
// main_scaffold. No polling outside a live game or while backgrounded.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../autopilot/game_day_autopilot_config.dart'
    show GameDayAutopilotConfig;
import '../../autopilot/game_day_autopilot_providers.dart'
    show enabledAutopilotConfigsProvider, gameDayAutopilotNotifierProvider;
import '../../autopilot/game_day_autopilot_service.dart'
    show AutopilotSession, AutopilotSessionPhase;
import '../../game_day/ephemeral_session/ephemeral_game_session.dart'
    show EphemeralGameSession, EphemeralSessionPhase;
import '../../game_day/ephemeral_session/ephemeral_game_session_providers.dart'
    show activeEphemeralSessionsProvider;
import '../../wled/wled_payload_utils.dart' show applyChannelFilter;
import '../../wled/wled_providers.dart' show wledRepositoryProvider;
import '../../wled/zone_providers.dart' show deviceChannelsProvider;
import '../models/score_alert_config.dart';
import 'alert_trigger_service.dart' show AlertAnimationStep;
import 'foreground_celebration_coordinator.dart';
import 'score_monitor_service.dart';

/// Real delivery: capture live state, play channel-filtered flash steps, revert
/// — all through [wledRepositoryProvider] so it works on LAN and via the cloud
/// relay, and fans out across every configured channel (bus).
class WledCelebrationDelivery implements CelebrationDelivery {
  WledCelebrationDelivery(this._ref);
  final Ref _ref;

  @override
  Future<Map<String, dynamic>?> capture() async {
    final repo = _ref.read(wledRepositoryProvider);
    if (repo == null) return null;
    return repo.getState();
  }

  @override
  Future<void> play(List<AlertAnimationStep> steps) async {
    final repo = _ref.read(wledRepositoryProvider);
    if (repo == null) return;
    final channels = _ref.read(deviceChannelsProvider);
    final ids = channels.map((c) => c.id).toList();
    for (final step in steps) {
      final payload = applyChannelFilter(step.payload, ids, channels);
      await repo.applyJson(payload);
      await Future<void>.delayed(step.hold);
    }
  }

  @override
  Future<void> revert(Map<String, dynamic> captured) async {
    final repo = _ref.read(wledRepositoryProvider);
    if (repo == null) return;
    // If a preset was active, reloading it is the cleanest restore.
    final ps = captured['ps'];
    if (ps is int && ps >= 0) {
      await repo.applyJson({'ps': ps});
      return;
    }
    // Otherwise restore on/bri/seg — this lands back on whatever the phase
    // machine had active (the team design) seamlessly.
    final restore = <String, dynamic>{
      if (captured['on'] != null) 'on': captured['on'],
      if (captured['bri'] != null) 'bri': captured['bri'],
      if (captured['seg'] != null) 'seg': captured['seg'],
    };
    if (restore.isNotEmpty) await repo.applyJson(restore);
  }
}

/// Singleton coordinator. Uses the reused [ScoreMonitorService] diff engine and
/// the [WledCelebrationDelivery]. Disposed with the container.
final foregroundCelebrationCoordinatorProvider =
    Provider<ForegroundCelebrationCoordinator>((ref) {
  final coordinator = ForegroundCelebrationCoordinator(
    monitor: ScoreMonitorService(),
    delivery: WledCelebrationDelivery(ref),
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

/// Teams currently in a liveGame phase whose Game Day config has celebrations
/// enabled. Empty → no polling. Respects the existing per-team
/// `scoreCelebrationEnabled` toggle (default ON) — no parallel setting invented.
///
/// Reads BOTH Game Day phase machines — see [computeLiveCelebrationTeams] for
/// why the ephemeral one has to be unioned in.
final liveCelebrationTeamsProvider = Provider<List<CelebrationTeam>>((ref) {
  return computeLiveCelebrationTeams(
    sessions: ref.watch(gameDayAutopilotNotifierProvider),
    ephemeralSessions:
        ref.watch(activeEphemeralSessionsProvider).valueOrNull ?? const [],
    configs: ref.watch(enabledAutopilotConfigsProvider),
  );
});

/// Pure derivation (unit-tested): a team celebrates iff it is in a liveGame
/// phase in EITHER Game Day phase machine AND its Game Day config is enabled
/// with `scoreCelebrationEnabled`. Sensitivity is [AlertSensitivity.allEvents]
/// — celebrate every score the per-sport diff engine emits (it already
/// throttles high-frequency leagues: NBA/NCAA-MB emit clutch only).
///
/// ── WHY TWO SOURCES (#54 union — delete deliberately, do not resurrect) ──────
/// The app has TWO Game Day phase machines with two separate enums:
///   • autopilot [gameDayAutopilotNotifierProvider] → [AutopilotSessionPhase],
///     calendar-scheduled, and it only ARMS via a 30-min pre-game window
///     (evaluateConfigs → hasGameSoon). It never reaches liveGame on a mid-game
///     cold open.
///   • ephemeral [activeEphemeralSessionsProvider] → [EphemeralSessionPhase],
///     the one-shot live session that catches in-progress joins directly
///     (ephemeral_game_session_service.dart idle→liveGame). This is what lights
///     the lights when a user opens the app because the game is already on.
/// Reading ONLY autopilot meant celebrations NEVER fired in the real world —
/// the machine that lit the lights was invisible to the coordinator. We union
/// both live sets here as the surgical fix. #54 consolidates the two machines
/// into one; when it lands, REMOVE the ephemeral loop deliberately as part of
/// that unification — do NOT quietly drop back to a single-source read, which
/// is exactly the bug this union closes.
List<CelebrationTeam> computeLiveCelebrationTeams({
  required Map<String, AutopilotSession> sessions,
  required List<EphemeralGameSession> ephemeralSessions,
  required List<GameDayAutopilotConfig> configs,
}) {
  // Union the live team slugs from both phase machines. A Set collapses a team
  // that is live in BOTH machines to a single slug, so the emission below can
  // never yield two entries for it (no double-poll, no stacked celebration).
  final liveSlugs = <String>{
    for (final s in sessions.values)
      if (s.phase == AutopilotSessionPhase.liveGame) s.teamSlug,
    for (final e in ephemeralSessions)
      if (e.phase == EphemeralSessionPhase.liveGame) e.teamSlug,
  };
  if (liveSlugs.isEmpty) return const [];

  // Config still gates (enabled + scoreCelebrationEnabled) and supplies the
  // sport. `seen` dedupes defensively in case configs ever carries a duplicate
  // slug — one CelebrationTeam per team, period.
  final seen = <String>{};
  return [
    for (final cfg in configs)
      if (cfg.enabled &&
          cfg.scoreCelebrationEnabled &&
          liveSlugs.contains(cfg.teamSlug) &&
          seen.add(cfg.teamSlug))
        CelebrationTeam(
          teamSlug: cfg.teamSlug,
          sport: cfg.sport,
          sensitivity: AlertSensitivity.allEvents,
        ),
  ];
}

/// Side-effect driver: pushes the live-team set into the coordinator whenever it
/// changes. Watch from a persistent surface (main_scaffold) to keep it alive;
/// the coordinator itself starts/stops polling based on the set + foreground
/// signal ([ForegroundCelebrationCoordinator.setForeground]).
final foregroundCelebrationControllerProvider = Provider<void>((ref) {
  final teams = ref.watch(liveCelebrationTeamsProvider);
  ref.read(foregroundCelebrationCoordinatorProvider).syncLiveTeams(teams);
});
