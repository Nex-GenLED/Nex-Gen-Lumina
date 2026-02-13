import 'package:flutter/material.dart';
import 'package:nexgen_command/features/design/models/clarification_models.dart';
import 'package:nexgen_command/features/design/models/design_intent.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart' hide ArchitecturalRole;

/// Service for building clarification dialogs and applying user choices.
///
/// This service transforms technical ambiguity flags from the NLU into
/// user-friendly questions, and then applies the user's choices back to
/// refine the design intent.
class ClarificationService {
  /// Build user-friendly questions from detected ambiguities.
  ///
  /// Transforms raw [AmbiguityFlag] items into [ClarificationQuestion]
  /// objects with appropriate options, descriptions, and preview payloads.
  List<ClarificationQuestion> buildQuestions({
    required List<AmbiguityFlag> ambiguities,
    required DesignIntent intent,
    RooflineConfiguration? config,
  }) {
    final questions = <ClarificationQuestion>[];
    int questionIndex = 0;

    for (final ambiguity in ambiguities) {
      final question = _buildQuestionFromAmbiguity(
        ambiguity: ambiguity,
        intent: intent,
        config: config,
        index: questionIndex++,
      );
      if (question != null) {
        questions.add(question);
      }
    }

    // Sort questions by priority (zone > color > spacing > direction > others)
    questions.sort((a, b) => _questionPriority(a.type).compareTo(_questionPriority(b.type)));

    return questions;
  }

  /// Apply user's clarification choices to refine the design intent.
  ///
  /// Returns a new [DesignIntent] with ambiguities resolved based on
  /// the user's selections.
  DesignIntent applyClarifications({
    required DesignIntent original,
    required Map<String, ClarificationOption> choices,
    required List<ClarificationQuestion> questions,
  }) {
    var updatedLayers = List<DesignLayer>.from(original.layers);
    final resolvedAmbiguities = <AmbiguityFlag>[];

    for (final question in questions) {
      final selectedOption = choices[question.id];
      if (selectedOption == null) continue;

      // Find the original ambiguity
      final ambiguity = original.ambiguities.firstWhere(
        (a) => a.affectedLayerId == question.affectedLayerId &&
               _ambiguityTypeMatchesClarificationType(a.type, question.type),
        orElse: () => original.ambiguities.first,
      );

      // Apply the choice to the affected layer
      if (question.affectedLayerId != null) {
        final layerIndex = updatedLayers.indexWhere((l) => l.id == question.affectedLayerId);
        if (layerIndex >= 0) {
          updatedLayers[layerIndex] = _applyChoiceToLayer(
            layer: updatedLayers[layerIndex],
            question: question,
            selectedOption: selectedOption,
            ambiguity: ambiguity,
          );
        }
      }

      resolvedAmbiguities.add(ambiguity);
    }

    // Remove resolved ambiguities
    final remainingAmbiguities = original.ambiguities
        .where((a) => !resolvedAmbiguities.any((r) =>
            r.affectedLayerId == a.affectedLayerId &&
            r.type == a.type))
        .toList();

    // Bump confidence based on resolved ambiguities
    final newConfidence = (original.confidence + (resolvedAmbiguities.length * 0.1))
        .clamp(0.0, 1.0);

    return original.copyWith(
      layers: updatedLayers,
      ambiguities: remainingAmbiguities,
      confidence: newConfidence,
    );
  }

  /// Generate a simple WLED preview payload for an option.
  ///
  /// This is a quick preview showing what the option would look like,
  /// not the full composed pattern.
  Map<String, dynamic> generatePreviewPayload({
    required ClarificationOption option,
    required DesignIntent intent,
    RooflineConfiguration? config,
    String? layerId,
  }) {
    final totalPixels = config?.totalPixelCount ?? 100;

    // If option already has a preview, use it
    if (option.previewPayload != null) {
      return option.previewPayload!;
    }

    // Generate preview based on option type
    if (option.colorSwatches != null && option.colorSwatches!.isNotEmpty) {
      return _generateColorPreview(option.colorSwatches!, totalPixels);
    }

    // Generate basic on preview
    return {
      'on': true,
      'bri': 200,
      'seg': [
        {
          'id': 0,
          'start': 0,
          'stop': totalPixels,
          'col': [[128, 128, 128]],
          'fx': 0,
        }
      ],
    };
  }

