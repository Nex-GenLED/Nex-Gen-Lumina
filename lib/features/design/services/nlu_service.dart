import 'package:flutter/material.dart';
import 'package:nexgen_command/features/design/models/design_intent.dart';
import 'package:nexgen_command/features/design/models/clarification_models.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';

/// Natural Language Understanding service for the Design Studio.
///
/// Parses complex, multi-clause natural language instructions into
/// structured [DesignIntent] objects that can be validated and composed.
class NLUService {
  /// Parse a user prompt into a structured design intent.
  ///
  /// This method handles complex instructions like:
  /// - "Dark green base with red accents on corners, light green wave right to left"
  /// - "Corners and peaks bright white, equally spaced soft white between"
  Future<DesignIntent> parseUserIntent(
    String prompt,
    RooflineConfiguration? config,
  ) async {
    final normalizedPrompt = _normalizePrompt(prompt);
    final clauses = _splitIntoClauses(normalizedPrompt);

    final layers = <DesignLayer>[];
    final ambiguities = <AmbiguityFlag>[];

    for (int i = 0; i < clauses.length; i++) {
      final clause = clauses[i];
      final layerResult = _parseClause(clause, i, config);

      if (layerResult.layer != null) {
        layers.add(layerResult.layer!);
      }
      ambiguities.addAll(layerResult.ambiguities);
    }

    // Detect cross-layer ambiguities
    ambiguities.addAll(_detectCrossLayerAmbiguities(layers));

    // Calculate confidence based on ambiguities and parsing quality
    final confidence = _calculateConfidence(layers, ambiguities);

    return DesignIntent(
      originalPrompt: prompt,
      layers: layers,
      ambiguities: ambiguities,
      confidence: confidence,
      parsedAt: DateTime.now(),
    );
  }

  /// Normalize a prompt for parsing (lowercase, trim, standardize).
  String _normalizePrompt(String prompt) {
    return prompt
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('colour', 'color')
        .replaceAll("'", '')
        .replaceAll('"', '');
  }

  /// Split a prompt into separate clauses for layer parsing.
  List<String> _splitIntoClauses(String prompt) {
    // Split on common clause separators
    final separators = [
      ', and ',
      ' and ',
      ', with ',
      ' with ',
      ', but ',
      ' but ',
      '. ',
      '; ',
    ];

    List<String> clauses = [prompt];

    for (final sep in separators) {
      final newClauses = <String>[];
      for (final clause in clauses) {
        newClauses.addAll(clause.split(sep).where((c) => c.trim().isNotEmpty));
      }
      clauses = newClauses;
    }

    return clauses.map((c) => c.trim()).where((c) => c.isNotEmpty).toList();
  }

  /// Parse a single clause into a design layer.
  _ClauseParseResult _parseClause(
    String clause,
    int index,
    RooflineConfiguration? config,
  ) {
    final ambiguities = <AmbiguityFlag>[];

    // Extract zone selector
    final zoneResult = _parseZoneSelector(clause, config);
    ambiguities.addAll(zoneResult.ambiguities);

    // Extract colors
    final colorResult = _parseColors(clause);
    ambiguities.addAll(colorResult.ambiguities);

    // Extract spacing rule
    final spacingRule = _parseSpacingRule(clause);

    // Extract motion settings
    final motionResult = _parseMotion(clause);
    ambiguities.addAll(motionResult.ambiguities);

    // Extract pattern type
    final patternType = _parsePatternType(clause);

    // Build the layer with combined color assignment
    final colorsWithSpacing = ColorAssignment(
      primaryColor: colorResult.colors.primaryColor,
      secondaryColor: colorResult.colors.secondaryColor,
      accentColor: colorResult.colors.accentColor,
      fillColor: colorResult.colors.fillColor,
      spacingRule: spacingRule ?? colorResult.colors.spacingRule,
    );

    final layer = DesignLayer(
      id: 'layer_$index',
      name: _generateLayerName(zoneResult.selector, colorResult.colors),
      targetZone: zoneResult.selector,
      colors: colorsWithSpacing,
      pattern: PatternRule(type: patternType),
      motion: motionResult.motion,
      priority: index,
    );

    return _ClauseParseResult(layer: layer, ambiguities: ambiguities);
  }

