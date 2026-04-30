import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/features/ai/lumina_command.dart';
import 'package:nexgen_command/features/ai/local_command_parser.dart';
import 'package:nexgen_command/features/ai/cloud_ai_processor.dart';
import 'package:nexgen_command/features/ai/lumina_sheet_controller.dart';
import 'package:nexgen_command/features/ai/lumina_defaults_engine.dart';
import 'package:nexgen_command/features/ai/command_intent_classifier.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/scenes/scene_providers.dart';

/// The most recent enriched suggestion produced by [LuminaDefaultsEngine].
///
/// Read by `LuminaResponseCard` to show per-parameter confidence indicators.
/// `null` when no enrichment has been performed yet.
final latestEnrichedSuggestionProvider =
    StateProvider<EnrichedSuggestion?>((ref) => null);

/// Two-tier command router for the Lumina voice assistant.
///
/// Processing flow:
///  1. Run the [LocalCommandParser] (Tier 1) for instant keyword matching.
///  2. If confidence > 0.85, execute locally and return immediately.
///  3. Otherwise, send to [CloudAIProcessor] (Tier 2) for AI interpretation.
///  4. If cloud processing fails, fall back to partial Tier 1 results with
///     suggested clarification chips.
class LuminaCommandRouter {
  /// Route [text] through the two-tier pipeline and return a result.
  ///
  /// - [ref] is needed for provider access (WLED state, scenes, AI).
  /// - [history] provides conversation context for multi-turn interactions.
  /// - [activePatternContext] triggers refinement mode in Tier 2.
  static Future<LuminaCommandResult> route(
    WidgetRef ref,
    String text, {
    List<LuminaMessage> history = const [],
    Map<String, dynamic>? activePatternContext,
  }) async {
    final stopwatch = Stopwatch()..start();

    // ------------------------------------------------------------------
    // TIER 0 — Conversational short-circuit (no AI call, no quota)
    //
    // Catches "thanks!", "awesome", "hi lumina", etc. so they don't burn
    // claudeProxy quota. Refinement mode skips this — those messages must
    // reach the cloud to update the active pattern.
    // ------------------------------------------------------------------
    if (activePatternContext == null) {
      if (_isConversationalAck(text)) {
        stopwatch.stop();
        debugPrint('💬 Tier 0 ack short-circuit [${stopwatch.elapsedMilliseconds}ms]');
        return _buildAckResult();
      }
      if (_isGreeting(text)) {
        stopwatch.stop();
        debugPrint('💬 Tier 0 greeting short-circuit [${stopwatch.elapsedMilliseconds}ms]');
        return _buildGreetingResult();
      }
    }

    // ------------------------------------------------------------------
    // CLASSIFY — Determine intent (adjustment vs new scene) before routing
    // ------------------------------------------------------------------
    final classification = CommandIntentClassifier.classify(ref, text);
    ref.read(latestClassificationProvider.notifier).state = classification;

    // ------------------------------------------------------------------
    // TIER 1 — Local keyword parser (instant)
    // ------------------------------------------------------------------
    final localParser = ref.read(localCommandParserProvider);
    final localCmd = localParser(text);
    debugPrint(
        '⚡ Tier 1 parse: ${localCmd.type} (confidence: ${localCmd.confidence.toStringAsFixed(2)}) [${stopwatch.elapsedMilliseconds}ms]');

    if (localCmd.isHighConfidence) {
      final localResult = await _executeLocal(ref, localCmd);
      stopwatch.stop();
      debugPrint(
          '✅ Tier 1 executing locally [${stopwatch.elapsedMilliseconds}ms total]');
      return _enrich(ref, localCmd, localResult, text);
    }

    // ------------------------------------------------------------------
    // TIER 2 — Cloud AI processing
    // ------------------------------------------------------------------
    debugPrint('☁️ Tier 1 confidence too low (${localCmd.confidence.toStringAsFixed(2)}), escalating to Tier 2...');

    try {
      final cloudResult = await CloudAIProcessor.process(
        ref,
        text,
        history: history,
        activePatternContext: activePatternContext,
      );
      stopwatch.stop();
      debugPrint(
          '✅ Tier 2 result: ${cloudResult.command?.type ?? "text-only"} [${stopwatch.elapsedMilliseconds}ms total]');
      return _enrich(ref, cloudResult.command, cloudResult, text);
    } catch (e) {
      stopwatch.stop();
      debugPrint('❌ Tier 2 failed: $e [${stopwatch.elapsedMilliseconds}ms]');

      // ------------------------------------------------------------------
      // FALLBACK — Offer best-effort suggestions from partial Tier 1 parsing
      // ------------------------------------------------------------------
      return _buildFallback(localCmd, text);
    }
  }

