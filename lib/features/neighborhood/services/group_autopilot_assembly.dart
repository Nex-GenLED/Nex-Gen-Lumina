// lib/features/neighborhood/services/group_autopilot_assembly.dart
//
// Pure builder for [GroupGameDayAutopilot] — the group-level Game Day
// Autopilot config that lives at:
//   /neighborhoods/{groupId}/game_day_autopilot/config
//
// The builder converts a host's individual [GameDayAutopilotConfig]
// (Path 1, the canonical per-user team config) into the group-shaped
// [GroupGameDayAutopilot] document that the host broadcasts.
//
// Pure function on purpose: no Firestore, no provider container. The
// host-team write path is exercised by tests; the persistence step
// runs through [GroupAutopilotService.configureForTeam] which feeds the
// built value into [GroupAutopilotService.setGroupAutopilot].
//
// Phase 1B groundwork — additive, not yet wired into the UI. The
// Sync→Complement→Game Day flow still constructs the legacy
// [GameDaySyncConfig] in-memory shape; the convergence Phase 2 step
// rewires that UI to use this builder + the Path 1 reader.

import '../models/group_game_day_autopilot.dart';
import '../../autopilot/game_day_autopilot_config.dart';

/// Build a [GroupGameDayAutopilot] from the host's Path 1 per-team
/// [GameDayAutopilotConfig].
///
/// Fields derive as follows:
///   - teamId       = sourceConfig.teamSlug
///   - teamName     = sourceConfig.teamName
///   - sport        = sourceConfig.sport
///   - hostUserId   = hostUserId (caller-supplied)
///   - hostDesignId = sourceConfig.savedDesignName, or a deterministic
///                    fallback string when no saved design is named.
///                    Fallback is `{teamSlug}:fx{effectId}` so the same
///                    Path 1 effect choice round-trips to the same id.
///   - enabled      = enabled (default true)
///   - activeMemberIds = initialActiveMemberIds (default empty; the
///                    service layer fills this from the opted-in
///                    member set just before write)
///   - updatedAt    = now (caller-supplied for testability)
///
/// Pure — does not read from Firestore or any provider container.
GroupGameDayAutopilot buildGroupAutopilotFromPath1({
  required GameDayAutopilotConfig sourceConfig,
  required String hostUserId,
  required DateTime now,
  bool enabled = true,
  List<String> initialActiveMemberIds = const [],
}) {
  assert(hostUserId.isNotEmpty, 'hostUserId must not be empty');
  return GroupGameDayAutopilot(
    teamId: sourceConfig.teamSlug,
    teamName: sourceConfig.teamName,
    sport: sourceConfig.sport,
    enabled: enabled,
    hostDesignId: _resolveHostDesignId(sourceConfig),
    hostUserId: hostUserId,
    activeMemberIds: List<String>.unmodifiable(initialActiveMemberIds),
    updatedAt: now,
  );
}

/// Resolve a stable, non-empty hostDesignId for a Path 1 config.
///
/// Priority:
///   1. savedDesignName when set (user-named design wins, mirrors the
///      designLabel resolution order in [GameDayAutopilotConfig]).
///   2. Deterministic fallback `{teamSlug}:fx{effectId}` so a host who
///      hasn't named a custom design still gets a non-empty id that
///      reflects the current effect choice.
String _resolveHostDesignId(GameDayAutopilotConfig config) {
  final saved = config.savedDesignName;
  if (saved != null && saved.isNotEmpty) return saved;
  return '${config.teamSlug}:fx${config.effectId}';
}
