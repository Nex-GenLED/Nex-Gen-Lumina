import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:nexgen_command/features/design/models/design_intent.dart';
import 'package:nexgen_command/features/design/models/clarification_models.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';

/// Service for validating design constraints and suggesting alternatives.
///
/// Handles:
/// - Spacing math validation (can X LEDs fit evenly in Y pixels?)
/// - Symmetry requirements
/// - Zone overlap resolution
/// - Color contrast validation
class ConstraintSolver {
  /// Validate all constraints in a design intent.
  ConstraintValidationResult validate({
    required DesignIntent intent,
    required RooflineConfiguration config,
  }) {
    final constraints = <DesignConstraint>[];
    final newAmbiguities = <AmbiguityFlag>[];

    for (final layer in intent.layers) {
      // Validate spacing if specified
      if (layer.colors.spacingRule != null) {
        final spacingResult = _validateLayerSpacing(
          layer: layer,
          config: config,
        );
        constraints.add(spacingResult.constraint);
        if (spacingResult.ambiguity != null) {
          newAmbiguities.add(spacingResult.ambiguity!);
        }
      }

      // Validate zone exists in config
      final zoneResult = _validateZoneExists(
        zone: layer.targetZone,
        config: config,
      );
      if (zoneResult != null) {
        constraints.add(zoneResult);
      }
    }

    // Validate color contrast between layers
    final contrastResult = _validateColorContrast(intent.layers);
    constraints.addAll(contrastResult);

    return ConstraintValidationResult(
      constraints: constraints,
      additionalAmbiguities: newAmbiguities,
      allSatisfied: constraints.every((c) => c.isSatisfied),
    );
  }

  /// Validate spacing for a single layer.
  _SpacingValidationResult _validateLayerSpacing({
    required DesignLayer layer,
    required RooflineConfiguration config,
  }) {
    final rule = layer.colors.spacingRule!;
    final pixelCount = _getPixelCountForZone(layer.targetZone, config);

    switch (rule.type) {
      case SpacingType.pattern:
        return _validatePatternSpacing(
          pixelCount: pixelCount,
          onCount: rule.onCount,
          offCount: rule.offCount,
          layerId: layer.id,
        );

      case SpacingType.equallySpaced:
        return _validateEqualSpacing(
          pixelCount: pixelCount,
          requestedCount: rule.onCount,
          layerId: layer.id,
        );

      case SpacingType.everyNth:
        return _validateEveryNthSpacing(
          pixelCount: pixelCount,
          interval: rule.interval ?? (rule.onCount + rule.offCount),
          layerId: layer.id,
        );

      case SpacingType.anchorsOnly:
        // Anchors only doesn't have math constraints
        return _SpacingValidationResult(
          constraint: DesignConstraint(
            type: ConstraintType.spacingMath,
            isSatisfied: true,
            layerId: layer.id,
          ),
        );

      case SpacingType.continuous:
        return _SpacingValidationResult(
          constraint: DesignConstraint(
            type: ConstraintType.spacingMath,
            isSatisfied: true,
            layerId: layer.id,
          ),
        );
    }
  }

