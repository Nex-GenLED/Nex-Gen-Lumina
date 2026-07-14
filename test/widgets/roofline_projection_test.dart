// test/widgets/roofline_projection_test.dart
//
// Covers the shared roofline projection (lib/widgets/roofline_projection.dart)
// and proves the two live surfaces (dashboard overlay + Design Studio preview)
// route through it identically — the drift guard for the "roofline renders low +
// flattened" bug, whose root cause was the Design Studio path feeding the cover
// transform no source aspect ratio so it silently no-op'd.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/models/roofline_mask.dart';
import 'package:nexgen_command/widgets/roofline_light_painter.dart';
import 'package:nexgen_command/widgets/roofline_projection.dart';

/// Canvas that records every drawCircle center; everything else is a no-op.
class _RecordingCanvas implements Canvas {
  final List<Offset> circles = [];

  @override
  void drawCircle(Offset c, double radius, Paint paint) => circles.add(c);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void expectOffset(Offset actual, Offset expected, {double eps = 1e-9}) {
  expect(actual.dx, closeTo(expected.dx, eps), reason: 'dx');
  expect(actual.dy, closeTo(expected.dy, eps), reason: 'dy');
}

void main() {
  // The painter parity tests exercise dart:ui drawing (gradients/shaders),
  // which needs the test binding initialized.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('projectRoofline — cover', () {
    test('vertical-crop regime (src taller/narrower than target): scaleY>1 + offsetY', () {
      // Wide canvas (aspect 2.0) with a square photo (aspect 1.0). Cover fills
      // width, overflows height → top/bottom cropped. This is the bug's regime.
      const size = Size(200, 100);
      const src = 1.0;
      // fittedH = 200 (2x canvas height) → vertical extent doubled; offsetY = -50.
      final pts = projectRoofline(
        normalized: const [
          Offset(0.5, 0.25), // interior
          Offset(0.5, 0.5), // interior
          Offset(0.5, 0.0), // above visible band → clamps
          Offset(0.5, 1.0), // below visible band → clamps
        ],
        canvasSize: size,
        sourceAspectRatio: src,
      );
      expectOffset(pts[0], const Offset(100, 0)); // -50 + 0.25*200
      expectOffset(pts[1], const Offset(100, 50)); // -50 + 0.5*200
      expectOffset(pts[2], const Offset(100, 0)); // -50 clamped to 0
      expectOffset(pts[3], const Offset(100, 100)); // 150 clamped to 100
    });

    test('horizontal-crop regime (src wider than target): scaleX>1 + offsetX', () {
      const size = Size(100, 200); // aspect 0.5
      const src = 1.0; // square is wider than tall container
      final pts = projectRoofline(
        normalized: const [
          Offset(0.25, 0.5),
          Offset(0.5, 0.5),
          Offset(0.75, 0.5),
        ],
        canvasSize: size,
        sourceAspectRatio: src,
      );
      expectOffset(pts[0], const Offset(0, 100)); // -50 + 0.25*200
      expectOffset(pts[1], const Offset(50, 100)); // -50 + 0.5*200
      expectOffset(pts[2], const Offset(100, 100)); // -50 + 0.75*200
    });

    test('src aspect == target aspect → identity (raw) map', () {
      const size = Size(200, 100); // aspect 2.0
      final pts = projectRoofline(
        normalized: const [Offset(0.3, 0.7)],
        canvasSize: size,
        sourceAspectRatio: 2.0,
      );
      expectOffset(pts.single, const Offset(60, 70));
    });

    test('nonzero alignment shifts the visible crop window', () {
      const size = Size(200, 100);
      const src = 1.0;
      // Top alignment (dy = -1) → offsetY = 0 (crop keeps the top of the photo).
      final top = projectRoofline(
        normalized: const [Offset(0.5, 0.0), Offset(0.5, 0.5)],
        canvasSize: size,
        sourceAspectRatio: src,
        alignment: const Offset(0, -1),
      );
      expectOffset(top[0], const Offset(100, 0)); // 0 + 0
      expectOffset(top[1], const Offset(100, 100)); // 0 + 0.5*200
    });
  });

  group('projectRoofline — contain (letterbox)', () {
    test('wide canvas, square photo → left/right letterbox', () {
      const size = Size(200, 100); // aspect 2.0
      final pts = projectRoofline(
        normalized: const [Offset(0, 0), Offset(1, 1), Offset(0.5, 0.5)],
        canvasSize: size,
        sourceAspectRatio: 1.0,
        fit: BoxFit.contain,
      );
      // scale = 100 → fitted 100x100, offsetX = 50, offsetY = 0.
      expectOffset(pts[0], const Offset(50, 0));
      expectOffset(pts[1], const Offset(150, 100));
      expectOffset(pts[2], const Offset(100, 50));
    });

    test('tall canvas, wide photo → top/bottom letterbox', () {
      const size = Size(100, 200); // aspect 0.5
      final pts = projectRoofline(
        normalized: const [Offset(0, 0), Offset(1, 1)],
        canvasSize: size,
        sourceAspectRatio: 2.0,
        fit: BoxFit.contain,
      );
      // scale = 50 → fitted 100x50, offsetX = 0, offsetY = 75.
      expectOffset(pts[0], const Offset(0, 75));
      expectOffset(pts[1], const Offset(100, 125));
    });
  });

  group('projectRoofline — fill / degenerate', () {
    test('BoxFit.fill is the raw stretch map (aspect ignored)', () {
      const size = Size(200, 100);
      final pts = projectRoofline(
        normalized: const [Offset(0.2, 0.2)],
        canvasSize: size,
        sourceAspectRatio: 1.0, // ignored under fill
        fit: BoxFit.fill,
      );
      expectOffset(pts.single, const Offset(40, 20));
    });

    test('non-finite / non-positive source aspect falls back to raw map', () {
      const size = Size(200, 100);
      for (final bad in [0.0, -1.0, double.nan, double.infinity]) {
        final pts = projectRoofline(
          normalized: const [Offset(0.2, 0.2)],
          canvasSize: size,
          sourceAspectRatio: bad,
        );
        expectOffset(pts.single, const Offset(40, 20));
      }
    });

    test('empty points / degenerate canvas → empty', () {
      expect(
        projectRoofline(
            normalized: const [], canvasSize: const Size(10, 10), sourceAspectRatio: 1),
        isEmpty,
      );
      expect(
        projectRoofline(
            normalized: const [Offset(0.5, 0.5)],
            canvasSize: const Size(0, 10),
            sourceAspectRatio: 1),
        isEmpty,
      );
    });

    test('clampToCanvas: false lets cover points extend past the canvas', () {
      const size = Size(200, 100);
      final pts = projectRoofline(
        normalized: const [Offset(0.5, 0.0)],
        canvasSize: size,
        sourceAspectRatio: 1.0,
        clampToCanvas: false,
      );
      expectOffset(pts.single, const Offset(100, -50)); // un-clamped
    });
  });

  group('legacy RooflineMask.getPointsForCover wraps projectRoofline', () {
    test('returns normalized container coords matching the shared math', () {
      // Square trace point on a square photo shown in a 2:1 container: cover
      // crops top/bottom, so a point at photo-y 0.5 stays centered (0.5) and a
      // point at y 0.25 maps above center.
      const mask = RooflineMask(
        points: [Offset(0.5, 0.5), Offset(0.5, 0.25)],
        isManuallyDrawn: true,
        sourceAspectRatio: 1.0,
      );
      // ignore: deprecated_member_use_from_same_package
      final norm = mask.getPointsForCover(targetAspectRatio: 2.0);
      // projectRoofline into a 200x100 canvas then normalize back (x/200, y/100).
      final screen = projectRoofline(
        normalized: mask.points,
        canvasSize: const Size(200, 100),
        sourceAspectRatio: 1.0,
      );
      for (var i = 0; i < norm.length; i++) {
        expectOffset(norm[i], Offset(screen[i].dx / 200.0, screen[i].dy / 100.0));
      }
    });
  });

  group('painter parity — dashboard-style vs Design-Studio-style construction', () {
    // Same trace, same aspect, same canvas: the ONLY difference is where the
    // source aspect comes from (mask vs SegmentPathData). Output must be
    // byte-identical, proving both surfaces share one projection.
    const size = Size(240, 120); // aspect 2.0
    const src = 1.0; // vertical-crop regime (the bug's regime)
    const points = [Offset(0.1, 0.6), Offset(0.5, 0.2), Offset(0.9, 0.6)]; // a peak
    final ledColors = List<Color>.filled(8, const Color(0xFFFFFFFF));

    List<Offset> render(RooflineLightPainter painter) {
      final rec = _RecordingCanvas();
      painter.paint(rec, size);
      return rec.circles;
    }

    test('identical circles when aspect comes from mask vs from the segment', () {
      final dashboardStyle = RooflineLightPainter(
        colors: const [Colors.white],
        isOn: true,
        brightness: 255,
        realIndexMode: true,
        useBoxFitCover: true,
        targetAspectRatio: 2.0,
        // Dashboard supplies the aspect via its mask.
        mask: const RooflineMask(
            points: points, isManuallyDrawn: true, sourceAspectRatio: src),
        segmentPaths: [
          SegmentPathData(
              points: points,
              channelIndex: 0,
              pixelCount: 8,
              ledColors: ledColors),
        ],
      );
      final designStudioStyle = RooflineLightPainter(
        colors: const [Colors.white],
        isOn: true,
        brightness: 255,
        realIndexMode: true,
        useBoxFitCover: true,
        targetAspectRatio: 2.0,
        // Design Studio supplies the aspect via the segment (no mask).
        segmentPaths: [
          SegmentPathData(
              points: points,
              channelIndex: 0,
              pixelCount: 8,
              ledColors: ledColors,
              sourceAspectRatio: src),
        ],
      );

      final a = render(dashboardStyle);
      final b = render(designStudioStyle);
      expect(a, isNotEmpty);
      expect(b.length, a.length);
      for (var i = 0; i < a.length; i++) {
        expectOffset(b[i], a[i]);
      }
    });

    test('cover compensation is active: differs from the raw map and expands Y', () {
      final cover = RooflineLightPainter(
        colors: const [Colors.white],
        isOn: true,
        brightness: 255,
        realIndexMode: true,
        useBoxFitCover: true,
        targetAspectRatio: 2.0,
        segmentPaths: [
          SegmentPathData(
              points: points,
              channelIndex: 0,
              pixelCount: 8,
              ledColors: ledColors,
              sourceAspectRatio: src),
        ],
      );
      final raw = RooflineLightPainter(
        colors: const [Colors.white],
        isOn: true,
        brightness: 255,
        realIndexMode: true,
        useBoxFitCover: false, // legacy raw stretch — the buggy behaviour
        segmentPaths: [
          SegmentPathData(
              points: points, channelIndex: 0, pixelCount: 8, ledColors: ledColors),
        ],
      );

      final coverC = render(cover);
      final rawC = render(raw);
      expect(coverC, isNot(equals(rawC)),
          reason: 'cover crop must change geometry vs the raw map');

      double span(List<Offset> cs) =>
          cs.map((o) => o.dy).reduce((a, b) => a > b ? a : b) -
          cs.map((o) => o.dy).reduce((a, b) => a < b ? a : b);
      // Vertical-crop regime doubles the vertical scale, so the peak reads with
      // a larger vertical span than the flattened raw map.
      expect(span(coverC), greaterThan(span(rawC)),
          reason: 'cover un-flattens the roof pitch');
    });
  });
}
