// +113 — deleting a segment by merging its lights into its neighbour keeps the
// channel's light count; the plain delete still drops them.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';

RooflineConfiguration _two() => RooflineConfiguration(
      id: 'c',
      controllerId: 'c',
      name: 'r',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      segments: const [
        RooflineSegment(
            id: 'a', name: 'Run 1', pixelCount: 42, startPixel: 0, channelIndex: 1,
            anchorPixels: [0], points: [Offset(0, 0), Offset(0.5, 0)]),
        RooflineSegment(
            id: 'b', name: 'Corner', pixelCount: 1, startPixel: 42, channelIndex: 1,
            type: SegmentType.corner, architecturalRole: ArchitecturalRole.corner,
            anchorPixels: [0], points: [Offset(0.5, 0), Offset(0.52, 0)]),
        RooflineSegment(
            id: 'c', name: 'Run 2', pixelCount: 2, startPixel: 43, channelIndex: 1,
            points: [Offset(0.52, 0), Offset(0.6, 0)]),
        RooflineSegment(
            id: 'z', name: 'Other channel', pixelCount: 44, startPixel: 0, channelIndex: 0),
      ],
    );

int _total(RooflineConfiguration c, int ch) =>
    c.segmentsForChannel(ch).fold(0, (a, s) => a + s.pixelCount);

void main() {
  test('merging a middle segment gives its lights to the one before it', () {
    final before = _two();
    final after = before.removeSegmentMerging('b');
    expect(after.segmentsForChannel(1).map((s) => s.id), ['a', 'c']);
    expect(_total(after, 1), 45);
    final a = after.segmentById('a')!;
    expect(a.pixelCount, 43);
    expect(a.anchorPixels, [0, 42], reason: 'the corner\'s anchor moves with its light');
    expect(a.points.length, 3, reason: 'outlines joined without the shared point');
    expect(after.segmentById('c')!.startPixel, 43, reason: 'rebased');
    expect(_total(after, 0), 44, reason: 'other channel untouched');
  });

  test('the first segment on a channel merges into the one after it', () {
    final after = _two().removeSegmentMerging('a');
    expect(after.segmentsForChannel(1).map((s) => s.id), ['b', 'c']);
    final b = after.segmentById('b')!;
    expect(b.pixelCount, 43);
    expect(b.startPixel, 0);
    expect(b.anchorPixels, [0, 42]);
    expect(b.type, SegmentType.corner, reason: 'the absorber keeps its identity');
    expect(_total(after, 1), 45);
  });

  test('a segment alone on its channel is left as is (caller falls back to remove)', () {
    final before = _two();
    expect(identical(before.removeSegmentMerging('z'), before), isTrue);
    expect(before.removeSegment('z').segmentsForChannel(0), isEmpty);
  });

  test('mergeNeighborOf names the absorber', () {
    final c = _two();
    expect(c.mergeNeighborOf('b')!.id, 'a');
    expect(c.mergeNeighborOf('a')!.id, 'b');
    expect(c.mergeNeighborOf('z'), isNull);
    expect(c.mergeNeighborOf('nope'), isNull);
  });

  test('only the first segment with a duplicated id is merged away', () {
    final dup = _two().copyWith(segments: [
      ..._two().segments,
      const RooflineSegment(
          id: 'b', name: 'Corner copy', pixelCount: 1, startPixel: 45, channelIndex: 1,
          type: SegmentType.corner),
    ]);
    final after = dup.removeSegmentMerging('b');
    expect(after.segmentsForChannel(1).where((s) => s.id == 'b').length, 1);
    expect(_total(after, 1), 46);
  });
}
