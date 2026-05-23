// lib/features/neighborhood/services/path1_game_day_snapshot.dart
//
// Read path: Path 2 (Sync→Complement→Game Day, neighborhood broadcast
// flow) reads a team's canonical Path 1 [GameDayAutopilotConfig] via
// this snapshot view-model.
//
// Why a snapshot and not raw [GameDayAutopilotConfig]?
//   - Path 2 only needs broadcast-shaped fields (effect, colors,
//     parameters, label). It does not need Firestore-only fields like
//     createdAt, motionStyle, lead-time overrides, or design payloads.
//   - The "absent" case is meaningful: Path 2 must distinguish "team
//     has no Path 1 config" (deep-link to Path 1 setup) from "team
//     has a config but it's disabled" (offer to enable + broadcast).
//     Treating null Path 1 as "absent" surfaces the right UX.
//
// Convergence-Phase-1B groundwork — additive helper, not yet wired
// into Path 2's UI. The Sync→Complement→Game Day flow still
// constructs the legacy in-memory GameDaySyncConfig; Phase 2 deletes
// that shape and rewires the UI to read this snapshot.

import 'dart:ui' show Color;

import '../../autopilot/game_day_autopilot_config.dart';
import '../../sports_alerts/models/sport_type.dart';

/// Path-2-shaped read view of a host's Path 1 per-team configuration.
///
/// Build via [Path1GameDaySnapshot.fromConfig]. Returns `null` when the
/// caller wants the "team has no Path 1 config OR config is disabled"
/// signal — see [Path1GameDaySnapshot.fromConfigOrNull].
class Path1GameDaySnapshot {
  /// Team slug key from kTeamColors (e.g. 'mlb_royals').
  final String teamSlug;

  /// Display name (e.g. 'Kansas City Royals').
  final String teamName;

  /// ESPN numeric team ID — needed by Path 2 for celebration matching.
  final String espnTeamId;

  /// Sport type.
  final SportType sport;

  /// Team primary color (ARGB int).
  final int primaryColorValue;

  /// Team secondary color (ARGB int).
  final int secondaryColorValue;

  /// Effect ID from Path 1 (0 = Solid, etc.).
  final int effectId;

  /// Speed parameter (0-255).
  final int speed;

  /// Intensity parameter (0-255).
  final int intensity;

  /// Brightness parameter (0-255).
  final int brightness;

  /// Whether score celebrations should fire during the game.
  final bool scoreCelebrationEnabled;

  /// Human-readable design label, derived from Path 1's resolution
  /// order (savedDesignName → effect-derived → mode-derived).
  final String designLabel;

  /// Whether Path 1 has autopilot enabled for this team.
  final bool autopilotEnabled;

  const Path1GameDaySnapshot({
    required this.teamSlug,
    required this.teamName,
    required this.espnTeamId,
    required this.sport,
    required this.primaryColorValue,
    required this.secondaryColorValue,
    required this.effectId,
    required this.speed,
    required this.intensity,
    required this.brightness,
    required this.scoreCelebrationEnabled,
    required this.designLabel,
    required this.autopilotEnabled,
  });

  /// Convenience accessor for the primary color.
  Color get primaryColor => Color(primaryColorValue);

  /// Convenience accessor for the secondary color.
  Color get secondaryColor => Color(secondaryColorValue);

  /// Build a snapshot from a Path 1 [GameDayAutopilotConfig].
  ///
  /// Always returns a non-null snapshot — disabled configs are mapped
  /// to `autopilotEnabled = false` so the caller can still display the
  /// existing design preview while offering an enable action.
  factory Path1GameDaySnapshot.fromConfig(GameDayAutopilotConfig config) {
    return Path1GameDaySnapshot(
      teamSlug: config.teamSlug,
      teamName: config.teamName,
      espnTeamId: config.espnTeamId,
      sport: config.sport,
      primaryColorValue: config.primaryColorValue,
      secondaryColorValue: config.secondaryColorValue,
      effectId: config.effectId,
      speed: config.speed,
      intensity: config.intensity,
      brightness: config.brightness,
      scoreCelebrationEnabled: config.scoreCelebrationEnabled,
      designLabel: config.designLabel,
      autopilotEnabled: config.enabled,
    );
  }

  /// Build a snapshot from a possibly-null [GameDayAutopilotConfig].
  /// Returns `null` when no Path 1 config exists for the team — Path 2
  /// uses that signal to deep-link the user into Path 1 setup before
  /// allowing host broadcast.
  static Path1GameDaySnapshot? fromConfigOrNull(
    GameDayAutopilotConfig? config,
  ) {
    if (config == null) return null;
    return Path1GameDaySnapshot.fromConfig(config);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// THREE-STATE RESOLUTION
// ─────────────────────────────────────────────────────────────────────────────
//
// AsyncLoading must be a distinct state from "no config" — collapsing
// the two (via maybeWhen orElse → null) caused the 1b configure-twice
// gap: tapping a configured team BEFORE its Firestore stream resolved
// treated it as un-configured and deep-linked to the Path 1 Fan Zone
// (a builder), defeating the point of Phase 2b.
//
// [Path1SnapshotResolution] makes the three states explicit so the
// row badge and the tap-handler branch on the SAME signal — they can
// never disagree (no path where the badge says "configured" but the
// tap says "needs setup").

/// Resolution of a team's Path 1 snapshot at a moment in time. Build
/// via [path1GameDaySnapshotResolutionProvider] in production or
/// construct directly in tests.
sealed class Path1SnapshotResolution {
  const Path1SnapshotResolution();
}

/// The user's Path 1 configs are still streaming in. Callers must NOT
/// treat this as "no config" — surface a loading affordance and gate
/// any deep-link or config-dependent action behind a resolved state.
class Path1SnapshotLoading extends Path1SnapshotResolution {
  const Path1SnapshotLoading();
}

/// A Path 1 config exists for this team. Carries the snapshot view-model
/// so the UI can render preview controls without a second provider read.
class Path1SnapshotReady extends Path1SnapshotResolution {
  final Path1GameDaySnapshot snapshot;
  const Path1SnapshotReady(this.snapshot);
}

/// The configs stream resolved and this team is NOT configured (or the
/// stream errored — treated as absent so the user can re-attempt Path 1
/// setup rather than getting stuck on a loading spinner). Carries the
/// team slug so the caller can deep-link cleanly.
class Path1SnapshotAbsent extends Path1SnapshotResolution {
  final String teamSlug;
  const Path1SnapshotAbsent(this.teamSlug);
}

