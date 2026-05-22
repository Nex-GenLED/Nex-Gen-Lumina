// lib/features/neighborhood/services/sync_teardown_resolver.dart
//
// Pure resolver for "what should each member do when sync stops?"
//
// Policy (locked, see brief 2026-05-22):
//   1. active schedule item right now → apply its wledPayload
//   2. else autopilot schedule item right now → apply its wledPayload
//   3. else pre-sync scene captured at sync start → restore it
//   4. else → off
//
// Distributed: each member resolves locally. Restoration apply still
// routes through [WledRepository.applyJson] → the chokepoint, so
// participation is respected on restore too.
//
// Convergence-Phase-1B groundwork — additive, DORMANT. The resolver
// and its composer provider exist but no production code path calls
// them. Phase 2 wires this into [NeighborhoodSyncEngine] / the stop
// path AND into the broken [SyncSessionManager._applyPostEventBehavior]
// (which today has placeholder implementations that don't actually
// restore — see audit notes).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/autopilot_schedule_item.dart';
import '../../../services/autopilot_scheduler.dart';
import '../../schedule/schedule_models.dart';
import '../../schedule/schedule_providers.dart';
import 'pre_sync_scene_snapshot.dart';

/// Sealed result of [resolveCurrentMemberState] describing what each
/// member should do when sync stops. Phase 2's executor branches on
/// the subtype and calls `applyJson` / power-off accordingly.
sealed class MemberTeardownAction {
  const MemberTeardownAction();
}

/// Priority 1: a schedule item is active right now — re-apply its payload.
class ApplySchedule extends MemberTeardownAction {
  final ScheduleItem item;
  const ApplySchedule(this.item);
}

/// Priority 2: an autopilot item is the current scheduled action.
class ApplyAutopilot extends MemberTeardownAction {
  final AutopilotScheduleItem item;
  const ApplyAutopilot(this.item);
}

/// Priority 3: restore the WLED state captured at sync start.
class ApplyPreSyncScene extends MemberTeardownAction {
  final PreSyncScene scene;
  const ApplyPreSyncScene(this.scene);
}

/// Priority 4 (fallback): nothing to restore — send the member off.
/// Explicit off, NOT freeze (locked policy).
class TurnOff extends MemberTeardownAction {
  const TurnOff();
}

/// Pure decision function over the four inputs.
///
/// REUSES existing providers (passed in here as plain values for
/// testability) — does NOT re-implement schedule or autopilot logic.
/// The composer provider [sustainedTeardownActionProvider] is the
/// production wiring that reads from the live providers and feeds
/// them in.
MemberTeardownAction resolveCurrentMemberState({
  required ScheduleItem? activeSchedule,
  required AutopilotScheduleItem? activeAutopilot,
  required PreSyncScene? preSyncScene,
}) {
  if (activeSchedule != null) return ApplySchedule(activeSchedule);
  if (activeAutopilot != null) return ApplyAutopilot(activeAutopilot);
  if (preSyncScene != null) return ApplyPreSyncScene(preSyncScene);
  return const TurnOff();
}

/// Composer provider — pure read of the three live inputs that feed
/// [resolveCurrentMemberState]. DORMANT: no consumer calls this in
/// production today. Exists so Phase 2's stop-path executor can read
/// the resolved action without re-implementing the lookup logic.
///
/// • Schedule input: [currentScheduledActionProvider] — the existing
///   per-user "what schedule item is active right now" view-model.
/// • Autopilot input: filtered through `nextAutopilotItemProvider`'s
///   underlying scheduler — we read the live "is an autopilot item
///   firing right now" signal by inspecting [activeSchedule] for the
///   item that matches the current minute. Phase 2 may surface a
///   dedicated "current autopilot action" provider if the inspection
///   here proves brittle; for now we lean on the existing
///   [nextAutopilotItemProvider] but only honor it when the next item
///   is in the past (i.e. it should already have fired).
/// • Snapshot input: [preSyncSceneProvider] — single-slot store.
final sustainedTeardownActionProvider =
    Provider<MemberTeardownAction>((ref) {
  final activeSchedule = ref.watch(currentScheduledActionProvider);

  final activeAutopilot = _currentAutopilotItem(ref);

  final preSyncScene = ref.watch(preSyncSceneProvider);

  return resolveCurrentMemberState(
    activeSchedule: activeSchedule,
    activeAutopilot: activeAutopilot,
    preSyncScene: preSyncScene,
  );
});

/// Read the autopilot scheduler's active items and return the one
/// that should be the current action (latest scheduledTime <= now).
///
/// Returns null when no autopilot item is currently active. Kept
/// private so the public surface of this file is the pure
/// [resolveCurrentMemberState] + the composer provider.
AutopilotScheduleItem? _currentAutopilotItem(Ref ref) {
  final scheduler = ref.watch(autopilotSchedulerProvider);
  final items = scheduler.activeSchedule;
  if (items.isEmpty) return null;

  final now = DateTime.now();
  AutopilotScheduleItem? latest;
  for (final item in items) {
    if (item.scheduledTime.isAfter(now)) continue;
    if (latest == null || item.scheduledTime.isAfter(latest.scheduledTime)) {
      latest = item;
    }
  }
  return latest;
}
