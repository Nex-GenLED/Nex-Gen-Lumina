import 'package:flutter/material.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';

/// Service for generating intelligent segment-aware patterns.
///
/// This service creates patterns that:
/// - Respect architectural boundaries (peaks, eaves, corners)
/// - Flow naturally along roofline direction
/// - Use symmetry for balanced visual appeal
/// - Highlight prominent features
class SegmentPatternGenerator {
  const SegmentPatternGenerator();

  /// Generates a symmetrical pattern mirrored across the main peak.
  ///
  /// Example: Red on left eaves, red on right eaves (mirrored)
  GeneratedPattern generateSymmetricalPattern({
    required RooflineConfiguration config,
    required List<Color> colors,
    required int effectId,
    int speed = 128,
    int intensity = 128,
  }) {
    // Find the main peak as symmetry axis
    final mainPeak = _findMainPeak(config);

    if (mainPeak == null) {
      // No peak found, fall back to standard pattern
      return _generateStandardPattern(
        config: config,
        colors: colors,
        effectId: effectId,
        speed: speed,
        intensity: intensity,
      );
    }

    final segments = <SegmentAssignment>[];
    final peakCenter = mainPeak.startPixel + (mainPeak.pixelCount ~/ 2);

    // Split segments into left and right of peak
    final leftSegments = config.segments
        .where((s) => s.endPixel < peakCenter && s.id != mainPeak.id)
        .toList();
    final rightSegments = config.segments
        .where((s) => s.startPixel > peakCenter && s.id != mainPeak.id)
        .toList();

    // Assign colors to left side
    for (int i = 0; i < leftSegments.length; i++) {
      final segment = leftSegments[i];
      final colorIndex = i % colors.length;
      segments.add(SegmentAssignment(
        segment: segment,
        color: colors[colorIndex],
        effectId: effectId,
        speed: speed,
        intensity: intensity,
      ));
    }

    // Mirror to right side
    for (int i = 0; i < rightSegments.length && i < leftSegments.length; i++) {
      final segment = rightSegments[i];
      final colorIndex = i % colors.length;
      segments.add(SegmentAssignment(
        segment: segment,
        color: colors[colorIndex],
        effectId: effectId,
        speed: speed,
        intensity: intensity,
      ));
    }

    // Special treatment for the peak itself
    final peakColor = colors.length > 1 ? colors[1] : colors[0];
    segments.add(SegmentAssignment(
      segment: mainPeak,
      color: peakColor,
      effectId: 0, // Solid for peak
      speed: speed,
      intensity: 255, // Maximum intensity for peak
    ));

    return GeneratedPattern(
      name: 'Symmetrical ${_effectName(effectId)}',
      description: 'Mirrored pattern across ${mainPeak.name}',
      segments: segments,
      useSymmetry: true,
      symmetryAxis: peakCenter,
    );
  }

  /// Generates a chase pattern that flows along the roofline direction.
  ///
  /// Example: Chase flows from left to right following segment directions
  GeneratedPattern generateFlowPattern({
    required RooflineConfiguration config,
    required List<Color> colors,
    required SegmentDirection flowDirection,
    int speed = 128,
  }) {
    final segments = <SegmentAssignment>[];

    // Sort segments by flow direction
    final sortedSegments = _sortByFlowDirection(config.segments, flowDirection);

    // Assign colors in sequence
    for (int i = 0; i < sortedSegments.length; i++) {
      final segment = sortedSegments[i];
      final colorIndex = i % colors.length;

      // Use chase effect with offset based on position
      final offset = (i * 30) % 255; // Stagger the chase

      segments.add(SegmentAssignment(
        segment: segment,
        color: colors[colorIndex],
        effectId: 28, // Chase effect
        speed: speed,
        intensity: 128,
        offset: offset,
      ));
    }

    return GeneratedPattern(
      name: 'Flow ${flowDirection.displayName}',
      description: 'Chase flowing ${flowDirection.displayName.toLowerCase()}',
      segments: segments,
      useSymmetry: false,
    );
  }

  /// Generates a pattern that highlights architectural features.
  ///
  /// Example: Peaks glow white, eaves pulse with color
  GeneratedPattern generateArchitecturalHighlight({
    required RooflineConfiguration config,
    required ArchitecturalRole targetRole,
    required Color highlightColor,
    Color? baseColor,
    int effectId = 0,
  }) {
    final segments = <SegmentAssignment>[];
    final actualBaseColor = baseColor ?? const Color(0xFF2A2A2A).withOpacity(0.3);

    for (final segment in config.segments) {
      if (segment.architecturalRole == targetRole) {
        // Highlight target role
        segments.add(SegmentAssignment(
          segment: segment,
          color: highlightColor,
          effectId: effectId,
          speed: 128,
          intensity: 255,
        ));
      } else {
        // Dim base color for other segments
        segments.add(SegmentAssignment(
          segment: segment,
          color: actualBaseColor,
          effectId: 0, // Solid
          speed: 128,
          intensity: 80,
        ));
      }
    }

    return GeneratedPattern(
      name: 'Highlight ${targetRole.pluralName}',
      description: '${targetRole.displayName} features highlighted',
      segments: segments,
      useSymmetry: false,
    );
  }

