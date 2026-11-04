// lib/features/wled/segment_count_save.dart
//
// +122 item 4 (TD-9 defect 3) — the LED-count save's segment write.
//
// HardwareConfigScreen._saveSegmentCounts ("Tier 1, LED counts only") wrote
// the new `hw.led` counts, then one `updateSegmentConfig` POST per segment,
// with no read-back and no retry. If the controller re-initialised its buses
// between those POSTs, segment 0's bounds were lost while segment 1's landed:
// segment 0 spanning the strip, segment 1 overlapping it in the firmware's
// default amber — the half-and-half shape seen in the field — and nothing in
// the app showed it. Installers use that screen during an install.
//
// Now: ONE geometry POST for every segment (the same repair body the healer
// writes, so a segment the live layout lacks takes segment 0's look), a
// read-back, and one retry. The outcome is reported in plain words.

import 'package:flutter/foundation.dart';
import 'package:nexgen_command/features/schedule/geometry_gate.dart';
import 'package:nexgen_command/features/wled/segment_layout_guard.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';

/// One segment per enabled port, in port order, laid end to end.
List<SegmentBounds> segmentBoundsForCounts(List<int> counts) {
  final out = <SegmentBounds>[];
  var start = 0;
  for (var i = 0; i < counts.length; i++) {
    out.add((id: i, start: start, stop: start + counts[i]));
    start += counts[i];
  }
  return out;
}

enum SegmentCountSaveOutcome {
  /// The read-back after the first POST showed the wanted layout.
  landed,

  /// The first POST did not land; the retry did.
  landedOnRetry,

  /// A POST failed outright (no 2xx) — the layout was not checked.
  postFailed,

  /// Every POST was accepted but the read-back never showed the wanted
  /// layout. [SegmentCountSaveResult.after] is what it showed.
  didNotLand,
}

class SegmentCountSaveResult {
  const SegmentCountSaveResult({
    required this.outcome,
    required this.posts,
    this.after,
  });

  final SegmentCountSaveOutcome outcome;

  /// Geometry POSTs sent (a per-segment fallback counts as one).
  final int posts;

  /// The layout the last read-back showed, null when unreadable.
  final List<SegmentShape>? after;

  @override
  String toString() =>
      'SegmentCountSave(${outcome.name} posts=$posts after=$after)';
}

String segmentCountSaveMessage(SegmentCountSaveOutcome outcome) {
  switch (outcome) {
    case SegmentCountSaveOutcome.landed:
      return 'LED counts updated.';
    case SegmentCountSaveOutcome.landedOnRetry:
      return 'LED counts updated on the second attempt.';
    case SegmentCountSaveOutcome.postFailed:
    case SegmentCountSaveOutcome.didNotLand:
      return 'LED counts saved, but the segment layout did not read back as '
          'expected. Check your controller.';
  }
}

/// Write [want] as one geometry POST, read the layout back, retry once on a
/// mismatch. The live layout is read first so a segment it lacks is re-created
/// with segment 0's look (never the firmware's default amber).
///
/// A repository without the provisioning door (the relay: `applyGeometryJson`
/// is the base class's `false`) gets the bounds per segment, as before, and
/// the same read-back. A LAN service's `false` is a real failure and is
/// reported as one.
Future<SegmentCountSaveResult> writeSegmentBoundsWithReadback(
  WledRepository repo,
  List<SegmentBounds> want, {
  int retries = 1,
}) async {
  if (want.isEmpty) {
    return const SegmentCountSaveResult(
        outcome: SegmentCountSaveOutcome.landed, posts: 0);
  }
  final wantShape = [for (final b in want) SegmentShape(b.id, b.start, b.stop)];

  Map<String, dynamic>? live;
  try {
    live = await repo.getState();
  } catch (_) {
    live = null;
  }

  var posts = 0;
  List<SegmentShape>? after;
  for (var attempt = 0; attempt <= retries; attempt++) {
    posts++;
    bool ok;
    try {
      ok = await repo
          .applyGeometryJson(geometryRepairPayload(want: want, liveState: live));
      if (!ok && repo is! WledService) {
        ok = await _perSegment(repo, want);
      }
    } catch (e) {
      debugPrint('Segment count save: POST threw: $e');
      ok = false;
    }
    if (!ok) {
      return SegmentCountSaveResult(
          outcome: SegmentCountSaveOutcome.postFailed,
          posts: posts,
          after: after);
    }
    try {
      live = await repo.getState();
      after = segmentShapeFromState(live);
    } catch (_) {
      live = null;
      after = null;
    }
    if (after != null && listEquals(after, wantShape)) {
      return SegmentCountSaveResult(
        outcome: attempt == 0
            ? SegmentCountSaveOutcome.landed
            : SegmentCountSaveOutcome.landedOnRetry,
        posts: posts,
        after: after,
      );
    }
  }
  return SegmentCountSaveResult(
      outcome: SegmentCountSaveOutcome.didNotLand, posts: posts, after: after);
}

Future<bool> _perSegment(WledRepository repo, List<SegmentBounds> want) async {
  var allOk = true;
  for (final b in want) {
    final ok = await repo.updateSegmentConfig(
        segmentId: b.id, start: b.start, stop: b.stop);
    if (!ok) allOk = false;
  }
  return allOk;
}
