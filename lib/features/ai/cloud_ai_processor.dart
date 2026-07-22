import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/features/ai/lumina_command.dart';
import 'package:nexgen_command/features/ai/lumina_brain.dart';
import 'package:nexgen_command/features/ai/scheduling_intent.dart';
import 'package:nexgen_command/features/ai/lumina_sheet_controller.dart';
import 'package:nexgen_command/lumina_ai/lumina_ai_service.dart'
    show LuminaResponseTruncatedException;
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
    } on LuminaResponseTruncatedException {
      // Truncation safety net (Layer 1): the reply overran the token cap and
      // its body is a partial, unbalanced payload. Never parse or post it —
      // surface a friendly, actionable message and return a result with NO
      // wledPayload and NO scheduling intents, so the UI shows clean prose and
      // creates no phantom schedule. Mirrors 2B: never present output that
      // outran a clean parse.
      debugPrint(
          'CloudAIProcessor: response truncated at token cap — friendly message, no payload');
      return const LuminaCommandResult(
        responseText:
            'That request was a bit much for me to set up in one go — '
            'try fewer days or designs and I\'ll get it.',
        tier: ProcessingTier.cloud,
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint('LuminaBrain.chat Firebase error: ${e.code} - ${e.message}');
      final message = switch (e.code) {
        'resource-exhausted' =>
            'You\'ve reached the hourly AI limit. Try again in an hour.',
        'unauthenticated' =>
            'Please sign out and sign back in to use Lumina AI.',
        'internal' =>
            'Lumina AI is temporarily unavailable. Try again shortly.',
        _ =>
            'I\'m having trouble connecting right now. Check your connection and try again.',
      };
      return LuminaCommandResult(
        responseText: message,
        tier: ProcessingTier.cloud,
      );
    } catch (e) {
      debugPrint('LuminaBrain.chat error type: ${e.runtimeType}');
      debugPrint('LuminaBrain.chat error detail: $e');
      return LuminaCommandResult(
        responseText:
            "I'm having trouble connecting right now. Check your connection and try again.",
        clarificationOptions: [
          'Turn on the lights',
          'Set to warm white',
          'Show me something festive',
        ],
        tier: ProcessingTier.cloud,
      );
    }
  }

  /// Test seam over [_parseAIResponse] — the pure raw-string → result parser.
  /// Lets the truncation safety net be proven with a forced-truncation input
  /// (an unbalanced/cut-off body) without standing up Firebase/Riverpod: a
  /// truncated string must yield NO wledPayload (no schedule), NO raw JSON in
  /// [LuminaCommandResult.responseText], and must not masquerade as a clean
  /// success. Genuine max_tokens truncation is caught upstream (Layer 1); this
  /// seam exercises Layer 3's defense-in-depth for unflagged malformed bodies.
  @visibleForTesting
  static LuminaCommandResult parseAiResponseForTest(
          String response, String rawText) =>
      _parseAIResponse(response, rawText);

  /// Parses the raw AI response text into a structured [LuminaCommandResult].
  ///
  /// The AI embeds JSON within its verbal response. We extract that JSON,
  /// pull out the WLED payload, preview colors, pattern metadata, and
  /// clarification options, then return the clean verbal text separately.
  static LuminaCommandResult _parseAIResponse(String response, String rawText) {
    final parsed = _extractJson(response);

    if (parsed == null) {
      // `_extractJson` returned null for one of TWO very different reasons —
      // and the truncation safety net (Layer 3) requires telling them apart:
      //
      //   (a) CLEAN conversational reply — no JSON at all (an unknown-entity
      //       color guess, a brainstorm, a clarifying question). This is an
      //       ordinary success: show the prose, no apply card.
      //   (b) PARSE FAILURE — the model embedded a WLED payload that failed to
      //       jsonDecode (trailing comma, unbalanced/truncated braces, prose
      //       braces widening the first-{…last-} span). This must NOT
      //       masquerade as a clean success: the raw payload must never reach
      //       the bubble, and an empty scrub must not show the success-toned
      //       "Done." over a reply where nothing actually happened.
      //
      // Genuine max_tokens truncation is already caught upstream (Layer 1) as
      // LuminaResponseTruncatedException and never reaches here; this branch
      // is the defense-in-depth for malformed-but-not-flagged payloads.
      //
      // stripJsonForDisplay scrubs balanced JSON blocks AND (Layer 3a) strips
      // an unbalanced trailing block to end-of-string, so raw JSON can never
      // leak regardless of which case this is. In both cases wledPayload stays
      // null → no schedule, no apply card.
      final scrubbed = stripJsonForDisplay(response);
      final parseFailed = _containedJsonAttempt(response);
      if (parseFailed) {
        return LuminaCommandResult(
          responseText: scrubbed.isNotEmpty
              ? scrubbed
              : "That didn't come through cleanly — mind trying that again?",
          tier: ProcessingTier.cloud,
        );
      }
      return LuminaCommandResult(
        responseText: scrubbed.isEmpty ? 'Done.' : scrubbed,
        tier: ProcessingTier.cloud,
      );
    }

    final obj = parsed.object;

    // Normalize the AI's scheduling-intent field(s) into a single canonical
    // List<Map> form. The cloud schema accepts BOTH:
    //   • `schedulingIntent` (singular Map|null) — original shape
    //   • `schedulingIntents` (array of Maps|null) — Item #51 compound-schedule
    //     support
    // Compound responses use the array. Single-schedule responses keep using
    // the singular form (prompt forbids emitting both). Whichever shape the
    // model returns, the handler downstream reads ONE canonical key —
    // `schedulingIntents` as a List<Map<String, dynamic>>. The singular-input
    // path is wrapped into a one-element list inside normalizeSchedulingIntents.
    // Drop malformed entries defensively — never throw on a bad model response.
    final normalizedIntents = normalizeSchedulingIntents(obj);

    // Extract WLED payload
    Map<String, dynamic>? wled;
    final candidate = obj['wled'];
    if (candidate is Map<String, dynamic>) {
      // Merge rich metadata into the WLED payload so downstream
      // _extractPreview() can find patternName, colors, and effect info.
      wled = {
        ...candidate,
        if (obj['patternName'] != null) 'patternName': obj['patternName'],
        if (obj['colors'] != null) 'colors': obj['colors'],
        if (obj['effect'] != null) 'effect': obj['effect'],
        if (obj['speed'] != null && !candidate.containsKey('speed'))
          'speed': obj['speed'],
        if (obj['intensity'] != null && !candidate.containsKey('intensity'))
          'intensity': obj['intensity'],
        // Canonical normalized list — present when the model emitted EITHER
        // shape. The handler reads only this key; the legacy singular
        // passthrough was retired in Item #51 Type-A completion.
        if (normalizedIntents != null) 'schedulingIntents': normalizedIntents,
      };
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

    // Clean verbal text: remove the extracted JSON substring, then defensively
    // scrub any *other* JSON-object block the span-extractor may have missed
    // (e.g. the model emitted two objects, or extra prose-wrapped JSON). The
    // payload itself lives in `wled` above — it is never sourced from `verbal`,
    // so scrubbing the display text cannot affect what gets applied to lights.
    var verbal = response.trim();
    verbal = verbal.replaceFirst(parsed.substring, '');
    verbal = stripJsonForDisplay(verbal);
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

    // Extract ephemeral session intent (Item #51). Item #51 Prompt 3 will
    // wire this into EphemeralGameSessionService; for now we surface it on
    // the result and log so end-to-end JSON shape can be verified.
    Map<String, dynamic>? ephemeralSession;
    final ephemeralRaw = obj['ephemeralSession'];
    if (ephemeralRaw is Map) {
      ephemeralSession = Map<String, dynamic>.from(ephemeralRaw);
      debugPrint('[Lumina AI] Ephemeral session intent received: $ephemeralSession');
    }

    // Extract recurring sports-autopilot rule. Emitted for "every game / all
    // season" team requests — a COMPACT rule (team slug + optional untilDate)
    // that the app routes to the existing Game Day Autopilot enable path,
    // instead of enumerating ~80 game dates (which truncates the response).
    Map<String, dynamic>? recurringSportsAutopilot;
    final recurringRaw = obj['recurringSportsAutopilot'];
    if (recurringRaw is Map) {
      recurringSportsAutopilot = Map<String, dynamic>.from(recurringRaw);
      debugPrint(
          '[Lumina AI] Recurring sports autopilot intent received: $recurringSportsAutopilot');
    }

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
      ephemeralSession: ephemeralSession,
      recurringSportsAutopilot: recurringSportsAutopilot,
      // Carry the normalized intents on the typed field INDEPENDENT of the
      // wled branch above (#58b). The in-wled mirror at the attach junction
      // (:193) is only populated when wled is a Map; this field is the
      // canonical carrier so intents survive a null/absent top-level wled.
      schedulingIntents: normalizedIntents,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Normalize the AI's scheduling-intent shape into a canonical
  /// List<SchedulingIntent>.
  ///
  /// Resolution order:
  ///   1. `schedulingIntents` is a List → keep Map elements, parse each
  ///      through [SchedulingIntent.fromJson], drop non-Map junk. Return the
  ///      parsed list (possibly empty → return null if every entry was
  ///      malformed, so the bag-assembly omits the key entirely).
  ///   2. `schedulingIntent` is a Map → wrap as `[SchedulingIntent.fromJson]`.
  ///   3. Neither field present (or both null) → return null.
  ///
  /// Defensive: never throws. The model occasionally returns a stray
  /// `false` or `"none"` for these fields; we silently coerce to "no
  /// intents present" rather than crashing the entire response pipeline.
  /// `SchedulingIntent.fromJson` is itself tolerant at the field level, so a
  /// well-formed Map with garbage field values parses to defaults rather than
  /// throwing.
  @visibleForTesting
  static List<SchedulingIntent>? normalizeSchedulingIntents(
      Map<String, dynamic> obj) {
    final arr = obj['schedulingIntents'];
    if (arr is List) {
      final filtered = <SchedulingIntent>[];
      for (final entry in arr) {
        if (entry is Map) {
          filtered.add(
              SchedulingIntent.fromJson(Map<String, dynamic>.from(entry)));
        }
      }
      return filtered.isEmpty ? null : filtered;
    }
    final single = obj['schedulingIntent'];
    if (single is Map) {
      return [SchedulingIntent.fromJson(Map<String, dynamic>.from(single))];
    }
    return null;
  }

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
    } catch (e) {
      debugPrint('Error in _extractJson: $e');
    }
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

  /// Removes any embedded JSON payload from text destined for the chat bubble.
  ///
  /// Lumina's transport returns prose with the WLED JSON appended (or fenced).
  /// The payload is extracted separately for the apply-to-device path; this
  /// function exists purely to guarantee that the *display* text never carries
  /// the raw, proprietary payload — even when the payload was malformed enough
  /// to defeat [_extractJson] (the leak in the `parsed == null` fallback).
  ///
  /// It strips balanced `{…}` blocks that look like JSON objects (i.e. contain
  /// a `"key":` pair) and any leftover code-fence markers. Prose braces with no
  /// quoted-key pattern (e.g. "a 2:1 ratio {roughly}") are preserved, so plain
  /// conversational replies pass through untouched.
  @visibleForTesting
  static String stripJsonForDisplay(String text) {
    var cleaned = _cleanText(_stripJsonObjects(text));
    // Collapse the gap left where a JSON block sat between two prose fragments
    // (e.g. "Done! {…} Enjoy!" → "Done!  Enjoy!" → "Done! Enjoy!").
    cleaned = cleaned.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r' +\n'), '\n');
    cleaned = cleaned.replaceAll(RegExp(r'\n +'), '\n');
    return cleaned.trim();
  }

  /// Walks [text] and drops every balanced top-level `{…}` block that looks
  /// like a JSON object. Brace matching is string-aware so braces inside
  /// quoted values don't throw off the depth count.
  static String _stripJsonObjects(String text) {
    final out = StringBuffer();
    int i = 0;
    while (i < text.length) {
      if (text[i] == '{') {
        final end = _matchingBrace(text, i);
        if (end != -1) {
          final block = text.substring(i, end + 1);
          if (_looksLikeJsonObject(block)) {
            i = end + 1; // skip the entire JSON object
            continue;
          }
        } else {
          // Unbalanced opening brace — no matching close. This is the
          // truncated/cut-off payload that previously LEAKED raw JSON into the
          // bubble (the _matchingBrace == -1 hole). If the remainder looks
          // like a JSON-object attempt (carries a quoted "key":), strip from
          // this brace to end-of-string so a partial payload can NEVER reach
          // the bubble (truncation safety net, Layer 3a). A genuine unbalanced
          // prose brace ("we use { to group") has no "key": pattern and is
          // left untouched.
          if (_looksLikeJsonObject(text.substring(i))) {
            break;
          }
        }
      }
      out.write(text[i]);
      i++;
    }
    return out.toString();
  }

  /// True when [response] contains a JSON-object ATTEMPT: an opening brace
  /// whose remainder carries a quoted `"key":` pair. Used by the parsed==null
  /// branch to tell a PARSE FAILURE (payload present but undecodable —
  /// malformed/unbalanced) apart from a CLEAN conversational reply (no payload
  /// at all). Only the former is a failure. Mirrors [_looksLikeJsonObject]'s
  /// discriminator so the two stay in agreement.
  static bool _containedJsonAttempt(String response) {
    final braceStart = response.indexOf('{');
    if (braceStart < 0) return false;
    return _looksLikeJsonObject(response.substring(braceStart));
  }

  /// Returns the index of the `}` that closes the `{` at [start], or -1 if
  /// unbalanced. Ignores braces and quotes that appear inside JSON strings.
  static int _matchingBrace(String text, int start) {
    int depth = 0;
    bool inString = false;
    bool escaped = false;
    for (int i = start; i < text.length; i++) {
      final ch = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch == r'\') {
          escaped = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }
      if (ch == '"') {
        inString = true;
      } else if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  /// A block "looks like" a JSON object when it contains at least one quoted
  /// key followed by a colon — the discriminator that separates a real payload
  /// from incidental prose braces.
  static bool _looksLikeJsonObject(String block) {
    return RegExp(r'"[^"]*"\s*:').hasMatch(block);
  }
}

class _JsonExtraction {
  final Map<String, dynamic> object;
  final String substring;
  const _JsonExtraction({required this.object, required this.substring});
}
