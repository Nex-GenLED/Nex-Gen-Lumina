import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design_studio/models/composed_pattern.dart';
import 'package:nexgen_command/features/design_studio/models/design_intent.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart' hide ArchitecturalRole;

/// Service for composing design intents into WLED-ready patterns.
///
/// Takes a validated [DesignIntent] and generates a [ComposedPattern]
/// containing LED color groups and the WLED JSON payload.
class PatternComposer {
  /// Compose a validated design intent into a WLED-ready pattern.
  ///
  /// The composition process:
  /// 1. Resolve zones to pixel ranges for each layer
  /// 2. Apply spacing rules to generate LED assignments
  /// 3. Merge layers respecting priority (higher = on top)
  /// 4. Generate the WLED JSON payload
  CompositionResult compose({
    required DesignIntent intent,
    required RooflineConfiguration config,
  }) {
    // Validate intent is ready
    if (!intent.isReady && intent.ambiguities.isNotEmpty) {
      return CompositionResult.failure(
        'Design intent has unresolved ambiguities',
        recommendManual: true,
        suggestions: ['Resolve clarification questions first'],
      );
    }

    if (intent.layers.isEmpty) {
      return CompositionResult.failure(
        'No design layers specified',
        suggestions: ['Add at least one layer to your design'],
      );
    }

    try {
      // Process each layer
      final layerGroups = <int, List<LedColorGroup>>{};
      final warnings = <String>[];

      for (final layer in intent.layers.where((l) => l.enabled)) {
        final groups = _composeLayer(layer, config);
        if (groups.isEmpty) {
          warnings.add('Layer "${layer.name}" produced no LED assignments');
        } else {
          layerGroups[layer.priority] = groups;
        }
      }

      if (layerGroups.isEmpty) {
        return CompositionResult.failure(
          'No layers produced LED assignments',
          suggestions: ['Check that zones match your roofline configuration'],
        );
      }

      // Merge layers by priority (lowest priority first, highest overwrites)
      final sortedPriorities = layerGroups.keys.toList()..sort();
      final mergedGroups = <LedColorGroup>[];

      for (final priority in sortedPriorities) {
        final groups = layerGroups[priority]!;
        mergedGroups.addAll(groups);
      }

      // Consolidate overlapping groups (later ones win)
      final finalGroups = _consolidateGroups(mergedGroups, config.totalPixelCount);

      // Extract used colors for display
      final usedColors = _extractUsedColors(finalGroups);

      // Determine if we have motion
      final hasMotion = intent.layers.any((l) => l.motion != null);
      final primaryMotion = intent.layers
          .where((l) => l.motion != null)
          .map((l) => l.motion!)
          .firstOrNull;

      // Generate WLED payload
      final wledPayload = _generateWledPayload(
        groups: finalGroups,
        motion: primaryMotion,
        globalSettings: intent.globalSettings,
        totalPixels: config.totalPixelCount,
      );

      // Build the composed pattern
      final pattern = ComposedPattern(
        name: _generatePatternName(intent),
        description: _generateDescription(intent),
        sourceIntent: intent,
        colorGroups: finalGroups,
        effectId: primaryMotion?.effectId ?? 0,
        speed: primaryMotion?.speed ?? 128,
        intensity: primaryMotion?.intensity ?? 128,
        brightness: intent.globalSettings.brightness,
        hasMotion: hasMotion,
        motionDirection: primaryMotion?.direction,
        reverse: primaryMotion?.reverse ?? false,
        wledPayload: wledPayload,
        usedColors: usedColors,
        totalPixels: config.totalPixelCount,
        composedAt: DateTime.now(),
        warnings: warnings,
      );

      return CompositionResult.success(
        pattern,
        warnings: warnings,
      );
    } catch (e) {
      return CompositionResult.failure(
        'Error composing pattern: $e',
        recommendManual: true,
      );
    }
  }

  /// Compose a single layer into LED color groups.
  List<LedColorGroup> _composeLayer(
    DesignLayer layer,
    RooflineConfiguration config,
  ) {
    // Get pixel ranges for the target zone
    final pixelRanges = _resolveZoneToPixels(layer.targetZone, config);
    if (pixelRanges.isEmpty) return [];

    final groups = <LedColorGroup>[];

    for (final range in pixelRanges) {
      final rangeGroups = _applyPatternToRange(
        range: range,
        colors: layer.colors,
        pattern: layer.pattern,
        config: config,
      );
      groups.addAll(rangeGroups);
    }

    return groups;
  }

