import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';
import 'package:nexgen_command/services/segment_pattern_generator.dart';

/// Service for parsing natural language commands that reference architectural features.
///
/// Examples:
/// - "Make the peaks glow white"
/// - "Chase the eaves with red"
/// - "Light up the front corners"
/// - "Pulse all prominent segments"
class ArchitecturalParserService {
  const ArchitecturalParserService();

  /// Parses a user command to identify target segments and desired effects.
  ///
  /// Returns a ParsedArchitecturalCommand with:
  /// - List of target segments matching the architectural description
  /// - Identified effect/pattern intention
  /// - Identified colors
  ArchitecturalCommand? parseCommand(
    String command,
    RooflineConfiguration config,
  ) {
    final lowerCommand = command.toLowerCase().trim();

    // Identify target segments
    final targetSegments = _identifyTargetSegments(lowerCommand, config);

    if (targetSegments.isEmpty) {
      debugPrint('ArchitecturalParser: No segments matched command: $command');
      return null;
    }

    // Identify effect intention
    final effect = _identifyEffect(lowerCommand);

    // Identify colors
    final colors = _identifyColors(lowerCommand);

    return ArchitecturalCommand(
      originalCommand: command,
      targetSegments: targetSegments,
      effect: effect,
      colors: colors,
    );
  }

  /// Identifies which segments match the architectural description in the command.
  List<RooflineSegment> _identifyTargetSegments(
    String command,
    RooflineConfiguration config,
  ) {
    final segments = <RooflineSegment>[];

    // Check for "all" or "entire" modifiers
    if (command.contains('all') || command.contains('entire') || command.contains('whole')) {
      // Special case: "all peaks", "all corners", etc.
      final role = _extractArchitecturalRole(command);
      if (role != null) {
        segments.addAll(
          config.segments.where((s) => s.architecturalRole == role),
        );
        if (segments.isNotEmpty) return segments;
      }

      // Otherwise, return all segments
      return config.segments;
    }

    // Check for location modifiers (front, back, left, right)
    final location = _extractLocation(command);

    // Check for architectural role
    final role = _extractArchitecturalRole(command);

    // Check for prominence
    final prominentOnly = command.contains('prominent') ||
                          command.contains('main') ||
                          command.contains('primary');

    // Filter segments
    for (final segment in config.segments) {
      bool matches = true;

      // Match by architectural role
      if (role != null) {
        if (segment.architecturalRole != role) {
          matches = false;
        }
      }

      // Match by location
      if (location != null && matches) {
        if (segment.location?.toLowerCase() != location.toLowerCase()) {
          matches = false;
        }
      }

      // Match by prominence
      if (prominentOnly && matches) {
        if (!segment.isProminent) {
          matches = false;
        }
      }

      // If no specific filters but segment name is mentioned
      if (role == null && location == null && !prominentOnly) {
        if (command.contains(segment.name.toLowerCase())) {
          matches = true;
        } else {
          matches = false;
        }
      }

      if (matches) {
        segments.add(segment);
      }
    }

    return segments;
  }

  /// Extracts architectural role from command text.
  ArchitecturalRole? _extractArchitecturalRole(String command) {
    // Check for plural forms (most common in natural language)
    if (command.contains('peak')) return ArchitecturalRole.peak;
    if (command.contains('eave')) return ArchitecturalRole.eave;
    if (command.contains('valley') || command.contains('valleys')) return ArchitecturalRole.valley;
    if (command.contains('ridge')) return ArchitecturalRole.ridge;
    if (command.contains('corner')) return ArchitecturalRole.corner;
    if (command.contains('fascia')) return ArchitecturalRole.fascia;
    if (command.contains('soffit')) return ArchitecturalRole.soffit;
    if (command.contains('gutter')) return ArchitecturalRole.gutter;
    if (command.contains('column')) return ArchitecturalRole.column;
    if (command.contains('arch')) return ArchitecturalRole.archway;

    return null;
  }

  /// Extracts location from command text.
  String? _extractLocation(String command) {
    if (command.contains('front')) return 'front';
    if (command.contains('back') || command.contains('rear')) return 'back';
    if (command.contains('left')) return 'left';
    if (command.contains('right')) return 'right';
    return null;
  }

  /// Identifies the desired effect from the command.
  String _identifyEffect(String command) {
    // Static/solid effects
    if (command.contains('solid') ||
        command.contains('static') ||
        command.contains('steady')) {
      return 'solid';
    }

    // Chase effects
    if (command.contains('chase') ||
        command.contains('running') ||
        command.contains('flow')) {
      return 'chase';
    }

    // Pulse/breathe effects
    if (command.contains('pulse') ||
        command.contains('breathe') ||
        command.contains('throb')) {
      return 'pulse';
    }

    // Twinkle/sparkle effects
    if (command.contains('twinkle') ||
        command.contains('sparkle') ||
        command.contains('shimmer')) {
      return 'twinkle';
    }

    // Glow effect (often used for peaks/corners)
    if (command.contains('glow') ||
        command.contains('illuminate') ||
        command.contains('light up')) {
      return 'glow';
    }

    // Rainbow effects
    if (command.contains('rainbow') ||
        command.contains('color cycle')) {
      return 'rainbow';
    }

    // Wave effects
    if (command.contains('wave') ||
        command.contains('ripple')) {
      return 'wave';
    }

    // Fire effects
    if (command.contains('fire') ||
        command.contains('flicker') ||
        command.contains('flame')) {
      return 'fire';
    }

    // Default to solid
    return 'solid';
  }

