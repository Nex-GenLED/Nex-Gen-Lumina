import 'package:nexgen_command/models/roofline_segment.dart';

/// Design Studio Slice 5 — pure boundary-nudge + proportional-rescale math for
/// the customer refine surface. Operates on ONE channel's ordered, gapless
/// feature list (channel-local, covering `[0, total)`). Deterministic, no I/O.

/// Which edge of a feature the customer is nudging.
enum BoundaryEdge { start, end }

int channelTotal(List<RooflineSegment> segments) =>
    segments.fold(0, (sum, s) => sum + s.pixelCount);

/// Recomputes contiguous `startPixel`/`sortOrder` so the list stays gapless.
List<RooflineSegment> _reflow(List<RooflineSegment> segments) {
  int start = 0;
  final out = <RooflineSegment>[];
  for (int i = 0; i < segments.length; i++) {
    out.add(segments[i].copyWith(startPixel: start, sortOrder: i));
    start += segments[i].pixelCount;
  }
  return out;
}

/// Nudges [featureIndex]'s [edge] boundary by [delta] pixels. The ADJACENT
/// feature absorbs or yields the pixels so the list stays gapless and the
/// channel total is preserved. Guards (delta is CLAMPED, not rejected):
///   • no feature inverts — every feature keeps ≥1 px (so an apex stays ≥1
///     and within its peak family);
///   • a boundary can't cross the neighbour's opposite boundary (the neighbour
///     can't shrink below 1 px);
///   • the first feature's start (0) and the last feature's end (channel end)
///     are fixed — nudging them is a no-op.
List<RooflineSegment> nudgeBoundary(
  List<RooflineSegment> segments,
  int featureIndex,
  BoundaryEdge edge,
  int delta,
) {
  if (featureIndex < 0 || featureIndex >= segments.length) return segments;

  // Map the (feature, edge) to the interior boundary b between seg[b] & seg[b+1].
  final int b;
  if (edge == BoundaryEdge.end) {
    if (featureIndex >= segments.length - 1) return segments; // last end fixed
    b = featureIndex;
  } else {
    if (featureIndex <= 0) return segments; // first start fixed
    b = featureIndex - 1;
  }

  final left = segments[b];
  final right = segments[b + 1];

  // Clamp so both sides keep ≥1 px: left may grow up to right.count-1 (right
  // shrinks to 1), or shrink down to -(left.count-1) (left shrinks to 1).
  final clamped = delta.clamp(-(left.pixelCount - 1), right.pixelCount - 1);
  if (clamped == 0) return segments;

  final next = [...segments];
  next[b] = left.copyWith(pixelCount: left.pixelCount + clamped);
  next[b + 1] = right.copyWith(pixelCount: right.pixelCount - clamped);
  return _reflow(next);
}

/// Proportionally rescales all features from [oldTotal] to [newTotal] (e.g. the
/// live `bus.len` after the roofline changed). Every feature keeps ≥1 px, the
/// result is gapless and sums EXACTLY to [newTotal] (largest-remainder rounding,
/// then a ±1 sweep to absorb the rounding drift). If [newTotal] is smaller than
/// the feature count, the lowest-priority (smallest) features are dropped so the
/// survivors can each keep ≥1 px.
List<RooflineSegment> rescaleChannel(
  List<RooflineSegment> segments,
  int oldTotal,
  int newTotal,
) {
  if (segments.isEmpty || newTotal <= 0) return segments;
  if (oldTotal <= 0 || newTotal == oldTotal) return _reflow(segments);

  var working = segments;
  // Can't keep every feature ≥1 if there are more features than pixels — drop
  // the smallest until they fit.
  if (working.length > newTotal) {
    working = [...working]..sort((a, b) => b.pixelCount.compareTo(a.pixelCount));
    working = working.take(newTotal).toList()
      ..sort((a, b) => a.startPixel.compareTo(b.startPixel));
  }

  final n = working.length;
  final scale = newTotal / oldTotal;
  final ideal = [for (final s in working) s.pixelCount * scale];
  // Floor to ≥1, track fractional remainders for largest-remainder rounding.
  final counts = [for (final v in ideal) v.floor() < 1 ? 1 : v.floor()];
  int sum = counts.fold(0, (a, b) => a + b);

  // Distribute the remaining pixels to the largest fractional parts.
  final order = List.generate(n, (i) => i)
    ..sort((a, b) => (ideal[b] - ideal[b].floor())
        .compareTo(ideal[a] - ideal[a].floor()));
  int k = 0;
  while (sum < newTotal) {
    counts[order[k % n]] += 1;
    sum++;
    k++;
  }
  // Over-shot (min-1 clamping can push sum above target) → shave largest first.
  while (sum > newTotal) {
    final big = _indexOfMaxAbove1(counts);
    if (big < 0) break;
    counts[big] -= 1;
    sum--;
  }

  final out = [
    for (int i = 0; i < n; i++) working[i].copyWith(pixelCount: counts[i]),
  ];
  return _reflow(out);
}

int _indexOfMaxAbove1(List<int> counts) {
  int best = -1, bestVal = 1;
  for (int i = 0; i < counts.length; i++) {
    if (counts[i] > bestVal) {
      best = i;
      bestVal = counts[i];
    }
  }
  return best;
}
