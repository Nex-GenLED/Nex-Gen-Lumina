import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/design_studio/models/clarification_models.dart';
import 'package:nexgen_command/features/design_studio/models/composed_pattern.dart';
import 'package:nexgen_command/features/design_studio/models/design_intent.dart';
import 'package:nexgen_command/features/design_studio/services/clarification_service.dart';
import 'package:nexgen_command/features/design_studio/services/constraint_solver.dart';
import 'package:nexgen_command/features/design_studio/services/design_studio_orchestrator.dart';
import 'package:nexgen_command/features/design_studio/services/nlu_service.dart';
import 'package:nexgen_command/features/design_studio/services/pattern_composer.dart';

// =============================================================================
// Service Providers
// =============================================================================

/// Provider for the NLU service.
final nluServiceProvider = Provider<NLUService>((ref) => NLUService());

/// Provider for the constraint solver.
final constraintSolverProvider = Provider<ConstraintSolver>((ref) => ConstraintSolver());

/// Provider for the clarification service.
final clarificationServiceProvider = Provider<ClarificationService>((ref) => ClarificationService());

/// Provider for the pattern composer.
final patternComposerProvider = Provider<PatternComposer>((ref) => PatternComposer());

/// Provider for the main orchestrator.
final designStudioOrchestratorProvider = Provider<DesignStudioOrchestrator>((ref) {
  return DesignStudioOrchestrator(
    nluService: ref.watch(nluServiceProvider),
    constraintSolver: ref.watch(constraintSolverProvider),
    clarificationService: ref.watch(clarificationServiceProvider),
    patternComposer: ref.watch(patternComposerProvider),
  );
});

// =============================================================================
// State Providers
// =============================================================================

/// Current state of the design studio.
final designStudioStateProvider = StateProvider<DesignStudioStatus>((ref) {
  return DesignStudioStatus.idle;
});

/// Current user input text.
final designStudioInputProvider = StateProvider<String>((ref) => '');

/// Whether voice input is active.
final voiceInputActiveProvider = StateProvider<bool>((ref) => false);

/// Whether live preview on lights is enabled.
final livePreviewEnabledProvider = StateProvider<bool>((ref) => false);

// =============================================================================
// Design Intent State
// =============================================================================

/// Current design intent being built.
final currentDesignIntentProvider = StateNotifierProvider<DesignIntentNotifier, DesignIntent?>((ref) {
  return DesignIntentNotifier();
});

/// Notifier for managing design intent state.
class DesignIntentNotifier extends StateNotifier<DesignIntent?> {
  DesignIntentNotifier() : super(null);

  /// Set a new design intent.
  void setIntent(DesignIntent intent) {
    state = intent;
  }

  /// Clear the current intent.
  void clear() {
    state = null;
  }

  /// Update the intent with refined data.
  void updateIntent(DesignIntent Function(DesignIntent) updater) {
    if (state != null) {
      state = updater(state!);
    }
  }

  /// Add or update a layer.
  void updateLayer(DesignLayer layer) {
    if (state == null) return;

    final layers = List<DesignLayer>.from(state!.layers);
    final index = layers.indexWhere((l) => l.id == layer.id);

    if (index >= 0) {
      layers[index] = layer;
    } else {
      layers.add(layer);
    }

    state = state!.copyWith(layers: layers);
  }

  /// Remove a layer by ID.
  void removeLayer(String layerId) {
    if (state == null) return;

    final layers = state!.layers.where((l) => l.id != layerId).toList();
    state = state!.copyWith(layers: layers);
  }
}

// =============================================================================
// Clarification State
// =============================================================================

/// Pending clarification questions.
final pendingClarificationsProvider = StateProvider<List<ClarificationQuestion>>((ref) {
  return [];
});

/// Current question index in the clarification flow.
final currentQuestionIndexProvider = StateProvider<int>((ref) => 0);

/// User's clarification choices (question ID -> selected option).
final clarificationChoicesProvider = StateProvider<Map<String, ClarificationOption>>((ref) {
  return {};
});

