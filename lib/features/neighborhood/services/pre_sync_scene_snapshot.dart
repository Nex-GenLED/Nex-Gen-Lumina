// lib/features/neighborhood/services/pre_sync_scene_snapshot.dart
//
// Pre-sync scene capture — mirrors the Game Day / Autopilot override pattern
// (revertWledPayload in ephemeral_game_session_service.dart + capturedState in
// services/autopilot_scheduler.dart). At sync START we snapshot the member's
// current WLED state so that on Stop Sync the member can fall back to the
// pre-sync scene when no schedule item and no autopilot item resolve.
//
// Convergence-Phase-1B groundwork — additive, DORMANT. This module:
//   • exposes a callable capture function and a single-slot Riverpod store
//   • is NOT yet wired into broadcastSync / startListening
//   • is consumed only by tests today (and by [SyncTeardownResolver] which
//     is itself dormant)
//
// Phase 2 wires the capture into the sync-start path and the consumption
// into the stop-sync teardown.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../wled/wled_repository.dart';

/// One captured snapshot of a member's pre-sync WLED state.
///
/// Held in memory only — never persisted. A new capture replaces the prior
/// one. Phase 2's teardown reads this when there is no active schedule item
/// and no autopilot item to restore.
class PreSyncScene {
  /// The group the snapshot was captured for. Phase 2 will check this
  /// against the active group at teardown time so a stale snapshot from
  /// a previous group doesn't leak across switches.
  final String groupId;

  /// The full WLED `/json/state` payload, round-trippable via [WledRepository.applyJson].
  final Map<String, dynamic> wledPayload;

  /// The Now Playing label that was active when the snapshot was taken.
  /// Null when no label was set (e.g. ad-hoc adjustments outside any
  /// preset). Restored alongside the payload to preserve the "current
  /// scene" identity in the UI.
  final String? activeLabel;

  /// When the snapshot was taken. Used for diagnostics and for the
  /// Phase 2 freshness check (a snapshot older than, say, the session
  /// duration is likely stale and should not be restored).
  final DateTime capturedAt;

  const PreSyncScene({
    required this.groupId,
    required this.wledPayload,
    required this.activeLabel,
    required this.capturedAt,
  });
}

/// Capture the member's current pre-sync state.
///
/// Returns `null` when the repository can't produce a state (offline
/// controller, demo mode, fetch error). The caller treats null as
/// "no snapshot available" — the teardown resolver will fall through
/// to the off-fallback instead of trying to restore garbage.
///
/// Pure-ish: takes [repo] as an argument so tests can supply a fake.
/// Does not read providers — the caller composes the snapshot into the
/// [preSyncSceneProvider] slot.
Future<PreSyncScene?> capturePreSyncScene({
  required String groupId,
  required WledRepository repo,
  required String? activeLabel,
  DateTime? now,
}) async {
  Map<String, dynamic>? state;
  try {
    state = await repo.getState();
  } catch (_) {
    return null;
  }
  if (state == null || state.isEmpty) return null;

  return PreSyncScene(
    groupId: groupId,
    wledPayload: Map<String, dynamic>.from(state),
    activeLabel: activeLabel,
    capturedAt: now ?? DateTime.now(),
  );
}

/// Single-slot Riverpod store for the most recent pre-sync snapshot.
///
/// One active group at a time, one snapshot at a time. Set to null
/// when there is no active sync (or to clear after a teardown that
/// consumed the snapshot). Mutated by the Phase 2 sync-start hook.
final preSyncSceneProvider = StateProvider<PreSyncScene?>((ref) => null);
