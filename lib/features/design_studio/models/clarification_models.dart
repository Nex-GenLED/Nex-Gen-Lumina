import 'package:flutter/material.dart';

/// A question to ask the user for clarification.
///
/// Used when the NLU detects ambiguity in the user's request.
class ClarificationQuestion {
  /// Unique identifier for this question.
  final String id;

  /// Type of clarification needed.
  final ClarificationType type;

  /// User-friendly question text.
  final String questionText;

  /// Available options to choose from.
  final List<ClarificationOption> options;

  /// Whether this question must be answered (vs. skippable).
  final bool isRequired;

  /// Hint for visual display (icon, image, etc.).
  final String? visualHint;

  /// The source text that caused this ambiguity.
  final String? sourceText;

  /// ID of the affected layer (if applicable).
  final String? affectedLayerId;

  /// Context information for better understanding.
  final String? context;

  const ClarificationQuestion({
    required this.id,
    required this.type,
    required this.questionText,
    required this.options,
    this.isRequired = true,
    this.visualHint,
    this.sourceText,
    this.affectedLayerId,
    this.context,
  });

  /// The recommended option, if any.
  ClarificationOption? get recommendedOption =>
      options.where((o) => o.isRecommended).firstOrNull;

  /// Index of the recommended option.
  int? get recommendedIndex {
    final idx = options.indexWhere((o) => o.isRecommended);
    return idx >= 0 ? idx : null;
  }

  ClarificationQuestion copyWith({
    String? id,
    ClarificationType? type,
    String? questionText,
    List<ClarificationOption>? options,
    bool? isRequired,
    String? visualHint,
    String? sourceText,
    String? affectedLayerId,
    String? context,
  }) {
    return ClarificationQuestion(
      id: id ?? this.id,
      type: type ?? this.type,
      questionText: questionText ?? this.questionText,
      options: options ?? this.options,
      isRequired: isRequired ?? this.isRequired,
      visualHint: visualHint ?? this.visualHint,
      sourceText: sourceText ?? this.sourceText,
      affectedLayerId: affectedLayerId ?? this.affectedLayerId,
      context: context ?? this.context,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'question_text': questionText,
        'options': options.map((o) => o.toJson()).toList(),
        'is_required': isRequired,
        'visual_hint': visualHint,
        'source_text': sourceText,
        'affected_layer_id': affectedLayerId,
        'context': context,
      };

  factory ClarificationQuestion.fromJson(Map<String, dynamic> json) {
    return ClarificationQuestion(
      id: json['id'] as String,
      type: ClarificationType.values.byName(json['type'] as String),
      questionText: json['question_text'] as String,
      options: (json['options'] as List)
          .map((o) => ClarificationOption.fromJson(o as Map<String, dynamic>))
          .toList(),
      isRequired: json['is_required'] as bool? ?? true,
      visualHint: json['visual_hint'] as String?,
      sourceText: json['source_text'] as String?,
      affectedLayerId: json['affected_layer_id'] as String?,
      context: json['context'] as String?,
    );
  }
}

/// An option in a clarification question.
class ClarificationOption {
  /// Unique identifier for this option.
  final String id;

  /// Display label.
  final String label;

  /// Optional description/explanation.
  final String? description;

  /// Whether this is the recommended option.
  final bool isRecommended;

  /// WLED payload for previewing this option.
  final Map<String, dynamic>? previewPayload;

  /// Icon to display.
  final IconData? icon;

  /// Color swatch(es) to display.
  final List<Color>? colorSwatches;

  /// The value this option represents.
  final dynamic value;

  /// Additional metadata.
  final Map<String, dynamic>? metadata;

  const ClarificationOption({
    required this.id,
    required this.label,
    this.description,
    this.isRecommended = false,
    this.previewPayload,
    this.icon,
    this.colorSwatches,
    this.value,
    this.metadata,
  });

