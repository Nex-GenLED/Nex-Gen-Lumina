// lib/features/neighborhood/services/path2_setup_resolution.dart
//
// Convergence-Phase-2 (additive) reader for the Sync→Complement→Game
// Day setup flow.
//
// Phase-2b destructive step: the existing GameDaySetupScreen reads a
// shallow in-memory [GameDaySyncConfig] from scratch — it does NOT
// consult the user's canonical Path 1 [GameDayAutopilotConfig]. That
// duplicate flow lets the host save a Path 2 config that diverges from
// Path 1 silently. Phase 2b deletes [GameDaySyncConfig] and rewires
// that screen to read this resolution instead.
//
// Until Phase 2b ships and Tyler reviews + hardware-probes, this
// helper stays UNWIRED. It is the additive groundwork for the destruc-
// tive step — symmetric to broadcastPath1ToGroup in
// [path2_host_broadcast.dart], which the host-broadcast write path
// already calls in Phase 2.
//
// Pure: no Riverpod, no Firestore. Caller resolves the snapshot via
// [path1GameDaySnapshotProvider] (or a fixture) and passes it
// explicitly.

import 'path1_game_day_snapshot.dart';

/// Outcome of resolving the Path 2 setup screen against the host's
/// Path 1 config. Phase 2b UI branches on the subtype:
///   - [Path2SetupReady]      → show the read-only Path 1 preview
///   - [Path2SetupNeedsPath1] → deep-link into Path 1 setup
sealed class Path2SetupResolution {
  const Path2SetupResolution();
}

/// A Path 1 config exists for the team — Phase 2b's UI renders the
/// existing design preview + offers the broadcast / light-up actions
/// against it.
class Path2SetupReady extends Path2SetupResolution {
  final Path1GameDaySnapshot snapshot;
  const Path2SetupReady(this.snapshot);
}

/// No Path 1 config exists for the team. The Phase 2b UI deep-links
/// the user straight into Path 1 setup for [teamSlug] before allowing
/// the broadcast or apply.
class Path2SetupNeedsPath1 extends Path2SetupResolution {
  final String teamSlug;
  const Path2SetupNeedsPath1(this.teamSlug);
}

/// Resolve which UI branch Phase 2b should render for [teamSlug] given
/// the snapshot returned by [path1GameDaySnapshotProvider].
///
/// Returns [Path2SetupNeedsPath1] when [snapshot] is null (no Path 1
/// config exists). A non-null snapshot — even one with
/// `autopilotEnabled = false` — returns [Path2SetupReady] so the UI
/// can show the existing design and offer to enable + broadcast.
Path2SetupResolution resolvePath2GameDaySetup({
  required String teamSlug,
  required Path1GameDaySnapshot? snapshot,
}) {
  if (snapshot == null) return Path2SetupNeedsPath1(teamSlug);
  return Path2SetupReady(snapshot);
}