  /// Identifies colors mentioned in the command.
  List<String> _identifyColors(String command) {
    final colors = <String>[];

    // Basic colors
    if (command.contains('red')) colors.add('red');
    if (command.contains('green')) colors.add('green');
    if (command.contains('blue')) colors.add('blue');
    if (command.contains('white')) colors.add('white');
    if (command.contains('yellow')) colors.add('yellow');
    if (command.contains('orange')) colors.add('orange');
    if (command.contains('purple') || command.contains('violet')) colors.add('purple');
    if (command.contains('pink') || command.contains('magenta')) colors.add('pink');
    if (command.contains('cyan') || command.contains('aqua')) colors.add('cyan');

    // Warm/cool descriptors
    if (command.contains('warm white')) {
      colors.clear();
      colors.add('warm white');
    } else if (command.contains('cool white')) {
      colors.clear();
      colors.add('cool white');
    }

    // Team/holiday colors
    if (command.contains('chiefs')) {
      colors.clear();
      colors.addAll(['red', 'yellow']);
    }
    if (command.contains('royals')) {
      colors.clear();
      colors.addAll(['blue', 'white']);
    }
    if (command.contains('christmas')) {
      colors.clear();
      colors.addAll(['red', 'green']);
    }
    if (command.contains('halloween')) {
      colors.clear();
      colors.addAll(['orange', 'purple']);
    }
    if (command.contains('patriotic') || command.contains('july') || command.contains('memorial day')) {
      colors.clear();
      colors.addAll(['red', 'white', 'blue']);
    }

    return colors;
  }

  /// Builds a description of the matched segments for user feedback.
  String describeTargets(List<RooflineSegment> segments) {
    if (segments.isEmpty) return 'no segments';
    if (segments.length == 1) return segments.first.name;

    // Group by architectural role
    final roleGroups = <ArchitecturalRole, int>{};
    for (final segment in segments) {
      if (segment.architecturalRole != null) {
        final role = segment.architecturalRole!;
        roleGroups[role] = (roleGroups[role] ?? 0) + 1;
      }
    }

    if (roleGroups.isNotEmpty && roleGroups.length == 1) {
      final role = roleGroups.keys.first;
      final count = roleGroups[role]!;
      if (count == 1) return 'the ${role.displayName.toLowerCase()}';
      return 'all ${role.pluralName}';
    }

    // Multiple roles or unnamed segments
    if (segments.length == 2) {
      return '${segments[0].name} and ${segments[1].name}';
    }

    // More than 2 segments
    return '${segments.length} segments';
  }

  /// Generates an intelligent pattern using segment-aware generation.
  ///
  /// This method uses the SegmentPatternGenerator to create patterns that:
  /// - Use symmetry when appropriate
  /// - Flow naturally along the roofline
  /// - Highlight architectural features
  GeneratedPattern generateIntelligentPattern({
    required RooflineConfiguration config,
    required ArchitecturalCommand command,
  }) {
    final generator = SegmentPatternGenerator();
    final colorObjects = command.colors.map(_colorNameToColorObject).toList();

    // Default to cyan if no colors specified
    if (colorObjects.isEmpty) {
      colorObjects.add(const Color(0xFF00E5FF));
    }

    // Determine pattern type based on command characteristics
    final commandLower = command.originalCommand.toLowerCase();

    // Check for symmetry keywords
    if (commandLower.contains('mirror') ||
        commandLower.contains('symmetrical') ||
        commandLower.contains('balanced')) {
      return generator.generateSymmetricalPattern(
        config: config,
        colors: colorObjects,
        effectId: ArchitecturalParserService._effectNameToId(command.effect),
      );
    }

    // Check for flow/chase keywords
    if (commandLower.contains('flow') || command.effect == 'chase') {
      final direction = _detectFlowDirection(commandLower);
      return generator.generateFlowPattern(
        config: config,
        colors: colorObjects,
        flowDirection: direction,
      );
    }

    // Check for wave keywords
    if (command.effect == 'wave') {
      return generator.generateWavePattern(
        config: config,
        colors: colorObjects,
      );
    }

    // Check for prominent accent
    if (commandLower.contains('prominent') ||
        commandLower.contains('accent') ||
        commandLower.contains('highlight')) {
      return generator.generateProminentAccent(
        config: config,
        accentColors: colorObjects,
      );
    }

    // Check for architectural highlight (single role)
    final role = _extractArchitecturalRole(commandLower);
    if (role != null && command.targetSegments.length < config.segments.length) {
      return generator.generateArchitecturalHighlight(
        config: config,
        targetRole: role,
        highlightColor: colorObjects.first,
        effectId: ArchitecturalParserService._effectNameToId(command.effect),
      );
    }

    // Default: standard pattern
    return generator.generateSymmetricalPattern(
      config: config,
      colors: colorObjects,
      effectId: ArchitecturalParserService._effectNameToId(command.effect),
    );
  }

