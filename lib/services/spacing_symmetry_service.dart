import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';

/// Service for calculating optimal LED spacing and ensuring visual symmetry.
///
/// This service provides algorithms for:
/// - Even spacing of lit LEDs across segments of varying lengths
/// - Ensuring anchor points (corners, peaks) are always lit
/// - Maintaining visual symmetry across the roofline
/// - Brightness gradient patterns
class SpacingSymmetryService {
  /// Calculate optimal spacing for downlighting pattern.
  ///
  /// Ensures:
  /// 1. Anchor points are always lit
  /// 2. Segment boundaries are always lit
  /// 3. Even visual distribution between anchors
  ///
  /// [config] - The roofline configuration
  /// [targetSpacing] - Desired number of dark LEDs between lit ones (e.g., 3 means every 4th LED)
  /// [anchorColor] - Color for anchor points
  /// [spacedColor] - Color for evenly spaced LEDs
  List<LedColorGroup> calculateDownlightingSpacing({
    required RooflineConfiguration config,
    required int targetSpacing,
    required Color anchorColor,
    required Color spacedColor,
  }) {
    final groups = <LedColorGroup>[];
    final anchorColorList = _colorToList(anchorColor);
    final spacedColorList = _colorToList(spacedColor);

    for (final segment in config.segments) {
      if (segment.pixelCount <= 0) continue;

      // Get effective anchors
      final anchors = segment.effectiveAnchorPoints;
      final anchorIndices = anchors.map((a) => a.ledIndex).toList()..sort();

      // If no anchors, add segment boundaries
      final effectiveAnchors = anchorIndices.isEmpty
          ? [0, segment.pixelCount - 1]
          : anchorIndices;

      // 1. Light all anchor zones
      for (final anchor in anchors) {
        final globalStart = segment.startPixel + anchor.ledIndex;
        final globalEnd = min(
          globalStart + anchor.zoneSize - 1,
          segment.endPixel,
        );
        groups.add(LedColorGroup(
          startLed: globalStart,
          endLed: globalEnd,
          color: anchorColorList,
        ));
      }

      // Also light segment boundaries if not already anchored
      if (!effectiveAnchors.contains(0)) {
        groups.add(LedColorGroup(
          startLed: segment.startPixel,
          endLed: segment.startPixel,
          color: spacedColorList,
        ));
      }
      if (!effectiveAnchors.contains(segment.pixelCount - 1)) {
        groups.add(LedColorGroup(
          startLed: segment.endPixel,
          endLed: segment.endPixel,
          color: spacedColorList,
        ));
      }

      // 2. Calculate evenly spaced LEDs between anchors
      if (targetSpacing > 0 && effectiveAnchors.length >= 2) {
        for (int i = 0; i < effectiveAnchors.length - 1; i++) {
          final zoneStart = effectiveAnchors[i] + segment.anchorLedCount;
          final zoneEnd = effectiveAnchors[i + 1] - 1;
          final zoneLength = zoneEnd - zoneStart + 1;

          if (zoneLength <= 0) continue;

          // Calculate how many LEDs should be lit in this zone
          final litCount = _calculateOptimalLitCount(zoneLength, targetSpacing);

          if (litCount > 0) {
            // Distribute evenly
            final interval = (zoneLength + 1) / (litCount + 1);

            for (int j = 1; j <= litCount; j++) {
              final localPixel = zoneStart + (interval * j).round() - 1;

              if (localPixel >= zoneStart && localPixel <= zoneEnd) {
                final globalPixel = segment.startPixel + localPixel;

                // Avoid anchor zones
                if (!_isInAnchorZone(localPixel, effectiveAnchors, segment.anchorLedCount)) {
                  groups.add(LedColorGroup(
                    startLed: globalPixel,
                    endLed: globalPixel,
                    color: spacedColorList,
                  ));
                }
              }
            }
          }
        }
      }
    }

    return _mergeAdjacentGroups(groups);
  }

  /// Calculate optimal number of lit LEDs for a zone based on target spacing.
  int _calculateOptimalLitCount(int zoneLength, int targetSpacing) {
    if (zoneLength <= 0) return 0;
    if (targetSpacing <= 0) return zoneLength;

    // Calculate based on desired spacing ratio
    final effectiveSpacing = targetSpacing + 1; // +1 for the lit LED itself
    return max(0, (zoneLength / effectiveSpacing).floor());
  }

