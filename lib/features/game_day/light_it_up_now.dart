// lib/features/game_day/light_it_up_now.dart
//
// Convergence-Phase-2b orchestrator for the unified "Light it Up Now"
// button. Chains:
//
//   1. apply Path 1 config to the device via applyPayloadWithLabel
//      (the participation-respecting chokepoint — Decision 2)
//   2. if broadcastToGroup is true, also persist a [GroupGameDayAutopilot]
//      via configureForTeam (the host-broadcast path validated in 2a)
//
// The broadcast is gated on (a) the explicit host checkbox AND (b) a
// successful local apply. If the apply fails the broadcast is skipped —
// the host's lights weren't lit, so broadcasting the team to neighbors
// would be confusing. This matches Decision 1 (broadcast is never
// auto, only on explicit opt-in) AND adds the soft guard that the
// host must successfully apply locally first.
//
// Riverpod-free + Firebase-free by design: both backing calls are
// passed as typedef-shaped callbacks so the orchestrator is unit-
// testable. Production wires them to
//   ref.read(wledStateProvider.notifier).applyPayloadWithLabel
//   ref.read(groupAutopilotServiceProvider).configureForTeam

import '../autopilot/game_day_autopilot_config.dart';
import '../neighborhood/models/group_game_day_autopilot.dart';
import '../neighborhood/services/path2_host_broadcast.dart';
import '../wled/zone_providers.dart' show DeviceChannel;
import 'game_day_apply.dart';

/// Outcome of the unified Light-it-Up-Now button. The UI branches on
/// the subtype to render the appropriate snackbar.
sealed class LightItUpNowOutcome {
  const LightItUpNowOutcome();
}

/// Apply succeeded; broadcast was not requested (DECISION 1 default).
class LightItUpApplied extends LightItUpNowOutcome {
  const LightItUpApplied();
}

/// Apply AND broadcast both succeeded. Carries the assembled doc so the
/// UI can surface activeMemberIds.length in the success snackbar.
class LightItUpAppliedAndBroadcasted extends LightItUpNowOutcome {
  final GroupGameDayAutopilot assembled;
  const LightItUpAppliedAndBroadcasted(this.assembled);
}

/// applyPayloadWithLabel returned false — device write didn't take.
/// Broadcast is NOT attempted in this branch (skip-if-apply-fails).
class LightItUpApplyFailed extends LightItUpNowOutcome {
  const LightItUpApplyFailed();
}

/// Apply succeeded but the configureForTeam write threw. The host's
/// lights are lit; the group doc is not. UI should surface the error
/// so the host can retry the broadcast separately.
class LightItUpAppliedButBroadcastFailed extends LightItUpNowOutcome {
  final Object error;
  const LightItUpAppliedButBroadcastFailed(this.error);
}

/// Run the Light-it-Up-Now chain.
///
/// - [config]            : the Path 1 config to apply + broadcast.
/// - [broadcastToGroup]  : the host's explicit checkbox value
///                         (DECISION 1: caller-supplied, default false
///                         at the UI layer).
/// - [groupId]           : active neighborhood; null disables broadcast
///                         even if [broadcastToGroup] is true (defensive).
/// - [participatingChannels] / [deviceChannels] : forwarded to
///                         [applyGameDayConfigToDevice] so the local apply
///                         enumerates ALL configured channels (channel-2 fix).
Future<LightItUpNowOutcome> lightItUpNow({
  required ApplyPayloadWithLabelCall applyPayloadWithLabel,
  required ConfigureForTeamCall configureForTeam,
  required GameDayAutopilotConfig config,
  required bool broadcastToGroup,
  required String? groupId,
  required List<int> participatingChannels,
  required List<DeviceChannel> deviceChannels,
  DateTime? now,
}) async {
  final applied = await applyGameDayConfigToDevice(
    applyPayloadWithLabel: applyPayloadWithLabel,
    config: config,
    participatingChannels: participatingChannels,
    deviceChannels: deviceChannels,
  );
  if (!applied) {
    return const LightItUpApplyFailed();
  }

  // Apply succeeded. Branch on the broadcast checkbox.
  if (!broadcastToGroup || groupId == null) {
    return const LightItUpApplied();
  }

  final broadcast = await broadcastPath1ToGroup(
    configureForTeam: configureForTeam,
    groupId: groupId,
    teamSlug: config.teamSlug,
    path1Config: config,
    now: now,
  );
  return switch (broadcast) {
    Path2HostBroadcastSucceeded(:final assembled) =>
      LightItUpAppliedAndBroadcasted(assembled),
    Path2HostBroadcastFailed(:final error) =>
      LightItUpAppliedButBroadcastFailed(error),
    // Unreachable in production — we pass path1Config=config (non-null),
    // so broadcastPath1ToGroup cannot return NeedsPath1Setup. Map it to
    // a recognizable error rather than a hidden no-op if it ever fires.
    Path2HostBroadcastNeedsPath1Setup() =>
      LightItUpAppliedButBroadcastFailed(
        StateError(
          'broadcastPath1ToGroup returned NeedsPath1Setup despite a '
          'non-null Path 1 config — orchestrator invariant violated.',
        ),
      ),
  };
}