  /// Parse zone selector from a clause.
  _ZoneParseResult _parseZoneSelector(String clause, RooflineConfiguration? config) {
    final ambiguities = <AmbiguityFlag>[];

    // Check for architectural role references
    final roles = <ArchitecturalRole>[];

    for (final entry in _architecturalSynonyms.entries) {
      for (final synonym in entry.value) {
        if (clause.contains(synonym)) {
          roles.add(entry.key);
          break;
        }
      }
    }

    if (roles.isNotEmpty) {
      // Check if we need clarification on which specific segments
      if (config != null && roles.length == 1) {
        final matchingSegments = config.segments.where((s) {
          final segType = s.type.toString().split('.').last;
          return roles.any((r) => r.name == segType ||
              (r == ArchitecturalRole.peak && segType == 'peak') ||
              (r == ArchitecturalRole.corner && segType == 'corner') ||
              (r == ArchitecturalRole.run && segType == 'run'));
        }).toList();

        if (matchingSegments.length > 4) {
          // Many matches - might want to clarify
          ambiguities.add(AmbiguityFlag(
            type: AmbiguityType.zoneAmbiguity,
            description: 'Multiple ${roles.first.displayName} found',
            choices: [
              ClarificationChoice(
                id: 'all',
                label: 'All ${roles.first.displayName}',
                isRecommended: true,
              ),
              ClarificationChoice(
                id: 'front_only',
                label: 'Front ${roles.first.displayName} only',
              ),
              ClarificationChoice(
                id: 'select',
                label: 'Let me select',
              ),
            ],
            sourceClause: clause,
          ));
        }
      }

      return _ZoneParseResult(
        selector: ZoneSelector.architectural(roles),
        ambiguities: ambiguities,
      );
    }

    // Check for location references
    for (final entry in _locationSynonyms.entries) {
      for (final synonym in entry.value) {
        if (clause.contains(synonym)) {
          return _ZoneParseResult(
            selector: ZoneSelector.location(entry.key),
            ambiguities: ambiguities,
          );
        }
      }
    }

    // Check for level references
    for (final entry in _levelSynonyms.entries) {
      for (final synonym in entry.value) {
        if (clause.contains(synonym)) {
          return _ZoneParseResult(
            selector: ZoneSelector.level(entry.key),
            ambiguities: ambiguities,
          );
        }
      }
    }

    // Default to all
    return _ZoneParseResult(
      selector: const ZoneSelector.all(),
      ambiguities: ambiguities,
    );
  }

  /// Parse colors from a clause.
  _ColorParseResult _parseColors(String clause) {
    final ambiguities = <AmbiguityFlag>[];
    final foundColors = <String, Color>{};

    // Check for specific color names
    for (final entry in _colorMap.entries) {
      for (final name in entry.value.names) {
        if (clause.contains(name)) {
          foundColors[entry.key] = entry.value.color;
          break;
        }
      }
    }

    // Check for vague color references that need clarification
    for (final entry in _vagueColors.entries) {
      if (clause.contains(entry.key) && !foundColors.containsKey(entry.key)) {
        ambiguities.add(AmbiguityFlag(
          type: AmbiguityType.colorAmbiguity,
          description: 'Which shade of ${entry.key}?',
          choices: entry.value.map((option) => ClarificationChoice(
            id: option.name,
            label: option.displayName,
            value: option.color.value,
          )).toList(),
          sourceClause: clause,
        ));

        // Use the first option as default
        if (entry.value.isNotEmpty) {
          foundColors[entry.key] = entry.value.first.color;
        }
      }
    }

    // Determine which color is primary, secondary, accent
    Color primaryColor = Colors.white;
    Color? secondaryColor;
    Color? accentColor;

    final colorList = foundColors.values.toList();
    if (colorList.isNotEmpty) {
      primaryColor = colorList.first;
      if (colorList.length > 1) {
        // Check if second color is for accents
        if (clause.contains('accent') || clause.contains('highlight')) {
          accentColor = colorList[1];
        } else {
          secondaryColor = colorList[1];
        }
      }
      if (colorList.length > 2) {
        accentColor ??= colorList[2];
      }
    }

    return _ColorParseResult(
      colors: ColorAssignment(
        primaryColor: primaryColor,
        secondaryColor: secondaryColor,
        accentColor: accentColor,
      ),
      ambiguities: ambiguities,
    );
  }

