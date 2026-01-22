import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';
import 'package:nexgen_command/openai/openai_config.dart';

/// LuminaBrain aggregates local context (who/where/when) and injects it into
/// every OpenAI request for improved grounding and personalization.
class LuminaBrain {
  /// Sends a conversational request enriched with context.
  static Future<String> chat(WidgetRef ref, String userPrompt) async {
    final contextBlock = _buildContextBlock(ref);
    return LuminaAI.chat(userPrompt, contextBlock: contextBlock);
  }

  /// Requests a strict WLED JSON payload with context aware instructions.
  static Future<Map<String, dynamic>> generateWledJson(WidgetRef ref, String userPrompt) async {
    final contextBlock = _buildContextBlock(ref);
    return LuminaAI.generateWledJson(userPrompt, contextBlock: contextBlock);
  }

  /// Sends a refinement request that modifies an existing pattern.
  /// The [currentPattern] is the full pattern context including colors, effect, speed, etc.
  /// The [refinementPrompt] describes what to change (e.g., "Make it slower").
  static Future<String> chatRefinement(
    WidgetRef ref,
    String refinementPrompt, {
    required Map<String, dynamic> currentPattern,
  }) async {
    final contextBlock = _buildContextBlock(ref);
    return LuminaAI.chatRefinement(
      refinementPrompt,
      currentPattern: currentPattern,
      contextBlock: contextBlock,
    );
  }

  /// Generates a segment-aware pattern suggestion based on the user's roofline.
  ///
  /// This method is specifically designed for the Design Studio to generate
  /// patterns that respect segment boundaries and anchor points.
  ///
  /// Returns a map with:
  /// - 'suggestion': Human-readable description
  /// - 'segments': List of segment color/effect assignments
  /// - 'wled': Ready-to-apply WLED payload
  static Future<Map<String, dynamic>> generateSegmentAwarePattern(
    WidgetRef ref,
    String userPrompt, {
    bool highlightAnchors = true,
    bool useSymmetry = true,
  }) async {
    // Get roofline config
    final rooflineConfig = ref.read(currentRooflineConfigProvider).maybeWhen(
          data: (config) => config,
          orElse: () => null,
        );

    if (rooflineConfig == null || rooflineConfig.segments.isEmpty) {
      // Fall back to standard generation if no roofline config
      return generateWledJson(ref, userPrompt);
    }

    // Build enhanced prompt with segment details
    final enhancedPrompt = _buildSegmentAwarePrompt(
      userPrompt,
      rooflineConfig,
      highlightAnchors: highlightAnchors,
      useSymmetry: useSymmetry,
    );

    final contextBlock = _buildContextBlock(ref);
    return LuminaAI.generateWledJson(enhancedPrompt, contextBlock: contextBlock);
  }

  /// Builds an enhanced prompt that includes segment-specific instructions.
  static String _buildSegmentAwarePrompt(
    String userPrompt,
    RooflineConfiguration config, {
    required bool highlightAnchors,
    required bool useSymmetry,
  }) {
    final buffer = StringBuffer(userPrompt);
    buffer.writeln('\n\nIMPORTANT - Apply this pattern to my specific roofline layout:');
    buffer.writeln('Total LEDs: ${config.totalPixelCount}');

    // Describe segments for the AI
    buffer.writeln('\nSegments:');
    for (final segment in config.segments) {
      buffer.write('- ${segment.name} (${_segmentTypeName(segment.type)}): ');
      buffer.writeln('LED range ${segment.startPixel} to ${segment.endPixel}');
    }

    if (highlightAnchors) {
      final anchors = <String>[];
      for (final segment in config.segments) {
        for (final anchorIdx in segment.anchorPixels) {
          final globalIdx = segment.startPixel + anchorIdx;
          anchors.add('LED $globalIdx (${segment.name})');
        }
      }
      if (anchors.isNotEmpty) {
        buffer.writeln('\nAccent points that should be highlighted:');
        for (final anchor in anchors.take(10)) {
          buffer.writeln('- $anchor');
        }
        if (anchors.length > 10) {
          buffer.writeln('- ... and ${anchors.length - 10} more');
        }
      }
    }

    if (useSymmetry) {
      // Find main peak for symmetry axis
      final peaks = config.segments.where((s) => s.type == SegmentType.peak).toList();
      if (peaks.isNotEmpty) {
        final mainPeak = peaks.reduce((a, b) => a.pixelCount > b.pixelCount ? a : b);
        buffer.writeln('\nSymmetry: The main peak "${mainPeak.name}" is the visual center.');
        buffer.writeln('Consider mirroring colors/effects on either side of the peak.');
      }
    }

    buffer.writeln('\nGenerate a WLED payload that applies this pattern across all segments.');

    return buffer.toString();
  }

