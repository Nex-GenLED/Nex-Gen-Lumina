import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:nexgen_command/models/roofline_mask.dart';

/// Service that auto-detects the roofline from a house photo.
///
/// Uses edge detection on the upper portion of the image to find
/// the dominant horizontal edge line, which typically corresponds
/// to the roofline where permanent LEDs are installed.
class RooflineAutoDetectService {
  /// Detect the roofline from an image provider.
  ///
  /// Returns a [RooflineMask] with normalized (0-1) points tracing the
  /// detected roofline. Returns null if detection fails.
  static Future<RooflineMask?> detectFromImage(ImageProvider imageProvider) async {
    try {
      // Load the image as ui.Image
      final image = await _loadImage(imageProvider);
      if (image == null) return null;

      // Get raw pixel data (RGBA)
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) return null;

      final width = image.width;
      final height = image.height;
      final pixels = byteData.buffer.asUint8List();

      // Run edge detection on the upper 50% of the image
      final rooflinePoints = _detectEdges(pixels, width, height);

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

  /// Load an ImageProvider into a ui.Image.
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

  /// Get the grayscale luminance of a pixel at (x, y).
  static int _luminance(Uint8List pixels, int width, int x, int y) {
    final i = (y * width + x) * 4;
    if (i + 2 >= pixels.length) return 0;
    // ITU-R BT.601 luma: 0.299*R + 0.587*G + 0.114*B
    return ((pixels[i] * 299 + pixels[i + 1] * 587 + pixels[i + 2] * 114) / 1000).round();
  }

  /// Run Sobel-inspired vertical edge detection on the upper portion.
  ///
  /// Strategy:
  /// 1. Compute vertical gradient (Sobel-Y) for the upper 50% of the image
  /// 2. For each column, find the row with the strongest vertical edge
  /// 3. Smooth the result to get a continuous roofline
  /// 4. Convert to normalized coordinates
  static List<Offset> _detectEdges(Uint8List pixels, int width, int height) {
    // Focus on the upper 55% of the image where the roofline likely is
    final scanHeight = (height * 0.55).round();
    if (scanHeight < 10 || width < 10) return [];

    // Step 1: Compute vertical gradient magnitude per pixel
    // Using a simplified Sobel-Y kernel:
    //  -1 -2 -1
    //   0  0  0
    //   1  2  1
    final gradientMap = Float32List(width * scanHeight);

    for (int y = 1; y < scanHeight - 1; y++) {
      for (int x = 1; x < width - 1; x++) {
        final topLeft = _luminance(pixels, width, x - 1, y - 1);
        final top = _luminance(pixels, width, x, y - 1);
        final topRight = _luminance(pixels, width, x + 1, y - 1);
        final bottomLeft = _luminance(pixels, width, x - 1, y + 1);
        final bottom = _luminance(pixels, width, x, y + 1);
        final bottomRight = _luminance(pixels, width, x + 1, y + 1);

        // Sobel-Y: emphasizes horizontal edges (vertical gradient)
        final gy = (-topLeft - 2 * top - topRight + bottomLeft + 2 * bottom + bottomRight).abs();

        gradientMap[y * width + x] = gy.toDouble();
      }
    }

    // Step 2: Divide image into vertical columns and find the strongest
    // edge row in each column. Use ~30-50 sample columns for a smooth result.
    final numSamples = width > 600 ? 40 : (width > 300 ? 30 : 20);
    final columnWidth = width / numSamples;

    final rawEdgeRows = <double>[];

    for (int col = 0; col < numSamples; col++) {
      final xStart = (col * columnWidth).round();
      final xEnd = ((col + 1) * columnWidth).round().clamp(0, width);

      double maxGradient = 0;
      int bestRow = scanHeight ~/ 3; // Default to upper third

      // Scan each row in this column band
      for (int y = 3; y < scanHeight - 3; y++) {
        double columnGradientSum = 0;
        int count = 0;

        for (int x = xStart; x < xEnd; x++) {
          columnGradientSum += gradientMap[y * width + x];
          count++;
        }

        final avgGradient = count > 0 ? columnGradientSum / count : 0.0;

        if (avgGradient > maxGradient) {
          maxGradient = avgGradient;
          bestRow = y;
        }
      }

      rawEdgeRows.add(bestRow.toDouble());
    }

    // Step 3: Smooth the detected edge rows to reduce noise.
    // Use a simple moving average with window size 5.
    final smoothedRows = _smoothCurve(rawEdgeRows, windowSize: 5);

    // Step 4: Filter out obvious outliers (rows that deviate too much
    // from the median). The roofline should be fairly consistent.
    final median = _median(smoothedRows);
    final maxDeviation = height * 0.15; // Allow 15% of image height deviation

    final filteredRows = smoothedRows.map((row) {
      if ((row - median).abs() > maxDeviation) return median;
      return row;
    }).toList();

    // Re-smooth after filtering
    final finalRows = _smoothCurve(filteredRows, windowSize: 3);

    // Step 5: Convert to normalized (0-1) coordinates
    final points = <Offset>[];
    for (int i = 0; i < numSamples; i++) {
      final normalizedX = (i + 0.5) / numSamples;
      final normalizedY = finalRows[i] / height;
      points.add(Offset(normalizedX.clamp(0.0, 1.0), normalizedY.clamp(0.0, 1.0)));
    }

    // Step 6: Simplify to reduce point count while preserving shape.
    // Use Douglas-Peucker-inspired simplification.
    final simplified = _simplifyPoints(points, epsilon: 0.008);

    // Ensure we have at least 2 points
    if (simplified.length < 2) return points.length >= 2 ? [points.first, points.last] : [];

    return simplified;
  }

  /// Simple moving average smoothing.
  static List<double> _smoothCurve(List<double> values, {int windowSize = 5}) {
    final result = List<double>.filled(values.length, 0);
    final halfWindow = windowSize ~/ 2;

    for (int i = 0; i < values.length; i++) {
      double sum = 0;
      int count = 0;
      for (int j = i - halfWindow; j <= i + halfWindow; j++) {
        if (j >= 0 && j < values.length) {
          sum += values[j];
          count++;
        }
      }
      result[i] = sum / count;
    }
    return result;
  }

  /// Compute the median of a list of doubles.
  static double _median(List<double> values) {
    final sorted = List<double>.from(values)..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length % 2 == 0) {
      return (sorted[mid - 1] + sorted[mid]) / 2;
    }
    return sorted[mid];
  }