  /// Parse spacing rule from a clause.
  SpacingRule? _parseSpacingRule(String clause) {
    // Check for spacing patterns
    for (final entry in _spacingSynonyms.entries) {
      for (final synonym in entry.value) {
        if (clause.contains(synonym)) {
          switch (entry.key) {
            case 'everyOther':
              return const SpacingRule.everyOther();
            case 'oneOnTwoOff':
              return const SpacingRule.oneOnTwoOff();
            case 'twoOnOneOff':
              return const SpacingRule.twoOnOneOff();
            case 'equallySpaced':
              // Try to extract count
              final countMatch = RegExp(r'(\d+)\s*(?:equally\s*)?spaced').firstMatch(clause);
              if (countMatch != null) {
                return SpacingRule.equallySpaced(int.parse(countMatch.group(1)!));
              }
              return const SpacingRule.equallySpaced(10); // Default count
            case 'anchorsOnly':
              return const SpacingRule(type: SpacingType.anchorsOnly);
          }
        }
      }
    }

    // Check for "every N" patterns
    final everyNMatch = RegExp(r'every\s*(\d+)').firstMatch(clause);
    if (everyNMatch != null) {
      return SpacingRule.everyNth(int.parse(everyNMatch.group(1)!));
    }

    // Check for "N on M off" patterns
    final onOffMatch = RegExp(r'(\d+)\s*on\s*(\d+)\s*off').firstMatch(clause);
    if (onOffMatch != null) {
      return SpacingRule(
        type: SpacingType.pattern,
        onCount: int.parse(onOffMatch.group(1)!),
        offCount: int.parse(onOffMatch.group(2)!),
      );
    }

    return null;
  }

  /// Parse motion settings from a clause.
  _MotionParseResult _parseMotion(String clause) {
    final ambiguities = <AmbiguityFlag>[];

    // Check for motion type
    MotionType? motionType;
    for (final entry in _motionTypeSynonyms.entries) {
      for (final synonym in entry.value) {
        if (clause.contains(synonym)) {
          motionType = entry.key;
          break;
        }
      }
      if (motionType != null) break;
    }

    if (motionType == null) {
      return _MotionParseResult(motion: null, ambiguities: []);
    }

    // Check for direction
    MotionDirection? direction;
    for (final entry in _directionSynonyms.entries) {
      for (final synonym in entry.value) {
        if (clause.contains(synonym)) {
          direction = entry.key;
          break;
        }
      }
      if (direction != null) break;
    }

    // If we have motion but no direction, add ambiguity
    if (direction == null) {
      ambiguities.add(AmbiguityFlag(
        type: AmbiguityType.directionAmbiguity,
        description: 'Which direction should the ${motionType.name} go?',
        choices: [
          const ClarificationChoice(
            id: 'left_to_right',
            label: 'Left to right',
            value: MotionDirection.leftToRight,
            isRecommended: true,
          ),
          const ClarificationChoice(
            id: 'right_to_left',
            label: 'Right to left',
            value: MotionDirection.rightToLeft,
          ),
        ],
        sourceClause: clause,
      ));
      direction = MotionDirection.leftToRight; // Default
    }

    // Parse speed
    int speed = 128;
    if (clause.contains('fast') || clause.contains('quick')) {
      speed = 200;
    } else if (clause.contains('slow')) {
      speed = 80;
    } else if (clause.contains('very fast')) {
      speed = 240;
    } else if (clause.contains('very slow')) {
      speed = 40;
    }

    return _MotionParseResult(
      motion: MotionSettings(
        motionType: motionType,
        direction: direction,
        speed: speed,
        reverse: direction == MotionDirection.rightToLeft,
      ),
      ambiguities: ambiguities,
    );
  }

  /// Parse pattern type from a clause.
  PatternType _parsePatternType(String clause) {
    if (clause.contains('gradient') || clause.contains('fade')) {
      return PatternType.gradient;
    }
    if (clause.contains('alternating') || clause.contains('alternate')) {
      return PatternType.alternating;
    }
    if (clause.contains('twinkle') || clause.contains('sparkle')) {
      return PatternType.twinkle;
    }
    if (clause.contains('wave')) {
      return PatternType.wave;
    }
    return PatternType.solid;
  }