  /// Detects flow direction from command text
  SegmentDirection _detectFlowDirection(String command) {
    if (command.contains('left to right') || command.contains('left-to-right')) {
      return SegmentDirection.leftToRight;
    }
    if (command.contains('right to left') || command.contains('right-to-left')) {
      return SegmentDirection.rightToLeft;
    }
    if (command.contains('up') || command.contains('upward')) {
      return SegmentDirection.upward;
    }
    if (command.contains('down') || command.contains('downward')) {
      return SegmentDirection.downward;
    }
    // Default to left-to-right
    return SegmentDirection.leftToRight;
  }

  /// Converts color name to Color object
  Color _colorNameToColorObject(String colorName) {
    switch (colorName.toLowerCase()) {
      case 'red':
        return const Color(0xFFFF0000);
      case 'green':
        return const Color(0xFF00FF00);
      case 'blue':
        return const Color(0xFF0000FF);
      case 'white':
        return const Color(0xFFFFFFFF);
      case 'warm white':
        return const Color(0xFFFFFAF4);
      case 'cool white':
        return const Color(0xFFC8DCFF);
      case 'yellow':
        return const Color(0xFFFFFF00);
      case 'orange':
        return const Color(0xFFFFA500);
      case 'purple':
        return const Color(0xFF800080);
      case 'pink':
        return const Color(0xFFFFC0CB);
      case 'cyan':
        return const Color(0xFF00FFFF);
      default:
        return const Color(0xFFFFFFFF);
    }
  }

  /// Converts effect name to WLED effect ID.
  static int _effectNameToId(String effectName) {
    switch (effectName.toLowerCase()) {
      case 'solid':
      case 'glow':
        return 0; // Solid
      case 'chase':
        return 28; // Chase
      case 'pulse':
        return 2; // Breathe
      case 'twinkle':
        return 43; // Twinkle
      case 'rainbow':
        return 9; // Rainbow
      case 'wave':
        return 35; // Sine Wave
      case 'fire':
        return 94; // Fire
      default:
        return 0; // Default to solid
    }
  }
}

/// Represents a parsed architectural command.
class ArchitecturalCommand {
  final String originalCommand;
  final List<RooflineSegment> targetSegments;
  final String effect;
  final List<String> colors;

  const ArchitecturalCommand({
    required this.originalCommand,
    required this.targetSegments,
    required this.effect,
    required this.colors,
  });

  /// Builds a WLED-compatible JSON payload for this command.
  Map<String, dynamic> toWledPayload() {
    // Build segment array with per-segment control
    final segArray = <Map<String, dynamic>>[];

    for (final segment in targetSegments) {
      final segPayload = <String, dynamic>{
        'start': segment.startPixel,
        'stop': segment.endPixel + 1, // WLED uses exclusive end
        'on': true,
      };

      // Apply colors
      if (colors.isNotEmpty) {
        segPayload['col'] = [_colorNameToRgb(colors.first)];
        if (colors.length > 1) {
          segPayload['col'].add(_colorNameToRgb(colors[1]));
        }
        if (colors.length > 2) {
          segPayload['col'].add(_colorNameToRgb(colors[2]));
        }
      }

      // Apply effect
      segPayload['fx'] = ArchitecturalParserService._effectNameToId(effect);

      segArray.add(segPayload);
    }

    return {
      'on': true,
      'bri': 255,
      'seg': segArray,
    };
  }

  /// Converts color name to RGB array.
  List<int> _colorNameToRgb(String colorName) {
    switch (colorName.toLowerCase()) {
      case 'red':
        return [255, 0, 0, 0];
      case 'green':
        return [0, 255, 0, 0];
      case 'blue':
        return [0, 0, 255, 0];
      case 'white':
        return [255, 255, 255, 0];
      case 'warm white':
        return [255, 250, 244, 0];
      case 'cool white':
        return [200, 220, 255, 0];
      case 'yellow':
        return [255, 255, 0, 0];
      case 'orange':
        return [255, 165, 0, 0];
      case 'purple':
        return [128, 0, 128, 0];
      case 'pink':
        return [255, 192, 203, 0];
      case 'cyan':
        return [0, 255, 255, 0];
      default:
        return [255, 255, 255, 0];
    }
  }

  @override
  String toString() {
    return 'ArchitecturalCommand(segments: ${targetSegments.length}, '
        'effect: $effect, colors: $colors)';
  }
}