/// Current clarification question (derived).
final currentQuestionProvider = Provider<ClarificationQuestion?>((ref) {
  final questions = ref.watch(pendingClarificationsProvider);
  final index = ref.watch(currentQuestionIndexProvider);

  if (questions.isEmpty || index >= questions.length) {
    return null;
  }

  return questions[index];
});

/// Whether all clarification questions have been answered.
final allQuestionsAnsweredProvider = Provider<bool>((ref) {
  final questions = ref.watch(pendingClarificationsProvider);
  final choices = ref.watch(clarificationChoicesProvider);

  if (questions.isEmpty) return true;

  // Check that all required questions have answers
  for (final q in questions.where((q) => q.isRequired)) {
    if (!choices.containsKey(q.id)) {
      return false;
    }
  }

  return true;
});

// =============================================================================
// Pattern State
// =============================================================================

/// Composed pattern ready for preview/apply.
final composedPatternProvider = StateProvider<ComposedPattern?>((ref) {
  return null;
});

/// Last composition result (for accessing warnings/errors).
final lastCompositionResultProvider = StateProvider<CompositionResult?>((ref) {
  return null;
});

// =============================================================================
// Processing Actions
// =============================================================================

/// Provider for processing user input through the orchestrator.
final processInputProvider = FutureProvider.family<DesignStudioResult, String>((ref, prompt) async {
  final orchestrator = ref.read(designStudioOrchestratorProvider);
  final configAsync = ref.read(currentRooflineConfigProvider);

  final config = configAsync.valueOrNull;

  // Update state to processing
  ref.read(designStudioStateProvider.notifier).state = DesignStudioStatus.processing;
  ref.read(designStudioInputProvider.notifier).state = prompt;

  final result = await orchestrator.processUserInput(
    prompt: prompt,
    config: config,
  );

  // Update state based on result
  ref.read(designStudioStateProvider.notifier).state = result.status;

  if (result.intent != null) {
    ref.read(currentDesignIntentProvider.notifier).setIntent(result.intent!);
  }

  if (result.needsClarification && result.pendingQuestions != null) {
    ref.read(pendingClarificationsProvider.notifier).state = result.pendingQuestions!;
    ref.read(currentQuestionIndexProvider.notifier).state = 0;
    ref.read(clarificationChoicesProvider.notifier).state = {};
  }

  if (result.isReady && result.pattern != null) {
    ref.read(composedPatternProvider.notifier).state = result.pattern;
  }

  return result;
});

/// Provider for applying clarification choices.
final applyClarificationsProvider = FutureProvider<DesignStudioResult>((ref) async {
  final orchestrator = ref.read(designStudioOrchestratorProvider);
  final intent = ref.read(currentDesignIntentProvider);
  final questions = ref.read(pendingClarificationsProvider);
  final choices = ref.read(clarificationChoicesProvider);
  final configAsync = ref.read(currentRooflineConfigProvider);

  final config = configAsync.valueOrNull;

  if (intent == null || config == null) {
    return DesignStudioResult.error('No design intent or configuration available');
  }

  ref.read(designStudioStateProvider.notifier).state = DesignStudioStatus.processing;

  final result = await orchestrator.applyClarifications(
    currentIntent: intent,
    questions: questions,
    choices: choices,
    config: config,
  );

  // Update state based on result
  ref.read(designStudioStateProvider.notifier).state = result.status;

  if (result.intent != null) {
    ref.read(currentDesignIntentProvider.notifier).setIntent(result.intent!);
  }

  if (result.needsClarification && result.pendingQuestions != null) {
    ref.read(pendingClarificationsProvider.notifier).state = result.pendingQuestions!;
    ref.read(currentQuestionIndexProvider.notifier).state = 0;
    // Keep existing choices that are still relevant
  }

  if (result.isReady && result.pattern != null) {
    ref.read(composedPatternProvider.notifier).state = result.pattern;
    // Clear clarification state
    ref.read(pendingClarificationsProvider.notifier).state = [];
    ref.read(clarificationChoicesProvider.notifier).state = {};
  }

  return result;
});