  /// Resolve a zone selector to pixel ranges.
  List<_PixelRange> _resolveZoneToPixels(
    ZoneSelector zone,
    RooflineConfiguration config,
  ) {
    switch (zone.type) {
      case ZoneSelectorType.all:
        return [_PixelRange(0, config.totalPixelCount - 1)];

      case ZoneSelectorType.segments:
        if (zone.segmentIds == null) {
          return [_PixelRange(0, config.totalPixelCount - 1)];
        }
        return config.segments
            .where((s) => zone.segmentIds!.contains(s.id))
            .map((s) => _PixelRange(s.startPixel, s.endPixel))
            .toList();

      case ZoneSelectorType.architectural:
        if (zone.roles == null) return [];
        return config.segments
            .where((s) => _segmentMatchesRoles(s, zone.roles!))
            .map((s) => _PixelRange(s.startPixel, s.endPixel))
            .toList();

      case ZoneSelectorType.location:
        // Filter segments by location tag (front, back, left, right)
        final location = zone.location?.toLowerCase() ?? '';
        return config.segments
            .where((s) => _segmentMatchesLocation(s, location))
            .map((s) => _PixelRange(s.startPixel, s.endPixel))
            .toList();

      case ZoneSelectorType.level:
        if (zone.level == null) return [];
        return config.segments
            .where((s) => s.level == zone.level)
            .map((s) => _PixelRange(s.startPixel, s.endPixel))
            .toList();

      case ZoneSelectorType.custom:
        if (zone.pixelRanges == null) return [];
        return zone.pixelRanges!
            .map((r) => _PixelRange(r.start, r.end))
            .toList();
    }
  }

  /// Check if a segment matches architectural roles.
  bool _segmentMatchesRoles(RooflineSegment segment, List<ArchitecturalRole> roles) {
    for (final role in roles) {
      switch (role) {
        case ArchitecturalRole.peak:
          if (segment.type == SegmentType.peak) return true;
          break;
        case ArchitecturalRole.corner:
          if (segment.type == SegmentType.corner) return true;
          break;
        case ArchitecturalRole.run:
        case ArchitecturalRole.eave:
        case ArchitecturalRole.fascia:
          if (segment.type == SegmentType.run) return true;
          break;
        case ArchitecturalRole.column:
          if (segment.type == SegmentType.column) return true;
          break;
        case ArchitecturalRole.connector:
          if (segment.type == SegmentType.connector) return true;
          break;
        default:
          break;
      }
    }
    return false;
  }

  /// Check if a segment matches a location (front, back, etc.).
  bool _segmentMatchesLocation(RooflineSegment segment, String location) {
    // Check segment name or tags for location keywords
    final nameLower = segment.name.toLowerCase();

    if (location == 'front') {
      return nameLower.contains('front') ||
             nameLower.contains('street') ||
             nameLower.contains('main');
    }
    if (location == 'back') {
      return nameLower.contains('back') ||
             nameLower.contains('rear') ||
             nameLower.contains('yard');
    }
    if (location == 'left') {
      return nameLower.contains('left') ||
             nameLower.contains('west');
    }
    if (location == 'right') {
      return nameLower.contains('right') ||
             nameLower.contains('east');
    }

    return false;
  }

  /// Apply pattern and colors to a pixel range.
  List<LedColorGroup> _applyPatternToRange({
    required _PixelRange range,
    required ColorAssignment colors,
    required PatternRule pattern,
    required RooflineConfiguration config,
  }) {
    final groups = <LedColorGroup>[];
    final primaryColorList = _colorToList(colors.primaryColor);

    // Handle spacing rules
    if (colors.spacingRule != null) {
      return _applySpacingRule(
        range: range,
        colors: colors,
        spacingRule: colors.spacingRule!,
        config: config,
      );
    }

    // Handle pattern types
    switch (pattern.type) {
      case PatternType.solid:
        groups.add(LedColorGroup(
          startLed: range.start,
          endLed: range.end,
          color: primaryColorList,
        ));
        break;

      case PatternType.alternating:
        final secondaryColorList = colors.secondaryColor != null
            ? _colorToList(colors.secondaryColor!)
            : _colorToList(Colors.black);

        for (int i = range.start; i <= range.end; i++) {
          final isOdd = (i - range.start) % 2 == 1;
          groups.add(LedColorGroup(
            startLed: i,
            endLed: i,
            color: isOdd ? secondaryColorList : primaryColorList,
          ));
        }
        break;

      case PatternType.gradient:
        if (pattern.gradientStops != null && pattern.gradientStops!.length >= 2) {
          groups.addAll(_generateGradient(
            range: range,
            stops: pattern.gradientStops!,
          ));
        } else {
          // Fallback to solid
          groups.add(LedColorGroup(
            startLed: range.start,
            endLed: range.end,
            color: primaryColorList,
          ));
        }
        break;

      case PatternType.wave:
      case PatternType.twinkle:
        // These are handled by WLED effects, just set the base color
        groups.add(LedColorGroup(
          startLed: range.start,
          endLed: range.end,
          color: primaryColorList,
        ));
        break;
    }

    return groups;
  }

