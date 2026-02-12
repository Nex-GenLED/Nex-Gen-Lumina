import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/features/ai/lumina_command.dart';
import 'package:nexgen_command/features/ai/local_command_parser.dart';
import 'package:nexgen_command/features/ai/cloud_ai_processor.dart';
import 'package:nexgen_command/features/ai/lumina_sheet_controller.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/scenes/scene_providers.dart';

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
    // TIER 1 — Local keyword parser (instant)
    // ------------------------------------------------------------------
    final localParser = ref.read(localCommandParserProvider);
    final localCmd = localParser(text);
    debugPrint(
        '⚡ Tier 1 parse: ${localCmd.type} (confidence: ${localCmd.confidence.toStringAsFixed(2)}) [${stopwatch.elapsedMilliseconds}ms]');

    if (localCmd.isHighConfidence) {
      stopwatch.stop();
      debugPrint(
          '✅ Tier 1 executing locally [${stopwatch.elapsedMilliseconds}ms total]');
      return _executeLocal(ref, localCmd);
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
      return cloudResult;
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
          'I\'m not sure what you meant. Could you try one of these?',
      clarificationOptions: suggestions,
      tier: ProcessingTier.local,
    );
  }
}
