import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:nexgen_command/features/design/design_color_summary.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/models/composed_pattern.dart';
import 'package:nexgen_command/features/design/models/design_intent.dart';
import 'package:nexgen_command/features/wled/design_spacing_defaults.dart';
import 'package:nexgen_command/features/wled/wled_service.dart' show rgbToRgbw;
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart' hide ArchitecturalRole;

/// Service for composing design intents into WLED-ready patterns.
///
/// Takes a validated [DesignIntent] and generates a [ComposedPattern]
/// containing LED color groups and the WLED JSON payload.
///
/// Roofline slice 3 (the D-2 global-index defect): the composer works
/// CHANNEL-LOCALLY. Every zone resolves to ranges on a named hardware channel
/// (bus), every pattern and spacing rule is laid down inside that channel, and
/// the result is kept per channel ([ComposedPattern.channelGroups]). The
/// whole-controller [ComposedPattern.colorGroups] are a projection of that,
/// for the consumers that still draw in one flat index space. It used to be
/// the other way round: one flat space across every bus, consolidated over the
/// MAPPED pixel total, with no channel awareness anywhere in the file — so a
/// bus mapped shorter than its strip ate the tail of the next bus, and with no
/// WLED segment list to split the result over every bus collapsed into
/// channel 0 (ROOFLINE_CUSTOM_DESIGN_AUDIT_2026-11-03 §A.4; Parent Segment
/// spec §3.2).
class PatternComposer {
  /// Compose a validated design intent into a WLED-ready pattern.
  ///
  /// The composition process:
  /// 1. Resolve zones to channel-local pixel ranges for each layer
  /// 2. Apply spacing rules to generate LED assignments
  /// 3. Merge layers respecting priority (higher = on top), per channel
  /// 4. Generate the WLED JSON payload
  ///
  /// [baseColors] — roofline slice 3, "start from this design": the colours
  /// of a saved design the customer is making variations of. A layer whose
  /// colours the prompt did not state (the parser's default: white, nothing
  /// else) takes the saved design's primary / secondary / accent instead, so
  /// "every other light" on a red-and-blue design composes in red and blue.
  /// A layer that names its own colours is left alone. Null: no seeding.
  CompositionResult compose({
    required DesignIntent intent,
    required RooflineConfiguration config,
    DesignColorSummary? baseColors,
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
      // Seed unstated colours from the saved design, when there is one. The
      // seeded intent is what gets composed, named, described and stored, so
      // a saved variation's own `source_intent` says the colours it used.
      final seededIntent = baseColors == null
          ? intent
          : intent.copyWith(
              layers: [
                for (final layer in intent.layers)
                  layer.copyWith(colors: seedColors(layer.colors, baseColors)),
              ],
            );

      // Process each layer: priority → channel → that channel's groups.
      final layerGroups = <int, Map<int, List<LedColorGroup>>>{};
      final warnings = <String>[];

      for (final layer in seededIntent.layers.where((l) => l.enabled)) {
        final byChannel = _composeLayer(layer, config);
        if (byChannel.isEmpty) {
          warnings.add('Layer "${layer.name}" produced no LED assignments');
        } else {
          layerGroups[layer.priority] = byChannel;
        }
      }

      if (layerGroups.isEmpty) {
        return CompositionResult.failure(
          'No layers produced LED assignments',
          suggestions: ['Check that zones match your roofline configuration'],
        );
      }

      // Merge layers by priority (lowest priority first, highest overwrites),
      // keeping every channel's groups on that channel.
      final sortedPriorities = layerGroups.keys.toList()..sort();
      final merged = <int, List<LedColorGroup>>{};
      for (final priority in sortedPriorities) {
        for (final entry in layerGroups[priority]!.entries) {
          (merged[entry.key] ??= <LedColorGroup>[]).addAll(entry.value);
        }
      }

      // Consolidate overlapping groups per channel (later ones win), each
      // channel over ITS OWN length.
      final channelGroups = <int, List<LedColorGroup>>{};
      final channelLengths = <int, int>{};
      for (final channel in _channels(config)) {
        final length = _channelLength(config, channel);
        if (length <= 0) continue;
        channelLengths[channel] = length;
        final groups = merged[channel];
        if (groups == null || groups.isEmpty) continue;
        final consolidated = _consolidateGroups(groups, length);
        if (consolidated.isNotEmpty) channelGroups[channel] = consolidated;
      }

      // The whole-controller projection, for the flat-space consumers.
      final finalGroups = _projectToGlobal(channelGroups, channelLengths);
      final totalPixels =
          channelLengths.values.fold<int>(0, (sum, len) => sum + len);

      // Extract used colors for display
      final usedColors = _extractUsedColors(finalGroups);

      // Determine if we have motion
      final hasMotion = seededIntent.layers.any((l) => l.motion != null);
      final primaryMotion = seededIntent.layers
          .where((l) => l.motion != null)
          .map((l) => l.motion!)
          .firstOrNull;

      // Generate WLED payload
      final wledPayload = _generateWledPayload(
        channelGroups: channelGroups,
        motion: primaryMotion,
        globalSettings: seededIntent.globalSettings,
      );

      // Build the composed pattern
      final pattern = ComposedPattern(
        name: _generatePatternName(seededIntent),
        description: _generateDescription(seededIntent),
        sourceIntent: seededIntent,
        colorGroups: finalGroups,
        channelGroups: channelGroups,
        channelLengths: channelLengths,
        effectId: primaryMotion?.effectId ?? 0,
        speed: primaryMotion?.speed ?? 128,
        intensity: primaryMotion?.intensity ?? 128,
        brightness: seededIntent.globalSettings.brightness,
        hasMotion: hasMotion,
        motionDirection: primaryMotion?.direction,
        reverse: primaryMotion?.reverse ?? false,
        wledPayload: wledPayload,
        usedColors: usedColors,
        totalPixels: totalPixels,
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

  /// The colours a layer composes with when a saved design is the starting
  /// point: [colors] untouched when it states any colour, else the saved
  /// design's own primary / secondary / accent with the layer's spacing rule
  /// kept. Pure; public for the tests.
  static ColorAssignment seedColors(
      ColorAssignment colors, DesignColorSummary base) {
    if (!isUnstatedColors(colors)) return colors;
    final primary = base.primary;
    if (primary == null) return colors;
    return ColorAssignment(
      primaryColor: primary,
      secondaryColor: base.secondary,
      accentColor: base.accent,
      spacingRule: colors.spacingRule,
    );
  }

  /// True when [colors] is exactly what the parser produces for a clause that
  /// names no colour: white, and nothing else. A clause that says "white"
  /// looks the same here — the orchestrator passes no base colours for a
  /// prompt that names any colour, so that case never reaches [seedColors].
  static bool isUnstatedColors(ColorAssignment colors) =>
      colors.primaryColor.toARGB32() == 0xFFFFFFFF &&
      colors.secondaryColor == null &&
      colors.accentColor == null &&
      colors.fillColor == null;

  // ── Channels ──────────────────────────────────────────────────────────────

  /// Every hardware channel the composer lays LEDs over: the mapped channels
  /// plus any channel the config carries a device length for, sorted. A bus
  /// the map says nothing about still has LEDs; "everywhere" means it too.
  List<int> _channels(RooflineConfiguration config) {
    final ids = <int>{
      ...config.allChannelIndices,
      ...config.channelPixelCounts.keys,
    };
    return ids.toList()..sort();
  }

  /// LED count of [channel]: device truth when the config carries it, else
  /// that channel's mapped total — the same rule
  /// [RooflineConfiguration.channelGlobalOffset] applies.
  int _channelLength(RooflineConfiguration config, int channel) {
    final known = config.channelPixelCounts[channel];
    if (known != null && known > 0) return known;
    return config
        .segmentsForChannel(channel)
        .fold<int>(0, (total, s) => total + s.pixelCount);
  }

  /// Channel-local groups → whole-controller groups, channels in id order,
  /// each offset by the summed lengths of the channels before it.
  List<LedColorGroup> _projectToGlobal(
    Map<int, List<LedColorGroup>> channelGroups,
    Map<int, int> channelLengths,
  ) {
    final out = <LedColorGroup>[];
    var offset = 0;
    final channels = channelLengths.keys.toList()..sort();
    for (final channel in channels) {
      for (final g in channelGroups[channel] ?? const <LedColorGroup>[]) {
        out.add(LedColorGroup(
          startLed: g.startLed + offset,
          endLed: g.endLed + offset,
          color: g.color,
        ));
      }
      offset += channelLengths[channel]!;
    }
    return out;
  }

  /// Compose a single layer into LED color groups, per channel.
  Map<int, List<LedColorGroup>> _composeLayer(
    DesignLayer layer,
    RooflineConfiguration config,
  ) {
    // Get channel-local pixel ranges for the target zone
    final pixelRanges = _resolveZoneToPixels(layer.targetZone, config);
    final byChannel = <int, List<LedColorGroup>>{};

    for (final range in pixelRanges) {
      final rangeGroups = _applyPatternToRange(
        range: range,
        colors: layer.colors,
        pattern: layer.pattern,
        config: config,
      );
      if (rangeGroups.isEmpty) continue;
      (byChannel[range.channel] ??= <LedColorGroup>[]).addAll(rangeGroups);
    }

    return byChannel;
  }

  /// Resolve a zone selector to channel-local pixel ranges.
  List<_PixelRange> _resolveZoneToPixels(
    ZoneSelector zone,
    RooflineConfiguration config,
  ) {
    switch (zone.type) {
      case ZoneSelectorType.all:
        return _wholeChannels(config);

      case ZoneSelectorType.segments:
        if (zone.segmentIds == null) return _wholeChannels(config);
        return _segmentRanges(
            config, config.segments.where((s) => zone.segmentIds!.contains(s.id)));

      case ZoneSelectorType.architectural:
        if (zone.roles == null) return [];
        return _segmentRanges(
            config, config.segments.where((s) => _segmentMatchesRoles(s, zone.roles!)));

      case ZoneSelectorType.location:
        // Filter segments by location tag (front, back, left, right)
        final location = zone.location?.toLowerCase() ?? '';
        return _segmentRanges(
            config, config.segments.where((s) => _segmentMatchesLocation(s, location)));

      case ZoneSelectorType.level:
        if (zone.level == null) return [];
        return _segmentRanges(
            config, config.segments.where((s) => s.level == zone.level));

      case ZoneSelectorType.custom:
        if (zone.pixelRanges == null) return [];
        return _customRanges(config, zone.pixelRanges!);
    }
  }

  /// Every LED of every channel.
  List<_PixelRange> _wholeChannels(RooflineConfiguration config) => [
        for (final channel in _channels(config))
          if (_channelLength(config, channel) > 0)
            _PixelRange(channel, 0, _channelLength(config, channel) - 1),
      ];

  /// Each segment's own LEDs on its own channel. A segment lying wholly past
  /// the end of its strip has no LEDs; one running past the end is clamped to
  /// the strip (the same clamp-at-consumption `globalEndOf` applies).
  List<_PixelRange> _segmentRanges(
    RooflineConfiguration config,
    Iterable<RooflineSegment> segments,
  ) {
    final out = <_PixelRange>[];
    for (final s in segments) {
      final length = _channelLength(config, s.channelIndex);
      final end = length > 0 ? math.min(s.endPixel, length - 1) : s.endPixel;
      if (end < s.startPixel) continue;
      out.add(_PixelRange(s.channelIndex, s.startPixel, end));
    }
    return out;
  }

  /// A custom [PixelRange] is the one input still numbered across the whole
  /// controller (nothing in the app produces one today); it is cut at the
  /// channel boundaries into channel-local pieces.
  List<_PixelRange> _customRanges(
    RooflineConfiguration config,
    List<PixelRange> ranges,
  ) {
    final out = <_PixelRange>[];
    for (final r in ranges) {
      var offset = 0;
      for (final channel in _channels(config)) {
        final length = _channelLength(config, channel);
        if (length > 0) {
          final start = math.max(r.start, offset);
          final end = math.min(r.end, offset + length - 1);
          if (end >= start) {
            out.add(_PixelRange(channel, start - offset, end - offset));
          }
        }
        offset += length;
      }
    }
    return out;
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

  /// Apply pattern and colors to a (channel-local) pixel range.
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

  /// Apply a spacing rule to a (channel-local) pixel range. The rule's phase
  /// starts at the range's first LED, so on a whole-house zone every bus
  /// starts its own "1 on, 3 off" at its own LED 0.
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
        // Only light anchor points in the affected segments of THIS channel.
        // Both the segment's startPixel and its anchors are channel-local.
        for (final segment in config.segmentsForChannel(range.channel)) {
          if (segment.startPixel > range.end || segment.endPixel < range.start) {
            continue; // Segment doesn't overlap
          }

          for (final anchorLocal in segment.anchorPixels) {
            final anchor = segment.startPixel + anchorLocal;
            if (anchor >= range.start && anchor <= range.end) {
              // Add anchor with its LED count
              final anchorEnd = math.min(
                anchor + segment.anchorLedCount - 1,
                range.end,
              );
              groups.add(LedColorGroup(
                startLed: anchor,
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

    if (sortedStops.isEmpty) return groups;

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

  /// Consolidate overlapping groups (later entries win) over one channel of
  /// [totalPixels] LEDs.
  List<LedColorGroup> _consolidateGroups(List<LedColorGroup> groups, int totalPixels) {
    if (groups.isEmpty) return groups;

    // Create a pixel-by-pixel color map
    final pixelColors = List<List<int>?>.filled(totalPixels, null);

    for (final group in groups) {
      for (int i = math.max(group.startLed, 0);
          i <= group.endLed && i < totalPixels;
          i++) {
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

  /// Generate the WLED JSON payload: one `seg` entry per channel the pattern
  /// paints, each addressed by its own segment id (= bus index) in its own
  /// channel-local index space.
  Map<String, dynamic> _generateWledPayload({
    required Map<int, List<LedColorGroup>> channelGroups,
    required MotionSettings? motion,
    required GlobalSettings globalSettings,
  }) {
    if (channelGroups.isEmpty) {
      return {'on': false};
    }

    final effectId = motion?.effectId ?? 0;
    final hasEffect = effectId > 0;

    if (hasEffect) {
      // For effects, use segment-based color setup
      return _generateEffectPayload(
        channelGroups: channelGroups,
        motion: motion!,
        globalSettings: globalSettings,
      );
    } else {
      // For static patterns, use individual LED addressing
      return _generateStaticPayload(
        channelGroups: channelGroups,
        globalSettings: globalSettings,
      );
    }
  }

  /// Generate payload for effects/motion.
  Map<String, dynamic> _generateEffectPayload({
    required Map<int, List<LedColorGroup>> channelGroups,
    required MotionSettings motion,
    required GlobalSettings globalSettings,
  }) {
    // Extract up to 3 colors for the effect, channels in id order.
    final channels = channelGroups.keys.toList()..sort();
    final colors = <List<int>>[];
    for (final channel in channels) {
      for (final group in channelGroups[channel]!) {
        final color = group.color.take(3).toList();
        if (!colors.any((c) => _colorsEqual(c, color))) {
          colors.add(color);
          if (colors.length >= 3) break;
        }
      }
      if (colors.length >= 3) break;
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
        for (final channel in channels)
          {
            // #88 — grp/spc asserted at their DESIGN defaults. A composed
            // pattern states its whole look; leaving spacing unstated let the
            // previous look's `spc` survive underneath it.
            ...kDesignSpacingDefaults,
            'id': channel,
            // #76 — start/stop removed: bounds are geometry (see below).

            'col': colors,
            'fx': motion.effectId ?? 0,
            'sx': motion.speed,
            'ix': motion.intensity,
            // #76 — `rev` removed. WLED spells direction as `rev`, which is a
            // geometry field owned by provisioning; a motion's "reverse" cannot
            // be expressed without clobbering the channel's installed
            // orientation. LOSES: motion.reverse no longer reaches the device.
          },
      ],
    };
  }

  /// Generate payload for static patterns.
  ///
  /// Emits the CANONICAL nested `i` form ([start, stop, [r,g,b,w]] range
  /// entries — stop exclusive), one entry per color group, per channel, with
  /// every color routed through [rgbToRgbw] so the RGBW W-channel is set (not
  /// dropped) and values are clamped. `fx: 0` (Solid) is required so the
  /// static paint persists — a running effect would repaint over the `i`
  /// colors (memory/project_blocks_boundary_blend_fix). The old flat
  /// `[idx, r, g, b, …]` form was RGB-only AND misread by WLED (it treated the
  /// r,g,b bytes as further indices) — Design Studio Slice 0.
  ///
  /// Roofline slice 3: one `seg` per channel, each `i` array channel-local.
  /// This used to be ONE seg 0 carrying a whole-controller array, which on a
  /// multi-bus install landed within seg 0's range and truncated everything
  /// past it (the D-2 defect on the wire).
  Map<String, dynamic> _generateStaticPayload({
    required Map<int, List<LedColorGroup>> channelGroups,
    required GlobalSettings globalSettings,
  }) {
    final channels = channelGroups.keys.toList()..sort();
    final segments = <Map<String, dynamic>>[];

    for (final channel in channels) {
      final ledArray = <dynamic>[];
      for (final group in channelGroups[channel]!) {
        if (group.endLed < group.startLed) continue;
        final c = group.color;
        final rgbw = c.length >= 4
            ? rgbToRgbw(c[0], c[1], c[2], explicitWhite: c[3])
            : rgbToRgbw(c[0], c[1], c[2], forceZeroWhite: true);
        if (group.startLed == group.endLed) {
          ledArray.add(group.startLed);
          ledArray.add(rgbw);
        } else {
          ledArray.add(group.startLed);
          ledArray.add(group.endLed + 1); // WLED range stop is EXCLUSIVE
          ledArray.add(rgbw);
        }
      }
      segments.add({
        // #88 — grp/spc asserted at their DESIGN defaults. Load-bearing on
        // THIS payload in particular: a per-pixel `i` array painted over a
        // segment still carrying `spc=2` renders every third pixel, so the
        // design would land correct and read wrong.
        ...kDesignSpacingDefaults,
        'id': channel,
        // #76 — bounds are never written: the array lands within the
        // channel's provisioned range. Painting across channels is what the
        // per-channel entries are for (docs/SYNC_GEOMETRY_LAYER.md).
        'fx': 0,
        'i': ledArray,
      });
    }

    return {
      'on': true,
      'bri': globalSettings.brightness,
      'transition': globalSettings.smoothTransition
          ? globalSettings.transitionDuration ~/ 100
          : 0,
      'seg': segments,
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

/// Internal helper: a CHANNEL-LOCAL LED range on one hardware channel.
class _PixelRange {
  final int channel;
  final int start;
  final int end;

  _PixelRange(this.channel, this.start, this.end);

  int get length => end - start + 1;
}

/// Extension for string capitalization.
extension _StringCapitalization on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