  /// Apply a spacing rule to a pixel range.
  List<LedColorGroup> _applySpacingRule({
    required _PixelRange range,
    required ColorAssignment colors,
    required SpacingRule spacingRule,
    required RooflineConfiguration config,
  }) {
    final groups = <LedColorGroup>[];
    final onColorList = colors.accentColor != null
        ? _colorToList(colors.accentColor!)
        : _colorToList(colors.primaryColor);
    final offColorList = colors.fillColor != null
        ? _colorToList(colors.fillColor!)
        : null;

    final rangeLength = range.end - range.start + 1;

    switch (spacingRule.type) {
      case SpacingType.pattern:
        // N on, M off repeating pattern
        final cycleLength = spacingRule.onCount + spacingRule.offCount;
        int position = 0;
        bool isOn = spacingRule.startWithOn;

        while (position < rangeLength) {
          final ledIndex = range.start + position;
          final count = isOn ? spacingRule.onCount : spacingRule.offCount;
          final endIndex = math.min(ledIndex + count - 1, range.end);

          if (isOn) {
            groups.add(LedColorGroup(
              startLed: ledIndex,
              endLed: endIndex,
              color: onColorList,
            ));
          } else if (offColorList != null) {
            groups.add(LedColorGroup(
              startLed: ledIndex,
              endLed: endIndex,
              color: offColorList,
            ));
          }

          position += count;
          isOn = !isOn;
        }
        break;

      case SpacingType.equallySpaced:
        // Distribute N lights evenly across the range
        final count = spacingRule.onCount;
        if (count <= 0) break;

        if (count == 1) {
          // Single light in the middle
          final midPoint = range.start + rangeLength ~/ 2;
          groups.add(LedColorGroup(
            startLed: midPoint,
            endLed: midPoint,
            color: onColorList,
          ));
        } else {
          // Distribute evenly including endpoints
          final spacing = (rangeLength - 1) / (count - 1);
          for (int i = 0; i < count; i++) {
            final ledIndex = range.start + (spacing * i).round();
            if (ledIndex <= range.end) {
              groups.add(LedColorGroup(
                startLed: ledIndex,
                endLed: ledIndex,
                color: onColorList,
              ));
            }
          }
        }

        // Fill between with off color if specified
        if (offColorList != null) {
          // This would need a more complex implementation to fill gaps
          // For now, we just add the "on" lights
        }
        break;

      case SpacingType.everyNth:
        // Light every Nth pixel
        final interval = spacingRule.interval ?? (spacingRule.onCount + spacingRule.offCount);
        for (int i = 0; i < rangeLength; i += interval) {
          final ledIndex = range.start + i;
          groups.add(LedColorGroup(
            startLed: ledIndex,
            endLed: ledIndex,
            color: onColorList,
          ));
        }
        break;

      case SpacingType.anchorsOnly:
        // Only light anchor points in the affected segments
        for (final segment in config.segments) {
          if (segment.startPixel > range.end || segment.endPixel < range.start) {
            continue; // Segment doesn't overlap
          }

          for (final anchorLocal in segment.anchorPixels) {
            final anchorGlobal = segment.startPixel + anchorLocal;
            if (anchorGlobal >= range.start && anchorGlobal <= range.end) {
              // Add anchor with its LED count
              final anchorEnd = math.min(
                anchorGlobal + segment.anchorLedCount - 1,
                range.end,
              );
              groups.add(LedColorGroup(
                startLed: anchorGlobal,
                endLed: anchorEnd,
                color: onColorList,
              ));
            }
          }
        }
        break;

      case SpacingType.continuous:
        // No spacing, solid fill
        groups.add(LedColorGroup(
          startLed: range.start,
          endLed: range.end,
          color: onColorList,
        ));
        break;
    }

    return groups;
  }