  static String _buildContextBlock(WidgetRef ref) {
    String location = 'Unknown';
    String interests = 'None';
    String avoid = '';
    String rooflineContext = '';

    try {
      final profile = ref.read(currentUserProfileProvider).maybeWhen(
            data: (u) => u,
            orElse: () => null,
          );
      if (profile != null) {
        // Prefer explicit location field (e.g., "Kansas City, MO").
        if (profile.location != null && profile.location!.trim().isNotEmpty) {
          location = profile.location!.trim();
        }
        // Build interests list from interestTags.
        if (profile.interestTags.isNotEmpty) {
          interests = profile.interestTags.join(', ');
        }
        if (profile.dislikes.isNotEmpty) {
          avoid = profile.dislikes.join(', ');
        }
      }
    } catch (e) {
      debugPrint('LuminaBrain context profile read error: $e');
    }

    // Build roofline context if available
    try {
      final rooflineConfig = ref.read(currentRooflineConfigProvider).maybeWhen(
            data: (config) => config,
            orElse: () => null,
          );
      if (rooflineConfig != null && rooflineConfig.segments.isNotEmpty) {
        rooflineContext = _buildRooflineContext(rooflineConfig);
      }
    } catch (e) {
      debugPrint('LuminaBrain roofline config read error: $e');
    }

    final now = DateTime.now();
    final dateStr = _formatFullDate(now);
    final tod = _timeOfDayLabel(now);

    // Per spec: append this block to the system message.
    // Plaintext
    // CONTEXT:
    // - User Location: [City, State]
    // - Current Date: [Date_String]
    // - Known Interests: [Interests_List]
    // - Time of Day: [Morning/Night]
    final buffer = StringBuffer('CONTEXT:\n'
        '- User Location: $location\n'
        '- Current Date: $dateStr\n'
        '- Known Interests: $interests\n'
        '- Time of Day: $tod');

    if (avoid.isNotEmpty) {
      buffer.write('\n- AVOID THESE: $avoid');
    }

    if (rooflineContext.isNotEmpty) {
      buffer.write('\n\n$rooflineContext');
    }

    return buffer.toString();
  }

  /// Builds a detailed roofline context string for AI to understand the user's
  /// specific LED installation and make segment-aware recommendations.
  static String _buildRooflineContext(RooflineConfiguration config) {
    final buffer = StringBuffer('ROOFLINE INSTALLATION:\n');
    buffer.writeln('- Total LED Count: ${config.totalPixelCount}');
    buffer.writeln('- Number of Segments: ${config.segmentCount}');

    // Count segment types
    final typeCounts = <SegmentType, int>{};
    for (final segment in config.segments) {
      typeCounts[segment.type] = (typeCounts[segment.type] ?? 0) + 1;
    }

    if (typeCounts.isNotEmpty) {
      final typeDescriptions = typeCounts.entries
          .map((e) => '${e.value} ${_segmentTypeName(e.key)}${e.value > 1 ? 's' : ''}')
          .join(', ');
      buffer.writeln('- Segment Types: $typeDescriptions');
    }

    // Total anchor points
    final totalAnchors = config.segments.fold(0, (sum, s) => sum + s.anchorPixels.length);
    if (totalAnchors > 0) {
      buffer.writeln('- Accent Points (corners/peaks): $totalAnchors');
    }

    // Describe segments
    buffer.writeln('\nSegments (in order from LED #0):');
    for (final segment in config.segments) {
      buffer.write('  ${segment.name} (${_segmentTypeName(segment.type)}): ');
      buffer.write('LEDs ${segment.startPixel}-${segment.endPixel}');
      buffer.write(' (${segment.pixelCount} pixels)');
      if (segment.anchorPixels.isNotEmpty) {
        buffer.write(' [${segment.anchorPixels.length} anchors]');
      }
      buffer.writeln();
    }

    // Add guidance for AI
    buffer.writeln();
    buffer.writeln('ROOFLINE-AWARE PATTERN GUIDANCE:');
    buffer.writeln('- For downlighting effects, ensure corners and peaks are always lit');
    buffer.writeln('- Chase effects should flow naturally along the roofline direction');
    buffer.writeln('- Use anchor points as accent areas for special colors');
    buffer.writeln('- Peak segments are great focal points for holiday themes');
    buffer.writeln('- Symmetry suggestions: mirror patterns across the main peak when possible');

    return buffer.toString();
  }

  /// Returns human-readable segment type name.
  static String _segmentTypeName(SegmentType type) {
    switch (type) {
      case SegmentType.run:
        return 'horizontal run';
      case SegmentType.corner:
        return 'corner';
      case SegmentType.peak:
        return 'peak';
      case SegmentType.column:
        return 'column';
      case SegmentType.connector:
        return 'connector';
    }
  }

  static String _timeOfDayLabel(DateTime dt) {
    final h = dt.hour;
    // Minimal spec asks Morning/Night. We'll treat 5:00–16:59 as Morning, else Night.
    return (h >= 5 && h < 17) ? 'Morning' : 'Night';
  }

  static const _weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  static String _formatFullDate(DateTime dt) {
    // Example: "Sunday, Jan 5, 2026, 1:00 PM"
    final weekday = _weekdays[(dt.weekday - 1).clamp(0, 6)];
    final month = _months[(dt.month - 1).clamp(0, 11)];
    final day = dt.day;
    final year = dt.year;
    final hour12 = ((dt.hour + 11) % 12) + 1;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$weekday, $month $day, $year, $hour12:$minute $ampm';
  }
}