  /// Generates a wave pattern that ripples across the roofline.
  ///
  /// Creates a smooth wave effect that travels across segments
  GeneratedPattern generateWavePattern({
    required RooflineConfiguration config,
    required List<Color> colors,
    int speed = 128,
  }) {
    final segments = <SegmentAssignment>[];

    for (int i = 0; i < config.segments.length; i++) {
      final segment = config.segments[i];
      final colorIndex = i % colors.length;

      // Phase offset for wave effect
      final phaseOffset = (i * 85) % 255;

      segments.add(SegmentAssignment(
        segment: segment,
        color: colors[colorIndex],
        effectId: 35, // Sine wave
        speed: speed,
        intensity: 128,
        offset: phaseOffset,
      ));
    }

    return GeneratedPattern(
      name: 'Wave Pattern',
      description: 'Smooth wave across roofline',
      segments: segments,
      useSymmetry: false,
    );
  }

  /// Generates an accent pattern for prominent segments.
  ///
  /// Prominent segments get special colors/effects, others are dimmed
  GeneratedPattern generateProminentAccent({
    required RooflineConfiguration config,
    required List<Color> accentColors,
    Color baseColor = const Color(0xFFFFFAF4),
  }) {
    final segments = <SegmentAssignment>[];

    for (final segment in config.segments) {
      if (segment.isProminent) {
        // Accent color for prominent segments
        final colorIndex = segments.where((s) => s.segment.isProminent).length;
        final accentColor = accentColors[colorIndex % accentColors.length];

        segments.add(SegmentAssignment(
          segment: segment,
          color: accentColor,
          effectId: 2, // Breathe
          speed: 100,
          intensity: 255,
        ));
      } else {
        // Warm white base for non-prominent
        segments.add(SegmentAssignment(
          segment: segment,
          color: baseColor,
          effectId: 0, // Solid
          speed: 128,
          intensity: 150,
        ));
      }
    }

    return GeneratedPattern(
      name: 'Prominent Accent',
      description: 'Highlighted key features',
      segments: segments,
      useSymmetry: false,
    );
  }

  /// Generates a pattern with anchor points highlighted.
  ///
  /// Anchor points (corners, peaks) get special treatment
  GeneratedPattern generateAnchorHighlight({
    required RooflineConfiguration config,
    required Color anchorColor,
    required Color fillColor,
  }) {
    final segments = <SegmentAssignment>[];

    // This would ideally use per-LED control, but for now we'll highlight
    // segments that have anchors with a special effect
    for (final segment in config.segments) {
      if (segment.anchorPixels.isNotEmpty) {
        // Segments with anchors get special color and twinkle
        segments.add(SegmentAssignment(
          segment: segment,
          color: anchorColor,
          effectId: 43, // Twinkle
          speed: 150,
          intensity: 200,
        ));
      } else {
        // Fill segments get solid color
        segments.add(SegmentAssignment(
          segment: segment,
          color: fillColor,
          effectId: 0, // Solid
          speed: 128,
          intensity: 128,
        ));
      }
    }

    return GeneratedPattern(
      name: 'Accent Points',
      description: 'Corners and peaks highlighted',
      segments: segments,
      useSymmetry: false,
    );
  }

  // Helper methods

  /// Finds the main peak segment (largest peak or most prominent)
  RooflineSegment? _findMainPeak(RooflineConfiguration config) {
    final peaks = config.segments
        .where((s) => s.type == SegmentType.peak || s.architecturalRole == ArchitecturalRole.peak)
        .toList();

    if (peaks.isEmpty) return null;

    // Prioritize prominent peaks
    final prominentPeaks = peaks.where((p) => p.isProminent).toList();
    if (prominentPeaks.isNotEmpty) {
      return prominentPeaks.reduce((a, b) => a.pixelCount > b.pixelCount ? a : b);
    }

    // Otherwise, return largest peak
    return peaks.reduce((a, b) => a.pixelCount > b.pixelCount ? a : b);
  }