  /// Validate repeating pattern spacing (N on, M off).
  _SpacingValidationResult _validatePatternSpacing({
    required int pixelCount,
    required int onCount,
    required int offCount,
    required String layerId,
  }) {
    final cycleLength = onCount + offCount;
    final fullCycles = pixelCount ~/ cycleLength;
    final remainder = pixelCount % cycleLength;

    // Pattern is satisfied if it fits reasonably
    // (small remainder is acceptable)
    final isSatisfied = remainder <= onCount;

    if (isSatisfied) {
      return _SpacingValidationResult(
        constraint: DesignConstraint(
          type: ConstraintType.spacingMath,
          isSatisfied: true,
          layerId: layerId,
        ),
      );
    }

    // Generate alternatives
    final alternatives = <AlternativeSuggestion>[];

    // Option 1: Stretch the pattern (slightly larger off count)
    final stretchedOff = (pixelCount / fullCycles - onCount).ceil();
    if (stretchedOff > 0 && stretchedOff != offCount) {
      alternatives.add(AlternativeSuggestion(
        id: 'stretch',
        label: '$onCount on, $stretchedOff off',
        description: 'Slightly larger gaps for even distribution',
        deviationScore: (stretchedOff - offCount).abs() / offCount,
      ));
    }

    // Option 2: Compress the pattern (slightly smaller off count)
    final compressedOff = (pixelCount / (fullCycles + 1) - onCount).floor();
    if (compressedOff > 0 && compressedOff != offCount) {
      alternatives.add(AlternativeSuggestion(
        id: 'compress',
        label: '$onCount on, $compressedOff off',
        description: 'Tighter spacing with more lit LEDs',
        deviationScore: (compressedOff - offCount).abs() / offCount,
      ));
    }

    // Option 3: Keep original and accept uneven ending
    alternatives.add(AlternativeSuggestion(
      id: 'original',
      label: '$onCount on, $offCount off (with remainder)',
      description: '$remainder extra pixels at the end',
      deviationScore: 0.1,
    ));

    return _SpacingValidationResult(
      constraint: DesignConstraint(
        type: ConstraintType.spacingMath,
        isSatisfied: false,
        failureReason:
            '$pixelCount pixels with $onCount on, $offCount off leaves $remainder extra',
        alternatives: alternatives,
        layerId: layerId,
      ),
      ambiguity: AmbiguityFlag(
        type: AmbiguityType.spacingImpossible,
        description:
            'The $onCount on, $offCount off pattern doesn\'t divide evenly into $pixelCount pixels',
        choices: alternatives
            .map((a) => ClarificationChoice(
                  id: a.id,
                  label: a.label,
                  description: a.description,
                ))
            .toList(),
        affectedLayerId: layerId,
      ),
    );
  }

  /// Validate equally spaced distribution.
  _SpacingValidationResult _validateEqualSpacing({
    required int pixelCount,
    required int requestedCount,
    required String layerId,
  }) {
    if (requestedCount <= 0) {
      return _SpacingValidationResult(
        constraint: DesignConstraint(
          type: ConstraintType.spacingMath,
          isSatisfied: false,
          failureReason: 'Requested count must be positive',
          layerId: layerId,
        ),
      );
    }

    if (requestedCount > pixelCount) {
      return _SpacingValidationResult(
        constraint: DesignConstraint(
          type: ConstraintType.spacingMath,
          isSatisfied: false,
          failureReason: 'Requested $requestedCount LEDs but only $pixelCount available',
          layerId: layerId,
          alternatives: [
            AlternativeSuggestion(
              id: 'max',
              label: 'Use all $pixelCount pixels',
              description: 'Every pixel lit',
              deviationScore: 0.5,
            ),
            AlternativeSuggestion(
              id: 'half',
              label: 'Use ${pixelCount ~/ 2} pixels',
              description: 'Half the available pixels',
              deviationScore: 0.3,
            ),
          ],
        ),
      );
    }

    final spacing = pixelCount / (requestedCount - 1);
    final isEven = (spacing - spacing.round()).abs() < 0.01;

    if (isEven || requestedCount == 1) {
      return _SpacingValidationResult(
        constraint: DesignConstraint(
          type: ConstraintType.spacingMath,
          isSatisfied: true,
          layerId: layerId,
        ),
      );
    }

    // Generate alternatives with exact spacing
    final alternatives = _generateEqualSpacingAlternatives(
      pixelCount: pixelCount,
      requestedCount: requestedCount,
    );

    return _SpacingValidationResult(
      constraint: DesignConstraint(
        type: ConstraintType.spacingMath,
        isSatisfied: false,
        failureReason:
            '$requestedCount equally spaced LEDs in $pixelCount pixels gives uneven spacing',
        alternatives: alternatives,
        layerId: layerId,
      ),
      ambiguity: AmbiguityFlag(
        type: AmbiguityType.spacingImpossible,
        description:
            '$requestedCount equally spaced LEDs doesn\'t divide evenly into $pixelCount pixels',
        choices: alternatives
            .map((a) => ClarificationChoice(
                  id: a.id,
                  label: a.label,
                  description: a.description,
                  isRecommended: a.deviationScore < 0.1,
                ))
            .toList(),
        affectedLayerId: layerId,
      ),
    );
  }

