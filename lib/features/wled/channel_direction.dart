// lib/features/wled/channel_direction.dart
//
// The user-facing DIRECTION write — the one place a person, not a
// provisioning routine, states which way a channel runs.
//
// WHY THIS FILE EXISTS
// --------------------
// `rev` is geometry. Since the wire pin was widened to cover orientation
// (`kGeometryKeys = ['start','stop','rev','mi']`, 2026-08-18), any `rev` sent
// through `applyJson` is stripped before it reaches the device — which is
// correct for the paths that were leaking it (a slider drag re-asserting
// direction from local state, a celebration revert replaying a captured
// `/json/state`), and WRONG for the two SegmentedButtons where flipping
// direction is the entire point of the control. Those went silently dead.
//
// So direction gets the provisioning door, `applyGeometryJson`, exactly as the
// pin's own doctrine says it should:
//
//   "If this caller legitimately provisions geometry it must use the geometry
//    entry point, not applyJson."
//
// ⚠️ #102 TENSION — READ BEFORE EXTENDING THIS.
// This is a NEW CLASS of `applyGeometryJson` caller. Every existing one derives
// its payload from the controller's OWN hardware buses; this one derives it
// from a tap. Once #102's shape-check ships, a UI direction flip that disagrees
// with the bus config's `rev` will be classified as DRIFT and "repaired" back —
// the user's choice will silently revert on the next heal.
//
// The real fix is that this write should ALSO update the installation record
// (the bus config is the source of truth the healer restores from), so the two
// agree. NOT RESOLVED HERE — made visible here, and filed on #102.

import 'package:flutter/foundation.dart';

import 'package:nexgen_command/features/wled/wled_repository.dart';

/// Build the direction payload for [channelIds].
///
/// Pure, so the shape is testable without a device or a widget. One `seg` entry
/// per channel carrying ONLY `id` + `rev`: a direction write states direction
/// and nothing else, so it can never smuggle a look change (or a bound) along
/// with it.
Map<String, dynamic> buildDirectionPayload({
  required List<int> channelIds,
  required bool reverse,
}) {
  return <String, dynamic>{
    'seg': [
      for (final id in channelIds) {'id': id, 'rev': reverse},
    ],
  };
}

/// Send a user-initiated direction change through the PROVISIONING door.
///
/// Returns false — writing nothing — when there is no repository, no channel to
/// target (the U1 participation gate), or when the transport cannot state
/// geometry at all. The last case is why this returns a bool rather than void:
/// `WledRepository.applyGeometryJson` defaults to false, so an off-LAN or demo
/// transport reports "not done" instead of pretending. Callers should surface
/// that rather than leave the toggle looking applied.
Future<bool> applyChannelDirection({
  required WledRepository? repo,
  required List<int> channelIds,
  required bool reverse,
}) async {
  if (repo == null) return false;
  if (channelIds.isEmpty) return false;
  try {
    return await repo.applyGeometryJson(
      buildDirectionPayload(channelIds: channelIds, reverse: reverse),
    );
  } on UnsupportedError catch (e) {
    // The relay has no provisioning door and says so by THROWING — a hard
    // capability boundary, not a transient failure (cloud_relay_repository).
    // Caught here so the boundary reaches the user as "not applied" rather
    // than as an unhandled async error from a button tap.
    debugPrint('applyChannelDirection: geometry is LAN-only on this '
        'transport — direction NOT applied. $e');
    return false;
  }
}
