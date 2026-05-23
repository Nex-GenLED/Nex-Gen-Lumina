// lib/features/neighborhood/services/path2_setup_resolution.dart
//
// Convergence-Phase-2b reader for the Sync→Complement→Game Day setup
// flow. Maps the 3-state [Path1SnapshotResolution] (Loading / Ready /
// Absent) into the 3-state UI decision that Path 2's screen branches
// on.
//
// 1b configure-twice regression sentinel: the AsyncLoading state MUST
// stay distinct from "no config". Collapsing the two (the original
// 2-state design) caused tapping a configured team mid-load to deep-
// link to the Fan Zone builder, defeating Phase 2b. The shared
// resolution upstream + the loading branch here are what guarantee
// the team-row badge and the tap handler can never disagree.

import 'path1_game_day_snapshot.dart';

/// Outcome of resolving the Path 2 setup screen against the host's
/// Path 1 config. Phase 2b UI branches on the subtype:
///   - [Path2SetupLoading]    → show a spinner / disable the tap
///   - [Path2SetupReady]      → show the read-only Path 1 preview
///   - [Path2SetupNeedsPath1] → deep-link into Path 1 setup
sealed class Path2SetupResolution {
  const Path2SetupResolution();
}

/// The underlying Path 1 config stream is still loading. The UI should
/// show a loading affordance and gate the tap until resolved — NOT
/// fall back to the deep-link branch (regression sentinel for the 1b
/// configure-twice gap).
class Path2SetupLoading extends Path2SetupResolution {
  const Path2SetupLoading();
}

/// A Path 1 config exists for the team — Phase 2b's UI renders the
/// existing design preview + offers the broadcast / light-up actions
/// against it.
class Path2SetupReady extends Path2SetupResolution {
  final Path1GameDaySnapshot snapshot;
  const Path2SetupReady(this.snapshot);
}

/// No Path 1 config exists for the team (stream resolved, no match —
/// or stream errored, folded to Absent so the user isn't stuck). The
/// Phase 2b UI deep-links the user straight into Path 1 setup for
/// [teamSlug] before allowing the broadcast or apply.
class Path2SetupNeedsPath1 extends Path2SetupResolution {
  final String teamSlug;
  const Path2SetupNeedsPath1(this.teamSlug);
}

/// Map a [Path1SnapshotResolution] into the Path 2 UI decision. Pure
/// switch on the sealed type — both branches go through the same
/// upstream signal so the team-row badge and the tap-handler can
/// never disagree.
Path2SetupResolution resolvePath2GameDaySetup({
  required Path1SnapshotResolution resolution,
}) {
  return switch (resolution) {
    Path1SnapshotLoading() => const Path2SetupLoading(),
    Path1SnapshotReady(:final snapshot) => Path2SetupReady(snapshot),
    Path1SnapshotAbsent(:final teamSlug) => Path2SetupNeedsPath1(teamSlug),
  };
}
