import 'package:nexgen_command/features/design_studio/models/clarification_models.dart';
import 'package:nexgen_command/features/design_studio/models/composed_pattern.dart';
import 'package:nexgen_command/features/design_studio/models/design_intent.dart';
import 'package:nexgen_command/features/design_studio/services/clarification_service.dart';
import 'package:nexgen_command/features/design_studio/services/constraint_solver.dart';
import 'package:nexgen_command/features/design_studio/services/nlu_service.dart';
import 'package:nexgen_command/features/design_studio/services/pattern_composer.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';

/// Main orchestrator for the AI Design Studio.
///
/// Coordinates the full pipeline from natural language input to WLED pattern:
/// 1. Parse user input (NLU)
/// 2. Validate constraints
/// 3. Handle clarifications if needed
/// 4. Compose final pattern
class DesignStudioOrchestrator {
  final NLUService _nluService;
  final ConstraintSolver _constraintSolver;
  final ClarificationService _clarificationService;
  final PatternComposer _patternComposer;

  DesignStudioOrchestrator({
    NLUService? nluService,
    ConstraintSolver? constraintSolver,
    ClarificationService? clarificationService,
    PatternComposer? patternComposer,
  })  : _nluService = nluService ?? NLUService(),
        _constraintSolver = constraintSolver ?? ConstraintSolver(),
        _clarificationService = clarificationService ?? ClarificationService(),
        _patternComposer = patternComposer ?? PatternComposer();

  /// Process user input through the full pipeline.
  ///
  /// Returns a [DesignStudioResult] indicating:
  /// - [DesignStudioStatus.needsClarification]: Questions need answers
  /// - [DesignStudioStatus.ready]: Pattern is ready to apply
  /// - [DesignStudioStatus.error]: Something went wrong
  Future<DesignStudioResult> processUserInput({
    required String prompt,
    required RooflineConfiguration? config,
  }) async {
    if (config == null) {
      return DesignStudioResult.error(
        'No roofline configuration found. Please set up your roofline first.',
        suggestions: ['Go to Settings > Roofline Setup'],
      );
    }

    if (prompt.trim().isEmpty) {
      return DesignStudioResult.error(
        'Please describe what you want your lights to do.',
      );
    }

    try {
      // Step 1: Parse user input into design intent
      final intent = await _nluService.parseUserIntent(prompt, config);

      // Step 2: Validate constraints
      final validationResult = _constraintSolver.validate(
        intent: intent,
        config: config,
      );

      // Merge any new ambiguities from validation
      final allAmbiguities = [
        ...intent.ambiguities,
        ...validationResult.additionalAmbiguities,
      ];

      // Update intent with validation results
      var updatedIntent = intent.copyWith(
        constraints: validationResult.constraints,
        ambiguities: allAmbiguities,
      );

      // Step 3: Check if clarification is needed
      if (allAmbiguities.isNotEmpty) {
        final questions = _clarificationService.buildQuestions(
          ambiguities: allAmbiguities,
          intent: updatedIntent,
          config: config,
        );

        return DesignStudioResult.needsClarification(
          intent: updatedIntent,
          questions: questions,
        );
      }

      // Step 4: Compose the pattern
      final compositionResult = _patternComposer.compose(
        intent: updatedIntent,
        config: config,
      );

      if (!compositionResult.isSuccess) {
        return DesignStudioResult.error(
          compositionResult.errorMessage ?? 'Failed to compose pattern',
          suggestions: compositionResult.suggestions,
          recommendManual: compositionResult.recommendManual,
        );
      }

      return DesignStudioResult.ready(
        intent: updatedIntent,
        pattern: compositionResult.pattern!,
        warnings: compositionResult.warnings,
      );
    } catch (e) {
      return DesignStudioResult.error(
        'Something went wrong: ${e.toString()}',
        recommendManual: true,
      );
    }
  }