  // ---------------------------------------------------------------------------
  // Defaults enrichment
  // ---------------------------------------------------------------------------

  /// Enrich a command result with intelligent defaults via [LuminaDefaultsEngine].
  ///
  /// Navigation and power-off commands are passed through without enrichment.
  /// The enriched suggestion is published to [latestEnrichedSuggestionProvider]
  /// so that the UI (response card, adjustment panel) can display per-parameter
  /// confidence indicators.
  static Future<LuminaCommandResult> _enrich(
    WidgetRef ref,
    LuminaCommand? command,
    LuminaCommandResult result,
    String rawQuery,
  ) async {
    // Skip enrichment for navigation, power-off, and text-only results
    if (command == null ||
        command.type == LuminaCommandType.navigate ||
        (command.type == LuminaCommandType.power &&
            command.parameters['on'] == false)) {
      return result;
    }

    try {
      final enriched = await LuminaDefaultsEngine.fillDefaults(
        command: command,
        commandResult: result,
        rawQuery: rawQuery,
        ref: ref,
      );
      ref.read(latestEnrichedSuggestionProvider.notifier).state = enriched;
      debugPrint(
          '🎯 Defaults enriched: confidence=${enriched.confidence.overallConfidence.toStringAsFixed(2)}');
      return result;
    } catch (e) {
      debugPrint('⚠️ Defaults enrichment failed (non-fatal): $e');
      return result;
    }
  }

  // ---------------------------------------------------------------------------
  // Local execution
  // ---------------------------------------------------------------------------

  /// Executes a high-confidence local command and returns a structured result.
  static Future<LuminaCommandResult> _executeLocal(
    WidgetRef ref,
    LuminaCommand cmd,
  ) async {
    final responseText = LocalCommandParser.responseText(cmd);

    // Handle navigation separately (no WLED payload needed)
    if (cmd.type == LuminaCommandType.navigate) {
      return LuminaCommandResult(
        command: cmd,
        responseText: responseText,
        tier: ProcessingTier.local,
      );
    }

    // Handle scene application
    if (cmd.type == LuminaCommandType.scene) {
      return _executeScene(ref, cmd, responseText);
    }

    // Build WLED payload for direct device commands
    Map<String, dynamic>? wled = LocalCommandParser.toWledPayload(cmd);

    // Handle relative brightness
    if (wled != null && wled.containsKey('_relativeBri')) {
      final delta = wled.remove('_relativeBri') as int;
      final currentBri = ref.read(wledStateProvider).brightness;
      final newBri = (currentBri + delta).clamp(5, 255);
      wled = {'on': true, 'bri': newBri};
    }

    // Build preview colors
    List<Color> previewColors = [];
    if (cmd.type == LuminaCommandType.solidColor) {
      final color = cmd.parameters['color'] as Color;
      previewColors = [color];
    }

    return LuminaCommandResult(
      command: cmd,
      responseText: responseText,
      wledPayload: wled,
      previewColors: previewColors,
      tier: ProcessingTier.local,
    );
  }

  /// Executes a saved scene by looking it up and converting to WLED payload.
  static Future<LuminaCommandResult> _executeScene(
    WidgetRef ref,
    LuminaCommand cmd,
    String responseText,
  ) async {
    final sceneId = cmd.parameters['sceneId'] as String;
    final scenesAsync = ref.read(allScenesProvider);

    final scenes = scenesAsync.whenOrNull(data: (s) => s) ?? [];
    final scene = scenes.where((s) => s.id == sceneId).firstOrNull;

    if (scene == null) {
      return LuminaCommandResult(
        command: cmd,
        responseText: 'I couldn\'t find that scene.',
        tier: ProcessingTier.local,
      );
    }

    // Get WLED payload from scene
    Map<String, dynamic>? wled;
    try {
      wled = scene.toWledPayload();
    } catch (e) {
      debugPrint('Scene toWledPayload failed: $e');
    }

    // Get preview colors
    final previewColors = scene.previewColors
        .map((c) => Color.fromARGB(255, c[0], c[1], c[2]))
        .toList();

    return LuminaCommandResult(
      command: cmd,
      responseText: responseText,
      wledPayload: wled,
      previewColors: previewColors,
      tier: ProcessingTier.local,
    );
  }

  // ---------------------------------------------------------------------------
  // Fallback
  // ---------------------------------------------------------------------------