  /// Check if a local index falls within any anchor zone.
  bool _isInAnchorZone(int localIndex, List<int> anchors, int anchorLedCount) {
    for (final anchor in anchors) {
      if (localIndex >= anchor && localIndex < anchor + anchorLedCount) {
        return true;
      }
    }
    return false;
  }

  /// Generate a brightness gradient pattern.
  ///
  /// Creates a repeating pattern like [bright, dim, dim, dim]
  /// adjusted for segment boundaries and anchors.
  List<LedColorGroup> calculateBrightnessGradient({
    required RooflineConfiguration config,
    required Color color,
    required List<int> brightnessPattern, // e.g., [255, 80, 80, 80]
  }) {
    final groups = <LedColorGroup>[];
    if (brightnessPattern.isEmpty) return groups;

    final baseColor = [color.red, color.green, color.blue, 0];

    for (final segment in config.segments) {
      if (segment.pixelCount <= 0) continue;

      int patternIndex = 0;

      for (int local = 0; local < segment.pixelCount; local++) {
        final global = segment.startPixel + local;
        final brightness = brightnessPattern[patternIndex];

        // Scale color by brightness
        final scaledColor = baseColor.map((c) => (c * brightness / 255).round()).toList();

        groups.add(LedColorGroup(
          startLed: global,
          endLed: global,
          color: scaledColor,
        ));

        patternIndex = (patternIndex + 1) % brightnessPattern.length;
      }
    }

    return _mergeAdjacentGroups(groups);
  }

  /// Analyze roofline for symmetry and return suggestions.
  SymmetryAnalysis analyzeSymmetry(RooflineConfiguration config) {
    final segments = config.segments;
    if (segments.isEmpty) {
      return SymmetryAnalysis(
        hasSymmetryAxis: false,
        symmetryAxisLed: null,
        leftSegments: [],
        rightSegments: [],
        recommendations: ['Add segments to analyze symmetry'],
      );
    }

    // Find potential symmetry axis (usually the main peak)
    final peaks = segments.where((s) => s.type == SegmentType.peak).toList();

    if (peaks.isEmpty) {
      return SymmetryAnalysis(
        hasSymmetryAxis: false,
        symmetryAxisLed: null,
        leftSegments: segments.map((s) => s.id).toList(),
        rightSegments: [],
        recommendations: ['No peak found - roofline appears asymmetric'],
      );
    }

    // Use the largest peak as symmetry axis
    final mainPeak = peaks.reduce((a, b) => a.pixelCount > b.pixelCount ? a : b);
    final axisLed = mainPeak.startPixel + (mainPeak.pixelCount ~/ 2);

    // Split segments into left and right of axis
    final leftSegments = <String>[];
    final rightSegments = <String>[];

    for (final segment in segments) {
      if (segment.id == mainPeak.id) continue;

      final segmentCenter = segment.startPixel + (segment.pixelCount ~/ 2);
      if (segmentCenter < axisLed) {
        leftSegments.add(segment.id);
      } else {
        rightSegments.add(segment.id);
      }
    }

    // Analyze balance
    final recommendations = <String>[];

    final leftLedCount = leftSegments
        .map((id) => segments.firstWhere((s) => s.id == id).pixelCount)
        .fold(0, (a, b) => a + b);
    final rightLedCount = rightSegments
        .map((id) => segments.firstWhere((s) => s.id == id).pixelCount)
        .fold(0, (a, b) => a + b);

    final imbalance = (leftLedCount - rightLedCount).abs();
    final imbalancePercent = (imbalance / max(1, leftLedCount + rightLedCount)) * 100;

    if (imbalancePercent > 20) {
      recommendations.add(
        'Roofline is ${imbalancePercent.toStringAsFixed(0)}% unbalanced - '
        'consider asymmetric patterns',
      );
    } else if (imbalancePercent > 10) {
      recommendations.add(
        'Slight asymmetry detected - patterns will be adjusted automatically',
      );
    } else {
      recommendations.add('Good symmetry - mirror patterns will work well');
    }

    return SymmetryAnalysis(
      hasSymmetryAxis: true,
      symmetryAxisLed: axisLed,
      leftSegments: leftSegments,
      rightSegments: rightSegments,
      recommendations: recommendations,
      imbalancePercent: imbalancePercent,
    );
  }

