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
import '../../wled/wled_payload_utils.dart';
import '../../wled/wled_repository.dart';
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
  return currentAutopilotItemFor(
    activeSchedule: scheduler.activeSchedule,
    now: DateTime.now(),
  );
}

/// Pure helper: pick the latest-firing autopilot item whose
/// `scheduledTime <= now` from [activeSchedule].
///
/// Returns null if no item has fired yet. Extracted from the
/// provider above so the engine's teardown path can call it
/// directly with a single [now] reference + so it's unit-testable
/// without standing up the scheduler.
AutopilotScheduleItem? currentAutopilotItemFor({
  required List<AutopilotScheduleItem> activeSchedule,
  required DateTime now,
}) {
  if (activeSchedule.isEmpty) return null;
  AutopilotScheduleItem? latest;
  for (final item in activeSchedule) {
    if (item.scheduledTime.isAfter(now)) continue;
    if (latest == null || item.scheduledTime.isAfter(latest.scheduledTime)) {
      latest = item;
    }
  }
  return latest;
}

// ─────────────────────────────────────────────────────────────────────────────
// Side-effecting orchestrator: composes freshness check + pure resolver +
// per-tier apply + clear-on-consumption. Wired by [NeighborhoodSyncEngine]
// at the listening→not-listening transition. Pure-callable in tests via
// passed-in deps (repo + restorePresetLabel + clearPreSyncScene callbacks).
// ─────────────────────────────────────────────────────────────────────────────

/// Run the Stop-Sync teardown for a single member.
///
/// Pipeline:
///   1. Apply staleness gate to [preSyncScene] via [isPreSyncSceneFresh].
///   2. Filter out schedule items without a wledPayload (preset-based
///      schedules have nothing concrete to apply for teardown — they
///      fall through to the next tier).
///   3. Resolve the action via [resolveCurrentMemberState].
///   4. Apply it via [repo.applyJson] — routes through the chokepoint
///      so participation is respected on restore too.
///   5. Restore the Now Playing label only for the [ApplyPreSyncScene]
///      tier (mirrors Game Day's setLabelWithFingerprint pattern). When
///      [scene.activeLabel] is null, the restorePresetLabel callback is
///      still invoked with null — the engine's wiring may choose to
///      no-op on null vs explicit clear.
///   6. Call [clearPreSyncScene] so the next sync session captures fresh.
///
/// Returns the [MemberTeardownAction] that was executed (helpful for
/// the engine's debug log and the test assertions).
Future<MemberTeardownAction> executeMemberTeardown({
  required ScheduleItem? activeSchedule,
  required AutopilotScheduleItem? activeAutopilot,
  required PreSyncScene? preSyncScene,
  required String? activeGroupId,
  required DateTime now,
  required WledRepository repo,
  required void Function(String? label) restorePresetLabel,
  required void Function() clearPreSyncScene,
  Duration maxStaleness = kPreSyncSceneMaxStaleness,
  List<int>? participating,
}) async {
  final freshScene = isPreSyncSceneFresh(
    scene: preSyncScene,
    activeGroupId: activeGroupId,
    now: now,
    maxStaleness: maxStaleness,
  )
      ? preSyncScene
      : null;

  // Preset-only schedules (no inline wledPayload) can't be re-applied
  // here — the chokepoint needs a payload, not a preset id. Drop them
  // so the resolver falls through to autopilot / scene / off.
  final usableSchedule =
      (activeSchedule != null && activeSchedule.hasWledPayload)
          ? activeSchedule
          : null;

  final action = resolveCurrentMemberState(
    activeSchedule: usableSchedule,
    activeAutopilot: activeAutopilot,
    preSyncScene: freshScene,
  );

  // Pre-applyJson defensive filter: strips non-participating segs from
  // externally-sourced multi-seg-with-ids payloads BEFORE they reach
  // the chokepoint (chokepoint Rule 4 passes that shape through
  // unchanged, which would force-light excluded channels on Stop Sync).
  // No-op for single-seg / no-seg / null-or-empty-participating cases —
  // those go through the chokepoint correctly on their own. Applied to
  // every tier defensively: the audit confirmed only scene-tier emits
  // multi-seg-with-ids today, but a future schedule/autopilot save flow
  // (e.g. "save current device state as a schedule") could regress, so
  // filtering pre-applyJson at the executor avoids special-casing.
  Future<bool> apply(Map<String, dynamic> payload) {
    final filtered = filterMultiSegByParticipation(payload, participating);
    return repo.applyJson(filtered);
  }

  switch (action) {
    case ApplySchedule(:final item):
      // wledPayload non-null guaranteed by the usableSchedule filter.
      await apply(item.wledPayload!);
    case ApplyAutopilot(:final item):
      await apply(item.wledPayload);
    case ApplyPreSyncScene(:final scene):
      await apply(scene.wledPayload);
      restorePresetLabel(scene.activeLabel);
    case TurnOff():
      await apply(const <String, dynamic>{'on': false});
  }

  clearPreSyncScene();
  return action;
}
