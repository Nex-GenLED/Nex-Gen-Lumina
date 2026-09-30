import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/design/models/clarification_models.dart';
import 'package:nexgen_command/features/design/models/composed_pattern.dart';
import 'package:nexgen_command/features/design/models/design_intent.dart';
import 'package:nexgen_command/features/design/services/clarification_service.dart';
import 'package:nexgen_command/features/design/services/constraint_solver.dart';
import 'package:nexgen_command/features/design/services/design_studio_orchestrator.dart';
import 'package:nexgen_command/features/design/services/nlu_service.dart';
import 'package:nexgen_command/features/design/services/pattern_composer.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';

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

/// The last result the orchestrator returned that the studio could not act
/// on: an error, with its message and suggestions. +110 E2 audit row 2 —
/// this used to be dropped on the floor (the text box just re-enabled), so a
/// home with no roofline map saw every prompt do nothing. Cleared by
/// [resetDesignStudio] and by the next successful result.
final designStudioLastErrorProvider =
    StateProvider<DesignStudioResult?>((ref) => null);

/// Records [result] on the studio's state providers — the ONE place the three
/// entry points (the screen's submit, [processInputProvider] and
/// [applyClarificationsProvider]) write their outcome, so an error can never
/// again be recorded by one and forgotten by another.
void recordDesignStudioResult(Ref ref, DesignStudioResult result) =>
    recordDesignStudioResultWith(ref.read, result);

/// See [recordDesignStudioResult]; takes `ref.read` from a widget.
void recordDesignStudioResultWith(
  T Function<T>(ProviderListenable<T> provider) read,
  DesignStudioResult result,
) {
  read(designStudioStateProvider.notifier).state = result.status;
  read(designStudioLastErrorProvider.notifier).state =
      result.isError ? result : null;

  if (result.intent != null) {
    read(currentDesignIntentProvider.notifier).setIntent(result.intent!);
  }

  if (result.needsClarification && result.pendingQuestions != null) {
    read(pendingClarificationsProvider.notifier).state =
        result.pendingQuestions!;
    read(currentQuestionIndexProvider.notifier).state = 0;
  }

  if (result.isReady && result.pattern != null) {
    read(composedPatternProvider.notifier).state = result.pattern;
    read(pendingClarificationsProvider.notifier).state = [];
    read(clarificationChoicesProvider.notifier).state = {};
  }
}

// =============================================================================
// Processing Actions
// =============================================================================

/// The roofline map as the AI pipeline needs it: with LIVE device bus lengths
/// attached when the controller is reachable. The composer emits
/// whole-controller LED groups, so it has to know where each channel really
/// starts on the wire — including channels that carry no map at all (see
/// RooflineConfiguration.globalStartOf). Falls back to the lengths recorded at
/// map time, which the config already carries.
RooflineConfiguration? _configForAiPipeline(Ref ref) {
  final config = ref.read(currentRooflineConfigProvider).valueOrNull;
  if (config == null) return null;
  final deviceChannels = ref.read(deviceChannelsProvider);
  if (deviceChannels.isEmpty) return config;
  return config.withChannelPixelCounts({
    for (final c in deviceChannels) c.id: c.stop - c.start,
  });
}

/// Provider for processing user input through the orchestrator.
final processInputProvider = FutureProvider.family<DesignStudioResult, String>((ref, prompt) async {
  final orchestrator = ref.read(designStudioOrchestratorProvider);
  final config = _configForAiPipeline(ref);

  // Update state to processing
  ref.read(designStudioStateProvider.notifier).state = DesignStudioStatus.processing;
  ref.read(designStudioInputProvider.notifier).state = prompt;

  final result = await orchestrator.processUserInput(
    prompt: prompt,
    config: config,
  );

  if (result.needsClarification) {
    ref.read(clarificationChoicesProvider.notifier).state = {};
  }
  recordDesignStudioResult(ref, result);

  return result;
});

/// Provider for applying clarification choices.
final applyClarificationsProvider = FutureProvider<DesignStudioResult>((ref) async {
  final orchestrator = ref.read(designStudioOrchestratorProvider);
  final intent = ref.read(currentDesignIntentProvider);
  final questions = ref.read(pendingClarificationsProvider);
  final choices = ref.read(clarificationChoicesProvider);
  final config = _configForAiPipeline(ref);

  if (intent == null || config == null) {
    final result = DesignStudioResult.error(
      config == null
          ? 'No roofline configuration found. Please set up your roofline '
              'first.'
          : 'Describe your design first, then answer the questions.',
      suggestions: config == null ? const ['Go to Settings > Roofline Setup'] : const [],
    );
    recordDesignStudioResult(ref, result);
    return result;
  }

  ref.read(designStudioStateProvider.notifier).state = DesignStudioStatus.processing;

  final result = await orchestrator.applyClarifications(
    currentIntent: intent,
    questions: questions,
    choices: choices,
    config: config,
  );

  // Existing choices that are still relevant are kept on a follow-up
  // question; they are cleared only when the pattern is ready.
  recordDesignStudioResult(ref, result);

  return result;
});

/// The primary action for [DesignStudioResult.suggestions] and the "no
/// roofline" error: true when the result is about the roofline map itself,
/// so the studio routes the customer to roofline setup rather than back to
/// the prompt (+110 E2 row 2).
bool isRooflineSetupError(DesignStudioResult result) {
  final text = '${result.errorMessage ?? ''} ${result.suggestions.join(' ')}'
      .toLowerCase();
  return text.contains('roofline');
}

// =============================================================================
// Helper Actions
// =============================================================================

/// Reset the design studio to initial state.
///
/// +110 E2 row 115: called by "Start over" and when the studio screen is
/// entered, so a pending question or a stale design from an earlier visit
/// never greets the customer on the next one. Takes `ref.read` so a
/// `WidgetRef` and a `Ref` can both call it.
void resetDesignStudio(WidgetRef ref) => resetDesignStudioWith(ref.read);

/// See [resetDesignStudio].
void resetDesignStudioWith(
    T Function<T>(ProviderListenable<T> provider) read) {
  read(designStudioStateProvider.notifier).state = DesignStudioStatus.idle;
  read(designStudioInputProvider.notifier).state = '';
  read(currentDesignIntentProvider.notifier).clear();
  read(pendingClarificationsProvider.notifier).state = [];
  read(currentQuestionIndexProvider.notifier).state = 0;
  read(clarificationChoicesProvider.notifier).state = {};
  read(composedPatternProvider.notifier).state = null;
  read(lastCompositionResultProvider.notifier).state = null;
  read(designStudioLastErrorProvider.notifier).state = null;
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