  /// Detect ambiguities that span multiple layers.
  List<AmbiguityFlag> _detectCrossLayerAmbiguities(List<DesignLayer> layers) {
    final ambiguities = <AmbiguityFlag>[];

    // Check for overlapping zones with different settings
    for (int i = 0; i < layers.length; i++) {
      for (int j = i + 1; j < layers.length; j++) {
        if (_zonesOverlap(layers[i].targetZone, layers[j].targetZone)) {
          // Check if they have conflicting settings
          if (layers[i].colors.primaryColor != layers[j].colors.primaryColor) {
            ambiguities.add(AmbiguityFlag(
              type: AmbiguityType.conflictResolution,
              description: 'Two instructions target overlapping areas with different colors',
              choices: [
                ClarificationChoice(
                  id: 'layer_${i}_wins',
                  label: 'Use ${_colorName(layers[i].colors.primaryColor)}',
                  value: i,
                ),
                ClarificationChoice(
                  id: 'layer_${j}_wins',
                  label: 'Use ${_colorName(layers[j].colors.primaryColor)}',
                  value: j,
                  isRecommended: true, // Later instruction typically wins
                ),
                const ClarificationChoice(
                  id: 'blend',
                  label: 'Blend both colors',
                ),
              ],
            ));
          }
        }
      }
    }

    return ambiguities;
  }

  /// Check if two zone selectors overlap.
  bool _zonesOverlap(ZoneSelector a, ZoneSelector b) {
    if (a.type == ZoneSelectorType.all || b.type == ZoneSelectorType.all) {
      return true;
    }
    if (a.type == b.type) {
      if (a.type == ZoneSelectorType.architectural) {
        return a.roles?.any((r) => b.roles?.contains(r) ?? false) ?? false;
      }
      if (a.type == ZoneSelectorType.location) {
        return a.location == b.location;
      }
      if (a.type == ZoneSelectorType.level) {
        return a.level == b.level;
      }
    }
    return false;
  }

  /// Calculate confidence score for the parsing.
  double _calculateConfidence(List<DesignLayer> layers, List<AmbiguityFlag> ambiguities) {
    if (layers.isEmpty) return 0.0;

    double confidence = 1.0;

    // Reduce confidence for each ambiguity
    confidence -= ambiguities.length * 0.15;

    // Reduce confidence for default fallbacks
    for (final layer in layers) {
      if (layer.targetZone.type == ZoneSelectorType.all) {
        confidence -= 0.05; // Might be default
      }
      if (layer.colors.primaryColor == Colors.white) {
        confidence -= 0.1; // Likely default
      }
    }

    return confidence.clamp(0.0, 1.0);
  }

  /// Generate a friendly layer name.
  String _generateLayerName(ZoneSelector zone, ColorAssignment colors) {
    final colorName = _colorName(colors.primaryColor);
    final zoneName = zone.description;
    return '$colorName on $zoneName';
  }

  /// Get a friendly name for a color.
  String _colorName(Color color) {
    // Check against known colors
    for (final entry in _colorMap.entries) {
      if (_colorsClose(color, entry.value.color)) {
        return entry.key;
      }
    }
    return 'custom color';
  }

  /// Check if two colors are close enough to be considered the same.
  bool _colorsClose(Color a, Color b, {int threshold = 30}) {
    return (a.red - b.red).abs() < threshold &&
        (a.green - b.green).abs() < threshold &&
        (a.blue - b.blue).abs() < threshold;
  }
}

// Helper classes for parsing results
class _ClauseParseResult {
  final DesignLayer? layer;
  final List<AmbiguityFlag> ambiguities;

  _ClauseParseResult({this.layer, this.ambiguities = const []});
}

class _ZoneParseResult {
  final ZoneSelector selector;
  final List<AmbiguityFlag> ambiguities;

  _ZoneParseResult({required this.selector, this.ambiguities = const []});
}

class _ColorParseResult {
  final ColorAssignment colors;
  final List<AmbiguityFlag> ambiguities;

  _ColorParseResult({required this.colors, this.ambiguities = const []});
}

class _MotionParseResult {
  final MotionSettings? motion;
  final List<AmbiguityFlag> ambiguities;

  _MotionParseResult({this.motion, this.ambiguities = const []});
}

// Terminology maps for flexible parsing

/// Synonyms for architectural roles.
const _architecturalSynonyms = <ArchitecturalRole, List<String>>{
  ArchitecturalRole.peak: [
    'peak', 'peaks', 'apex', 'apexes', 'tip', 'tips', 'point', 'points',
    'gable', 'gables', 'top', 'tops', 'highest'
  ],
  ArchitecturalRole.corner: [
    'corner', 'corners', 'angle', 'angles', 'turn', 'turns', 'bend', 'bends',
    'corner point', 'corner points'
  ],
  ArchitecturalRole.run: [
    'run', 'runs', 'horizontal', 'flat', 'straight', 'eave', 'eaves',
    'roofline', 'roof line', 'along the roof'
  ],
  ArchitecturalRole.column: [
    'column', 'columns', 'pillar', 'pillars', 'post', 'posts', 'vertical',
    'verticals'
  ],
  ArchitecturalRole.eave: [
    'eave', 'eaves', 'overhang', 'overhangs', 'edge', 'edges'
  ],
  ArchitecturalRole.fascia: [
    'fascia', 'fascias', 'trim', 'board', 'boards'
  ],
  ArchitecturalRole.soffit: [
    'soffit', 'soffits', 'underside', 'underneath'
  ],
};