  /// Generate alternative counts for equal spacing.
  List<AlternativeSuggestion> _generateEqualSpacingAlternatives({
    required int pixelCount,
    required int requestedCount,
  }) {
    final alternatives = <AlternativeSuggestion>[];

    // Find counts that divide evenly
    for (int count = requestedCount - 3; count <= requestedCount + 3; count++) {
      if (count <= 1 || count > pixelCount) continue;

      final spacing = (pixelCount - 1) / (count - 1);
      final isEven = (spacing - spacing.round()).abs() < 0.01;

      if (isEven || count == 1) {
        final deviation = (count - requestedCount).abs() / requestedCount;
        alternatives.add(AlternativeSuggestion(
          id: 'count_$count',
          label: '$count LEDs (every ${spacing.round()} pixels)',
          description: count > requestedCount
              ? '${count - requestedCount} more than requested'
              : '${requestedCount - count} fewer than requested',
          deviationScore: deviation,
        ));
      }
    }

    // Sort by deviation score
    alternatives.sort((a, b) => a.deviationScore.compareTo(b.deviationScore));

    return alternatives.take(4).toList();
  }

  /// Validate every-Nth spacing.
  _SpacingValidationResult _validateEveryNthSpacing({
    required int pixelCount,
    required int interval,
    required String layerId,
  }) {
    if (interval <= 0) {
      return _SpacingValidationResult(
        constraint: DesignConstraint(
          type: ConstraintType.spacingMath,
          isSatisfied: false,
          failureReason: 'Interval must be positive',
          layerId: layerId,
        ),
      );
    }

    final litCount = (pixelCount / interval).ceil();
    final remainder = pixelCount % interval;

    // Small remainder is acceptable
    if (remainder <= interval ~/ 2) {
      return _SpacingValidationResult(
        constraint: DesignConstraint(
          type: ConstraintType.spacingMath,
          isSatisfied: true,
          layerId: layerId,
        ),
      );
    }

    final alternatives = <AlternativeSuggestion>[];

    // Find nearby intervals that work better
    for (int i = interval - 2; i <= interval + 2; i++) {
      if (i <= 0) continue;
      final newRemainder = pixelCount % i;
      if (newRemainder < remainder && newRemainder <= i ~/ 2) {
        alternatives.add(AlternativeSuggestion(
          id: 'interval_$i',
          label: 'Every $i pixels',
          description: '${(pixelCount / i).ceil()} lit LEDs',
          deviationScore: (i - interval).abs() / interval,
        ));
      }
    }

    if (alternatives.isEmpty) {
      return _SpacingValidationResult(
        constraint: DesignConstraint(
          type: ConstraintType.spacingMath,
          isSatisfied: true, // Accept as-is if no better option
          layerId: layerId,
        ),
      );
    }

    return _SpacingValidationResult(
      constraint: DesignConstraint(
        type: ConstraintType.spacingMath,
        isSatisfied: false,
        failureReason: 'Every $interval pixels has uneven ending',
        alternatives: alternatives,
        layerId: layerId,
      ),
    );
  }

  /// Validate that a zone selector maps to existing segments.
  DesignConstraint? _validateZoneExists({
    required ZoneSelector zone,
    required RooflineConfiguration config,
  }) {
    if (zone.type == ZoneSelectorType.all) {
      return null; // All always exists
    }

    if (zone.type == ZoneSelectorType.segments && zone.segmentIds != null) {
      final missingIds = zone.segmentIds!
          .where((id) => !config.segments.any((s) => s.id == id))
          .toList();

      if (missingIds.isNotEmpty) {
        return DesignConstraint(
          type: ConstraintType.pixelCount,
          isSatisfied: false,
          failureReason: 'Segment(s) not found: ${missingIds.join(", ")}',
        );
      }
    }

    if (zone.type == ZoneSelectorType.level && zone.level != null) {
      final hasLevel = config.segments.any((s) => s.level == zone.level);
      if (!hasLevel) {
        return DesignConstraint(
          type: ConstraintType.pixelCount,
          isSatisfied: false,
          failureReason: 'No segments found on level ${zone.level}',
        );
      }
    }

    return null; // Constraint satisfied
  }