  /// Apply user's clarification choices and continue processing.
  Future<DesignStudioResult> applyClarifications({
    required DesignIntent currentIntent,
    required List<ClarificationQuestion> questions,
    required Map<String, ClarificationOption> choices,
    required RooflineConfiguration config,
  }) async {
    // Check if user wants manual controls
    final wantsManual = choices.values.any((opt) => opt.id == 'manual');
    if (wantsManual) {
      return DesignStudioResult.manualRequested(
        intent: currentIntent,
        aspect: _getManualAspect(questions, choices),
      );
    }

    // Apply the clarifications to refine the intent
    final refinedIntent = _clarificationService.applyClarifications(
      original: currentIntent,
      choices: choices,
      questions: questions,
    );

    // Re-validate with refined intent
    final validationResult = _constraintSolver.validate(
      intent: refinedIntent,
      config: config,
    );

    // Check for any remaining ambiguities
    final remainingAmbiguities = [
      ...refinedIntent.ambiguities,
      ...validationResult.additionalAmbiguities,
    ];

    if (remainingAmbiguities.isNotEmpty) {
      final newQuestions = _clarificationService.buildQuestions(
        ambiguities: remainingAmbiguities,
        intent: refinedIntent,
        config: config,
      );

      return DesignStudioResult.needsClarification(
        intent: refinedIntent,
        questions: newQuestions,
      );
    }

    // Compose the final pattern
    final compositionResult = _patternComposer.compose(
      intent: refinedIntent,
      config: config,
    );

    if (!compositionResult.isSuccess) {
      return DesignStudioResult.error(
        compositionResult.errorMessage ?? 'Failed to compose pattern',
        suggestions: compositionResult.suggestions,
        recommendManual: compositionResult.recommendManual,
      );
    }

    return DesignStudioResult.ready(
      intent: refinedIntent,
      pattern: compositionResult.pattern!,
      warnings: compositionResult.warnings,
    );
  }

  /// Generate a preview for a specific clarification option.
  Map<String, dynamic> generateOptionPreview({
    required ClarificationOption option,
    required DesignIntent intent,
    RooflineConfiguration? config,
  }) {
    return _clarificationService.generatePreviewPayload(
      option: option,
      intent: intent,
      config: config,
    );
  }

  /// Quick compose without full pipeline (for previews).
  CompositionResult quickCompose({
    required DesignIntent intent,
    required RooflineConfiguration config,
  }) {
    return _patternComposer.compose(
      intent: intent,
      config: config,
    );
  }

  /// Parse input without validation (for understanding display).
  Future<DesignIntent> parseOnly({
    required String prompt,
    RooflineConfiguration? config,
  }) async {
    return _nluService.parseUserIntent(prompt, config);
  }

  /// Validate an intent without composing.
  ConstraintValidationResult validateOnly({
    required DesignIntent intent,
    required RooflineConfiguration config,
  }) {
    return _constraintSolver.validate(
      intent: intent,
      config: config,
    );
  }

  String _getManualAspect(
    List<ClarificationQuestion> questions,
    Map<String, ClarificationOption> choices,
  ) {
    for (final entry in choices.entries) {
      if (entry.value.id == 'manual') {
        final question = questions.firstWhere(
          (q) => q.id == entry.key,
          orElse: () => questions.first,
        );
        return question.type.displayName;
      }
    }
    return 'settings';
  }
}

/// Result from the design studio orchestrator.
class DesignStudioResult {
  /// Current status of the design process.
  final DesignStudioStatus status;

  /// The current design intent (may be partial).
  final DesignIntent? intent;

  /// Questions needing user answers (if status is needsClarification).
  final List<ClarificationQuestion>? pendingQuestions;

  /// The composed pattern (if status is ready).
  final ComposedPattern? pattern;

  /// Error message (if status is error).
  final String? errorMessage;

  /// Suggestions for the user.
  final List<String> suggestions;

  /// Warnings that don't prevent success.
  final List<String> warnings;

  /// Whether manual controls are recommended.
  final bool recommendManual;

  /// Which aspect needs manual control (if manualRequested).
  final String? manualAspect;

  const DesignStudioResult._({
    required this.status,
    this.intent,
    this.pendingQuestions,
    this.pattern,
    this.errorMessage,
    this.suggestions = const [],
    this.warnings = const [],
    this.recommendManual = false,
    this.manualAspect,
  });

  /// Create a result indicating clarification is needed.
  factory DesignStudioResult.needsClarification({
    required DesignIntent intent,
    required List<ClarificationQuestion> questions,
  }) {
    return DesignStudioResult._(
      status: DesignStudioStatus.needsClarification,
      intent: intent,
      pendingQuestions: questions,
    );
  }

  /// Create a result indicating the pattern is ready.
  factory DesignStudioResult.ready({
    required DesignIntent intent,
    required ComposedPattern pattern,
    List<String> warnings = const [],
  }) {
    return DesignStudioResult._(
      status: DesignStudioStatus.ready,
      intent: intent,
      pattern: pattern,
      warnings: warnings,
    );
  }

