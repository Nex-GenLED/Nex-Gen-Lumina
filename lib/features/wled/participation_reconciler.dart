// lib/features/wled/participation_reconciler.dart
//
// Foreground reconciliation of the persisted participation cache against
// the current device + roofline shape. See
// docs/audits/CHANNEL_MAPPING_AUDIT_2026-05.md Addendum 1 for the full
// derivation; one-paragraph version:
//
// The participation cache (SharedPreferences key
// `_kLocalParticipatingChannelsKey`, in-memory `participationCacheNotifier`)
// stores the resolver's OUTPUT — not the user's INPUT. When the device
// shape changes after the cache is written (e.g. a 2nd bus is wired up
// after the cache was first populated against a 1-bus device), the stored
// value is no longer what the resolver would produce today. The Lumina
// chip-grey-out logic and the apply-chokepoint participation filter both
// honor the stored value, so a stale value silently excludes the newly-
// added bus on every subsequent apply.
//
// This module:
//   • exposes a pure boolean predicate testable without Riverpod or
//     SharedPreferences ([isParticipationCacheStale])
//   • exposes a foreground-only adapter that gates on both providers
//     being ready and clears the cache exactly once per app session
//     ([runParticipationReconciliationIfReady])
//
// The persistence helpers in
// `sync_event_background_persistence.dart` stay Riverpod-free so the
// background isolate can keep using them unchanged.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/neighborhood/services/channel_participation_resolver.dart';
import 'package:nexgen_command/features/neighborhood/services/sync_event_background_persistence.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/models/roofline_segment.dart';

/// Pure staleness predicate. Returns true when the persisted participation
/// cache no longer matches what
/// [resolveParticipatingChannels] would produce for the current device +
/// roofline shape — i.e. the cache is stale and should be cleared.
///
/// Confirmed root cause (CHANNEL_MAPPING_AUDIT_2026-05 Addendum 1, verified
/// on a live install): cache written when the device had fewer buses than
/// it has now.
///
/// Guards:
///   • [cached] == null     → false (nothing to reconcile — no preference).
///   • [deviceIds].isEmpty  → false (device not loaded / no device).
///                             Returning true here would falsely clear a
///                             legitimate cache during the boot window
///                             before /json/cfg returns.
bool isParticipationCacheStale({
  required List<int>? cached,
  required List<int> deviceIds,
  required List<RooflineSegment> segments,
}) {
  if (cached == null) return false;
  if (deviceIds.isEmpty) return false;

  // RESOLVED (was TODO(participation-pickers)): a picker now ships, so a cache
  // written from a user's EXPLICIT set is no longer comparable to the
  // default-policy recompute. The provenance flag is the override's existence
  // (`participationOverrideNotifier` / `getParticipationOverride`), and the
  // caller — [runParticipationReconciliationIfReady] — checks it BEFORE calling
  // this predicate, routing override-sourced caches to
  // [pruneOverrideToDevice] instead. This function keeps its narrow contract:
  // it answers "is a DERIVED cache stale", and `explicit: null` is correct for
  // that question and only that question.
  final expected = resolveParticipatingChannels(
    explicit: null,
    segments: segments,
    allDeviceChannelIds: deviceIds,
  );

  return !setEquals(cached.toSet(), expected.toSet());
}

/// Reconciliation for an OVERRIDE-sourced participation set.
///
/// A user's explicit set must not be judged against the geometry — that is the
/// whole point of it outranking the geometry. But it can still name a channel
/// the device no longer reports (bus removed, controller swapped), and a
/// participation entry for a channel that does not exist is dead weight that
/// would survive every future reconcile.
///
/// So the only reconciliation an override gets is a PRUNE to live device ids.
/// Returns the pruned list, or null when nothing survives — a null result means
/// "drop the override entirely", handing control back to the default policy
/// rather than leaving the user with an empty participation set they cannot see
/// or clear. Returns [override] unchanged (same instance semantics not
/// guaranteed, only equality) when every channel still exists.
///
/// Pure — no I/O, so the decision is testable without SharedPreferences.
List<int>? pruneOverrideToDevice({
  required List<int> override,
  required List<int> deviceIds,
}) {
  if (deviceIds.isEmpty) return override; // device not loaded — never prune
  final live = deviceIds.toSet();
  final kept = override.where(live.contains).toList();
  if (kept.isEmpty) return null;
  return kept;
}