  // Private helper methods

  ClarificationQuestion? _buildQuestionFromAmbiguity({
    required AmbiguityFlag ambiguity,
    required DesignIntent intent,
    RooflineConfiguration? config,
    required int index,
  }) {
    switch (ambiguity.type) {
      case AmbiguityType.zoneAmbiguity:
        return _buildZoneQuestion(ambiguity, config, index);

      case AmbiguityType.colorAmbiguity:
        return _buildColorQuestion(ambiguity, index);

      case AmbiguityType.spacingImpossible:
        return _buildSpacingQuestion(ambiguity, config, index);

      case AmbiguityType.directionAmbiguity:
        return _buildDirectionQuestion(ambiguity, index);

      case AmbiguityType.conflictResolution:
        return _buildConflictQuestion(ambiguity, intent, index);

      case AmbiguityType.effectAmbiguity:
        return _buildEffectQuestion(ambiguity, index);
    }
  }

  ClarificationQuestion _buildZoneQuestion(
    AmbiguityFlag ambiguity,
    RooflineConfiguration? config,
    int index,
  ) {
    // Convert existing choices to options
    final options = ambiguity.choices.map((choice) {
      return ClarificationOption(
        id: choice.id,
        label: choice.label,
        description: choice.description,
        isRecommended: choice.isRecommended,
        icon: _getZoneIcon(choice.label),
        value: choice.value,
      );
    }).toList();

    // Add segment-based options if we have config
    if (config != null && options.length < 4) {
      final segmentOptions = _buildSegmentOptions(config, ambiguity.sourceClause);
      for (final opt in segmentOptions) {
        if (!options.any((o) => o.id == opt.id)) {
          options.add(opt);
        }
        if (options.length >= 4) break;
      }
    }

    // Add "all" option if not present
    if (!options.any((o) => o.id == 'all')) {
      options.add(const ClarificationOption(
        id: 'all',
        label: 'Entire roofline',
        description: 'Apply to all segments',
        icon: Icons.home,
      ));
    }

    return ClarificationQuestion(
      id: 'zone_$index',
      type: ClarificationType.zoneAmbiguity,
      questionText: _buildZoneQuestionText(ambiguity.sourceClause),
      options: options.take(4).toList(),
      sourceText: ambiguity.sourceClause,
      affectedLayerId: ambiguity.affectedLayerId,
      context: ambiguity.description,
    );
  }

  ClarificationQuestion _buildColorQuestion(
    AmbiguityFlag ambiguity,
    int index,
  ) {
    // Extract color name from description
    final colorName = _extractColorName(ambiguity.sourceClause ?? ambiguity.description);

    // Get color variations
    final options = _getColorVariations(colorName).map((colorInfo) {
      return ClarificationOption(
        id: colorInfo['id'] as String,
        label: colorInfo['label'] as String,
        description: colorInfo['description'] as String?,
        isRecommended: colorInfo['recommended'] == true,
        colorSwatches: [colorInfo['color'] as Color],
        value: colorInfo['color'],
      );
    }).toList();

    return ClarificationQuestion(
      id: 'color_$index',
      type: ClarificationType.colorAmbiguity,
      questionText: 'Which shade of $colorName did you have in mind?',
      options: options.take(4).toList(),
      sourceText: ambiguity.sourceClause,
      affectedLayerId: ambiguity.affectedLayerId,
      context: 'There are several variations of $colorName - pick your favorite!',
    );
  }

  ClarificationQuestion _buildSpacingQuestion(
    AmbiguityFlag ambiguity,
    RooflineConfiguration? config,
    int index,
  ) {
    // Convert choices to options with visual previews
    final options = ambiguity.choices.map((choice) {
      return ClarificationOption(
        id: choice.id,
        label: choice.label,
        description: choice.description,
        isRecommended: choice.isRecommended,
        icon: Icons.straighten,
        value: choice.value,
        // Preview payload would show the spacing pattern
        previewPayload: _generateSpacingPreview(
          choice.id,
          config?.totalPixelCount ?? 100,
        ),
      );
    }).toList();

    // Add manual option
    options.add(const ClarificationOption(
      id: 'manual',
      label: 'Set manually',
      description: 'Open spacing controls',
      icon: Icons.tune,
    ));

    return ClarificationQuestion(
      id: 'spacing_$index',
      type: ClarificationType.spacingImpossible,
      questionText: 'The spacing doesn\'t quite work - which option looks best?',
      options: options.take(4).toList(),
      sourceText: ambiguity.sourceClause,
      affectedLayerId: ambiguity.affectedLayerId,
      context: ambiguity.description,
    );
  }

