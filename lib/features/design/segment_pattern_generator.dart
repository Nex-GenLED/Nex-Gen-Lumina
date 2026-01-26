import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';
import 'package:nexgen_command/models/segment_aware_pattern.dart';

/// Generator for segment-aware LED patterns.
///
/// This class contains algorithms for generating patterns that respect
/// roofline segment structure, anchor points, and architectural features.
class SegmentPatternGenerator {
  /// Generate LED color groups based on the pattern template and configuration.
  ///
  /// Returns a list of [LedColorGroup] that can be applied to a WLED device.
  List<LedColorGroup> generate({
    required RooflineConfiguration config,
    required SegmentAwarePattern pattern,
  }) {
    switch (pattern.templateType) {
      case PatternTemplateType.downlighting:
        return generateDownlighting(
          config: config,
          anchorColor: pattern.anchorColor,
          spacedColor: pattern.spacedColor,
          spacingCount: pattern.spacingCount,
          anchorAlwaysOn: pattern.anchorAlwaysOn,
        );

      case PatternTemplateType.chaseBySegment:
        return generateChaseBySegment(
          config: config,
          color: pattern.anchorColor,
        );

      case PatternTemplateType.alternatingSegments:
        return generateAlternatingSegments(
          config: config,
          color1: pattern.anchorColor,
          color2: pattern.secondaryColor ?? pattern.spacedColor,
        );

      case PatternTemplateType.cornerAccent:
        return generateCornerAccent(
          config: config,
          accentColor: pattern.anchorColor,
          fillColor: pattern.spacedColor,
        );

      case PatternTemplateType.uniform:
        return generateUniform(
          config: config,
          color: pattern.anchorColor,
        );
    }
  }

