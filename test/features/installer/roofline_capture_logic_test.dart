// Design Studio Slice 2 — pure capture logic + capture-state tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/installer/map_roofline/roofline_capture_logic.dart';
import 'package:nexgen_command/features/installer/map_roofline/roofline_capture_state.dart';
import 'package:nexgen_command/models/roofline_segment.dart';

void main() {
  group('compileMarksToChannelSegments', () {
    test('no marks → one run covering the whole channel', () {
      final segs = compileMarksToChannelSegments(
          channelIndex: 0, pixelCount: 40, marks: const []);
      expect(segs.length, 1);
      expect(segs.first.type, SegmentType.run);
      expect(segs.first.startPixel, 0);
      expect(segs.first.pixelCount, 40);
    });

    test('a corner splits the channel into run · corner · run', () {
      final segs = compileMarksToChannelSegments(
        channelIndex: 0,
        pixelCount: 20,
        marks: const [CaptureMark(pixel: 5, kind: MarkKind.corner)],
      );
      expect(segs.map((s) => s.type),
          [SegmentType.run, SegmentType.corner, SegmentType.run]);
      expect(segs.map((s) => s.startPixel), [0, 5, 6]);
      expect(segs.map((s) => s.pixelCount), [5, 1, 14]);
      expect(segs.map((s) => s.sortOrder), [0, 1, 2]);
      // Run labels auto-numbered.
      expect(segs[0].name, 'Run 1');
      expect(segs[2].name, 'Run 2');
    });

    test('runBoundary splits the inferred run into two runs', () {
      final segs = compileMarksToChannelSegments(
        channelIndex: 0,
        pixelCount: 20,
        marks: const [CaptureMark(pixel: 10, kind: MarkKind.runBoundary)],
      );
      expect(segs.length, 2);
      expect(segs.every((s) => s.type == SegmentType.run), isTrue);
      expect(segs.map((s) => s.startPixel), [0, 10]);
      expect(segs.map((s) => s.pixelCount), [10, 10]);
    });

    test('peak mark expands to symmetric up/apex/down with directions', () {
      final segs = compileMarksToChannelSegments(
        channelIndex: 0,
        pixelCount: 60,
        marks: const [CaptureMark(pixel: 30, kind: MarkKind.peak, slopeLength: 6)],
      );
      // run · peakUp · peak · peakDown · run
      expect(segs.map((s) => s.type), [
        SegmentType.run,
        SegmentType.peak,
        SegmentType.peak,
        SegmentType.peak,
        SegmentType.run,
      ]);
      final up = segs[1], apex = segs[2], down = segs[3];
      expect(up.direction, SegmentDirection.upward);
      expect(up.startPixel, 24);
      expect(up.pixelCount, 6);
      expect(apex.startPixel, 30);
      expect(apex.pixelCount, 1);
      expect(apex.isProminent, isTrue);
      expect(down.direction, SegmentDirection.downward);
      expect(down.startPixel, 31);
      expect(down.pixelCount, 6);
    });

    test('audit-example shape: corner/run/corner/peak/corner', () {
      // 1px corners at 0 and 24, peak apex at 32 (slope 6), corner at 57.
      final segs = compileMarksToChannelSegments(
        channelIndex: 0,
        pixelCount: 64,
        marks: const [
          CaptureMark(pixel: 0, kind: MarkKind.corner),
          CaptureMark(pixel: 24, kind: MarkKind.corner),
          CaptureMark(pixel: 32, kind: MarkKind.peak, slopeLength: 6),
          CaptureMark(pixel: 57, kind: MarkKind.corner),
        ],
      );
      // corner, run, corner, run, peakUp, peak, peakDown, run, corner, run
      final types = segs.map((s) => s.type.name).toList();
      expect(types.first, 'corner');
      expect(types.where((t) => t == 'peak').length, 3);
      expect(types.contains('run'), isTrue);
      // Contiguous, non-overlapping, covers the whole channel.
      int expectedStart = 0;
      for (final s in segs) {
        expect(s.startPixel, expectedStart);
        expectedStart = s.endPixel + 1;
      }
      expect(expectedStart, 64);
    });

    test('overlapping features: later overlap dropped (keep earlier)', () {
      final segs = compileMarksToChannelSegments(
        channelIndex: 0,
        pixelCount: 20,
        marks: const [
          CaptureMark(pixel: 5, kind: MarkKind.corner, width: 4), // [5,9)
          CaptureMark(pixel: 6, kind: MarkKind.corner), // overlaps → dropped
        ],
      );
      final corners = segs.where((s) => s.type == SegmentType.corner).toList();
      expect(corners.length, 1);
      expect(corners.first.startPixel, 5);
      expect(corners.first.pixelCount, 4);
    });

    test('out-of-range mark pixel is clamped into the channel', () {
      final segs = compileMarksToChannelSegments(
        channelIndex: 0,
        pixelCount: 20,
        marks: const [CaptureMark(pixel: 100, kind: MarkKind.corner)],
      );
      final corner = segs.firstWhere((s) => s.type == SegmentType.corner);
      expect(corner.startPixel, 19);
    });

    test('empty for non-positive pixelCount', () {
      expect(
        compileMarksToChannelSegments(
            channelIndex: 0, pixelCount: 0, marks: const []),
        isEmpty,
      );
    });
  });

  group('symmetricPeakSegments', () {
    test('produces up/apex/down clamped to the channel', () {
      final segs = symmetricPeakSegments(
          channelIndex: 1, pixelCount: 50, apexPixel: 10, slopeLength: 4);
      expect(segs.map((s) => s.direction), [
        SegmentDirection.upward,
        SegmentDirection.leftToRight, // apex
        SegmentDirection.downward,
      ]);
      expect(segs.every((s) => s.channelIndex == 1), isTrue);
      expect(segs[0].startPixel, 6);
      expect(segs[0].pixelCount, 4);
      expect(segs[2].startPixel, 11);
      expect(segs[2].pixelCount, 4);
    });
  });

  group('copyChannelSegments', () {
    test('re-keys onto the target channel, preserving ranges/types', () {
      final source = compileMarksToChannelSegments(
        channelIndex: 0,
        pixelCount: 30,
        marks: const [CaptureMark(pixel: 10, kind: MarkKind.corner)],
      );
      final copied = copyChannelSegments(source, targetChannelIndex: 2);
      expect(copied.length, source.length);
      expect(copied.every((s) => s.channelIndex == 2), isTrue);
      expect(copied.map((s) => s.type), source.map((s) => s.type));
      expect(copied.map((s) => s.startPixel), source.map((s) => s.startPixel));
      // Ids re-keyed (no collision with source ids).
      expect(copied.first.id.startsWith('ch2_'), isTrue);
    });
  });

  group('RooflineCaptureNotifier', () {
    test('addMark keeps insertion order; undoLast removes the most recent', () {
      final n = RooflineCaptureNotifier();
      n.addMark(0, const CaptureMark(pixel: 30, kind: MarkKind.corner));
      n.addMark(0, const CaptureMark(pixel: 5, kind: MarkKind.corner));
      expect(n.channel(0).marks.map((m) => m.pixel), [30, 5]); // insertion order
      n.undoLast(0);
      expect(n.channel(0).marks.map((m) => m.pixel), [30]); // removed the '5'
    });

    test('updateMark by index adjusts a mark; markSaved/markSkipped flags', () {
      final n = RooflineCaptureNotifier();
      n.addMark(0, const CaptureMark(pixel: 10, kind: MarkKind.corner));
      n.updateMark(0, 0,
          const CaptureMark(pixel: 12, kind: MarkKind.corner));
      expect(n.channel(0).marks.first.pixel, 12);

      expect(n.channel(0).saved, isFalse);
      n.markSaved(0);
      expect(n.channel(0).saved, isTrue);
      expect(n.channel(0).isAddressed, isTrue);

      n.markSkipped(1);
      expect(n.channel(1).skipped, isTrue);
      expect(n.channel(1).isAddressed, isTrue);
    });

    test('setMarks replaces (copy-across-channels) and clears flags', () {
      final n = RooflineCaptureNotifier();
      n.markSkipped(1);
      n.setMarks(1, const [CaptureMark(pixel: 3, kind: MarkKind.peak)]);
      expect(n.channel(1).marks.length, 1);
      expect(n.channel(1).skipped, isFalse);
    });

    test('reset clears all channel state', () {
      final n = RooflineCaptureNotifier();
      n.addMark(0, const CaptureMark(pixel: 1, kind: MarkKind.corner));
      n.reset();
      expect(n.state, isEmpty);
    });
  });
}
