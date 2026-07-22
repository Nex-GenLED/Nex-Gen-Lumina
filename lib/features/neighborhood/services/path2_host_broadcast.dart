// lib/features/neighborhood/services/path2_host_broadcast.dart
//
// Convergence-Phase-2 (additive) host-broadcast orchestrator.
//
// Gives [GroupAutopilotService.configureForTeam] its first production
// caller — the host's "Set Game Day for Whole Neighborhood" button.
//
// Policy: the host broadcast must use the canonical Path 1
// [GameDayAutopilotConfig]. Shallow in-memory GameDaySyncConfigs do not
// participate — members never receive a partial config. If the host
// has no Path 1 set up for the team, this helper returns
// [Path2HostBroadcastNeedsPath1Setup] and the UI deep-links into Path 1
// setup before allowing the broadcast.
//
// Riverpod-free + Firebase-free by design: the configureForTeam call is
// passed in as a typedef-shaped callback so this orchestrator is fully
// unit-testable. Production wires it to
// `ref.read(groupAutopilotServiceProvider).configureForTeam`.

import '../../autopilot/game_day_autopilot_config.dart';
import '../models/group_game_day_autopilot.dart';

/// Shape of [GroupAutopilotService.configureForTeam], lifted to a top-
/// level typedef so this file does not depend on the service class.
typedef ConfigureForTeamCall = Future<GroupGameDayAutopilot> Function({
  required String groupId,
  required GameDayAutopilotConfig sourceConfig,
  DateTime? now,
});

/// Outcome of a host broadcast attempt. The Phase 2 UI branches on the
/// subtype to render the success / setup-required / error snackbar.
sealed class Path2HostBroadcastResult {
  const Path2HostBroadcastResult();
}

/// configureForTeam returned successfully. The assembled document
/// reflects the activeMemberIds the service stamped at write time.
class Path2HostBroadcastSucceeded extends Path2HostBroadcastResult {
  final GroupGameDayAutopilot assembled;
  const Path2HostBroadcastSucceeded(this.assembled);
}

/// No Path 1 [GameDayAutopilotConfig] exists for the team — the host
/// must complete Path 1 setup before broadcasting. Carries the team
/// slug so the UI can deep-link straight into the right team's setup.
class Path2HostBroadcastNeedsPath1Setup extends Path2HostBroadcastResult {
  final String teamSlug;
  const Path2HostBroadcastNeedsPath1Setup(this.teamSlug);
}

/// configureForTeam threw — surface the error to the UI for a snackbar.
class Path2HostBroadcastFailed extends Path2HostBroadcastResult {
  final Object error;
  const Path2HostBroadcastFailed(this.error);
}

/// Host-broadcast entry point. Assembles + persists a
/// [GroupGameDayAutopilot] derived from the host's Path 1 config.
///
/// Pure orchestration — caller resolves the Path 1 config via Riverpod
/// (or a test fixture) and passes it explicitly so this function has
/// no Riverpod dependency.
///
/// Returns:
///   - [Path2HostBroadcastNeedsPath1Setup] when [path1Config] is null
///     (no Path 1 set up yet).
///   - [Path2HostBroadcastSucceeded] on a successful write.
///   - [Path2HostBroadcastFailed] when configureForTeam throws.
Future<Path2HostBroadcastResult> broadcastPath1ToGroup({
  required ConfigureForTeamCall configureForTeam,
  required String groupId,
  required String teamSlug,
  required GameDayAutopilotConfig? path1Config,
  DateTime? now,
}) async {
  if (path1Config == null) {
    return Path2HostBroadcastNeedsPath1Setup(teamSlug);
  }
  try {
    final assembled = await configureForTeam(
      groupId: groupId,
      sourceConfig: path1Config,
      now: now,
    );
    return Path2HostBroadcastSucceeded(assembled);
  } catch (e) {
    return Path2HostBroadcastFailed(e);
  }
}