  /// Generate a downlighting pattern.
  ///
  /// This is the primary pattern requested by the user:
  /// - 2 LEDs at each anchor point (corners, peaks) are always lit
  /// - Equal spacing between anchors with single LEDs
  ///
  /// Algorithm:
  /// 1. For each segment, mark anchor zones as lit
  /// 2. Calculate space between consecutive anchors
  /// 3. Distribute [spacingCount] single LEDs evenly in each zone
  List<LedColorGroup> generateDownlighting({
    required RooflineConfiguration config,
    required Color anchorColor,
    required Color spacedColor,
    required int spacingCount,
    bool anchorAlwaysOn = true,
  }) {
    final groups = <LedColorGroup>[];
    final anchorColorList = _colorToList(anchorColor);
    final spacedColorList = _colorToList(spacedColor);

    for (final segment in config.segments) {
      // Skip segments with no pixels
      if (segment.pixelCount <= 0) continue;

      // Get sorted anchor positions (local indices)
      final anchors = List<int>.from(segment.anchorPixels)..sort();

      // If no anchors defined, use defaults based on segment type
      final effectiveAnchors = anchors.isEmpty ? segment.defaultAnchors : anchors;

      // 1. Add anchor zones
      if (anchorAlwaysOn) {
        for (final anchorStart in effectiveAnchors) {
          final globalStart = segment.startPixel + anchorStart;
          final globalEnd = min(
            globalStart + segment.anchorLedCount - 1,
            segment.endPixel,
          );

          groups.add(LedColorGroup(
            startLed: globalStart,
            endLed: globalEnd,
            color: anchorColorList,
          ));
        }
      }

      // 2. Calculate evenly-spaced LEDs between consecutive anchors
      if (spacingCount > 0 && effectiveAnchors.length >= 2) {
        for (int i = 0; i < effectiveAnchors.length - 1; i++) {
          final anchorEnd = effectiveAnchors[i] + segment.anchorLedCount;
          final nextAnchorStart = effectiveAnchors[i + 1];

          // Zone between this anchor's end and next anchor's start
          final zoneStart = anchorEnd;
          final zoneEnd = nextAnchorStart - 1;
          final zoneLength = zoneEnd - zoneStart + 1;

          if (zoneLength <= 0) continue;

          // Calculate interval for even spacing
          final interval = zoneLength / (spacingCount + 1);

          for (int j = 1; j <= spacingCount; j++) {
            final localPixel = zoneStart + (interval * j).round();

            // Validate the pixel is within the zone
            if (localPixel < zoneStart || localPixel > zoneEnd) continue;

            final globalPixel = segment.startPixel + localPixel;

            // Don't overlap with anchor zones
            if (!segment.isAnchorPixel(localPixel)) {
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

    return _mergeAdjacentGroups(groups);
  }

  /// Generate a chase pattern that respects segment boundaries.
  ///
  /// This creates a pattern where each segment is filled with the same color.
  /// The WLED effect will animate within each segment.
  List<LedColorGroup> generateChaseBySegment({
    required RooflineConfiguration config,
    required Color color,
  }) {
    final groups = <LedColorGroup>[];
    final colorList = _colorToList(color);

    for (final segment in config.segments) {
      if (segment.pixelCount <= 0) continue;

      groups.add(LedColorGroup(
        startLed: segment.startPixel,
        endLed: segment.endPixel,
        color: colorList,
      ));
    }

    return groups;
  }

  /// Generate alternating colors for odd and even segments.
  List<LedColorGroup> generateAlternatingSegments({
    required RooflineConfiguration config,
    required Color color1,
    required Color color2,
  }) {
    final groups = <LedColorGroup>[];
    final color1List = _colorToList(color1);
    final color2List = _colorToList(color2);

    for (int i = 0; i < config.segments.length; i++) {
      final segment = config.segments[i];
      if (segment.pixelCount <= 0) continue;

      final colorList = (i % 2 == 0) ? color1List : color2List;

      groups.add(LedColorGroup(
        startLed: segment.startPixel,
        endLed: segment.endPixel,
        color: colorList,
      ));
    }

    return groups;
  }

  /// Generate a pattern that highlights corners and peaks with accent color.
  ///
  /// - Corner and peak segments get the accent color
  /// - Other segments get the fill color
  List<LedColorGroup> generateCornerAccent({
    required RooflineConfiguration config,
    required Color accentColor,
    required Color fillColor,
  }) {
    final groups = <LedColorGroup>[];
    final accentList = _colorToList(accentColor);
    final fillList = _colorToList(fillColor);

    for (final segment in config.segments) {
      if (segment.pixelCount <= 0) continue;

      final isAccent = segment.type == SegmentType.corner ||
          segment.type == SegmentType.peak;

      groups.add(LedColorGroup(
        startLed: segment.startPixel,
        endLed: segment.endPixel,
        color: isAccent ? accentList : fillList,
      ));
    }

    return groups;
  }

  /// Generate a uniform fill across all segments.
  List<LedColorGroup> generateUniform({
    required RooflineConfiguration config,
    required Color color,
  }) {
    if (config.totalPixelCount <= 0) return [];

    return [
      LedColorGroup(
        startLed: 0,
        endLed: config.totalPixelCount - 1,
        color: _colorToList(color),
      ),
    ];
  }

  /// Generate anchor-only pattern (just the corner/peak lights).
  ///
  /// Useful for minimal downlighting with no spaced LEDs.
  List<LedColorGroup> generateAnchorsOnly({
    required RooflineConfiguration config,
    required Color color,
  }) {
    return generateDownlighting(
      config: config,
      anchorColor: color,
      spacedColor: color, // Not used since spacingCount is 0
      spacingCount: 0,
      anchorAlwaysOn: true,
    );
  }

  /// Convert a Flutter Color to a list [R, G, B, W].
  List<int> _colorToList(Color color, {int white = 0}) {
    return [color.red, color.green, color.blue, white];
  }

  /// Merge adjacent color groups with the same color to reduce payload size.
  List<LedColorGroup> _mergeAdjacentGroups(List<LedColorGroup> groups) {
    if (groups.isEmpty) return groups;

    // Sort by start LED
    final sorted = List<LedColorGroup>.from(groups)
      ..sort((a, b) => a.startLed.compareTo(b.startLed));

    final merged = <LedColorGroup>[];
    var current = sorted.first;

    for (int i = 1; i < sorted.length; i++) {
      final next = sorted[i];

      // Check if adjacent and same color
      if (current.endLed + 1 == next.startLed &&
          _colorsEqual(current.color, next.color)) {
        // Merge
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

  /// Check if two color lists are equal.
  bool _colorsEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Provider for the segment pattern generator.
final segmentPatternGeneratorProvider =
    Provider<SegmentPatternGenerator>((ref) => SegmentPatternGenerator());

/// Extension on SegmentPatternGenerator to create WLED payloads.
extension WledPayloadGeneration on SegmentPatternGenerator {
  /// Generate a WLED JSON payload for individual LED control.
  ///
  /// Uses WLED's "i" array for per-LED color assignment.
  ///
  /// [totalPixelCount] - Optional total pixel count to set segment boundaries.
  /// This ensures motion effects wrap correctly at the last pixel.
  Map<String, dynamic> toWledIndividualPayload({
    required List<LedColorGroup> groups,
    required int brightness,
    int segmentId = 0,
    int? totalPixelCount,
  }) {
    // Build the individual LED array
    // Format: [LED_INDEX, R, G, B, LED_INDEX, R, G, B, ...]
    final ledArray = <int>[];

    // Track max LED index for segment boundary
    int maxLed = 0;

    for (final group in groups) {
      for (int led = group.startLed; led <= group.endLed; led++) {
        ledArray.add(led);
        ledArray.addAll(group.color.take(3)); // R, G, B only
        if (led > maxLed) maxLed = led;
      }
    }

    // Determine stop position: use provided totalPixelCount or calculate from groups
    final stopPosition = totalPixelCount ?? (maxLed + 1);

    // Build segment configuration with explicit boundaries
    // This is CRITICAL for motion effects to wrap correctly at pixel boundaries
    final segmentConfig = <String, dynamic>{
      'id': segmentId,
      'start': 0,           // Segment starts at pixel 0
      'stop': stopPosition, // Segment ends at last pixel (exclusive)
      'i': ledArray,
    };

    return {
      'on': true,
      'bri': brightness,
      'seg': [segmentConfig],
    };
  }

  /// Generate a WLED JSON payload for motion effects (chase, rainbow, etc).
  ///
  /// This payload explicitly sets segment boundaries to ensure proper wrapping.
  /// When a motion effect reaches the last pixel, it will wrap back to pixel 0.
  Map<String, dynamic> toWledMotionPayload({
    required int brightness,
    required int effectId,
    required int totalPixelCount,
    List<List<int>>? colors,
    int speed = 128,
    int intensity = 128,
    int segmentId = 0,
  }) {
    final effectColors = colors ?? [[255, 255, 255]];

    return {
      'on': true,
      'bri': brightness,
      'seg': [
        {
          'id': segmentId,
          'start': 0,                // Start at pixel 0
          'stop': totalPixelCount,   // End at last pixel (exclusive, so wraps correctly)
          'col': effectColors,
          'fx': effectId,
          'sx': speed,
          'ix': intensity,
        }
      ],
    };
  }

  /// Generate a standard WLED payload with segment-based colors.
  ///
  /// Uses the first few colors from the groups for the segment's color slots.
  /// [totalPixelCount] - Optional total pixel count for segment boundaries.
  Map<String, dynamic> toWledSegmentPayload({
    required List<LedColorGroup> groups,
    required int brightness,
    required int effectId,
    int speed = 128,
    int intensity = 128,
    int segmentId = 0,
    int? totalPixelCount,
  }) {
    // Get unique colors (up to 3 for WLED)
    final colors = <List<int>>[];
    int maxLed = 0;

    for (final group in groups) {
      final color = group.color.take(3).toList();
      if (!colors.any((c) => _colorsEqual(c, color))) {
        colors.add(color);
        if (colors.length >= 3) break;
      }
      if (group.endLed > maxLed) maxLed = group.endLed;
    }

    if (colors.isEmpty) {
      colors.add([255, 255, 255]); // Default white
    }

    // Determine stop position
    final stopPosition = totalPixelCount ?? (maxLed + 1);

    return {
      'on': true,
      'bri': brightness,
      'seg': [
        {
          'id': segmentId,
          'start': 0,           // Explicit start boundary
          'stop': stopPosition, // Explicit stop boundary for proper wrapping
          'col': colors,
          'fx': effectId,
          'sx': speed,
          'ix': intensity,
        }
      ],
    };
  }

  bool _colorsEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Validates pixel count configuration between app and device.
class PixelCountValidator {
  /// Check if app pixel count matches device pixel count.
  static bool isValid({
    required int appPixelCount,
    required int devicePixelCount,
  }) {
    return appPixelCount == devicePixelCount;
  }

  /// Get a user-friendly message describing the mismatch.
  static String getMismatchMessage({
    required int appPixelCount,
    required int devicePixelCount,
  }) {
    final difference = (appPixelCount - devicePixelCount).abs();
    if (appPixelCount > devicePixelCount) {
      return 'App configured for $appPixelCount LEDs, but device only has $devicePixelCount. '
          '$difference LEDs will not be addressable.';
    } else {
      return 'Device has $devicePixelCount LEDs, but app configured for $appPixelCount. '
          '$difference LEDs at the end will not be controlled.';
    }
  }
}