  /// Sorts segments by flow direction
  List<RooflineSegment> _sortByFlowDirection(
    List<RooflineSegment> segments,
    SegmentDirection direction,
  ) {
    final sorted = List<RooflineSegment>.from(segments);

    switch (direction) {
      case SegmentDirection.leftToRight:
      case SegmentDirection.towardStreet:
        sorted.sort((a, b) => a.startPixel.compareTo(b.startPixel));
        break;
      case SegmentDirection.rightToLeft:
      case SegmentDirection.awayFromStreet:
        sorted.sort((a, b) => b.startPixel.compareTo(a.startPixel));
        break;
      case SegmentDirection.upward:
        // Sort by architectural role (eaves first, then peaks)
        sorted.sort((a, b) {
          final aIsEave = a.architecturalRole == ArchitecturalRole.eave;
          final bIsEave = b.architecturalRole == ArchitecturalRole.eave;
          if (aIsEave && !bIsEave) return -1;
          if (!aIsEave && bIsEave) return 1;
          return a.startPixel.compareTo(b.startPixel);
        });
        break;
      case SegmentDirection.downward:
        // Sort by architectural role (peaks first, then eaves)
        sorted.sort((a, b) {
          final aIsPeak = a.architecturalRole == ArchitecturalRole.peak;
          final bIsPeak = b.architecturalRole == ArchitecturalRole.peak;
          if (aIsPeak && !bIsPeak) return -1;
          if (!aIsPeak && bIsPeak) return 1;
          return a.startPixel.compareTo(b.startPixel);
        });
        break;
      default:
        // Keep original order
        break;
    }

    return sorted;
  }

  /// Generates a standard pattern (fallback when no special handling needed)
  GeneratedPattern _generateStandardPattern({
    required RooflineConfiguration config,
    required List<Color> colors,
    required int effectId,
    int speed = 128,
    int intensity = 128,
  }) {
    final segments = <SegmentAssignment>[];

    for (int i = 0; i < config.segments.length; i++) {
      final segment = config.segments[i];
      final colorIndex = i % colors.length;

      segments.add(SegmentAssignment(
        segment: segment,
        color: colors[colorIndex],
        effectId: effectId,
        speed: speed,
        intensity: intensity,
      ));
    }

    return GeneratedPattern(
      name: 'Standard ${_effectName(effectId)}',
      description: 'Applied across all segments',
      segments: segments,
      useSymmetry: false,
    );
  }

  String _effectName(int effectId) {
    switch (effectId) {
      case 0:
        return 'Solid';
      case 2:
        return 'Breathe';
      case 28:
        return 'Chase';
      case 35:
        return 'Wave';
      case 43:
        return 'Twinkle';
      default:
        return 'Effect $effectId';
    }
  }

  /// Converts a generated pattern to WLED JSON payload
  Map<String, dynamic> patternToWledPayload(GeneratedPattern pattern) {
    final segArray = <Map<String, dynamic>>[];

    for (final assignment in pattern.segments) {
      final segment = assignment.segment;

      segArray.add({
        'start': segment.startPixel,
        'stop': segment.endPixel + 1, // WLED uses exclusive end
        'on': true,
        'col': [
          [
            assignment.color.red,
            assignment.color.green,
            assignment.color.blue,
            0, // White channel
          ]
        ],
        'fx': assignment.effectId,
        'sx': assignment.speed,
        'ix': assignment.intensity,
        if (assignment.offset != null) 'o1': assignment.offset,
      });
    }

    return {
      'on': true,
      'bri': 255,
      'seg': segArray,
    };
  }
}

/// Represents an assignment of color/effect to a specific segment
class SegmentAssignment {
  final RooflineSegment segment;
  final Color color;
  final int effectId;
  final int speed;
  final int intensity;
  final int? offset;

  const SegmentAssignment({
    required this.segment,
    required this.color,
    required this.effectId,
    this.speed = 128,
    this.intensity = 128,
    this.offset,
  });
}

/// Represents a generated pattern with metadata
class GeneratedPattern {
  final String name;
  final String description;
  final List<SegmentAssignment> segments;
  final bool useSymmetry;
  final int? symmetryAxis;

  const GeneratedPattern({
    required this.name,
    required this.description,
    required this.segments,
    this.useSymmetry = false,
    this.symmetryAxis,
  });

  /// Get all colors used in this pattern
  List<Color> get colors {
    return segments.map((s) => s.color).toSet().toList();
  }

  /// Get primary effect ID (most common)
  int get primaryEffectId {
    if (segments.isEmpty) return 0;
    final effectCounts = <int, int>{};
    for (final seg in segments) {
      effectCounts[seg.effectId] = (effectCounts[seg.effectId] ?? 0) + 1;
    }
    return effectCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }
}