  ClarificationQuestion _buildDirectionQuestion(
    AmbiguityFlag ambiguity,
    int index,
  ) {
    // Extract effect name from context
    final effectName = _extractEffectName(ambiguity.sourceClause ?? 'motion');

    List<ClarificationOption> options;
    if (ambiguity.choices.isNotEmpty) {
      options = ambiguity.choices.map((choice) {
        return ClarificationOption(
          id: choice.id,
          label: choice.label,
          description: choice.description,
          isRecommended: choice.isRecommended,
          icon: _getDirectionIcon(choice.id),
          value: choice.value ?? _parseDirection(choice.id),
        );
      }).toList();
    } else {
      // Default direction options
      options = const [
        ClarificationOption(
          id: 'left_to_right',
          label: 'Left to right →',
          description: 'Moves from left side to right side',
          icon: Icons.arrow_forward,
          isRecommended: true,
          value: MotionDirection.leftToRight,
        ),
        ClarificationOption(
          id: 'right_to_left',
          label: '← Right to left',
          description: 'Moves from right side to left side',
          icon: Icons.arrow_back,
          value: MotionDirection.rightToLeft,
        ),
        ClarificationOption(
          id: 'inward',
          label: '→ ← Inward',
          description: 'From both ends toward center',
          icon: Icons.compress,
          value: MotionDirection.inward,
        ),
        ClarificationOption(
          id: 'outward',
          label: '← → Outward',
          description: 'From center toward both ends',
          icon: Icons.expand,
          value: MotionDirection.outward,
        ),
      ];
    }

    return ClarificationQuestion(
      id: 'direction_$index',
      type: ClarificationType.directionAmbiguity,
      questionText: 'Which direction should the $effectName go?',
      options: options.take(4).toList(),
      sourceText: ambiguity.sourceClause,
      affectedLayerId: ambiguity.affectedLayerId,
    );
  }

  ClarificationQuestion _buildConflictQuestion(
    AmbiguityFlag ambiguity,
    DesignIntent intent,
    int index,
  ) {
    // Convert choices to options
    final options = ambiguity.choices.map((choice) {
      return ClarificationOption(
        id: choice.id,
        label: choice.label,
        description: choice.description,
        isRecommended: choice.isRecommended,
        icon: Icons.layers,
        value: choice.value,
      );
    }).toList();

    // Add merge option if not present
    if (!options.any((o) => o.id == 'merge')) {
      options.add(const ClarificationOption(
        id: 'merge',
        label: 'Blend both',
        description: 'Layer the designs together',
        icon: Icons.blur_linear,
      ));
    }

    return ClarificationQuestion(
      id: 'conflict_$index',
      type: ClarificationType.conflictResolution,
      questionText: 'These settings overlap - which should take priority?',
      options: options.take(4).toList(),
      sourceText: ambiguity.sourceClause,
      affectedLayerId: ambiguity.affectedLayerId,
      context: ambiguity.description,
    );
  }

  ClarificationQuestion _buildEffectQuestion(
    AmbiguityFlag ambiguity,
    int index,
  ) {
    // Convert choices to options
    final options = ambiguity.choices.map((choice) {
      return ClarificationOption(
        id: choice.id,
        label: choice.label,
        description: choice.description,
        isRecommended: choice.isRecommended,
        icon: _getEffectIcon(choice.id),
        value: choice.value,
      );
    }).toList();

    // Add common effect options if we don't have enough
    if (options.length < 2) {
      options.addAll(_getDefaultEffectOptions());
    }

    return ClarificationQuestion(
      id: 'effect_$index',
      type: ClarificationType.effectAmbiguity,
      questionText: 'Which effect did you have in mind?',
      options: options.take(4).toList(),
      sourceText: ambiguity.sourceClause,
      affectedLayerId: ambiguity.affectedLayerId,
      context: ambiguity.description,
    );
  }

