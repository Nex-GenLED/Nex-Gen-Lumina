import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/features/ai/lumina_command.dart';
import 'package:nexgen_command/features/ai/lumina_brain.dart';
import 'package:nexgen_command/features/ai/lumina_sheet_controller.dart';
import 'package:nexgen_command/theme.dart';

/// Tier 2 — Cloud AI processor for complex / creative lighting commands.
///
/// Delegates to the existing [LuminaBrain] pipeline which calls a Firebase
/// Cloud Function that proxies to the AI API. The AI receives:
///   - User's zone/segment configuration
///   - Available WLED effects and IDs
///   - Saved scenes and favorites
///   - Current lighting state
///   - Conversation history (last 10 messages)
///
/// The AI returns a response containing:
///   - Verbal text (what Lumina says to the user)
///   - An embedded JSON payload with WLED commands, preview colors, pattern
///     metadata, and optional clarification suggestions.
class CloudAIProcessor {
  /// Process [text] through the cloud AI pipeline and return a structured result.
  ///
  /// Conversation [history] is used for multi-turn context. If the conversation
  /// has an [activePatternContext], refinement mode is used instead.
  static Future<LuminaCommandResult> process(
    WidgetRef ref,
    String text, {
    List<LuminaMessage> history = const [],
    Map<String, dynamic>? activePatternContext,
  }) async {
    try {
      String aiResponse;

      // Use refinement path if there's an active pattern context
      if (activePatternContext != null) {
        aiResponse = await LuminaBrain.chatRefinement(
          ref,
          text,
          currentPattern: activePatternContext,
        );
      } else {
        aiResponse = await LuminaBrain.chat(ref, text);
      }

      return _parseAIResponse(aiResponse, text);
    } catch (e) {
      debugPrint('CloudAIProcessor error: $e');
      return LuminaCommandResult(
        responseText: 'I had trouble processing that. Try saying it differently.',
        clarificationOptions: [
          'Turn on the lights',
          'Set to warm white',
          'Show me something festive',
        ],
        tier: ProcessingTier.cloud,
      );
    }
  }