// =============================================================================
// Helper Actions
// =============================================================================

/// Reset the design studio to initial state.
void resetDesignStudio(WidgetRef ref) {
  ref.read(designStudioStateProvider.notifier).state = DesignStudioStatus.idle;
  ref.read(designStudioInputProvider.notifier).state = '';
  ref.read(currentDesignIntentProvider.notifier).clear();
  ref.read(pendingClarificationsProvider.notifier).state = [];
  ref.read(currentQuestionIndexProvider.notifier).state = 0;
  ref.read(clarificationChoicesProvider.notifier).state = {};
  ref.read(composedPatternProvider.notifier).state = null;
  ref.read(lastCompositionResultProvider.notifier).state = null;
}

/// Select an answer for the current clarification question.
void selectClarificationOption(WidgetRef ref, ClarificationOption option) {
  final currentQuestion = ref.read(currentQuestionProvider);
  if (currentQuestion == null) return;

  // Add/update the choice
  final choices = Map<String, ClarificationOption>.from(
    ref.read(clarificationChoicesProvider),
  );
  choices[currentQuestion.id] = option;
  ref.read(clarificationChoicesProvider.notifier).state = choices;

  // Move to next question if available
  final questions = ref.read(pendingClarificationsProvider);
  final currentIndex = ref.read(currentQuestionIndexProvider);

  if (currentIndex < questions.length - 1) {
    ref.read(currentQuestionIndexProvider.notifier).state = currentIndex + 1;
  }
}

/// Go back to previous clarification question.
void previousClarificationQuestion(WidgetRef ref) {
  final currentIndex = ref.read(currentQuestionIndexProvider);
  if (currentIndex > 0) {
    ref.read(currentQuestionIndexProvider.notifier).state = currentIndex - 1;
  }
}

// =============================================================================
// Derived State
// =============================================================================

/// Whether the design studio is currently processing.
final isProcessingProvider = Provider<bool>((ref) {
  return ref.watch(designStudioStateProvider) == DesignStudioStatus.processing;
});

/// Whether we're in clarification mode.
final isClarifyingProvider = Provider<bool>((ref) {
  return ref.watch(designStudioStateProvider) == DesignStudioStatus.needsClarification;
});

/// Whether a pattern is ready.
final patternReadyProvider = Provider<bool>((ref) {
  return ref.watch(designStudioStateProvider) == DesignStudioStatus.ready &&
         ref.watch(composedPatternProvider) != null;
});

/// Understanding summary for display.
final understandingSummaryProvider = Provider<List<String>>((ref) {
  final intent = ref.watch(currentDesignIntentProvider);
  if (intent == null) return [];

  final summary = <String>[];

  for (final layer in intent.layers) {
    // Color
    summary.add('${_colorDescription(layer.colors)} color');

    // Zone
    if (layer.targetZone.type != ZoneSelectorType.all) {
      summary.add('on ${layer.targetZone.description}');
    }

    // Motion
    if (layer.motion != null) {
      summary.add('${layer.motion!.motionType.name} ${layer.motion!.direction.displayName}');
    }

    // Spacing
    if (layer.colors.spacingRule != null) {
      summary.add(layer.colors.spacingRule!.description);
    }
  }

  return summary;
});

String _colorDescription(ColorAssignment colors) {
  // Simple description - could be enhanced with actual color names
  if (colors.accentColor != null) {
    return 'accented';
  }
  if (colors.secondaryColor != null) {
    return 'two-tone';
  }
  return 'solid';
}

/// Clarification progress (0.0 to 1.0).
final clarificationProgressProvider = Provider<double>((ref) {
  final questions = ref.watch(pendingClarificationsProvider);
  final choices = ref.watch(clarificationChoicesProvider);

  if (questions.isEmpty) return 1.0;

  return choices.length / questions.length;
});
