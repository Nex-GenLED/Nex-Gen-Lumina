import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:nexgen_command/models/roofline_mask.dart';

/// Service that auto-detects the roofline from a house photo.
///
/// Uses a two-pass strategy:
///   1. **Sky segmentation** — sample the sky color from the top rows and scan
///      downward in each column to find where the image diverges from sky.
///   2. **Edge refinement** — run a Sobel-Y gradient pass in a narrow band
///      around the sky boundary to snap to the nearest strong horizontal edge.
///
/// This approach is far more accurate than raw edge detection alone because it
/// ignores tree lines, ground-level fences, and other strong edges that are not
/// the roofline.
class RooflineAutoDetectService {
  /// Detect the roofline from an image provider.
  ///
  /// Returns a [RooflineMask] with normalized (0-1) points tracing the
  /// detected roofline. Returns null if detection fails.
  static Future<RooflineMask?> detectFromImage(ImageProvider imageProvider) async {
    try {
      final image = await _loadImage(imageProvider);
      if (image == null) return null;

      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) return null;

      final width = image.width;
      final height = image.height;
      final pixels = byteData.buffer.asUint8List();

      final rooflinePoints = _detect(pixels, width, height);
      if (rooflinePoints.isEmpty) return null;

      return RooflineMask(
        points: rooflinePoints,
        maskHeight: 0.25,
        isManuallyDrawn: false,
        sourceAspectRatio: width / height,
      );
    } catch (e) {
      debugPrint('RooflineAutoDetect: Failed to detect roofline: $e');
      return null;
    }
  }

  // ── Image loading ──────────────────────────────────────────────────────

  static Future<ui.Image?> _loadImage(ImageProvider provider) async {
    try {
      final stream = provider.resolve(ImageConfiguration.empty);
      final completer = Completer<ui.Image>();
      final listener = ImageStreamListener(
        (info, _) => completer.complete(info.image),
        onError: (error, stack) => completer.completeError(error),
      );
      stream.addListener(listener);
      final image = await completer.future.timeout(const Duration(seconds: 10));
      stream.removeListener(listener);
      return image;
    } catch (e) {
      debugPrint('RooflineAutoDetect: Image load failed: $e');
      return null;
    }
  }

  // ── Pixel helpers ──────────────────────────────────────────────────────

  static int _r(Uint8List px, int w, int x, int y) => px[(y * w + x) * 4];
  static int _g(Uint8List px, int w, int x, int y) => px[(y * w + x) * 4 + 1];
  static int _b(Uint8List px, int w, int x, int y) => px[(y * w + x) * 4 + 2];

  static int _luminance(Uint8List px, int w, int x, int y) {
    final i = (y * w + x) * 4;
    if (i + 2 >= px.length) return 0;
    return ((px[i] * 299 + px[i + 1] * 587 + px[i + 2] * 114) / 1000).round();
  }

  /// Squared color distance between a pixel and a reference RGB triple.
  static double _colorDistSq(Uint8List px, int w, int x, int y,
      double refR, double refG, double refB) {
    final dr = _r(px, w, x, y) - refR;
    final dg = _g(px, w, x, y) - refG;
    final db = _b(px, w, x, y) - refB;
    return dr * dr + dg * dg + db * db;
  }

  // ── Main detection pipeline ────────────────────────────────────────────

  static List<Offset> _detect(Uint8List pixels, int width, int height) {
    if (height < 20 || width < 20) return [];

    // ── Pass 1: Compute the sky reference color ──
    // Sample the top 3% of the image (but at least 4 rows, at most 30).
    final skyRows = (height * 0.03).round().clamp(4, 30);
    double skyR = 0, skyG = 0, skyB = 0;
    int skySamples = 0;

    // Sample from the central 80% width to avoid corner vignetting.
    final xMargin = (width * 0.10).round();
    for (int y = 0; y < skyRows; y++) {
      for (int x = xMargin; x < width - xMargin; x++) {
        skyR += _r(pixels, width, x, y);
        skyG += _g(pixels, width, x, y);
        skyB += _b(pixels, width, x, y);
        skySamples++;
      }
    }
    if (skySamples == 0) return [];
    skyR /= skySamples;
    skyG /= skySamples;
    skyB /= skySamples;

    // Compute the variance of sky color to set an adaptive threshold.
    double skyVariance = 0;
    for (int y = 0; y < skyRows; y++) {
      for (int x = xMargin; x < width - xMargin; x++) {
        skyVariance += _colorDistSq(pixels, width, x, y, skyR, skyG, skyB);
      }
    }
    skyVariance /= skySamples;
    // Threshold = mean sky variance * multiplier. Higher multiplier = more
    // tolerant of sky color variation (clouds, gradient skies).
    final skyThreshold = skyVariance * 5.0 + 900.0; // floor of 900 ≈ 30² RGB distance

    // ── Pass 2: Sky boundary scan ──
    // For each column, scan downward and find the first row where the color
    // diverges from sky for a sustained run (3+ consecutive non-sky rows).
    // Limit scan to upper 70% — the roofline is almost never in the bottom 30%.
    final scanLimit = (height * 0.70).round();
    final numCols = width > 800 ? 60 : (width > 400 ? 45 : 30);
    final colWidth = width / numCols;

    final skyBoundaryRows = List<double>.filled(numCols, -1);

    for (int col = 0; col < numCols; col++) {
      final xStart = (col * colWidth).round().clamp(0, width - 1);
      final xEnd = ((col + 1) * colWidth).round().clamp(0, width);
      final bandWidth = xEnd - xStart;
      if (bandWidth <= 0) continue;

      int consecutiveNonSky = 0;
      int boundaryRow = -1;

      for (int y = skyRows; y < scanLimit; y++) {
        // Average color distance from sky across this column band.
        double avgDist = 0;
        for (int x = xStart; x < xEnd; x++) {
          avgDist += _colorDistSq(pixels, width, x, y, skyR, skyG, skyB);
        }
        avgDist /= bandWidth;

        if (avgDist > skyThreshold) {
          consecutiveNonSky++;
          if (consecutiveNonSky >= 3) {
            boundaryRow = y - 2; // First row of the run
            break;
          }
        } else {
          consecutiveNonSky = 0;
        }
      }

      skyBoundaryRows[col] = boundaryRow >= 0 ? boundaryRow.toDouble() : -1;
    }

    // ── Pass 3: Edge refinement ──
    // For each column with a sky boundary, look for the strongest Sobel-Y
    // edge within ±refineRadius rows. This snaps to the actual architectural
    // edge rather than the approximate color transition.
    final refineRadius = (height * 0.04).round().clamp(3, 30);
    final refinedRows = List<double>.filled(numCols, -1);

    for (int col = 0; col < numCols; col++) {
      if (skyBoundaryRows[col] < 0) {
        refinedRows[col] = -1;
        continue;
      }

      final centerRow = skyBoundaryRows[col].round();
      final yMin = (centerRow - refineRadius).clamp(1, height - 2);
      final yMax = (centerRow + refineRadius).clamp(1, height - 2);

      final xStart = (col * colWidth).round().clamp(1, width - 2);
      final xEnd = ((col + 1) * colWidth).round().clamp(1, width - 1);
      final bandWidth = xEnd - xStart;
      if (bandWidth <= 0) {
        refinedRows[col] = skyBoundaryRows[col];
        continue;
      }

      double bestGradient = 0;
      int bestRow = centerRow;

      for (int y = yMin; y <= yMax; y++) {
        double gradientSum = 0;
        for (int x = xStart; x < xEnd; x++) {
          // Sobel-Y: emphasizes horizontal edges.
          final topLeft = _luminance(pixels, width, x - 1, y - 1);
          final top = _luminance(pixels, width, x, y - 1);
          final topRight = _luminance(pixels, width, x + 1, y - 1);
          final bottomLeft = _luminance(pixels, width, x - 1, y + 1);
          final bottom = _luminance(pixels, width, x, y + 1);
          final bottomRight = _luminance(pixels, width, x + 1, y + 1);

          final gy = (-topLeft - 2 * top - topRight +
                       bottomLeft + 2 * bottom + bottomRight).abs();
          gradientSum += gy;
        }
        final avgGradient = gradientSum / bandWidth;

        if (avgGradient > bestGradient) {
          bestGradient = avgGradient;
          bestRow = y;
        }
      }

      // Only snap to edge if it's reasonably strong; otherwise keep sky boundary.
      refinedRows[col] = bestGradient > 15 ? bestRow.toDouble() : skyBoundaryRows[col];
    }

    // ── Pass 4: Fill gaps and filter ──
    // Columns where sky boundary wasn't found (e.g. tree occluded the sky)
    // are filled by interpolating from neighbors.
    _fillGaps(refinedRows);

    // Median filter (window 5) — much more robust to outlier spikes than mean.
    final medianFiltered = _medianFilter(refinedRows, windowSize: 5);

    // Light smoothing pass to remove small jitter.
    final smoothed = _smoothCurve(medianFiltered, windowSize: 3);

    // ── Pass 5: Normalize and simplify ──
    final points = <Offset>[];
    for (int i = 0; i < numCols; i++) {
      if (smoothed[i] < 0) continue;
      final nx = (i + 0.5) / numCols;
      final ny = smoothed[i] / height;
      points.add(Offset(nx.clamp(0.0, 1.0), ny.clamp(0.0, 1.0)));
    }

    if (points.length < 2) return [];

    // Douglas-Peucker simplification — keep enough detail for peaks/gables.
    final simplified = _simplifyPoints(points, epsilon: 0.006);
    if (simplified.length < 2) {
      return points.length >= 2 ? [points.first, points.last] : [];
    }

    return simplified;
  }

  // ── Gap filling ────────────────────────────────────────────────────────

  /// Fill -1 gaps in the row array by linear interpolation from neighbors.
  static void _fillGaps(List<double> rows) {
    // Forward pass: find first valid value.
    int firstValid = -1;
    for (int i = 0; i < rows.length; i++) {
      if (rows[i] >= 0) { firstValid = i; break; }
    }
    if (firstValid < 0) return; // No valid data at all.

    // Fill leading gap.
    for (int i = 0; i < firstValid; i++) {
      rows[i] = rows[firstValid];
    }

    // Fill trailing gap.
    int lastValid = firstValid;
    for (int i = rows.length - 1; i >= 0; i--) {
      if (rows[i] >= 0) { lastValid = i; break; }
    }
    for (int i = lastValid + 1; i < rows.length; i++) {
      rows[i] = rows[lastValid];
    }

    // Interpolate interior gaps.
    int gapStart = -1;
    for (int i = firstValid; i <= lastValid; i++) {
      if (rows[i] < 0) {
        if (gapStart < 0) gapStart = i;
      } else {
        if (gapStart >= 0) {
          // Interpolate from gapStart-1 to i.
          final from = rows[gapStart - 1];
          final to = rows[i];
          final span = i - gapStart + 1;
          for (int j = gapStart; j < i; j++) {
            rows[j] = from + (to - from) * (j - gapStart + 1) / span;
          }
          gapStart = -1;
        }
      }
    }
  }

  // ── Median filter ──────────────────────────────────────────────────────

  static List<double> _medianFilter(List<double> values, {int windowSize = 5}) {
    final result = List<double>.from(values);
    final half = windowSize ~/ 2;
    final window = <double>[];

    for (int i = 0; i < values.length; i++) {
      window.clear();
      for (int j = i - half; j <= i + half; j++) {
        if (j >= 0 && j < values.length && values[j] >= 0) {
          window.add(values[j]);
        }
      }
      if (window.isNotEmpty) {
        window.sort();
        result[i] = window[window.length ~/ 2];
      }
    }
    return result;
  }

  // ── Moving average smoothing ───────────────────────────────────────────

  static List<double> _smoothCurve(List<double> values, {int windowSize = 5}) {
    final result = List<double>.filled(values.length, 0);
    final halfWindow = windowSize ~/ 2;

    for (int i = 0; i < values.length; i++) {
      double sum = 0;
      int count = 0;
      for (int j = i - halfWindow; j <= i + halfWindow; j++) {
        if (j >= 0 && j < values.length && values[j] >= 0) {
          sum += values[j];
          count++;
        }
      }
      result[i] = count > 0 ? sum / count : values[i];
    }
    return result;
  }

  // ── Douglas-Peucker simplification ─────────────────────────────────────

  static List<Offset> _simplifyPoints(List<Offset> points, {double epsilon = 0.01}) {
    if (points.length <= 2) return points;

    double maxDistance = 0;
    int maxIndex = 0;
    final first = points.first;
    final last = points.last;

    for (int i = 1; i < points.length - 1; i++) {
      final d = _perpendicularDistance(points[i], first, last);
      if (d > maxDistance) {
        maxDistance = d;
        maxIndex = i;
      }
    }

    if (maxDistance > epsilon) {
      final left = _simplifyPoints(points.sublist(0, maxIndex + 1), epsilon: epsilon);
      final right = _simplifyPoints(points.sublist(maxIndex), epsilon: epsilon);
      return [...left.sublist(0, left.length - 1), ...right];
    }

    return [first, last];
  }

  static double _perpendicularDistance(Offset point, Offset lineStart, Offset lineEnd) {
    final dx = lineEnd.dx - lineStart.dx;
    final dy = lineEnd.dy - lineStart.dy;
    final length = dx * dx + dy * dy;

    if (length == 0) return (point - lineStart).distance;

    final t = ((point.dx - lineStart.dx) * dx + (point.dy - lineStart.dy) * dy) / length;
    final tClamped = t.clamp(0.0, 1.0);
    final projection = Offset(
      lineStart.dx + tClamped * dx,
      lineStart.dy + tClamped * dy,
    );
    return (point - projection).distance;
  }

  // ── Templates ──────────────────────────────────────────────────────────

  /// Common roofline templates for manual fallback.
  static List<RooflineTemplate> get templates => const [
    RooflineTemplate(
      name: 'Peaked (A-Frame)',
      icon: Icons.change_history,
      points: [
        Offset(0.05, 0.35),
        Offset(0.25, 0.18),
        Offset(0.50, 0.05),
        Offset(0.75, 0.18),
        Offset(0.95, 0.35),
      ],
    ),
    RooflineTemplate(
      name: 'Flat / Low Slope',
      icon: Icons.horizontal_rule,
      points: [
        Offset(0.05, 0.22),
        Offset(0.25, 0.20),
        Offset(0.50, 0.19),
        Offset(0.75, 0.20),
        Offset(0.95, 0.22),
      ],
    ),
    RooflineTemplate(
      name: 'Gabled',
      icon: Icons.home,
      points: [
        Offset(0.02, 0.35),
        Offset(0.15, 0.18),
        Offset(0.30, 0.08),
        Offset(0.45, 0.18),
        Offset(0.55, 0.18),
        Offset(0.70, 0.08),
        Offset(0.85, 0.18),
        Offset(0.98, 0.35),
      ],
    ),
    RooflineTemplate(
      name: 'Hip Roof',
      icon: Icons.roofing,
      points: [
        Offset(0.05, 0.30),
        Offset(0.20, 0.18),
        Offset(0.35, 0.12),
        Offset(0.65, 0.12),
        Offset(0.80, 0.18),
        Offset(0.95, 0.30),
      ],
    ),
  ];
}

/// A named roofline template with preset points.
class RooflineTemplate {
  final String name;
  final IconData icon;
  final List<Offset> points;

  const RooflineTemplate({
    required this.name,
    required this.icon,
    required this.points,
  });

  /// Convert this template to a RooflineMask.
  RooflineMask toMask({double? sourceAspectRatio}) {
    return RooflineMask(
      points: points,
      maskHeight: 0.25,
      isManuallyDrawn: false,
      sourceAspectRatio: sourceAspectRatio,
    );
  }
}