  /// Create an error result.
  factory DesignStudioResult.error(
    String message, {
    List<String> suggestions = const [],
    bool recommendManual = false,
  }) {
    return DesignStudioResult._(
      status: DesignStudioStatus.error,
      errorMessage: message,
      suggestions: suggestions,
      recommendManual: recommendManual,
    );
  }

  /// Create a result indicating user requested manual controls.
  factory DesignStudioResult.manualRequested({
    required DesignIntent intent,
    required String aspect,
  }) {
    return DesignStudioResult._(
      status: DesignStudioStatus.manualRequested,
      intent: intent,
      manualAspect: aspect,
      recommendManual: true,
    );
  }

  /// Whether clarification is needed.
  bool get needsClarification => status == DesignStudioStatus.needsClarification;

  /// Whether the pattern is ready to apply.
  bool get isReady => status == DesignStudioStatus.ready;

  /// Whether there was an error.
  bool get isError => status == DesignStudioStatus.error;

  /// Whether manual controls were requested.
  bool get isManualRequested => status == DesignStudioStatus.manualRequested;

  /// Get a user-friendly status message.
  String get statusMessage {
    switch (status) {
      case DesignStudioStatus.idle:
        return 'Ready for your design';
      case DesignStudioStatus.processing:
        return 'Understanding your request...';
      case DesignStudioStatus.needsClarification:
        final count = pendingQuestions?.length ?? 0;
        return count == 1
            ? 'I have a quick question'
            : 'I have $count quick questions';
      case DesignStudioStatus.ready:
        return 'Your design is ready!';
      case DesignStudioStatus.error:
        return errorMessage ?? 'Something went wrong';
      case DesignStudioStatus.manualRequested:
        return 'Opening manual controls for $manualAspect';
    }
  }
}

/// Status of the design studio process.
enum DesignStudioStatus {
  /// Waiting for user input.
  idle,

  /// Processing user input.
  processing,

  /// Needs clarification from user.
  needsClarification,

  /// Pattern is ready to preview/apply.
  ready,

  /// An error occurred.
  error,

  /// User requested manual controls.
  manualRequested,
}

/// Lightweight result for understanding display (before full composition).
class UnderstandingResult {
  /// What we understood from the user's input.
  final List<UnderstandingItem> items;

  /// Overall confidence (0.0-1.0).
  final double confidence;

  /// Whether there are ambiguities.
  final bool hasAmbiguities;

  const UnderstandingResult({
    required this.items,
    required this.confidence,
    required this.hasAmbiguities,
  });

  /// Create from a design intent.
  factory UnderstandingResult.fromIntent(DesignIntent intent) {
    final items = <UnderstandingItem>[];

    for (final layer in intent.layers) {
      // Add color understanding
      items.add(UnderstandingItem(
        category: 'Color',
        description: _describeColor(layer.colors),
        icon: 'palette',
      ));

      // Add zone understanding
      if (layer.targetZone.type != ZoneSelectorType.all) {
        items.add(UnderstandingItem(
          category: 'Area',
          description: layer.targetZone.description,
          icon: 'location_on',
        ));
      }

      // Add motion understanding
      if (layer.motion != null) {
        items.add(UnderstandingItem(
          category: 'Motion',
          description: '${layer.motion!.motionType.name} ${layer.motion!.direction.displayName}',
          icon: 'animation',
        ));
      }

      // Add spacing understanding
      if (layer.colors.spacingRule != null) {
        items.add(UnderstandingItem(
          category: 'Spacing',
          description: layer.colors.spacingRule!.description,
          icon: 'straighten',
        ));
      }
    }

    return UnderstandingResult(
      items: items,
      confidence: intent.confidence,
      hasAmbiguities: intent.needsClarification,
    );
  }

  static String _describeColor(ColorAssignment colors) {
    final parts = <String>[];

    parts.add(_colorToName(colors.primaryColor));

    if (colors.secondaryColor != null) {
      parts.add('with ${_colorToName(colors.secondaryColor!)}');
    }

    if (colors.accentColor != null) {
      parts.add('accented ${_colorToName(colors.accentColor!)}');
    }

    return parts.join(' ');
  }

  static String _colorToName(dynamic color) {
    // Simple color naming - could be enhanced
    return 'color';
  }
}

/// A single item of understanding to display.
class UnderstandingItem {
  final String category;
  final String description;
  final String icon;

  const UnderstandingItem({
    required this.category,
    required this.description,
    required this.icon,
  });
}