// Module-level once-per-session flag. CRITICAL: only set true AFTER both
// providers are confirmed ready (see [runParticipationReconciliationIfReady]).
// Setting it on an early-return-not-ready path would permanently disable
// reconciliation for the session — the exact false-negative that would
// leave a stale cache unfixed.
bool _reconciledThisSession = false;

/// Foreground-only adapter. Reads [deviceChannelsProvider] and
/// [currentRooflineConfigProvider] via [ref], awaits the persisted cache
/// from disk, runs [isParticipationCacheStale], and clears the cache to
/// null if stale. Self-gates: returns early (without marking reconciled)
/// if either provider hasn't emitted yet, so the caller can invoke this
/// from a `ref.listen` on either provider and it'll re-check on each
/// emission until both are ready, then run exactly once.
///
/// Returns `true` if reconciliation ran this call (whether or not it
/// cleared), `false` if it skipped due to readiness or because already-
/// reconciled.
Future<bool> runParticipationReconciliationIfReady(WidgetRef ref) async {
  if (_reconciledThisSession) return false;

  final deviceIds =
      ref.read(deviceChannelsProvider).map((c) => c.id).toList();
  if (deviceIds.isEmpty) return false;

  final rooflineAsync = ref.read(currentRooflineConfigProvider);
  if (!rooflineAsync.hasValue) return false;
  final segments =
      rooflineAsync.value?.segments ?? const <RooflineSegment>[];

  // Both ready → reconcile exactly once. Set the flag NOW so a concurrent
  // listener tick (from the other provider firing at nearly the same
  // moment) doesn't re-enter.
  _reconciledThisSession = true;

  // PROVENANCE BRANCH. Read the override from disk (not the peek — it may not
  // be warm this early) before touching the cache. A non-null override means
  // the cache downstream of it is the user's statement, not a derivation, and
  // the staleness predicate below would clear it on the very next launch —
  // rebuilding the one-way door from the other side.
  final override = await getParticipationOverride();
  if (override != null) {
    final pruned = pruneOverrideToDevice(
      override: override,
      deviceIds: deviceIds,
    );
    if (!setEquals(pruned?.toSet(), override.toSet())) {
      await saveParticipationOverride(pruned);
      debugPrint(
          'participation_reconciler: pruned override to live device shape '
          '(override=$override, pruned=$pruned, deviceIds=$deviceIds)');
    }
    return true;
  }

  // Read the persisted value directly — not the peek — so a cold cache
  // (chokepoint hasn't run applyJson yet this session) still gets
  // reconciled. Peek would return null and skip a real stale value.
  final cached = await loadLocalParticipatingChannels();

  if (isParticipationCacheStale(
    cached: cached,
    deviceIds: deviceIds,
    segments: segments,
  )) {
    // Clear → restores "no preference → resolver runs fresh next apply"
    // default. Also clears the in-memory ValueNotifier (per
    // [saveLocalParticipatingChannels]'s implementation), so the
    // dashboard chip-grey-out rebuilds immediately.
    await saveLocalParticipatingChannels(null);
    debugPrint(
        'participation_reconciler: cleared stale cache '
        '(cached=$cached, deviceIds=$deviceIds, '
        'segments=${segments.length})');
  }

  return true;
}

/// Test helper — clears the once-per-session flag so each test starts cold.
@visibleForTesting
void resetParticipationReconcilerForTest() {
  _reconciledThisSession = false;
}
