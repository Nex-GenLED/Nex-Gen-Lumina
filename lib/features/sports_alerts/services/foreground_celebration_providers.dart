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

/// Teams currently in the liveGame phase whose Game Day config has celebrations
/// enabled. Empty → no polling. Respects the existing per-team
/// `scoreCelebrationEnabled` toggle (default ON) — no parallel setting invented.
final liveCelebrationTeamsProvider = Provider<List<CelebrationTeam>>((ref) {
  return computeLiveCelebrationTeams(
    sessions: ref.watch(gameDayAutopilotNotifierProvider),
    configs: ref.watch(enabledAutopilotConfigsProvider),
  );
});

/// Pure derivation (unit-tested): a team celebrates iff it is in the liveGame
/// phase AND its Game Day config is enabled with `scoreCelebrationEnabled`.
/// Sensitivity is [AlertSensitivity.allEvents] — celebrate every score the
/// per-sport diff engine emits (it already throttles high-frequency leagues:
/// NBA/NCAA-MB emit clutch only).
List<CelebrationTeam> computeLiveCelebrationTeams({
  required Map<String, AutopilotSession> sessions,
  required List<GameDayAutopilotConfig> configs,
}) {
  final liveSlugs = <String>{
    for (final s in sessions.values)
      if (s.phase == AutopilotSessionPhase.liveGame) s.teamSlug,
  };
  if (liveSlugs.isEmpty) return const [];

  return [
    for (final cfg in configs)
      if (cfg.enabled &&
          cfg.scoreCelebrationEnabled &&
          liveSlugs.contains(cfg.teamSlug))
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