  /// Generate gradient color groups.
  List<LedColorGroup> _generateGradient({
    required _PixelRange range,
    required List<GradientStop> stops,
  }) {
    final groups = <LedColorGroup>[];
    final rangeLength = range.end - range.start + 1;

    // Sort stops by position
    final sortedStops = List<GradientStop>.from(stops)
      ..sort((a, b) => a.position.compareTo(b.position));

    for (int i = range.start; i <= range.end; i++) {
      final position = (i - range.start) / rangeLength;

      // Find the two stops we're between
      GradientStop lower = sortedStops.first;
      GradientStop upper = sortedStops.last;

      for (int j = 0; j < sortedStops.length - 1; j++) {
        if (sortedStops[j].position <= position &&
            sortedStops[j + 1].position >= position) {
          lower = sortedStops[j];
          upper = sortedStops[j + 1];
          break;
        }
      }

      // Interpolate color
      final t = upper.position == lower.position
          ? 0.0
          : (position - lower.position) / (upper.position - lower.position);

      final color = Color.lerp(lower.color, upper.color, t) ?? lower.color;

      groups.add(LedColorGroup(
        startLed: i,
        endLed: i,
        color: _colorToList(color),
      ));
    }

    return _mergeAdjacentSameColor(groups);
  }

  /// Consolidate overlapping groups (later entries win).
  List<LedColorGroup> _consolidateGroups(List<LedColorGroup> groups, int totalPixels) {
    if (groups.isEmpty) return groups;

    // Create a pixel-by-pixel color map
    final pixelColors = List<List<int>?>.filled(totalPixels, null);

    for (final group in groups) {
      for (int i = group.startLed; i <= group.endLed && i < totalPixels; i++) {
        pixelColors[i] = group.color;
      }
    }

    // Convert back to groups
    final result = <LedColorGroup>[];
    int? currentStart;
    List<int>? currentColor;

    for (int i = 0; i < totalPixels; i++) {
      final color = pixelColors[i];

      if (color == null) {
        // End current group if any
        if (currentStart != null && currentColor != null) {
          result.add(LedColorGroup(
            startLed: currentStart,
            endLed: i - 1,
            color: currentColor,
          ));
          currentStart = null;
          currentColor = null;
        }
      } else if (currentColor == null || !_colorsEqual(color, currentColor)) {
        // End previous group
        if (currentStart != null && currentColor != null) {
          result.add(LedColorGroup(
            startLed: currentStart,
            endLed: i - 1,
            color: currentColor,
          ));
        }
        // Start new group
        currentStart = i;
        currentColor = color;
      }
    }

    // Close final group
    if (currentStart != null && currentColor != null) {
      result.add(LedColorGroup(
        startLed: currentStart,
        endLed: totalPixels - 1,
        color: currentColor,
      ));
    }

    return result;
  }