  /// Apply a selected option to a design layer.
  DesignLayer _applyChoiceToLayer({
    required DesignLayer layer,
    required ClarificationQuestion question,
    required ClarificationOption selectedOption,
    required AmbiguityFlag ambiguity,
  }) {
    switch (question.type) {
      case ClarificationType.zoneAmbiguity:
        return _applyZoneChoice(layer, selectedOption);

      case ClarificationType.colorAmbiguity:
        return _applyColorChoice(layer, selectedOption);

      case ClarificationType.spacingImpossible:
        return _applySpacingChoice(layer, selectedOption);

      case ClarificationType.directionAmbiguity:
        return _applyDirectionChoice(layer, selectedOption);

      case ClarificationType.conflictResolution:
        return _applyConflictChoice(layer, selectedOption);

      case ClarificationType.effectAmbiguity:
        return _applyEffectChoice(layer, selectedOption);

      case ClarificationType.brightnessAmbiguity:
        return _applyBrightnessChoice(layer, selectedOption);

      case ClarificationType.speedAmbiguity:
        return _applySpeedChoice(layer, selectedOption);

      case ClarificationType.confirmation:
      case ClarificationType.manualFallback:
        return layer; // No change needed
    }
  }

  DesignLayer _applyZoneChoice(DesignLayer layer, ClarificationOption option) {
    if (option.value is ZoneSelector) {
      return layer.copyWith(targetZone: option.value as ZoneSelector);
    }

    // Parse from option id
    ZoneSelector? newZone;
    if (option.id == 'all') {
      newZone = const ZoneSelector.all();
    } else if (option.id.startsWith('segment_')) {
      final segmentId = option.id.replaceFirst('segment_', '');
      newZone = ZoneSelector.segments([segmentId]);
    } else if (option.id == 'peaks' || option.id == 'corners') {
      newZone = ZoneSelector.architectural([
        option.id == 'peaks' ? ArchitecturalRole.peak : ArchitecturalRole.corner,
      ]);
    } else if (option.id == 'peaks_and_corners') {
      newZone = ZoneSelector.architectural([
        ArchitecturalRole.peak,
        ArchitecturalRole.corner,
      ]);
    }

    return newZone != null ? layer.copyWith(targetZone: newZone) : layer;
  }

  DesignLayer _applyColorChoice(DesignLayer layer, ClarificationOption option) {
    if (option.value is Color) {
      return layer.copyWith(
        colors: ColorAssignment(
          primaryColor: option.value as Color,
          secondaryColor: layer.colors.secondaryColor,
          accentColor: layer.colors.accentColor,
          fillColor: layer.colors.fillColor,
          spacingRule: layer.colors.spacingRule,
        ),
      );
    }
    return layer;
  }

  DesignLayer _applySpacingChoice(DesignLayer layer, ClarificationOption option) {
    if (option.id == 'manual') {
      return layer; // Manual handling elsewhere
    }

    SpacingRule? newRule;
    if (option.value is SpacingRule) {
      newRule = option.value as SpacingRule;
    } else if (option.id.startsWith('count_')) {
      final count = int.tryParse(option.id.replaceFirst('count_', ''));
      if (count != null) {
        newRule = SpacingRule.equallySpaced(count);
      }
    } else if (option.id.startsWith('interval_')) {
      final interval = int.tryParse(option.id.replaceFirst('interval_', ''));
      if (interval != null) {
        newRule = SpacingRule.everyNth(interval);
      }
    } else if (option.id == 'stretch' || option.id == 'compress' || option.id == 'original') {
      // Parse from metadata or label
      final match = RegExp(r'(\d+)\s*on,?\s*(\d+)\s*off').firstMatch(option.label);
      if (match != null) {
        final on = int.parse(match.group(1)!);
        final off = int.parse(match.group(2)!);
        newRule = SpacingRule(type: SpacingType.pattern, onCount: on, offCount: off);
      }
    }

    if (newRule != null) {
      return layer.copyWith(
        colors: ColorAssignment(
          primaryColor: layer.colors.primaryColor,
          secondaryColor: layer.colors.secondaryColor,
          accentColor: layer.colors.accentColor,
          fillColor: layer.colors.fillColor,
          spacingRule: newRule,
        ),
      );
    }

    return layer;
  }

