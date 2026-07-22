// Design Studio Slice 5 — boundary nudge + proportional rescale math.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/refine/boundary_nudge_logic.dart';
import 'package:nexgen_command/models/roofline_segment.dart';

/// Channel: corner[0-1] · run[2-21] · peak[22-22] · run[23-49]  (total 50)
List<RooflineSegment> _chan() => [
      const RooflineSegment(id: 'c1', name: 'Corner', startPixel: 0, pixelCount: 2, type: SegmentType.corner, channelIndex: 0, sortOrder: 0),
      const RooflineSegment(id: 'r1', name: 'Run 1', startPixel: 2, pixelCount: 20, type: SegmentType.run, channelIndex: 0, sortOrder: 1),
      const RooflineSegment(id: 'pk', name: 'Peak', startPixel: 22, pixelCount: 1, type: SegmentType.peak, isProminent: true, channelIndex: 0, sortOrder: 2),
      const RooflineSegment(id: 'r2', name: 'Run 2', startPixel: 23, pixelCount: 27, type: SegmentType.run, channelIndex: 0, sortOrder: 3),
    ];

void _assertGapless(List<RooflineSegment> segs, int total) {
  int expected = 0;
  for (int i = 0; i < segs.length; i++) {
    expect(segs[i].startPixel, expected, reason: 'seg $i start');
    expect(segs[i].sortOrder, i);
    expected += segs[i].pixelCount;
  }
  expect(expected, total);
}

void main() {
  group('nudgeBoundary', () {
    test('moving a corner END grows it and shrinks the neighbouring run', () {
      final out = nudgeBoundary(_chan(), 0, BoundaryEdge.end, 3);
      expect(out[0].pixelCount, 5); // corner 2 → 5
      expect(out[1].pixelCount, 17); // run absorbs: 20 → 17
      _assertGapless(out, 50);
    });

    test('moving a run START (−) yields pixels from the previous feature', () {
      // Run 1 start −1 → run grows leftward by 1, corner yields 1 (2 → 1).
      final out = nudgeBoundary(_chan(), 1, BoundaryEdge.start, -1);
      expect(out[0].pixelCount, 1); // corner yields 1
      expect(out[1].pixelCount, 21); // run absorbs 1
      _assertGapless(out, 50);
    });

    test('yield clamps at the 1px floor (2px corner can only give 1)', () {
      final out = nudgeBoundary(_chan(), 1, BoundaryEdge.start, -5);
      expect(out[0].pixelCount, 1); // clamped, not 0/negative
      expect(out[1].pixelCount, 21);
      _assertGapless(out, 50);
    });

    test('guard: a feature can never invert / drop below 1px (clamped)', () {
      // Try to shrink the 1px peak's left neighbour boundary massively.
      final out = nudgeBoundary(_chan(), 2, BoundaryEdge.start, -100);
      // boundary(1,2): left=run1(20), right=peak(1). delta clamped so peak≥1
      // and run1≥1. Growing peak means delta<0 shrinks left... peak is right,
      // so delta -100 → right(peak) grows, left(run1) shrinks to 1.
      _assertGapless(out, 50);
      expect(out.every((s) => s.pixelCount >= 1), isTrue);
    });

    test('apex (1px peak) stays ≥1 when its boundaries are nudged', () {
      // Grow run1's end into the peak: boundary(1,2) delta +100 → peak shrinks,
      // clamped so peak stays ≥1.
      final out = nudgeBoundary(_chan(), 1, BoundaryEdge.end, 100);
      final peak = out.firstWhere((s) => s.id == 'pk');
      expect(peak.pixelCount, greaterThanOrEqualTo(1));
      _assertGapless(out, 50);
    });

    test('first feature start and last feature end are fixed (no-op)', () {
      expect(nudgeBoundary(_chan(), 0, BoundaryEdge.start, 5), _chan());
      expect(nudgeBoundary(_chan(), 3, BoundaryEdge.end, 5), _chan());
    });

    test('total is always preserved', () {
      for (final d in [-5, -1, 1, 5, 50]) {
        expect(channelTotal(nudgeBoundary(_chan(), 1, BoundaryEdge.end, d)), 50);
      }
    });
  });

  group('rescaleChannel', () {
    test('proportional up: sums exactly to the new total, gapless, all ≥1', () {
      final out = rescaleChannel(_chan(), 50, 100); // 2x
      expect(channelTotal(out), 100);
      expect(out.every((s) => s.pixelCount >= 1), isTrue);
      _assertGapless(out, 100);
      // Roughly doubled (largest-remainder rounding).
      expect(out[1].pixelCount, inInclusiveRange(38, 42)); // run 20 → ~40
    });

    test('proportional down: sums exactly, apex survives at ≥1', () {
      final out = rescaleChannel(_chan(), 50, 25);
      expect(channelTotal(out), 25);
      expect(out.firstWhere((s) => s.id == 'pk').pixelCount, greaterThanOrEqualTo(1));
      _assertGapless(out, 25);
    });

    test('same total is a no-op reflow', () {
      expect(channelTotal(rescaleChannel(_chan(), 50, 50)), 50);
    });

    test('newTotal smaller than feature count drops smallest features', () {
      // 4 features, newTotal 3 → keep 3 largest, each ≥1.
      final out = rescaleChannel(_chan(), 50, 3);
      expect(channelTotal(out), 3);
      expect(out.length, 3);
      expect(out.every((s) => s.pixelCount >= 1), isTrue);
    });
  });
}