  /// Validate color contrast between layers.
  List<DesignConstraint> _validateColorContrast(List<DesignLayer> layers) {
    final constraints = <DesignConstraint>[];

    for (int i = 0; i < layers.length; i++) {
      for (int j = i + 1; j < layers.length; j++) {
        final colorA = layers[i].colors.primaryColor;
        final colorB = layers[j].colors.primaryColor;

        final contrast = _calculateContrast(colorA, colorB);

        if (contrast < 0.3 && _zonesOverlap(layers[i].targetZone, layers[j].targetZone)) {
          constraints.add(DesignConstraint(
            type: ConstraintType.colorContrast,
            isSatisfied: false,
            failureReason:
                'Colors in layers ${i + 1} and ${j + 1} may be hard to distinguish',
            alternatives: [
              AlternativeSuggestion(
                id: 'keep',
                label: 'Keep both colors',
                description: 'Low contrast may be intentional',
                deviationScore: 0,
              ),
              AlternativeSuggestion(
                id: 'brighten',
                label: 'Increase brightness difference',
                description: 'Make one color brighter',
                deviationScore: 0.2,
              ),
            ],
          ));
        }
      }
    }

    return constraints;
  }

  /// Calculate contrast ratio between two colors.
  double _calculateContrast(Color a, Color b) {
    final lumA = _relativeLuminance(a);
    final lumB = _relativeLuminance(b);
    final lighter = math.max(lumA, lumB);
    final darker = math.min(lumA, lumB);
    return (lighter + 0.05) / (darker + 0.05) / 21.0; // Normalize to 0-1
  }