  DesignLayer _applyDirectionChoice(DesignLayer layer, ClarificationOption option) {
    MotionDirection? direction;
    if (option.value is MotionDirection) {
      direction = option.value as MotionDirection;
    } else {
      direction = _parseDirection(option.id);
    }

    if (direction == null) return layer;

    final existingMotion = layer.motion;
    if (existingMotion != null) {
      return layer.copyWith(
        motion: MotionSettings(
          motionType: existingMotion.motionType,
          direction: direction,
          speed: existingMotion.speed,
          intensity: existingMotion.intensity,
          reverse: direction == MotionDirection.rightToLeft,
          effectId: existingMotion.effectId,
        ),
      );
    }

    return layer;
  }

  DesignLayer _applyConflictChoice(DesignLayer layer, ClarificationOption option) {
    if (option.id == 'merge') {
      // Mark for merging in composer
      return layer.copyWith(priority: layer.priority + 1);
    }
    // Other conflict resolutions handled by priority adjustments
    return layer;
  }

  DesignLayer _applyEffectChoice(DesignLayer layer, ClarificationOption option) {
    MotionType? motionType;
    int? effectId;

    switch (option.id) {
      case 'chase':
        motionType = MotionType.chase;
        effectId = 28; // WLED Chase effect
        break;
      case 'wave':
        motionType = MotionType.wave;
        effectId = 67; // WLED Colorwaves
        break;
      case 'twinkle':
        motionType = MotionType.twinkle;
        effectId = 80; // WLED Twinkle
        break;
      case 'pulse':
        motionType = MotionType.pulse;
        effectId = 2; // WLED Breathe
        break;
      case 'flow':
        motionType = MotionType.flow;
        effectId = 68; // WLED Flow
        break;
    }

    if (motionType != null) {
      final existingMotion = layer.motion;
      return layer.copyWith(
        motion: MotionSettings(
          motionType: motionType,
          direction: existingMotion?.direction ?? MotionDirection.leftToRight,
          speed: existingMotion?.speed ?? 128,
          intensity: existingMotion?.intensity ?? 128,
          reverse: existingMotion?.reverse ?? false,
          effectId: effectId,
        ),
      );
    }

    return layer;
  }

  DesignLayer _applyBrightnessChoice(DesignLayer layer, ClarificationOption option) {
    // Brightness is handled at global level, not layer level
    return layer;
  }

  DesignLayer _applySpeedChoice(DesignLayer layer, ClarificationOption option) {
    final existingMotion = layer.motion;
    if (existingMotion == null) return layer;

    int speed = existingMotion.speed;
    if (option.value is int) {
      speed = option.value as int;
    } else {
      switch (option.id) {
        case 'slow':
          speed = 64;
          break;
        case 'medium':
          speed = 128;
          break;
        case 'fast':
          speed = 192;
          break;
        case 'very_fast':
          speed = 240;
          break;
      }
    }

    return layer.copyWith(
      motion: MotionSettings(
        motionType: existingMotion.motionType,
        direction: existingMotion.direction,
        speed: speed,
        intensity: existingMotion.intensity,
        reverse: existingMotion.reverse,
        effectId: existingMotion.effectId,
      ),
    );
  }

  // Utility methods

  int _questionPriority(ClarificationType type) {
    switch (type) {
      case ClarificationType.zoneAmbiguity:
        return 0;
      case ClarificationType.colorAmbiguity:
        return 1;
      case ClarificationType.spacingImpossible:
        return 2;
      case ClarificationType.directionAmbiguity:
        return 3;
      case ClarificationType.effectAmbiguity:
        return 4;
      case ClarificationType.conflictResolution:
        return 5;
      case ClarificationType.brightnessAmbiguity:
        return 6;
      case ClarificationType.speedAmbiguity:
        return 7;
      case ClarificationType.confirmation:
        return 8;
      case ClarificationType.manualFallback:
        return 9;
    }
  }

  bool _ambiguityTypeMatchesClarificationType(AmbiguityType ambiguity, ClarificationType clarification) {
    switch (ambiguity) {
      case AmbiguityType.zoneAmbiguity:
        return clarification == ClarificationType.zoneAmbiguity;
      case AmbiguityType.colorAmbiguity:
        return clarification == ClarificationType.colorAmbiguity;
      case AmbiguityType.spacingImpossible:
        return clarification == ClarificationType.spacingImpossible;
      case AmbiguityType.directionAmbiguity:
        return clarification == ClarificationType.directionAmbiguity;
      case AmbiguityType.conflictResolution:
        return clarification == ClarificationType.conflictResolution;
      case AmbiguityType.effectAmbiguity:
        return clarification == ClarificationType.effectAmbiguity;
    }
  }