  ClarificationOption copyWith({
    String? id,
    String? label,
    String? description,
    bool? isRecommended,
    Map<String, dynamic>? previewPayload,
    IconData? icon,
    List<Color>? colorSwatches,
    dynamic value,
    Map<String, dynamic>? metadata,
  }) {
    return ClarificationOption(
      id: id ?? this.id,
      label: label ?? this.label,
      description: description ?? this.description,
      isRecommended: isRecommended ?? this.isRecommended,
      previewPayload: previewPayload ?? this.previewPayload,
      icon: icon ?? this.icon,
      colorSwatches: colorSwatches ?? this.colorSwatches,
      value: value ?? this.value,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'description': description,
        'is_recommended': isRecommended,
        'preview_payload': previewPayload,
        'icon': icon?.codePoint,
        'color_swatches': colorSwatches?.map((c) => c.value).toList(),
        'value': value,
        'metadata': metadata,
      };

  factory ClarificationOption.fromJson(Map<String, dynamic> json) {
    return ClarificationOption(
      id: json['id'] as String,
      label: json['label'] as String,
      description: json['description'] as String?,
      isRecommended: json['is_recommended'] as bool? ?? false,
      previewPayload: json['preview_payload'] as Map<String, dynamic>?,
      icon: json['icon'] != null
          ? IconData(json['icon'] as int, fontFamily: 'MaterialIcons')
          : null,
      colorSwatches: (json['color_swatches'] as List?)
          ?.map((c) => Color(c as int))
          .toList(),
      value: json['value'],
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }
}

/// Types of clarification questions.
enum ClarificationType {
  /// Zone/segment selection is ambiguous.
  /// e.g., "corners" could mean front corners, all corners, etc.
  zoneAmbiguity,

  /// Color specification is vague.
  /// e.g., "green" could be forest, lime, mint, etc.
  colorAmbiguity,

  /// Requested spacing can't be achieved exactly.
  /// e.g., "equally spaced" doesn't divide evenly.
  spacingImpossible,

  /// Motion direction is unclear.
  /// e.g., "chase" without specifying direction.
  directionAmbiguity,

  /// Multiple layers have conflicting settings.
  /// e.g., two layers target same pixels with different colors.
  conflictResolution,

  /// Effect/animation type is unclear.
  /// e.g., "flashy" could mean twinkle, strobe, etc.
  effectAmbiguity,

  /// Brightness level is vague.
  /// e.g., "bright but not too bright".
  brightnessAmbiguity,

  /// Speed setting is vague.
  /// e.g., "fast" could mean different speeds.
  speedAmbiguity,

  /// User confirmation for a best-guess interpretation.
  confirmation,

  /// Manual control offer after repeated failures.
  manualFallback,
}

/// Extension with display names and icons for clarification types.
extension ClarificationTypeExtension on ClarificationType {
  String get displayName {
    switch (this) {
      case ClarificationType.zoneAmbiguity:
        return 'Which area?';
      case ClarificationType.colorAmbiguity:
        return 'Which shade?';
      case ClarificationType.spacingImpossible:
        return 'Spacing options';
      case ClarificationType.directionAmbiguity:
        return 'Which direction?';
      case ClarificationType.conflictResolution:
        return 'Resolve conflict';
      case ClarificationType.effectAmbiguity:
        return 'Which effect?';
      case ClarificationType.brightnessAmbiguity:
        return 'How bright?';
      case ClarificationType.speedAmbiguity:
        return 'How fast?';
      case ClarificationType.confirmation:
        return 'Confirm';
      case ClarificationType.manualFallback:
        return 'Manual controls';
    }
  }

  IconData get icon {
    switch (this) {
      case ClarificationType.zoneAmbiguity:
        return Icons.location_on;
      case ClarificationType.colorAmbiguity:
        return Icons.palette;
      case ClarificationType.spacingImpossible:
        return Icons.space_bar;
      case ClarificationType.directionAmbiguity:
        return Icons.swap_horiz;
      case ClarificationType.conflictResolution:
        return Icons.layers;
      case ClarificationType.effectAmbiguity:
        return Icons.auto_awesome;
      case ClarificationType.brightnessAmbiguity:
        return Icons.brightness_6;
      case ClarificationType.speedAmbiguity:
        return Icons.speed;
      case ClarificationType.confirmation:
        return Icons.check_circle_outline;
      case ClarificationType.manualFallback:
        return Icons.tune;
    }
  }
}

/// Result of a clarification session.
class ClarificationResult {
  /// Questions that were asked.
  final List<ClarificationQuestion> questions;

  /// User's choices (question ID -> option ID).
  final Map<String, String> choices;

  /// Whether all required questions were answered.
  final bool isComplete;

  /// Whether user opted for manual controls.
  final bool wantsManualControls;

  /// Timestamp when clarification was completed.
  final DateTime? completedAt;

  const ClarificationResult({
    required this.questions,
    required this.choices,
    this.isComplete = false,
    this.wantsManualControls = false,
    this.completedAt,
  });

  /// Get the selected option for a question.
  ClarificationOption? getSelectedOption(String questionId) {
    final question = questions.where((q) => q.id == questionId).firstOrNull;
    final optionId = choices[questionId];
    if (question == null || optionId == null) return null;
    return question.options.where((o) => o.id == optionId).firstOrNull;
  }

  ClarificationResult copyWith({
    List<ClarificationQuestion>? questions,
    Map<String, String>? choices,
    bool? isComplete,
    bool? wantsManualControls,
    DateTime? completedAt,
  }) {
    return ClarificationResult(
      questions: questions ?? this.questions,
      choices: choices ?? this.choices,
      isComplete: isComplete ?? this.isComplete,
      wantsManualControls: wantsManualControls ?? this.wantsManualControls,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'questions': questions.map((q) => q.toJson()).toList(),
        'choices': choices,
        'is_complete': isComplete,
        'wants_manual_controls': wantsManualControls,
        'completed_at': completedAt?.toIso8601String(),
      };
}

/// Builder helpers for common clarification questions.
class ClarificationQuestionBuilder {
  /// Build a zone ambiguity question.
  static ClarificationQuestion zoneAmbiguity({
    required String id,
    required String sourceText,
    required List<ClarificationOption> options,
    String? layerId,
  }) {
    return ClarificationQuestion(
      id: id,
      type: ClarificationType.zoneAmbiguity,
      questionText: 'Which areas should this apply to?',
      options: options,
      sourceText: sourceText,
      affectedLayerId: layerId,
      context: 'You said "$sourceText" - I want to make sure I light the right areas.',
    );
  }

  /// Build a color ambiguity question.
  static ClarificationQuestion colorAmbiguity({
    required String id,
    required String colorName,
    required List<ClarificationOption> options,
    String? layerId,
  }) {
    return ClarificationQuestion(
      id: id,
      type: ClarificationType.colorAmbiguity,
      questionText: 'Which shade of $colorName?',
      options: options,
      sourceText: colorName,
      affectedLayerId: layerId,
      context: 'There are several shades of $colorName - which looks best to you?',
    );
  }

  /// Build a spacing impossible question.
  static ClarificationQuestion spacingImpossible({
    required String id,
    required int pixelCount,
    required int requestedSpacing,
    required List<ClarificationOption> alternatives,
    String? layerId,
  }) {
    return ClarificationQuestion(
      id: id,
      type: ClarificationType.spacingImpossible,
      questionText: 'The spacing doesn\'t divide evenly - which option works best?',
      options: [
        ...alternatives,
        ClarificationOption(
          id: 'manual',
          label: 'Set manually',
          description: 'Open spacing controls to fine-tune',
          icon: Icons.tune,
        ),
      ],
      sourceText: 'every $requestedSpacing',
      affectedLayerId: layerId,
      context: 'With $pixelCount pixels, spacing by $requestedSpacing leaves some remainder.',
    );
  }

  /// Build a direction ambiguity question.
  static ClarificationQuestion directionAmbiguity({
    required String id,
    required String effectName,
    String? layerId,
  }) {
    return ClarificationQuestion(
      id: id,
      type: ClarificationType.directionAmbiguity,
      questionText: 'Which direction should the $effectName go?',
      options: const [
        ClarificationOption(
          id: 'left_to_right',
          label: 'Left to right',
          description: 'Moves from left side to right side',
          icon: Icons.arrow_forward,
          isRecommended: true,
        ),
        ClarificationOption(
          id: 'right_to_left',
          label: 'Right to left',
          description: 'Moves from right side to left side',
          icon: Icons.arrow_back,
        ),
        ClarificationOption(
          id: 'inward',
          label: 'Inward',
          description: 'Moves from both ends toward center',
          icon: Icons.compress,
        ),
        ClarificationOption(
          id: 'outward',
          label: 'Outward',
          description: 'Moves from center toward both ends',
          icon: Icons.expand,
        ),
      ],
      sourceText: effectName,
      affectedLayerId: layerId,
    );
  }

  /// Build a manual fallback question after repeated failures.
  static ClarificationQuestion manualFallback({
    required String id,
    required String aspect,
    required ClarificationOption manualOption,
  }) {
    return ClarificationQuestion(
      id: id,
      type: ClarificationType.manualFallback,
      questionText: 'Would you like to set the $aspect manually?',
      options: [
        const ClarificationOption(
          id: 'try_again',
          label: 'Let me try again',
          description: 'Describe what you want differently',
          icon: Icons.refresh,
        ),
        manualOption.copyWith(isRecommended: true),
      ],
      isRequired: false,
      context: 'I\'m having trouble understanding the $aspect. Manual controls let you set it exactly how you want.',
    );
  }

  /// Build a confirmation question for a best-guess interpretation.
  static ClarificationQuestion confirmation({
    required String id,
    required String interpretation,
    required Map<String, dynamic> previewPayload,
    String? layerId,
  }) {
    return ClarificationQuestion(
      id: id,
      type: ClarificationType.confirmation,
      questionText: 'Does this look right?',
      options: [
        ClarificationOption(
          id: 'yes',
          label: 'Yes, that\'s it!',
          icon: Icons.check,
          isRecommended: true,
          previewPayload: previewPayload,
        ),
        const ClarificationOption(
          id: 'no',
          label: 'No, let me adjust',
          icon: Icons.edit,
        ),
      ],
      affectedLayerId: layerId,
      context: 'I interpreted your request as: "$interpretation"',
    );
  }
}
