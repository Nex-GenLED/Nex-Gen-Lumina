import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/features/ai/classification_signals.dart';
import 'package:nexgen_command/features/favorites/favorites_providers.dart';
import 'package:nexgen_command/features/scenes/scene_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

/// High-level intent classification for an incoming voice command.
enum CommandClassification {
  /// Modify the current lighting state — keep unmentioned parameters.
  adjustment,

  /// Start a completely fresh scene with new palette, effect, and defaults.
  newScene,

  /// Could be either — the UI should offer both options.
  ambiguous,
}

/// Result of running the [CommandIntentClassifier] on raw input text.
class ClassificationResult {
  /// The winning classification.
  final CommandClassification classification;

  /// Cumulative score for the "adjustment" hypothesis.
  final double adjustmentScore;

  /// Cumulative score for the "new scene" hypothesis.
  final double newSceneScore;

  /// Human-readable explanation for debug logs.
  final String reasoning;

  /// Which keywords/patterns contributed to the scores.
  final List<String> matchedSignals;

  /// If a user favorite/scene name was matched, its name.
  final String? matchedFavoriteName;

  const ClassificationResult({
    required this.classification,
    required this.adjustmentScore,
    required this.newSceneScore,
    required this.reasoning,
    required this.matchedSignals,
    this.matchedFavoriteName,
  });

  @override
  String toString() =>
      'ClassificationResult($classification, adj=$adjustmentScore, '
      'new=$newSceneScore, signals=${matchedSignals.length})';
}

// ---------------------------------------------------------------------------
// Provider — stores the latest classification for downstream consumers
// ---------------------------------------------------------------------------

/// The most recent classification result.
///
/// Set by [LuminaCommandRouter] before routing. Read by [LuminaBrain] to
/// inject classification context into the AI system prompt.
final latestClassificationProvider =
    StateProvider<ClassificationResult?>((ref) => null);

// ---------------------------------------------------------------------------
// Classifier
// ---------------------------------------------------------------------------

/// Classifies incoming voice/text commands as adjustment, new scene, or
/// ambiguous BEFORE they are sent to the local parser or cloud AI.
///
/// The classifier examines:
/// 1. Keyword/pattern signals from [adjustmentSignals] and [newSceneSignals]
/// 2. User's saved favorite/scene names (exact name → strong new-scene)
/// 3. Current WLED state (active scene provides adjustment bonus)
/// 4. Single-color ambiguity detection
class CommandIntentClassifier {
  CommandIntentClassifier._();

  /// Classify [text] given the current app context via [ref].
  static ClassificationResult classify(WidgetRef ref, String text) {
    final lower = text.toLowerCase().trim();
    final matched = <String>[];
    double adjScore = 0.0;
    double newScore = 0.0;

    // -----------------------------------------------------------------
    // 1. Score against adjustment signals
    // -----------------------------------------------------------------
    for (final signal in adjustmentSignals) {
      if (_matches(lower, signal)) {
        adjScore += signal.weight;
        matched.add('adj:${signal.keyword}');
      }
    }

    // -----------------------------------------------------------------
    // 2. Score against new-scene signals
    // -----------------------------------------------------------------
    for (final signal in newSceneSignals) {
      if (_matches(lower, signal)) {
        newScore += signal.weight;
        matched.add('new:${signal.keyword}');
      }
    }

    // -----------------------------------------------------------------
    // 3. Check ambiguity signals — add to BOTH scores
    // -----------------------------------------------------------------
    for (final signal in ambiguitySignals) {
      if (_matches(lower, signal)) {
        adjScore += signal.weight * 0.5;
        newScore += signal.weight * 0.5;
        matched.add('amb:${signal.keyword}');
      }
    }

    // -----------------------------------------------------------------
    // 4. Check user favorites/scene names
    // -----------------------------------------------------------------
    String? matchedFav;

    // Favorites
    final favs = ref.read(favoritesPatternsProvider).maybeWhen(
          data: (list) => list,
          orElse: () => <FavoritePattern>[],
        );
    for (final fav in favs) {
      if (_fuzzyNameMatch(lower, fav.name)) {
        newScore += kFavoriteMatchBonus;
        matchedFav = fav.name;
        matched.add('fav:${fav.name}');
        break;
      }
    }

    // Scenes (only check if no favorite matched)
    if (matchedFav == null) {
      final scenes = ref.read(allScenesProvider).whenOrNull(data: (s) => s);
      if (scenes != null) {
        for (final scene in scenes) {
          if (_fuzzyNameMatch(lower, scene.name)) {
            newScore += kFavoriteMatchBonus;
            matchedFav = scene.name;
            matched.add('scene:${scene.name}');
            break;
          }
        }
      }
    }

    // -----------------------------------------------------------------
    // 5. Active-scene bonus — if lights are on with an effect, adjustment
    //    is more likely for borderline commands
    // -----------------------------------------------------------------
    final wled = ref.read(wledStateProvider);
    if (wled.isOn && wled.effectId != 0) {
      adjScore += kActiveSceneAdjustmentBonus;
      matched.add('ctx:active_scene');
    }

    // -----------------------------------------------------------------
    // 6. Single-color-word ambiguity
    // -----------------------------------------------------------------
    if (_isSingleColorWord(lower) && wled.colorSequence.length > 1) {
      adjScore += kSingleColorAmbiguityBonus * 0.5;
      newScore += kSingleColorAmbiguityBonus * 0.5;
      matched.add('amb:single_color_multi_scene');
    }

    // -----------------------------------------------------------------
    // 7. Determine classification
    // -----------------------------------------------------------------
    final gap = (adjScore - newScore).abs();
    final maxScore = adjScore > newScore ? adjScore : newScore;

    CommandClassification classification;
    String reasoning;

    if (maxScore < kMinConfidenceThreshold) {
      // No strong signal either way
      classification = CommandClassification.ambiguous;
      reasoning = 'No strong signals detected (max score '
          '${maxScore.toStringAsFixed(2)} < threshold $kMinConfidenceThreshold)';
    } else if (gap < kAmbiguityGap) {
      classification = CommandClassification.ambiguous;
      reasoning = 'Scores too close: adj=${adjScore.toStringAsFixed(2)}, '
          'new=${newScore.toStringAsFixed(2)} (gap ${gap.toStringAsFixed(2)} '
          '< $kAmbiguityGap)';
    } else if (adjScore > newScore) {
      classification = CommandClassification.adjustment;
      reasoning = 'Adjustment wins: ${adjScore.toStringAsFixed(2)} vs '
          '${newScore.toStringAsFixed(2)}';
    } else {
      classification = CommandClassification.newScene;
      reasoning = 'New scene wins: ${newScore.toStringAsFixed(2)} vs '
          '${adjScore.toStringAsFixed(2)}';
    }

    final result = ClassificationResult(
      classification: classification,
      adjustmentScore: adjScore,
      newSceneScore: newScore,
      reasoning: reasoning,
      matchedSignals: matched,
      matchedFavoriteName: matchedFav,
    );

    debugPrint('🏷️ Classification: ${result.classification.name} — '
        '${result.reasoning} [${matched.length} signals]');

    return result;
  }