  /// Merge adjacent groups with the same color.
  List<LedColorGroup> _mergeAdjacentSameColor(List<LedColorGroup> groups) {
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

  /// Extract unique colors used in the groups.
  List<Color> _extractUsedColors(List<LedColorGroup> groups) {
    final colors = <int, Color>{};

    for (final group in groups) {
      final color = group.flutterColor;
      colors[color.value] = color;
    }

    return colors.values.toList();
  }

  /// Generate the WLED JSON payload.
  Map<String, dynamic> _generateWledPayload({
    required List<LedColorGroup> groups,
    required MotionSettings? motion,
    required GlobalSettings globalSettings,
    required int totalPixels,
  }) {
    if (groups.isEmpty) {
      return {'on': false};
    }

    final effectId = motion?.effectId ?? 0;
    final hasEffect = effectId > 0;

    if (hasEffect) {
      // For effects, use segment-based color setup
      return _generateEffectPayload(
        groups: groups,
        motion: motion!,
        globalSettings: globalSettings,
        totalPixels: totalPixels,
      );
    } else {
      // For static patterns, use individual LED addressing
      return _generateStaticPayload(
        groups: groups,
        globalSettings: globalSettings,
        totalPixels: totalPixels,
      );
    }
  }

  /// Generate payload for effects/motion.
  Map<String, dynamic> _generateEffectPayload({
    required List<LedColorGroup> groups,
    required MotionSettings motion,
    required GlobalSettings globalSettings,
    required int totalPixels,
  }) {
    // Extract up to 3 colors for the effect
    final colors = <List<int>>[];
    for (final group in groups) {
      final color = group.color.take(3).toList();
      if (!colors.any((c) => _colorsEqual(c, color))) {
        colors.add(color);
        if (colors.length >= 3) break;
      }
    }

    if (colors.isEmpty) {
      colors.add([255, 255, 255]);
    }

    return {
      'on': true,
      'bri': globalSettings.brightness,
      'transition': globalSettings.smoothTransition
          ? globalSettings.transitionDuration ~/ 100
          : 0,
      'seg': [
        {
          'id': 0,
          'start': 0,
          'stop': totalPixels,
          'col': colors,
          'fx': motion.effectId ?? 0,
          'sx': motion.speed,
          'ix': motion.intensity,
          'rev': motion.reverse,
        }
      ],
    };
  }

  /// Generate payload for static patterns.
  Map<String, dynamic> _generateStaticPayload({
    required List<LedColorGroup> groups,
    required GlobalSettings globalSettings,
    required int totalPixels,
  }) {
    // Build individual LED array
    final ledArray = <int>[];

    for (final group in groups) {
      for (int led = group.startLed; led <= group.endLed; led++) {
        ledArray.add(led);
        ledArray.addAll(group.color.take(3));
      }
    }

    return {
      'on': true,
      'bri': globalSettings.brightness,
      'transition': globalSettings.smoothTransition
          ? globalSettings.transitionDuration ~/ 100
          : 0,
      'seg': [
        {
          'id': 0,
          'start': 0,
          'stop': totalPixels,
          'i': ledArray,
        }
      ],
    };
  }

  /// Generate a name for the pattern.
  String _generatePatternName(DesignIntent intent) {
    if (intent.layers.isEmpty) return 'Custom Pattern';

    final primaryLayer = intent.layers.first;
    final hasMotion = intent.layers.any((l) => l.motion != null);

    final parts = <String>[];

    // Add primary color
    final color = primaryLayer.colors.primaryColor;
    parts.add(_getColorName(color));

    // Add zone if not "all"
    if (primaryLayer.targetZone.type != ZoneSelectorType.all) {
      parts.add(primaryLayer.targetZone.description);
    }

    // Add motion type if present
    if (hasMotion) {
      final motion = intent.layers.firstWhere((l) => l.motion != null).motion!;
      parts.add(motion.motionType.name);
    }

    return parts.join(' ').capitalize();
  }

  /// Generate a description for the pattern.
  String _generateDescription(DesignIntent intent) {
    if (intent.layers.isEmpty) return 'Custom pattern';

    final descriptions = <String>[];

    for (final layer in intent.layers) {
      final colorName = _getColorName(layer.colors.primaryColor);
      final zone = layer.targetZone.description;
      var desc = '$colorName on $zone';

      if (layer.colors.spacingRule != null) {
        desc += ' (${layer.colors.spacingRule!.description})';
      }

      if (layer.motion != null) {
        desc += ' with ${layer.motion!.motionType.name} ${layer.motion!.direction.displayName}';
      }

      descriptions.add(desc);
    }

    return descriptions.join('; ');
  }

  /// Get a human-readable name for a color.
  String _getColorName(Color color) {
    // Check against common colors
    if (_isCloseColor(color, Colors.red)) return 'Red';
    if (_isCloseColor(color, Colors.green)) return 'Green';
    if (_isCloseColor(color, Colors.blue)) return 'Blue';
    if (_isCloseColor(color, Colors.yellow)) return 'Yellow';
    if (_isCloseColor(color, Colors.orange)) return 'Orange';
    if (_isCloseColor(color, Colors.purple)) return 'Purple';
    if (_isCloseColor(color, Colors.pink)) return 'Pink';
    if (_isCloseColor(color, Colors.cyan)) return 'Cyan';
    if (_isCloseColor(color, Colors.white)) return 'White';
    if (_isCloseColor(color, Colors.black)) return 'Black';
    if (_isCloseColor(color, const Color(0xFF228B22))) return 'Forest Green';
    if (_isCloseColor(color, const Color(0xFFFFD700))) return 'Gold';
    if (_isCloseColor(color, const Color(0xFFFF6B6B))) return 'Coral';

    // Default to hex
    return '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
  }

  /// Check if two colors are close (within threshold).
  bool _isCloseColor(Color a, Color b, {int threshold = 30}) {
    return (a.red - b.red).abs() < threshold &&
           (a.green - b.green).abs() < threshold &&
           (a.blue - b.blue).abs() < threshold;
  }

  /// Convert a Flutter Color to RGBW list.
  List<int> _colorToList(Color color, {int white = 0}) {
    return [color.red, color.green, color.blue, white];
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

/// Internal helper for pixel ranges.
class _PixelRange {
  final int start;
  final int end;

  _PixelRange(this.start, this.end);

  int get length => end - start + 1;
}

/// Extension for string capitalization.
extension _StringCapitalization on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
