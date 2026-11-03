// lib/features/wled/segment_geometry_reheal.dart
//
// +122 item 2 (TD-9) — the ONE segment-geometry repair every caller shares.
//
// A controller that boots with no boot preset comes up as one factory segment
// over the whole strip (TD-11), and a preset saved while collapsed re-collapses
// it on every fire. Before +122 the repair lived inside the connect-time
// healer (`ControllerDefaultsHealer._healSegmentGeometry`, +80) and ran ONLY
// when the app met a NEW endpoint, and it wrote BOUNDS ONLY, so a segment it
// re-created came up in the firmware's default look (amber 255,160,0, fx 0):
// a whole-house look became half-house. Field case 2026-10-23 (TD-8/9/10), and
// the Oct 28 bench rehearsal: a one-segment boot turned into four default-
// coloured segments by a geometry-only write while the app was open.
//
// This module makes the repair deliberate and reusable:
//   • `decideGeometryHeal`  — the verdict (moved here from the healer; same
//     body, same tests). Stands aside on ignorance, repairs a KNOWN mismatch.
//   • `geometryRepairPayload` — the body of the repair: bounds for every bus
//     segment, and a segment the live layout LACKS also takes segment 0's look
//     (on, bri, col, fx, sx, ix, pal) in the same POST. Segment 0 is what the
//     whole strip was showing while collapsed, so that is the previous look —
//     nothing invented, no "current design" guessed.
//   • `rehealSegmentGeometry` — read buses, read live, decide, write through
//     the provisioning door, read back; one result record for the caller.
// Callers: the connect-time healer, the restart watch (uptime drop / cold
// start), the TD-10 apply guard, and the Light Up Now revert capture.

import 'package:flutter/foundation.dart';
import 'package:nexgen_command/features/schedule/gated_preset_save.dart'
    show expectedShapeFromChannels;
import 'package:nexgen_command/features/schedule/geometry_gate.dart';
import 'package:nexgen_command/features/wled/device_channel.dart';
import 'package:nexgen_command/features/wled/segment_layout_guard.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';

export 'package:nexgen_command/features/wled/segment_layout_guard.dart'
    show kSegmentLookKeys, segmentZeroLook, geometryRepairPayload;

/// Connect-time geometry verdict (+80).
enum GeometryHealVerdict {
  /// Cfg or state unreadable — do nothing (never repair a suspicion).
  standAside,

  /// Live layout equals the bus-derived layout — zero writes.
  healthy,

  /// Live layout disagrees with the controller's own buses — re-provision.
  drifted,
}

/// Pure verdict: is the live layout what the controller's own buses say?
///
/// `expected` comes from `hw.led.ins`
/// (`expectedShapeFromChannels(deviceChannelsFromConfig(cfg))`), never from the
/// app's model of the installation. `live` is `segmentShapeFromState`, where
/// null means the body did not tell us the shape.
GeometryHealVerdict decideGeometryHeal({
  required List<SegmentShape> expected,
  required List<SegmentShape>? live,
}) {
  if (expected.isEmpty) return GeometryHealVerdict.standAside;
  if (live == null || live.isEmpty) return GeometryHealVerdict.standAside;
  return listEquals(live, expected)
      ? GeometryHealVerdict.healthy
      : GeometryHealVerdict.drifted;
}

enum GeometryRehealOutcome {
  /// Buses or live layout unreadable — nothing written.
  standAside,

  /// Live layout already matches the buses — nothing written.
  healthy,

  /// Written and the read-back shows the bus layout.
  repaired,

  /// The provisioning POST failed (no 2xx) — nothing to read back.
  postFailed,

  /// The POST was accepted but the read-back does not show the bus layout.
  didNotLand,
}

class GeometryRehealResult {
  const GeometryRehealResult({
    required this.outcome,
    required this.expected,
    this.before,
    this.after,
    this.posted,
    this.note = '',
  });

  final GeometryRehealOutcome outcome;
  final List<SegmentShape> expected;
  final List<SegmentShape>? before;
  final List<SegmentShape>? after;
  final Map<String, dynamic>? posted;
  final String note;

  /// Ids the repair re-created with segment 0's look (empty when none).
  List<int> get lookCopiedTo {
    final seg = posted?['seg'];
    if (seg is! List) return const [];
    return [
      for (final s in seg)
        if (s is Map && s.keys.any(kSegmentLookKeys.contains)) s['id'] as int,
    ];
  }

  @override
  String toString() =>
      'GeometryReheal(${outcome.name} expected=$expected before=$before '
      'after=$after${note.isEmpty ? '' : ' $note'})';
}

/// Read the controller's own buses and live layout, repair a KNOWN mismatch
/// through the provisioning door, and read back. [liveState] lets a caller
/// that just read `/json/state` skip the second read.
Future<GeometryRehealResult> rehealSegmentGeometry(
  WledService svc, {
  Map<String, dynamic>? liveState,
}) async {
  List<SegmentShape> want;
  try {
    final cfg = await svc.getConfig();
    want = cfg == null
        ? const []
        : expectedShapeFromChannels(deviceChannelsFromConfig(cfg));
  } catch (e) {
    want = const [];
  }

  Map<String, dynamic>? state = liveState;
  if (state == null) {
    try {
      state = await svc.getState();
    } catch (e) {
      return GeometryRehealResult(
        outcome: GeometryRehealOutcome.standAside,
        expected: want,
        note: 'live shape unreadable ($e)',
      );
    }
  }
  final live = segmentShapeFromState(state);

  switch (decideGeometryHeal(expected: want, live: live)) {
    case GeometryHealVerdict.standAside:
      return GeometryRehealResult(
        outcome: GeometryRehealOutcome.standAside,
        expected: want,
        before: live,
        note: want.isEmpty ? 'buses unreadable' : 'live shape unavailable',
      );
    case GeometryHealVerdict.healthy:
      return GeometryRehealResult(
        outcome: GeometryRehealOutcome.healthy,
        expected: want,
        before: live,
      );
    case GeometryHealVerdict.drifted:
      break;
  }

  final body = geometryRepairPayload(
    want: [for (final w in want) (id: w.id, start: w.start, stop: w.stop)],
    liveState: state,
  );
  bool ok;
  try {
    // applyGeometryJson, not applyJson: this is the provisioning door. The
    // wire pin refuses bounds on every other path (+80).
    ok = await svc.applyGeometryJson(body);
  } catch (e) {
    debugPrint('[GeometryReheal] provisioning POST threw: $e');
    ok = false;
  }
  if (!ok) {
    return GeometryRehealResult(
      outcome: GeometryRehealOutcome.postFailed,
      expected: want,
      before: live,
      posted: body,
    );
  }

  // READBACK-GATED: a 2xx proves delivery, never content.
  try {
    final after = segmentShapeFromState(await svc.getState());
    if (after != null && listEquals(after, want)) {
      return GeometryRehealResult(
        outcome: GeometryRehealOutcome.repaired,
        expected: want,
        before: live,
        after: after,
        posted: body,
      );
    }
    return GeometryRehealResult(
      outcome: GeometryRehealOutcome.didNotLand,
      expected: want,
      before: live,
      after: after,
      posted: body,
    );
  } catch (e) {
    return GeometryRehealResult(
      outcome: GeometryRehealOutcome.didNotLand,
      expected: want,
      before: live,
      posted: body,
      note: 'readback failed ($e)',
    );
  }
}