  /// Build a context string suitable for injection into the AI system prompt.
  ///
  /// Tells the AI how to handle this command based on its classification.
  static String buildAIContextHint(ClassificationResult result) {
    final buf = StringBuffer('COMMAND INTENT CLASSIFICATION:\n');

    switch (result.classification) {
      case CommandClassification.adjustment:
        buf.writeln('- Classification: ADJUSTMENT '
            '(confidence: adj=${result.adjustmentScore.toStringAsFixed(2)}, '
            'new=${result.newSceneScore.toStringAsFixed(2)})');
        buf.writeln('- CRITICAL: This is an adjustment to the CURRENT scene.');
        buf.writeln('  Preserve ALL parameters the user did NOT mention.');
        buf.writeln('  Only modify the specific parameter(s) they referenced.');
        buf.writeln('  Keep the current palette, effect, brightness, and speed '
            'unless the user explicitly asks to change them.');

      case CommandClassification.newScene:
        buf.writeln('- Classification: NEW_SCENE '
            '(confidence: adj=${result.adjustmentScore.toStringAsFixed(2)}, '
            'new=${result.newSceneScore.toStringAsFixed(2)})');
        if (result.matchedFavoriteName != null) {
          buf.writeln(
              '- Matched saved name: "${result.matchedFavoriteName}"');
        }
        buf.writeln('- CRITICAL: Generate a COMPLETELY FRESH palette, effect, '
            'brightness, and speed appropriate to the concept.');
        buf.writeln('  Do NOT carry over any parameters from the current '
            'lighting state unless the user explicitly asks to keep something.');
        buf.writeln('  A new scene means a fresh start.');

      case CommandClassification.ambiguous:
        buf.writeln('- Classification: AMBIGUOUS '
            '(adj=${result.adjustmentScore.toStringAsFixed(2)}, '
            'new=${result.newSceneScore.toStringAsFixed(2)})');
        buf.writeln('- This command is ambiguous — it could be an adjustment '
            'or a new scene request.');
        buf.writeln('- Return TWO suggestions in your response:');
        buf.writeln(
            '  1. An "adjustment" version (current palette preserved, '
            'requested change applied)');
        buf.writeln(
            '  2. A "new scene" version (fresh palette and parameters '
            'for the concept)');
        buf.writeln(
            '- Include both with preview colors so the UI can show them '
            'side by side.');
        buf.writeln(
            '- Use the JSON key "alternatives" as a list of two objects, '
            'each with full wled/colors/effect data.');
    }

    if (result.matchedSignals.isNotEmpty) {
      buf.writeln(
          '- Matched signals: ${result.matchedSignals.take(8).join(", ")}');
    }

    return buf.toString();
  }

  // -----------------------------------------------------------------------
  // Internal helpers
  // -----------------------------------------------------------------------

  /// Check if [text] matches a [SignalEntry].
  static bool _matches(String text, SignalEntry signal) {
    if (signal.isRegex) {
      return RegExp(signal.keyword, caseSensitive: false).hasMatch(text);
    }
    return text.contains(signal.keyword.toLowerCase());
  }

  /// Fuzzy name matching: does [text] contain the lowercase [name]?
  ///
  /// For very short names (≤ 3 chars), require a word boundary to avoid
  /// false positives (e.g., "off" matching "coffee").
  static bool _fuzzyNameMatch(String text, String name) {
    final lowerName = name.toLowerCase().trim();
    if (lowerName.isEmpty) return false;

    if (lowerName.length <= 3) {
      return RegExp('\\b${RegExp.escape(lowerName)}\\b').hasMatch(text);
    }
    return text.contains(lowerName);
  }

  /// Common single-color words (without adjectives like "warm" or "deep").
  static const _singleColors = {
    'red', 'blue', 'green', 'purple', 'pink', 'orange', 'yellow',
    'cyan', 'magenta', 'teal', 'white', 'gold', 'amber', 'indigo',
    'violet', 'coral', 'salmon', 'lime', 'turquoise', 'lavender',
  };

  /// Returns true if the entire input is essentially a single color word.
  static bool _isSingleColorWord(String text) {
    // Strip common filler words
    final stripped = text
        .replaceAll(RegExp(r'\b(set|to|the|lights?|make|it|go)\b'), '')
        .trim();
    return _singleColors.contains(stripped);
  }
}