  /// Generate a symmetrical pattern (left side mirrors right side).
  List<LedColorGroup> generateMirrorPattern({
    required RooflineConfiguration config,
    required List<LedColorGroup> leftSideGroups,
  }) {
    final analysis = analyzeSymmetry(config);
    if (!analysis.hasSymmetryAxis || analysis.symmetryAxisLed == null) {
      return leftSideGroups;
    }

    final axisLed = analysis.symmetryAxisLed!;
    final mirroredGroups = <LedColorGroup>[];

    // Add original left side groups
    mirroredGroups.addAll(leftSideGroups.where((g) => g.endLed < axisLed));

    // Mirror to right side
    for (final group in leftSideGroups.where((g) => g.endLed < axisLed)) {
      final distanceFromAxis = axisLed - group.startLed;
      final mirroredStart = axisLed + distanceFromAxis - (group.endLed - group.startLed);
      final mirroredEnd = axisLed + (axisLed - group.startLed);

      if (mirroredStart >= 0 && mirroredEnd < config.totalPixelCount) {
        mirroredGroups.add(LedColorGroup(
          startLed: mirroredStart,
          endLed: mirroredEnd,
          color: group.color,
        ));
      }
    }

    return _mergeAdjacentGroups(mirroredGroups);
  }

  /// Calculate accent pattern with colors applied to peaks and corners.
  List<LedColorGroup> calculateAccentPattern({
    required RooflineConfiguration config,
    required Color primaryColor,
    required Color accentColor,
    bool accentPeaks = true,
    bool accentCorners = true,
  }) {
    final groups = <LedColorGroup>[];
    final primaryList = _colorToList(primaryColor);
    final accentList = _colorToList(accentColor);

    for (final segment in config.segments) {
      if (segment.pixelCount <= 0) continue;

      final isAccent = (accentPeaks && segment.type == SegmentType.peak) ||
          (accentCorners && segment.type == SegmentType.corner);

      groups.add(LedColorGroup(
        startLed: segment.startPixel,
        endLed: segment.endPixel,
        color: isAccent ? accentList : primaryList,
      ));
    }

    return groups;
  }

  List<int> _colorToList(Color color, {int white = 0}) {
    return [color.red, color.green, color.blue, white];
  }

  List<LedColorGroup> _mergeAdjacentGroups(List<LedColorGroup> groups) {
    if (groups.isEmpty) return groups;

    final sorted = List<LedColorGroup>.from(groups)
      ..sort((a, b) => a.startLed.compareTo(b.startLed));

    final merged = <LedColorGroup>[];
    var current = sorted.first;

    for (int i = 1; i < sorted.length; i++) {
      final next = sorted[i];

      if (current.endLed + 1 == next.startLed &&
          _colorsEqual(current.color, next.color)) {
        current = LedColorGroup(
          startLed: current.startLed,
          endLed: next.endLed,
          color: current.color,
        );
      } else {
        merged.add(current);
        current = next;
      }
    }
    merged.add(current);

    return merged;
  }

  bool _colorsEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Result of symmetry analysis.
class SymmetryAnalysis {
  /// Whether a valid symmetry axis was found
  final bool hasSymmetryAxis;

  /// LED index of the symmetry axis (usually center of main peak)
  final int? symmetryAxisLed;

  /// Segment IDs to the left of the axis
  final List<String> leftSegments;

  /// Segment IDs to the right of the axis
  final List<String> rightSegments;

  /// Recommendations based on analysis
  final List<String> recommendations;

  /// Percentage of imbalance between left and right
  final double imbalancePercent;

  const SymmetryAnalysis({
    required this.hasSymmetryAxis,
    required this.symmetryAxisLed,
    required this.leftSegments,
    required this.rightSegments,
    required this.recommendations,
    this.imbalancePercent = 0,
  });

  /// Whether the roofline is well-balanced for symmetric patterns
  bool get isWellBalanced => imbalancePercent <= 15;
}

/// Provider for the spacing and symmetry service.
final spacingSymmetryServiceProvider = Provider<SpacingSymmetryService>(
  (ref) => SpacingSymmetryService(),
);