  /// Calculate relative luminance of a color.
  double _relativeLuminance(Color color) {
    final r = _linearize(color.red / 255);
    final g = _linearize(color.green / 255);
    final b = _linearize(color.blue / 255);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  double _linearize(double value) {
    return value <= 0.03928
        ? value / 12.92
        : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  }

  /// Get the total pixel count for a zone selector.
  int _getPixelCountForZone(ZoneSelector zone, RooflineConfiguration config) {
    switch (zone.type) {
      case ZoneSelectorType.all:
        return config.totalPixelCount;

      case ZoneSelectorType.segments:
        if (zone.segmentIds == null) return config.totalPixelCount;
        return config.segments
            .where((s) => zone.segmentIds!.contains(s.id))
            .fold(0, (sum, s) => sum + s.pixelCount);

      case ZoneSelectorType.architectural:
        // Estimate based on typical architectural element sizes
        // This is a rough estimate - real implementation would check config
        return (config.totalPixelCount * 0.2).round();

      case ZoneSelectorType.location:
        // Estimate half the roofline for front/back
        return (config.totalPixelCount * 0.4).round();

      case ZoneSelectorType.level:
        // Check actual level distribution
        return config.segments
            .where((s) => s.level == zone.level)
            .fold(0, (sum, s) => sum + s.pixelCount);

      case ZoneSelectorType.custom:
        if (zone.pixelRanges == null) return 0;
        return zone.pixelRanges!.fold(0, (sum, r) => sum + r.length);
    }
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

  /// Check if spacing can be achieved exactly.
  SpacingValidation validateSpacing({
    required int pixelCount,
    required int anchorCount,
    required int desiredSpacing,
    required SpacingRule rule,
  }) {
    switch (rule.type) {
      case SpacingType.equallySpaced:
        final effectiveCount = rule.onCount;
        if (effectiveCount <= 1) {
          return SpacingValidation.valid();
        }
        final spacing = (pixelCount - 1) / (effectiveCount - 1);
        final isValid = (spacing - spacing.round()).abs() < 0.01;
        return SpacingValidation(
          isValid: isValid,
          actualSpacing: spacing.round(),
          remainder: isValid ? 0 : ((spacing - spacing.round()) * (effectiveCount - 1)).round().abs(),
        );

      case SpacingType.pattern:
        final cycleLength = rule.onCount + rule.offCount;
        final remainder = pixelCount % cycleLength;
        return SpacingValidation(
          isValid: remainder == 0,
          actualSpacing: cycleLength,
          remainder: remainder,
        );

      case SpacingType.everyNth:
        final interval = rule.interval ?? (rule.onCount + rule.offCount);
        final remainder = pixelCount % interval;
        return SpacingValidation(
          isValid: remainder <= interval ~/ 2,
          actualSpacing: interval,
          remainder: remainder,
        );

      case SpacingType.anchorsOnly:
      case SpacingType.continuous:
        return SpacingValidation.valid();
    }
  }

  /// Suggest spacing alternatives when exact match isn't possible.
  List<SpacingAlternative> suggestSpacingAlternatives({
    required int pixelCount,
    required SpacingRule requestedRule,
  }) {
    final alternatives = <SpacingAlternative>[];

    switch (requestedRule.type) {
      case SpacingType.equallySpaced:
        // Find nearby counts that divide evenly
        final requested = requestedRule.onCount;
        for (int count = math.max(2, requested - 5);
            count <= math.min(pixelCount, requested + 5);
            count++) {
          if (count == requested) continue;
          final spacing = (pixelCount - 1) / (count - 1);
          if ((spacing - spacing.round()).abs() < 0.01) {
            alternatives.add(SpacingAlternative(
              count: count,
              spacing: spacing.round(),
              description: '$count lights, every ${spacing.round()} pixels',
            ));
          }
        }
        break;

      case SpacingType.pattern:
        // Try nearby pattern variations
        for (int off = math.max(1, requestedRule.offCount - 2);
            off <= requestedRule.offCount + 2;
            off++) {
          if (off == requestedRule.offCount) continue;
          final cycleLength = requestedRule.onCount + off;
          if (pixelCount % cycleLength == 0 || pixelCount % cycleLength <= requestedRule.onCount) {
            alternatives.add(SpacingAlternative(
              count: pixelCount ~/ cycleLength * requestedRule.onCount,
              spacing: cycleLength,
              description: '${requestedRule.onCount} on, $off off',
            ));
          }
        }
        break;

      case SpacingType.everyNth:
        // Try nearby intervals
        final requestedInterval = requestedRule.interval ?? (requestedRule.onCount + requestedRule.offCount);
        for (int interval = math.max(2, requestedInterval - 3);
            interval <= requestedInterval + 3;
            interval++) {
          if (interval == requestedInterval) continue;
          final remainder = pixelCount % interval;
          if (remainder <= interval ~/ 2) {
            alternatives.add(SpacingAlternative(
              count: (pixelCount / interval).ceil(),
              spacing: interval,
              description: 'Every $interval pixels',
            ));
          }
        }
        break;

      case SpacingType.anchorsOnly:
      case SpacingType.continuous:
        // No alternatives needed
        break;
    }

    // Sort by how close to original
    alternatives.sort((a, b) =>
        (a.count - requestedRule.onCount).abs().compareTo(
            (b.count - requestedRule.onCount).abs()));

    return alternatives.take(4).toList();
  }
}

/// Result of constraint validation.
class ConstraintValidationResult {
  final List<DesignConstraint> constraints;
  final List<AmbiguityFlag> additionalAmbiguities;
  final bool allSatisfied;

  const ConstraintValidationResult({
    required this.constraints,
    this.additionalAmbiguities = const [],
    required this.allSatisfied,
  });

  /// Constraints that are not satisfied.
  List<DesignConstraint> get unsatisfied =>
      constraints.where((c) => !c.isSatisfied).toList();
}

/// Result of spacing validation.
class SpacingValidation {
  final bool isValid;
  final String? errorMessage;
  final int? actualSpacing;
  final int? remainder;

  const SpacingValidation({
    required this.isValid,
    this.errorMessage,
    this.actualSpacing,
    this.remainder,
  });

  factory SpacingValidation.valid() => const SpacingValidation(isValid: true);
}

/// An alternative spacing suggestion.
class SpacingAlternative {
  final int count;
  final int spacing;
  final String description;

  const SpacingAlternative({
    required this.count,
    required this.spacing,
    required this.description,
  });
}

/// Internal result for spacing validation.
class _SpacingValidationResult {
  final DesignConstraint constraint;
  final AmbiguityFlag? ambiguity;

  _SpacingValidationResult({
    required this.constraint,
    this.ambiguity,
  });
}