  /// Parses the raw AI response text into a structured [LuminaCommandResult].
  ///
  /// The AI embeds JSON within its verbal response. We extract that JSON,
  /// pull out the WLED payload, preview colors, pattern metadata, and
  /// clarification options, then return the clean verbal text separately.
  static LuminaCommandResult _parseAIResponse(String response, String rawText) {
    final parsed = _extractJson(response);

    if (parsed == null) {
      // No JSON — pure conversational response
      return LuminaCommandResult(
        responseText: response.trim(),
        tier: ProcessingTier.cloud,
      );
    }

    final obj = parsed.object;

    // Extract WLED payload
    Map<String, dynamic>? wled;
    final candidate = obj['wled'];
    if (candidate is Map<String, dynamic>) {
      wled = candidate;
    } else if (obj.containsKey('seg') ||
        obj.containsKey('on') ||
        obj.containsKey('bri')) {
      wled = obj.cast<String, dynamic>();
    }

    // Extract preview colors
    final previewColors = <Color>[];
    final colorsArray = obj['colors'];
    if (colorsArray is List) {
      for (final c in colorsArray) {
        if (c is Map) {
          final rgb = c['rgb'];
          if (rgb is List && rgb.length >= 3) {
            previewColors.add(Color.fromARGB(
              255,
              (rgb[0] as num).toInt(),
              (rgb[1] as num).toInt(),
              (rgb[2] as num).toInt(),
            ));
          }
        }
      }
    }

    // Fallback: extract colors from wled seg[0].col
    if (previewColors.isEmpty && wled != null) {
      final seg = wled['seg'];
      if (seg is List && seg.isNotEmpty && seg.first is Map) {
        final col = (seg.first as Map)['col'];
        if (col is List) {
          for (final c in col) {
            if (c is List && c.length >= 3) {
              previewColors.add(Color.fromARGB(
                255,
                (c[0] as num).toInt(),
                (c[1] as num).toInt(),
                (c[2] as num).toInt(),
              ));
            }
          }
        }
      }
    }

    if (previewColors.isEmpty) {
      previewColors.addAll(const [NexGenPalette.cyan, Color(0xFF102040)]);
    }

    // Extract clarification options (if the AI provided them)
    final clarificationOptions = <String>[];
    final suggestions = obj['clarification_options'] ?? obj['suggestions'];
    if (suggestions is List) {
      for (final s in suggestions) {
        if (s is String) clarificationOptions.add(s);
      }
    }

    // Clean verbal text: remove JSON substring and code fences
    var verbal = response.trim();
    verbal = verbal.replaceFirst(parsed.substring, '');
    verbal = _cleanText(verbal);
    if (verbal.isEmpty) verbal = 'Done.';

    // Determine command type from parsed data
    LuminaCommandType type = LuminaCommandType.unknown;
    if (wled != null) {
      if (wled.containsKey('seg')) {
        final seg = wled['seg'];
        if (seg is List && seg.isNotEmpty && seg.first is Map) {
          final fx = (seg.first as Map)['fx'];
          type = (fx == 0 || fx == null)
              ? LuminaCommandType.solidColor
              : LuminaCommandType.effect;
        }
      } else if (wled.containsKey('on') && !wled.containsKey('bri')) {
        type = LuminaCommandType.power;
      } else if (wled.containsKey('bri')) {
        type = LuminaCommandType.brightness;
      }
    }

    // Detect intent
    final intent = obj['intent'] as String?;
    if (intent == 'navigation') type = LuminaCommandType.navigate;

    // Build pattern name for the command
    final patternName = obj['patternName'] as String?;

    // Build effect metadata
    String? effectName;
    int? effectId;
    final effectObj = obj['effect'];
    if (effectObj is Map) {
      effectName = effectObj['name'] as String?;
      effectId = (effectObj['id'] as num?)?.toInt();
    }

    // Determine confidence (cloud results are always accepted)
    final confidence = (obj['confidence'] as num?)?.toDouble() ?? 0.90;

    final command = LuminaCommand(
      type: type,
      parameters: {
        if (wled != null) 'wled': wled,
        if (patternName != null) 'patternName': patternName,
        if (effectName != null) 'effectName': effectName,
        if (effectId != null) 'effectId': effectId,
        'previewColors': previewColors,
      },
      confidence: confidence,
      rawText: rawText,
      tier: ProcessingTier.cloud,
    );

    return LuminaCommandResult(
      command: command,
      responseText: verbal,
      wledPayload: wled,
      previewColors: previewColors,
      clarificationOptions: clarificationOptions,
      tier: ProcessingTier.cloud,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static _JsonExtraction? _extractJson(String content) {
    try {
      // Fenced code block
      final fenceMatch =
          RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(content);
      if (fenceMatch != null) {
        final jsonStr = fenceMatch.group(1)!.trim();
        final obj = jsonDecode(jsonStr) as Map<String, dynamic>;
        return _JsonExtraction(object: obj, substring: fenceMatch.group(0)!);
      }
      // Raw JSON object
      final braceStart = content.indexOf('{');
      final braceEnd = content.lastIndexOf('}');
      if (braceStart >= 0 && braceEnd > braceStart) {
        final jsonStr = content.substring(braceStart, braceEnd + 1);
        final obj = jsonDecode(jsonStr) as Map<String, dynamic>;
        return _JsonExtraction(object: obj, substring: jsonStr);
      }
    } catch (_) {}
    return null;
  }

  static String _cleanText(String text) {
    var cleaned = text;
    cleaned = cleaned.replaceAll(RegExp(r'```\w*\s*'), '');
    cleaned = cleaned.replaceAll(RegExp(r'```'), '');
    cleaned = cleaned.replaceAll(RegExp(r"'''\w*\s*"), '');
    cleaned = cleaned.replaceAll(RegExp(r"'''"), '');
    cleaned = cleaned.replaceAll(RegExp(r'\n\s*\n'), '\n');
    return cleaned.trim();
  }
}

class _JsonExtraction {
  final Map<String, dynamic> object;
  final String substring;
  const _JsonExtraction({required this.object, required this.substring});
}
