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

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../wled/wled_repository.dart';

/// One captured snapshot of a member's pre-sync WLED state.
///
/// Held in the [preSyncSceneProvider] slot AND mirrored to SharedPreferences
/// so it survives an app restart. Before persistence existed, killing the app
/// mid-session dropped the snapshot, which made the teardown fall through to
/// the [TurnOff] tier — that is what made "leave sync" shut the whole system
/// off instead of restoring. A new capture replaces the prior one.
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

  /// snake_case per the repo's serialization convention. `capturedAt` is an
  /// ISO-8601 string rather than a Timestamp — this lands in SharedPreferences
  /// as JSON, not in Firestore.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'group_id': groupId,
        'wled_payload': wledPayload,
        'active_label': activeLabel,
        'captured_at': capturedAt.toIso8601String(),
      };

  /// Returns null on ANY malformed field. A corrupt snapshot must read as
  /// "no snapshot" so the teardown falls through the tiers normally, rather
  /// than throwing on a path whose whole job is restoring the user's lights.
  static PreSyncScene? fromJson(Map<String, dynamic> json) {
    final groupId = json['group_id'];
    final payload = json['wled_payload'];
    final capturedAt = json['captured_at'];
    if (groupId is! String || payload is! Map || capturedAt is! String) {
      return null;
    }
    final parsedAt = DateTime.tryParse(capturedAt);
    if (parsedAt == null) return null;
    return PreSyncScene(
      groupId: groupId,
      wledPayload: Map<String, dynamic>.from(payload),
      activeLabel: json['active_label'] as String?,
      capturedAt: parsedAt,
    );
  }
}

/// SharedPreferences key for the persisted snapshot. Local device state only —
/// deliberately NOT Firestore: this is "what were my lights doing before the
/// sync", which is per-device and has no business in the cloud.
const String kPreSyncScenePrefsKey = 'neighborhood_pre_sync_scene_v1';

/// Mirror [scene] to disk (or clear it when null).
///
/// Best-effort: a persistence failure must never break sync-start, so errors
/// are swallowed and logged. Worst case the snapshot stays in-memory-only and
/// behaves exactly as it did before persistence existed.
Future<void> savePreSyncScene(PreSyncScene? scene) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (scene == null) {
      await prefs.remove(kPreSyncScenePrefsKey);
      return;
    }
    await prefs.setString(kPreSyncScenePrefsKey, jsonEncode(scene.toJson()));
  } catch (e) {
    debugPrint('PreSyncScene: persist failed (non-fatal): $e');
  }
}

/// Read the persisted snapshot, or null when absent/corrupt.
///
/// The freshness gate ([isPreSyncSceneFresh]) still applies to whatever this
/// returns — surviving a restart does NOT exempt a snapshot from the 12h
/// staleness rule or the group-id match.
Future<PreSyncScene?> loadPersistedPreSyncScene() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kPreSyncScenePrefsKey);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    return PreSyncScene.fromJson(Map<String, dynamic>.from(decoded));
  } catch (e) {
    debugPrint('PreSyncScene: load failed, treating as absent: $e');
    return null;
  }
}

/// Drop the persisted snapshot. Called after a teardown consumes it so a
/// later, unrelated leave can't restore a stale scene.
Future<void> clearPersistedPreSyncScene() => savePreSyncScene(null);

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
/// consumed the snapshot). Mutated by the sync-start hook in
/// [NeighborhoodSyncEngine] and cleared by the teardown executor.
///
/// In-memory ONLY — this slot is empty after an app restart. The durable copy
/// lives in SharedPreferences ([loadPersistedPreSyncScene]); the teardown falls
/// back to it when this slot is null, which is what keeps a restart from
/// turning into a blanket master-off on leave.
final preSyncSceneProvider = StateProvider<PreSyncScene?>((ref) => null);

/// Default maximum staleness for a pre-sync snapshot before the
/// teardown executor treats it as stale and falls through to the
/// next priority tier.
///
/// 12 hours: longer than the longest reasonable single sync session
/// (e.g. an all-night Christmas / July 4 broadcast — see PausedSessionState
/// for the longForm session shape) but short enough to bail on
/// day-after stale snapshots if the app was killed mid-session and a
/// next-day stop is triggered against state that no longer reflects
/// the user's actual "before sync" condition.
const Duration kPreSyncSceneMaxStaleness = Duration(hours: 12);

/// True when [scene] is fresh enough to be restored at teardown.
///
/// Stale criteria (any of these → returns false):
///   • [scene] is null
///   • [scene.groupId] mismatches the (possibly null) [activeGroupId] —
///     guards against group-switch mid-session (snapshot from group A
///     must not restore for group B)
///   • [now] − [scene.capturedAt] > [maxStaleness]
///
/// Callers treat the scene as absent when this returns false and
/// fall through to the next priority tier (autopilot → off).
bool isPreSyncSceneFresh({
  required PreSyncScene? scene,
  required String? activeGroupId,
  required DateTime now,
  Duration maxStaleness = kPreSyncSceneMaxStaleness,
}) {
  if (scene == null) return false;
  if (scene.groupId != activeGroupId) return false;
  if (now.difference(scene.capturedAt) > maxStaleness) return false;
  return true;
}