  /// Builds a graceful fallback when both tiers produce incomplete results.
  static LuminaCommandResult _buildFallback(
    LuminaCommand partialCmd,
    String rawText,
  ) {
    // If Tier 1 had any signal, offer related suggestions
    final suggestions = <String>[];

    switch (partialCmd.type) {
      case LuminaCommandType.brightness:
        suggestions.addAll([
          'Set brightness to 50%',
          'Full brightness',
          'Dim the lights',
        ]);
      case LuminaCommandType.solidColor:
        suggestions.addAll([
          'Warm white',
          'Cool white',
          'Set to red',
        ]);
      case LuminaCommandType.power:
        suggestions.addAll([
          'Turn on the lights',
          'Turn off the lights',
        ]);
      default:
        suggestions.addAll([
          'Turn on the lights',
          'Set to warm white',
          'Show me something festive',
          'Surprise me',
        ]);
    }

    return LuminaCommandResult(
      responseText:
          "I didn't quite catch that — try describing the lighting effect or color you have in mind.",
      clarificationOptions: suggestions,
      tier: ProcessingTier.local,
    );
  }

  // ---------------------------------------------------------------------------
  // Tier 0 — Conversational short-circuit
  // ---------------------------------------------------------------------------

  // Single-word acknowledgements (matched whole-word, not substring, so 'ok'
  // doesn't hit inside "look", "block", etc.).
  static const _ackWords = <String>{
    'thank', 'thanks', 'thx', 'ty',
    'awesome', 'great', 'perfect', 'cool', 'nice', 'excellent',
    'amazing', 'wonderful', 'sweet', 'rad', 'lit', 'fire',
    'okay', 'ok', 'good', 'yes', 'yep', 'yeah', 'yup',
  };

  // Multi-word acknowledgements (matched as substrings on the punctuation-
  // stripped lowercase message).
  static const _ackPhrases = <String>[
    'got it', 'love it', 'sounds good', 'thank you', 'thanks so much',
    'appreciate it',
  ];

  // Filler words that may sit alongside ack words without disqualifying the
  // message from being a pure acknowledgement.
  static const _ackFillers = <String>{
    'you', 'it', 'lumina', 'man', 'dude', 'so', 'much', 'a', 'lot', 'really',
    'very', 'that', 'this', 'is',
  };

  // Greeting words (matched whole-word). All other words must be fillers.
  static const _greetingWords = <String>{
    'hi', 'hey', 'hello', 'yo', 'sup', 'howdy',
  };

  // Status-check phrases — short messages where the user is just probing
  // whether Lumina is listening.
  static const _statusPhrases = <String>[
    'are you there', 'you there', 'lumina?', 'hello?', 'still there',
    'you alive',
  ];

  static List<String> _tokens(String prompt) {
    final stripped = prompt.toLowerCase().replaceAll(RegExp(r"[^\w\s']"), ' ');
    return stripped
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
  }

  static bool _isConversationalAck(String prompt) {
    final lower = prompt.trim().toLowerCase();
    if (lower.isEmpty) return false;

    // Multi-word phrase match — short message containing a known phrase.
    final words = _tokens(lower);
    if (words.isEmpty || words.length > 6) return false;
    for (final phrase in _ackPhrases) {
      if (lower.contains(phrase)) return true;
    }

    // Whole-word match — every token must be either an ack word or filler,
    // and at least one must be an ack word.
    bool hasAck = false;
    for (final word in words) {
      if (_ackWords.contains(word)) {
        hasAck = true;
      } else if (!_ackFillers.contains(word)) {
        return false;
      }
    }
    return hasAck;
  }

  static bool _isGreeting(String prompt) {
    final lower = prompt.trim().toLowerCase();
    if (lower.isEmpty) return false;

    final words = _tokens(lower);
    if (words.isEmpty || words.length > 6) return false;

    // Status probes ("are you there?", "lumina?")
    for (final phrase in _statusPhrases) {
      if (lower.contains(phrase)) return true;
    }
    if (words.length == 1 && words.first == 'lumina') return true;

    // Whole-word greeting match — every token must be a greeting or filler.
    bool hasGreeting = false;
    for (final word in words) {
      if (_greetingWords.contains(word)) {
        hasGreeting = true;
      } else if (!_ackFillers.contains(word)) {
        return false;
      }
    }
    return hasGreeting;
  }

  static const _ackResponses = <String>[
    'Glad you like it! Let me know if you want to adjust anything.',
    'Happy to help! Your lights are all set.',
    'Anytime! Let me know when you want to change things up.',
    'Of course! Enjoy the lighting.',
  ];

  static LuminaCommandResult _buildAckResult() {
    final pick = DateTime.now().millisecond % _ackResponses.length;
    return LuminaCommandResult(
      responseText: _ackResponses[pick],
      tier: ProcessingTier.local,
    );
  }

  static LuminaCommandResult _buildGreetingResult() {
    return const LuminaCommandResult(
      responseText: 'Hey! What would you like to do with your lights?',
      tier: ProcessingTier.local,
    );
  }
}