/// Synonyms for locations.
const _locationSynonyms = <String, List<String>>{
  'front': [
    'front', 'facing', 'street side', 'curb side', 'main', 'facade',
    'front of house', 'front of the house', 'face'
  ],
  'back': [
    'back', 'rear', 'backyard', 'back of house', 'back of the house',
    'behind', 'back side'
  ],
  'left': [
    'left', 'left side', 'left of house', 'on the left'
  ],
  'right': [
    'right', 'right side', 'right of house', 'on the right'
  ],
};

/// Synonyms for levels/stories.
const _levelSynonyms = <int, List<String>>{
  1: [
    'first floor', 'ground floor', 'ground level', 'lower', 'bottom',
    'main level', '1st floor', 'first story', 'lower level'
  ],
  2: [
    'second floor', 'upper', 'top', 'second story', '2nd floor',
    'upstairs', 'upper level', 'second level'
  ],
  3: [
    'third floor', 'third story', '3rd floor', 'third level'
  ],
};

/// Synonyms for spacing patterns.
const _spacingSynonyms = <String, List<String>>{
  'everyOther': [
    'every other', 'alternating', 'alternate', 'skip one', 'every second',
    'one on one off', '1 on 1 off'
  ],
  'oneOnTwoOff': [
    'one on two off', '1 on 2 off', 'spaced out', 'sparse'
  ],
  'twoOnOneOff': [
    'two on one off', '2 on 1 off', 'dense'
  ],
  'equallySpaced': [
    'equally spaced', 'evenly spaced', 'uniform spacing', 'evenly',
    'uniformly', 'distributed', 'spread out', 'equally distributed'
  ],
  'anchorsOnly': [
    'anchors only', 'just anchors', 'only anchors', 'anchor points only',
    'only at corners', 'only at peaks', 'just at corners', 'just at peaks'
  ],
};

/// Synonyms for motion types.
const _motionTypeSynonyms = <MotionType, List<String>>{
  MotionType.chase: [
    'chase', 'chasing', 'running', 'run', 'flowing', 'flow', 'moving',
    'move', 'traveling', 'travel', 'march', 'marching'
  ],
  MotionType.wave: [
    'wave', 'waving', 'ripple', 'rippling', 'undulating', 'rolling',
    'pulse', 'pulsing', 'breathing'
  ],
  MotionType.twinkle: [
    'twinkle', 'twinkling', 'sparkle', 'sparkling', 'glitter', 'glittering',
    'shimmer', 'shimmering', 'flicker', 'flickering'
  ],
  MotionType.pulse: [
    'pulse', 'pulsing', 'breathe', 'breathing', 'throb', 'throbbing'
  ],
  MotionType.scan: [
    'scan', 'scanning', 'sweep', 'sweeping', 'back and forth'
  ],
};

/// Synonyms for motion directions.
const _directionSynonyms = <MotionDirection, List<String>>{
  MotionDirection.leftToRight: [
    'left to right', 'l to r', 'rightward', 'to the right', '→', '->',
    'from left', 'toward right'
  ],
  MotionDirection.rightToLeft: [
    'right to left', 'r to l', 'leftward', 'to the left', '←', '<-',
    'from right', 'toward left'
  ],
  MotionDirection.inward: [
    'inward', 'in', 'toward center', 'to center', 'center', 'converging',
    'from edges', 'from ends'
  ],
  MotionDirection.outward: [
    'outward', 'out', 'from center', 'expanding', 'diverging',
    'toward edges', 'toward ends'
  ],
  MotionDirection.upward: [
    'upward', 'up', 'ascending', 'rising', 'toward top'
  ],
  MotionDirection.downward: [
    'downward', 'down', 'descending', 'falling', 'toward bottom'
  ],
};