  /// Douglas-Peucker line simplification.
  /// Reduces the number of points while preserving the shape.
  static List<Offset> _simplifyPoints(List<Offset> points, {double epsilon = 0.01}) {
    if (points.length <= 2) return points;

    // Find the point with the maximum distance from the line
    // between the first and last points
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

    // If max distance is greater than epsilon, recursively simplify
    if (maxDistance > epsilon) {
      final left = _simplifyPoints(points.sublist(0, maxIndex + 1), epsilon: epsilon);
      final right = _simplifyPoints(points.sublist(maxIndex), epsilon: epsilon);

      // Combine (remove duplicate point at junction)
      return [...left.sublist(0, left.length - 1), ...right];
    }

    // Otherwise, return just the endpoints
    return [first, last];
  }

  /// Perpendicular distance from a point to a line defined by two points.
  static double _perpendicularDistance(Offset point, Offset lineStart, Offset lineEnd) {
    final dx = lineEnd.dx - lineStart.dx;
    final dy = lineEnd.dy - lineStart.dy;
    final length = (dx * dx + dy * dy);

    if (length == 0) {
      // Line start and end are the same point
      return (point - lineStart).distance;
    }

    // Project point onto line
    final t = ((point.dx - lineStart.dx) * dx + (point.dy - lineStart.dy) * dy) / length;
    final tClamped = t.clamp(0.0, 1.0);

    final projection = Offset(
      lineStart.dx + tClamped * dx,
      lineStart.dy + tClamped * dy,
    );

    return (point - projection).distance;
  }

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