  String _buildZoneQuestionText(String? sourceClause) {
    if (sourceClause != null && sourceClause.isNotEmpty) {
      return 'You mentioned "$sourceClause" - which areas exactly?';
    }
    return 'Which areas should this apply to?';
  }

  IconData _getZoneIcon(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('peak') || lower.contains('gable')) {
      return Icons.change_history;
    }
    if (lower.contains('corner')) {
      return Icons.turn_right;
    }
    if (lower.contains('run') || lower.contains('eave')) {
      return Icons.horizontal_rule;
    }
    if (lower.contains('front')) {
      return Icons.home;
    }
    if (lower.contains('back')) {
      return Icons.home_outlined;
    }
    if (lower.contains('all') || lower.contains('entire')) {
      return Icons.roofing;
    }
    return Icons.location_on;
  }

  IconData _getDirectionIcon(String id) {
    switch (id) {
      case 'left_to_right':
        return Icons.arrow_forward;
      case 'right_to_left':
        return Icons.arrow_back;
      case 'inward':
        return Icons.compress;
      case 'outward':
        return Icons.expand;
      case 'upward':
        return Icons.arrow_upward;
      case 'downward':
        return Icons.arrow_downward;
      default:
        return Icons.swap_horiz;
    }
  }

  IconData _getEffectIcon(String id) {
    switch (id) {
      case 'chase':
        return Icons.directions_run;
      case 'wave':
        return Icons.waves;
      case 'twinkle':
        return Icons.auto_awesome;
      case 'pulse':
        return Icons.favorite;
      case 'flow':
        return Icons.water;
      case 'scan':
        return Icons.radar;
      default:
        return Icons.animation;
    }
  }

  List<ClarificationOption> _buildSegmentOptions(
    RooflineConfiguration config,
    String? sourceClause,
  ) {
    final options = <ClarificationOption>[];

    // Group segments by type
    final peaks = config.segments.where((s) => s.type == SegmentType.peak).toList();
    final corners = config.segments.where((s) => s.type == SegmentType.corner).toList();
    final runs = config.segments.where((s) => s.type == SegmentType.run).toList();

    if (peaks.isNotEmpty) {
      options.add(ClarificationOption(
        id: 'peaks',
        label: 'Peaks (${peaks.length})',
        description: 'All peak/gable segments',
        icon: Icons.change_history,
        value: ZoneSelector.architectural([ArchitecturalRole.peak]),
      ));
    }

    if (corners.isNotEmpty) {
      options.add(ClarificationOption(
        id: 'corners',
        label: 'Corners (${corners.length})',
        description: 'All corner segments',
        icon: Icons.turn_right,
        value: ZoneSelector.architectural([ArchitecturalRole.corner]),
      ));
    }

    if (peaks.isNotEmpty && corners.isNotEmpty) {
      options.add(ClarificationOption(
        id: 'peaks_and_corners',
        label: 'Peaks & Corners',
        description: 'Both peaks and corners',
        icon: Icons.architecture,
        isRecommended: true,
        value: ZoneSelector.architectural([
          ArchitecturalRole.peak,
          ArchitecturalRole.corner,
        ]),
      ));
    }

    if (runs.isNotEmpty) {
      options.add(ClarificationOption(
        id: 'runs',
        label: 'Runs (${runs.length})',
        description: 'Horizontal run segments',
        icon: Icons.horizontal_rule,
        value: ZoneSelector.architectural([ArchitecturalRole.run]),
      ));
    }

    return options;
  }

  String _extractColorName(String text) {
    final colorWords = [
      'red', 'green', 'blue', 'yellow', 'orange', 'purple', 'pink',
      'white', 'cyan', 'magenta', 'violet', 'teal', 'lime', 'gold',
      'amber', 'indigo', 'coral', 'turquoise', 'brown', 'grey', 'gray'
    ];

    final lower = text.toLowerCase();
    for (final color in colorWords) {
      if (lower.contains(color)) {
        return color;
      }
    }
    return 'color';
  }

  List<Map<String, dynamic>> _getColorVariations(String colorName) {
    final lower = colorName.toLowerCase();

    switch (lower) {
      case 'green':
        return [
          {'id': 'forest', 'label': 'Forest Green', 'color': const Color(0xFF228B22), 'description': 'Deep and rich', 'recommended': true},
          {'id': 'lime', 'label': 'Lime Green', 'color': const Color(0xFF32CD32), 'description': 'Bright and vibrant'},
          {'id': 'emerald', 'label': 'Emerald', 'color': const Color(0xFF50C878), 'description': 'Classic jewel tone'},
          {'id': 'mint', 'label': 'Mint', 'color': const Color(0xFF98FB98), 'description': 'Light and fresh'},
        ];

      case 'blue':
        return [
          {'id': 'royal', 'label': 'Royal Blue', 'color': const Color(0xFF4169E1), 'description': 'Bold and classic', 'recommended': true},
          {'id': 'sky', 'label': 'Sky Blue', 'color': const Color(0xFF87CEEB), 'description': 'Light and airy'},
          {'id': 'navy', 'label': 'Navy', 'color': const Color(0xFF000080), 'description': 'Deep and sophisticated'},
          {'id': 'cyan', 'label': 'Cyan', 'color': const Color(0xFF00FFFF), 'description': 'Bright and electric'},
        ];

      case 'red':
        return [
          {'id': 'crimson', 'label': 'Crimson', 'color': const Color(0xFFDC143C), 'description': 'Deep and warm', 'recommended': true},
          {'id': 'scarlet', 'label': 'Scarlet', 'color': const Color(0xFFFF2400), 'description': 'Bold and bright'},
          {'id': 'cherry', 'label': 'Cherry', 'color': const Color(0xFFDE3163), 'description': 'Sweet and vibrant'},
          {'id': 'brick', 'label': 'Brick Red', 'color': const Color(0xFFCB4154), 'description': 'Earthy tone'},
        ];

      case 'white':
        return [
          {'id': 'pure', 'label': 'Pure White', 'color': const Color(0xFFFFFFFF), 'description': 'Bright white', 'recommended': true},
          {'id': 'warm', 'label': 'Warm White', 'color': const Color(0xFFFFF5E0), 'description': 'Soft and cozy'},
          {'id': 'cool', 'label': 'Cool White', 'color': const Color(0xFFF0FFFF), 'description': 'Crisp and clean'},
          {'id': 'soft', 'label': 'Soft White', 'color': const Color(0xFFFAF0E6), 'description': 'Gentle glow'},
        ];

      case 'purple':
      case 'violet':
        return [
          {'id': 'royal_purple', 'label': 'Royal Purple', 'color': const Color(0xFF7851A9), 'description': 'Regal and rich', 'recommended': true},
          {'id': 'lavender', 'label': 'Lavender', 'color': const Color(0xFFE6E6FA), 'description': 'Soft and calming'},
          {'id': 'plum', 'label': 'Plum', 'color': const Color(0xFF8E4585), 'description': 'Deep and warm'},
          {'id': 'violet', 'label': 'Violet', 'color': const Color(0xFFEE82EE), 'description': 'Bright and vivid'},
        ];

      case 'orange':
        return [
          {'id': 'tangerine', 'label': 'Tangerine', 'color': const Color(0xFFFF9966), 'description': 'Classic orange', 'recommended': true},
          {'id': 'amber', 'label': 'Amber', 'color': const Color(0xFFFFBF00), 'description': 'Warm golden'},
          {'id': 'burnt', 'label': 'Burnt Orange', 'color': const Color(0xFFCC5500), 'description': 'Deep autumn tone'},
          {'id': 'coral', 'label': 'Coral', 'color': const Color(0xFFFF7F50), 'description': 'Soft pink-orange'},
        ];

      case 'yellow':
        return [
          {'id': 'golden', 'label': 'Golden Yellow', 'color': const Color(0xFFFFD700), 'description': 'Rich gold', 'recommended': true},
          {'id': 'lemon', 'label': 'Lemon', 'color': const Color(0xFFFFF44F), 'description': 'Bright citrus'},
          {'id': 'butter', 'label': 'Butter', 'color': const Color(0xFFFFEF9F), 'description': 'Soft and warm'},
          {'id': 'canary', 'label': 'Canary', 'color': const Color(0xFFFFEF00), 'description': 'Vivid yellow'},
        ];

      case 'pink':
        return [
          {'id': 'hot_pink', 'label': 'Hot Pink', 'color': const Color(0xFFFF69B4), 'description': 'Bold and fun', 'recommended': true},
          {'id': 'blush', 'label': 'Blush', 'color': const Color(0xFFDE5D83), 'description': 'Soft rose'},
          {'id': 'magenta', 'label': 'Magenta', 'color': const Color(0xFFFF00FF), 'description': 'Electric bright'},
          {'id': 'salmon', 'label': 'Salmon', 'color': const Color(0xFFFA8072), 'description': 'Peachy pink'},
        ];

      default:
        // Generic fallback
        return [
          {'id': 'standard', 'label': colorName.capitalize(), 'color': Colors.grey, 'description': 'Standard $colorName', 'recommended': true},
          {'id': 'light', 'label': 'Light $colorName', 'color': Colors.grey.shade300, 'description': 'Lighter variation'},
          {'id': 'dark', 'label': 'Dark $colorName', 'color': Colors.grey.shade700, 'description': 'Darker variation'},
          {'id': 'vivid', 'label': 'Vivid $colorName', 'color': Colors.grey.shade500, 'description': 'More saturated'},
        ];
    }
  }

  String _extractEffectName(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('chase') || lower.contains('running')) return 'chase effect';
    if (lower.contains('wave') || lower.contains('ripple')) return 'wave';
    if (lower.contains('twinkle') || lower.contains('sparkle')) return 'twinkle';
    if (lower.contains('pulse') || lower.contains('breath')) return 'pulse';
    if (lower.contains('flow')) return 'flow';
    return 'motion';
  }

  MotionDirection? _parseDirection(String id) {
    switch (id) {
      case 'left_to_right':
        return MotionDirection.leftToRight;
      case 'right_to_left':
        return MotionDirection.rightToLeft;
      case 'inward':
        return MotionDirection.inward;
      case 'outward':
        return MotionDirection.outward;
      case 'upward':
        return MotionDirection.upward;
      case 'downward':
        return MotionDirection.downward;
      default:
        return null;
    }
  }

  List<ClarificationOption> _getDefaultEffectOptions() {
    return const [
      ClarificationOption(
        id: 'chase',
        label: 'Chase',
        description: 'Running lights that move along',
        icon: Icons.directions_run,
        isRecommended: true,
      ),
      ClarificationOption(
        id: 'wave',
        label: 'Wave',
        description: 'Smooth wave of color',
        icon: Icons.waves,
      ),
      ClarificationOption(
        id: 'twinkle',
        label: 'Twinkle',
        description: 'Sparkling like stars',
        icon: Icons.auto_awesome,
      ),
      ClarificationOption(
        id: 'pulse',
        label: 'Pulse',
        description: 'Gentle breathing effect',
        icon: Icons.favorite,
      ),
    ];
  }

  Map<String, dynamic> _generateColorPreview(List<Color> colors, int totalPixels) {
    if (colors.isEmpty) {
      return {
        'on': true,
        'bri': 200,
        'seg': [{'id': 0, 'start': 0, 'stop': totalPixels, 'col': [[128, 128, 128]], 'fx': 0}],
      };
    }

    final color = colors.first;
    return {
      'on': true,
      'bri': 200,
      'seg': [
        {
          'id': 0,
          'start': 0,
          'stop': totalPixels,
          'col': [[color.red, color.green, color.blue]],
          'fx': 0,
        }
      ],
    };
  }

  Map<String, dynamic> _generateSpacingPreview(String optionId, int totalPixels) {
    // Generate a preview showing the spacing pattern
    // This creates a simple segment config showing the pattern
    return {
      'on': true,
      'bri': 200,
      'seg': [
        {
          'id': 0,
          'start': 0,
          'stop': totalPixels,
          'col': [[255, 255, 255], [0, 0, 0]],
          'fx': 0, // Solid - actual spacing shown in composer
        }
      ],
    };
  }
}

/// Extension for string capitalization.
extension StringCapitalization on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