/// Map of specific color names to colors.
final _colorMap = <String, _ColorEntry>{
  // Whites
  'white': _ColorEntry(const Color(0xFFFFFFFF), ['white', 'pure white']),
  'warm white': _ColorEntry(const Color(0xFFFFE4C4), ['warm white', 'soft white', 'cozy white']),
  'cool white': _ColorEntry(const Color(0xFFF0F8FF), ['cool white', 'bright white', 'daylight']),
  'soft white': _ColorEntry(const Color(0xFFFFF5E1), ['soft white', 'gentle white']),

  // Reds
  'red': _ColorEntry(const Color(0xFFFF0000), ['red', 'bright red']),
  'dark red': _ColorEntry(const Color(0xFF8B0000), ['dark red', 'deep red', 'maroon']),
  'crimson': _ColorEntry(const Color(0xFFDC143C), ['crimson']),

  // Greens
  'green': _ColorEntry(const Color(0xFF00FF00), ['green', 'bright green']),
  'dark green': _ColorEntry(const Color(0xFF006400), ['dark green', 'forest green', 'deep green']),
  'light green': _ColorEntry(const Color(0xFF90EE90), ['light green', 'lime', 'pale green']),
  'emerald': _ColorEntry(const Color(0xFF50C878), ['emerald', 'emerald green']),

  // Blues
  'blue': _ColorEntry(const Color(0xFF0000FF), ['blue', 'bright blue']),
  'dark blue': _ColorEntry(const Color(0xFF00008B), ['dark blue', 'navy', 'navy blue', 'deep blue']),
  'light blue': _ColorEntry(const Color(0xFFADD8E6), ['light blue', 'sky blue', 'pale blue']),
  'cyan': _ColorEntry(const Color(0xFF00FFFF), ['cyan', 'aqua', 'turquoise']),

  // Yellows
  'yellow': _ColorEntry(const Color(0xFFFFFF00), ['yellow', 'bright yellow']),
  'gold': _ColorEntry(const Color(0xFFFFD700), ['gold', 'golden']),
  'amber': _ColorEntry(const Color(0xFFFFBF00), ['amber', 'honey']),

  // Oranges
  'orange': _ColorEntry(const Color(0xFFFFA500), ['orange', 'bright orange']),
  'dark orange': _ColorEntry(const Color(0xFFFF8C00), ['dark orange', 'deep orange']),

  // Purples
  'purple': _ColorEntry(const Color(0xFF800080), ['purple', 'violet']),
  'magenta': _ColorEntry(const Color(0xFFFF00FF), ['magenta', 'fuchsia', 'pink']),
  'lavender': _ColorEntry(const Color(0xFFE6E6FA), ['lavender', 'light purple']),

  // Others
  'pink': _ColorEntry(const Color(0xFFFFC0CB), ['pink', 'rose']),
  'black': _ColorEntry(const Color(0xFF000000), ['black', 'off']),
};

/// Vague color references that need clarification.
final _vagueColors = <String, List<_ColorOption>>{
  'green': [
    _ColorOption('forest', 'Forest Green', const Color(0xFF228B22)),
    _ColorOption('lime', 'Lime Green', const Color(0xFF32CD32)),
    _ColorOption('emerald', 'Emerald', const Color(0xFF50C878)),
    _ColorOption('mint', 'Mint', const Color(0xFF98FF98)),
  ],
  'blue': [
    _ColorOption('royal', 'Royal Blue', const Color(0xFF4169E1)),
    _ColorOption('sky', 'Sky Blue', const Color(0xFF87CEEB)),
    _ColorOption('navy', 'Navy Blue', const Color(0xFF000080)),
    _ColorOption('cyan', 'Cyan/Aqua', const Color(0xFF00FFFF)),
  ],
  'red': [
    _ColorOption('bright', 'Bright Red', const Color(0xFFFF0000)),
    _ColorOption('crimson', 'Crimson', const Color(0xFFDC143C)),
    _ColorOption('dark', 'Dark Red', const Color(0xFF8B0000)),
  ],
  'purple': [
    _ColorOption('violet', 'Violet', const Color(0xFFEE82EE)),
    _ColorOption('deep', 'Deep Purple', const Color(0xFF673AB7)),
    _ColorOption('lavender', 'Lavender', const Color(0xFFE6E6FA)),
  ],
};

class _ColorEntry {
  final Color color;
  final List<String> names;

  const _ColorEntry(this.color, this.names);
}

class _ColorOption {
  final String name;
  final String displayName;
  final Color color;

  const _ColorOption(this.name, this.displayName, this.color);
}
