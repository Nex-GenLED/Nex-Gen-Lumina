import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// OpenAI configuration and client for Lumina.
///
/// Uses Firebase Cloud Functions as a proxy to OpenAI API.
/// The function 'openaiProxy' handles authentication and API key management.

class LuminaAI {
  static final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'us-central1');

  /// Sends a standard chat request to Lumina via Firebase Cloud Function.
  /// Returns the assistant's textual response (which may include
  /// a hidden JSON block according to the output rules).
  ///
  /// [contextBlock] can be used to inject dynamic user context into the
  /// system instruction (e.g., location, date, interests, time of day).
  static Future<String> chat(String userPrompt, {String? contextBlock}) async {

    // System instruction per product spec - uses canonical palettes for consistency
    String systemInstruction =
        'You are Lumina, the AI Lighting Controller for Nex-Gen LED. '
        'You are helpful, concise, and enthusiastic.\n\n'
        'Output rules:\n'
        '- If the user asks to change the lights, you MUST include a JSON object in your response alongside a short verbal confirmation.\n'
        '- The JSON must follow this schema: {"patternName": string, "thought": string, "colors": [{"name": string, "rgb": [R,G,B,W]}], "effect": {"name": string, "id": number, "direction": string, "isStatic": boolean}, "speed": number, "intensity": number, "wled": object}.\n'
        '- patternName: A descriptive name for the pattern (e.g., "Chiefs Game Day", "Spooky Halloween", "Warm Relaxation").\n'
        '- colors: Array of color objects with human-readable name and RGBW values. IMPORTANT: For saturated colors (red, green, blue, etc.), always set W=0. Only use W>0 for white tones.\n'
        '- effect: Object with name (e.g., "Chase", "Breathe", "Solid", "Twinkle", "Rainbow"), id (WLED fx number), direction ("left", "right", "center-out", "alternating", "none"), isStatic (true if no movement).\n'
        '- speed: 0-255 where 128 is medium.\n'
        '- intensity: 0-255 where 128 is medium.\n'
        '- The "wled" object must be a valid WLED /json state payload.\n'
        '- Do not explain the JSON. Just include the JSON block hidden within the message text so the app can parse it.\n'
        '- Keep verbal confirmations brief, friendly, and on one line.\n\n'
        'WLED Effect Reference (fx values):\n'
        '- 0: Solid (static, no movement)\n'
        '- 1: Blink\n'
        '- 2: Breathe (smooth fade in/out)\n'
        '- 3: Wipe (one direction sweep)\n'
        '- 12: Theater Chase\n'
        '- 27: Colorful (multi-color shift)\n'
        '- 37: Candle (flickering flame)\n'
        '- 41: Running (smooth chase)\n'
        '- 43: Twinkle\n'
        '- 52: Fireworks\n'
        '- 65: Chase (moving dots)\n'
        '- 70: Twinkle Fox\n'
        '- 72: Sparkle\n'
        '- 77: Meteor\n'
        '- 95: Ripple\n'
        '- 110: Flow\n\n'
        'RAINBOW EFFECTS (ONLY use when user explicitly requests rainbow/multicolor):\n'
        '- 9: Rainbow (overrides colors with rainbow spectrum)\n'
        '- 10: Rainbow Cycle (overrides colors with cycling rainbow)\n'
        '- 38: Chase Rainbow (overrides colors with rainbow chase)\n'
        '- 96: Ripple Rainbow (overrides colors with rainbow ripple)\n'
        'WARNING: These effects IGNORE the color palette and display rainbow colors instead.\n'
        'NEVER use these for holiday themes, sports teams, or any theme with specific colors.\n\n'
        'CANONICAL COLOR PALETTES (ALWAYS use these exact colors as the default - only vary when user explicitly requests something different):\n\n'
        '== HOLIDAYS ==\n'
        '4th of July / Independence Day / Patriotic / USA:\n'
        '  - Old Glory Red [191,10,48,0], White [255,255,255,0], Old Glory Blue [0,40,104,0]\n'
        '  - Default fx: 52 (Fireworks), alt: 41, 12, 43 | speed: 150, intensity: 200\n'
        '  - Aliases: july 4th, independence day, patriotic, usa, american, merica\n\n'
        'Christmas / Holiday:\n'
        '  - Christmas Red [255,0,0,0], Christmas Green [0,255,0,0], Snow White [255,255,255,0]\n'
        '  - Default fx: 12 (Theater Chase), alt: 41, 43, 70 | speed: 100, intensity: 180\n'
        '  - Aliases: xmas, holiday, merry christmas, festive\n\n'
        'Halloween / Spooky:\n'
        '  - Pumpkin Orange [255,102,0,0], Witch Purple [148,0,211,0], Slime Green [57,255,20,0]\n'
        '  - Default fx: 43 (Twinkle), alt: 52, 37, 77 | speed: 80, intensity: 200\n'
        '  - Aliases: spooky, trick or treat, scary, october\n\n'
        'Valentines Day / Romantic:\n'
        '  - Rose Red [255,0,64,0], Blush Pink [255,105,180,0], Soft White [255,240,245,0]\n'
        '  - Default fx: 2 (Breathe), alt: 43, 70, 0 | speed: 60, intensity: 150\n'
        '  - Aliases: valentines, love, romantic, hearts\n\n'
        'St Patricks Day / Irish:\n'
        '  - Shamrock Green [0,158,96,0], Kelly Green [76,187,23,0], Gold [255,215,0,0]\n'
        '  - Default fx: 41 (Running), alt: 12, 43 | speed: 120, intensity: 180\n'
        '  - Aliases: st paddys, irish, lucky, green\n\n'
        'Easter / Spring:\n'
        '  - Easter Pink [255,182,193,0], Easter Yellow [253,253,150,0], Easter Blue [173,216,230,0], Easter Lavender [230,190,255,0]\n'
        '  - Default fx: 2 (Breathe), alt: 43, 70 | speed: 80, intensity: 150\n'
        '  - Aliases: spring, pastel, bunny\n\n'
        'Thanksgiving / Autumn:\n'
        '  - Harvest Orange [255,117,24,0], Cranberry [159,0,63,0], Golden Brown [153,101,21,0]\n'
        '  - Default fx: 37 (Candle), alt: 2, 43 | speed: 60, intensity: 180\n'
        '  - Aliases: fall, autumn, harvest, turkey day\n\n'
        '== SPORTS TEAMS ==\n'
        'Chiefs / Kansas City Chiefs:\n'
        '  - Chiefs Red [227,24,55,0], Chiefs Gold [255,184,28,0]\n'
        '  - Default fx: 9 (Chase), alt: 41, 12, 52 | speed: 150, intensity: 220\n'
        '  - Aliases: kc chiefs, kansas city, arrowhead, mahomes\n\n'
        'Cowboys / Dallas Cowboys:\n'
        '  - Cowboys Blue [0,53,148,0], Cowboys Silver [134,147,151,0], White [255,255,255,0]\n'
        '  - Default fx: 9 (Chase), alt: 41, 12 | speed: 140, intensity: 200\n'
        '  - Aliases: dallas, americas team, dak\n\n'
        'Royals / Kansas City Royals:\n'
        '  - Royals Blue [0,70,135,0], Royals Gold [189,155,96,0]\n'
        '  - Default fx: 41 (Running), alt: 9, 12 | speed: 120, intensity: 180\n'
        '  - Aliases: kc royals, kansas city royals\n\n'
        'Titans / Tennessee Titans:\n'
        '  - Titans Navy [12,35,64,0], Titans Light Blue [75,146,219,0], Titans Red [200,16,46,0]\n'
        '  - Default fx: 9 (Chase), alt: 41 | speed: 140, intensity: 200\n'
        '  - Aliases: tennessee, nashville titans\n\n'
        '== MOODS & THEMES ==\n'
        'Romantic / Date Night:\n'
        '  - Deep Red [139,0,0,0], Soft Pink [255,182,193,0], Warm White [255,200,150,100]\n'
        '  - Default fx: 2 (Breathe), alt: 0, 43 | speed: 40, intensity: 120\n\n'
        'Relaxing / Calm:\n'
        '  - Warm White [255,180,100,200]\n'
        '  - Default fx: 0 (Solid) | speed: 0, intensity: 128\n'
        '  - Aliases: relax, chill, unwind, cozy\n\n'
        'Party / Celebration:\n'
        '  - Hot Pink [255,20,147,0], Electric Blue [0,255,255,0], Lime Green [50,205,50,0], Purple [148,0,211,0]\n'
        '  - Default fx: 52 (Fireworks), alt: 43, 38, 41 | speed: 200, intensity: 255\n'
        '  - Aliases: celebrate, dance, fun, rave\n\n'
        'Ocean / Beach:\n'
        '  - Deep Ocean [0,105,148,0], Seafoam [64,224,208,0], Sandy White [255,245,238,0]\n'
        '  - Default fx: 110 (Flow), alt: 95, 2 | speed: 80, intensity: 180\n'
        '  - Aliases: beach, sea, underwater, aquatic, waves\n\n'
        'Sunset / Golden Hour:\n'
        '  - Sunset Orange [255,107,53,0], Sunset Pink [255,105,180,0], Sunset Purple [139,90,139,0]\n'
        '  - Default fx: 2 (Breathe), alt: 110, 41 | speed: 60, intensity: 150\n'
        '  - Aliases: golden hour, dusk, evening\n\n'
        'Neon / Cyberpunk:\n'
        '  - Neon Pink [255,16,240,0], Neon Blue [0,255,255,0], Neon Green [57,255,20,0]\n'
        '  - Default fx: 41 (Running), alt: 9, 52 | speed: 180, intensity: 255\n'
        '  - Aliases: cyber, synthwave, retro, 80s\n\n'
        'Elegant / Classy:\n'
        '  - Champagne Gold [247,231,206,0], Soft White [255,250,250,0]\n'
        '  - Default fx: 2 (Breathe), alt: 0, 43 | speed: 40, intensity: 100\n'
        '  - Aliases: sophisticated, upscale, fancy, formal\n\n'
        'IMPORTANT CONSISTENCY RULES:\n'
        '- ALWAYS use the exact canonical colors listed above when user requests a theme.\n'
        '- Same query = same colors. "4th of July" always returns [191,10,48], [255,255,255], [0,40,104].\n'
        '- Only introduce variations when user EXPLICITLY requests: "brighter", "more subtle", "different shade", "vintage", "modern", "playful".\n'
        '- If user says "4th of July but more subtle", you may reduce saturation. If they just say "4th of July", use exact canonical colors.\n'
        '- For unknown themes not in the list, you may create reasonable colors, but be consistent if asked again.\n\n'
        'WLED Color Format (RGBW):\n'
        '- Use standard 4-element color arrays [R,G,B,W] in the wled payload. WLED handles any color order conversion internally.\n'
        '- For saturated colors, ALWAYS set W=0 to avoid washing out the color.\n'
        '- Only use W>0 for warm/cool white effects.\n\n'
        'Examples:\n'
        'User: 4th of July\n'
        'Assistant: Happy Independence Day! Here come the red, white, and blue fireworks! {"patternName":"4th of July","thought":"Applying official US flag colors with fireworks effect","colors":[{"name":"Old Glory Red","rgb":[191,10,48,0]},{"name":"White","rgb":[255,255,255,0]},{"name":"Old Glory Blue","rgb":[0,40,104,0]}],"effect":{"name":"Fireworks","id":52,"direction":"center-out","isStatic":false},"speed":150,"intensity":200,"wled":{"on":true,"bri":255,"seg":[{"col":[[191,10,48,0],[255,255,255,0],[0,40,104,0]],"fx":52,"sx":150,"ix":200}]}}\n\n'
        'User: Go Chiefs!\n'
        'Assistant: Chiefs Kingdom! Red and Gold chase coming up! {"patternName":"Chiefs Game Day","thought":"Applying official Chiefs colors with chase effect","colors":[{"name":"Chiefs Red","rgb":[227,24,55,0]},{"name":"Chiefs Gold","rgb":[255,184,28,0]}],"effect":{"name":"Chase","id":9,"direction":"right","isStatic":false},"speed":150,"intensity":220,"wled":{"on":true,"bri":255,"seg":[{"col":[[227,24,55,0],[255,184,28,0]],"fx":9,"sx":150,"ix":220}]}}\n\n'
        'User: Spooky vibes\n'
        'Assistant: Spooky mode activated! {"patternName":"Spooky Halloween","thought":"Halloween palette with twinkle effect","colors":[{"name":"Pumpkin Orange","rgb":[255,102,0,0]},{"name":"Witch Purple","rgb":[148,0,211,0]},{"name":"Slime Green","rgb":[57,255,20,0]}],"effect":{"name":"Twinkle","id":43,"direction":"alternating","isStatic":false},"speed":80,"intensity":200,"wled":{"on":true,"bri":255,"seg":[{"col":[[255,102,0,0],[148,0,211,0],[57,255,20,0]],"fx":43,"sx":80,"ix":200}]}}\n\n'
        'User: Something relaxing\n'
        'Assistant: Time to unwind with warm, static whites. {"patternName":"Warm Relaxation","thought":"Soft warm white for relaxation","colors":[{"name":"Warm White","rgb":[255,180,100,200]}],"effect":{"name":"Solid","id":0,"direction":"none","isStatic":true},"speed":0,"intensity":128,"wled":{"on":true,"bri":180,"seg":[{"col":[[255,180,100,200]],"fx":0}]}}';

    if (contextBlock != null && contextBlock.trim().isNotEmpty) {
      systemInstruction = '$systemInstruction\n\n$contextBlock';
    }

    final body = {
      'model': 'gpt-4o',
      'temperature': 0.5,
      'messages': [
        {
          'role': 'system',
          'content': systemInstruction,
        },
        {
          'role': 'user',
          'content': userPrompt,
        },
      ],
    };

    int attempt = 0;
    while (true) {
      attempt++;
      try {
        // Call Firebase Cloud Function instead of direct OpenAI API
        final callable = _functions.httpsCallable('openaiProxy');
        final result = await callable.call(body);

        final rawData = result.data;
        debugPrint('🤖 Lumina raw response type: ${rawData.runtimeType}');
        debugPrint('🤖 Lumina raw response: $rawData');

        // Handle the response - it may come back in different formats
        Map<String, dynamic>? data;
        if (rawData is Map<String, dynamic>) {
          data = rawData;
        } else if (rawData is Map) {
          data = Map<String, dynamic>.from(rawData);
        }

        if (data == null) {
          throw Exception('OpenAI returned no data');
        }

        try {
          // Try to get choices - may be at root level or nested
          List? choices = data['choices'] as List?;
          debugPrint('🤖 Lumina choices: $choices');

          if (choices == null || choices.isEmpty) {
            // Maybe the entire response IS the message content?
            debugPrint('🤖 No choices found, checking data keys: ${data.keys.toList()}');
          }

          final first = choices != null && choices.isNotEmpty ? choices.first : null;
          debugPrint('🤖 Lumina first choice: $first');

          Map<String, dynamic>? message;
          if (first is Map<String, dynamic>) {
            message = first['message'] as Map<String, dynamic>?;
          } else if (first is Map) {
            final firstMap = Map<String, dynamic>.from(first);
            message = firstMap['message'] is Map ? Map<String, dynamic>.from(firstMap['message']) : null;
          }

          debugPrint('🤖 Lumina message: $message');
          final content = message?['content'] as String?;
          debugPrint('🤖 Lumina content: $content');
          if (content != null && content.trim().isNotEmpty) return content;
        } catch (e, stack) {
          debugPrint('Lumina chat parse error: $e');
          debugPrint('Stack trace: $stack');
        }

        throw Exception('OpenAI chat returned empty message. Raw data keys: ${data.keys.toList()}');
      } on FirebaseFunctionsException catch (e) {
        debugPrint('Lumina Firebase function error: ${e.code} - ${e.message}');
        if (attempt >= 3) {
          throw Exception('Lumina AI failed: ${e.message}');
        }
        await Future.delayed(Duration(milliseconds: 300 * attempt));
      } catch (e) {
        if (attempt >= 3) rethrow;
        await Future.delayed(Duration(milliseconds: 300 * attempt));
      }
    }
  }

  /// Handles refinement requests that modify an existing pattern.
  /// The AI is instructed to ONLY change the specific parameter requested
  /// while preserving all other pattern attributes (colors, effect type, etc.).
  static Future<String> chatRefinement(
    String refinementPrompt, {
    required Map<String, dynamic> currentPattern,
    String? contextBlock,
  }) async {
    // Build a specialized system prompt for refinement
    String systemInstruction =
        'You are Lumina, the AI Lighting Controller for Nex-Gen LED. '
        'You are modifying an EXISTING pattern based on user feedback.\n\n'
        'CRITICAL RULES FOR REFINEMENT:\n'
        '1. You MUST preserve the current pattern\'s colors, effect type, and overall theme.\n'
        '2. ONLY modify the specific parameter the user requested.\n'
        '3. Do NOT interpret refinement as a new search - this is an adjustment to the CURRENT pattern.\n\n'
        'Parameter Mapping:\n'
        '- "slower" / "less movement": DECREASE speed (sx) value by 30-50 points (min 0)\n'
        '- "faster" / "more movement": INCREASE speed (sx) value by 30-50 points (max 255)\n'
        '- "brighter": INCREASE brightness (bri) value by 30-50 (max 255)\n'
        '- "dimmer" / "more subtle": DECREASE brightness (bri) value by 30-50 (min 30)\n'
        '- "warmer": Shift colors toward orange/yellow tones while maintaining the theme\n'
        '- "cooler": Shift colors toward blue tones while maintaining the theme\n'
        '- "different effect": Change ONLY the fx value to a similar effect, keep colors identical\n\n'
        'Output rules:\n'
        '- Include the modified JSON object in your response alongside a short verbal confirmation.\n'
        '- Use the same schema: {"patternName": string, "thought": string, "colors": [...], "effect": {...}, "speed": number, "intensity": number, "wled": object}.\n'
        '- The "wled" object must be a valid WLED /json state payload.\n'
        '- Keep verbal confirmations brief (e.g., "Slowed it down for you!").\n\n'
        'WLED Effect Reference (fx values):\n'
        '- 0: Solid (static, no movement)\n'
        '- 2: Breathe (smooth fade in/out)\n'
        '- 12: Theater Chase\n'
        '- 41: Running (smooth chase)\n'
        '- 43: Twinkle\n'
        '- 52: Fireworks\n'
        '- 65: Chase (moving dots)\n'
        '- 70: Twinkle Fox\n'
        '- 72: Sparkle\n'
        '- 77: Meteor\n'
        '- 95: Ripple\n'
        '- 110: Flow\n\n'
        'WARNING: Do NOT use rainbow effects (9, 10, 38, 96) unless the current pattern is already a rainbow pattern.\n'
        'Rainbow effects override the color palette completely.\n';

    if (contextBlock != null && contextBlock.trim().isNotEmpty) {
      systemInstruction = '$systemInstruction\n\n$contextBlock';
    }

    // Serialize the current pattern for the AI
    final patternJson = jsonEncode(currentPattern);

    final body = {
      'model': 'gpt-4o',
      'temperature': 0.3, // Lower temperature for more predictable refinements
      'messages': [
        {
          'role': 'system',
          'content': systemInstruction,
        },
        {
          'role': 'assistant',
          'content': 'Here is the current pattern that is active on the lights:\n$patternJson',
        },
        {
          'role': 'user',
          'content': refinementPrompt,
        },
      ],
    };

    int attempt = 0;
    while (true) {
      attempt++;
      try {
        final callable = _functions.httpsCallable('openaiProxy');
        final result = await callable.call(body);

        final rawData = result.data;
        debugPrint('🔧 Lumina refinement raw response type: ${rawData.runtimeType}');
        debugPrint('🔧 Lumina refinement raw response: $rawData');

        Map<String, dynamic>? data;
        if (rawData is Map<String, dynamic>) {
          data = rawData;
        } else if (rawData is Map) {
          data = Map<String, dynamic>.from(rawData);
        }

        if (data == null) {
          throw Exception('OpenAI returned no data');
        }

        try {
          List? choices = data['choices'] as List?;
          final first = choices != null && choices.isNotEmpty ? choices.first : null;

          Map<String, dynamic>? message;
          if (first is Map<String, dynamic>) {
            message = first['message'] as Map<String, dynamic>?;
          } else if (first is Map) {
            final firstMap = Map<String, dynamic>.from(first);
            message = firstMap['message'] is Map ? Map<String, dynamic>.from(firstMap['message']) : null;
          }

          final content = message?['content'] as String?;
          debugPrint('🔧 Lumina refinement content: $content');
          if (content != null && content.trim().isNotEmpty) return content;
        } catch (e, stack) {
          debugPrint('Lumina refinement parse error: $e');
          debugPrint('Stack trace: $stack');
        }

        throw Exception('OpenAI refinement returned empty message. Raw data keys: ${data.keys.toList()}');
      } on FirebaseFunctionsException catch (e) {
        debugPrint('Lumina Firebase function error: ${e.code} - ${e.message}');
        if (attempt >= 3) {
          throw Exception('Lumina AI refinement failed: ${e.message}');
        }
        await Future.delayed(Duration(milliseconds: 300 * attempt));
      } catch (e) {
        if (attempt >= 3) rethrow;
        await Future.delayed(Duration(milliseconds: 300 * attempt));
      }
    }
  }

  /// Generates a WLED-compatible JSON payload from a natural language prompt.
  /// Uses JSON response format to ensure valid JSON output.
  /// Same as [chat] but requests structured JSON only. The [contextBlock]
  /// is appended to the system message for better grounding.
  static Future<Map<String, dynamic>> generateWledJson(String userPrompt, {String? contextBlock}) async {
    String system =
        'You are Lumina, an assistant that translates user intents into strict WLED JSON payloads for the /json API. Output ONLY a valid JSON object as the final answer. Do not include code fences or commentary. Ensure the result follows WLED JSON structure. Use standard 4-element RGBW arrays [R,G,B,W]. For red send [[255,0,0,0]], for green send [[0,255,0,0]], for blue send [[0,0,255,0]]. Only use W>0 for warm/cool whites - set W=0 for saturated colors. Example: {"on":true,"bri":128,"seg":[{"id":0,"fx":12,"col":[[255,0,0,0],[0,255,0,0]]}]} (red and green). Prefer fx/pal combinations when effects are requested. The response MUST be a JSON object.';

    if (contextBlock != null && contextBlock.trim().isNotEmpty) {
      system = '$system\n\n$contextBlock';
    }

    final body = {
      'model': 'gpt-4o',
      'response_format': {'type': 'json_object'},
      'temperature': 0.2,
      'messages': [
        {
          'role': 'system',
          'content': system
        },
        {
          'role': 'user',
          'content': userPrompt,
        }
      ],
    };

    int attempt = 0;
    while (true) {
      attempt++;
      try {
        // Call Firebase Cloud Function instead of direct OpenAI API
        final callable = _functions.httpsCallable('openaiProxy');
        final result = await callable.call(body);

        final rawData = result.data;
        debugPrint('🤖 Lumina JSON raw response type: ${rawData.runtimeType}');
        debugPrint('🤖 Lumina JSON raw response: $rawData');

        Map<String, dynamic>? data;
        if (rawData is Map<String, dynamic>) {
          data = rawData;
        } else if (rawData is Map) {
          data = Map<String, dynamic>.from(rawData);
        }

        if (data == null) {
          throw Exception('OpenAI returned no data');
        }

        Map<String, dynamic>? parsed;
        try {
          List? choices = data['choices'] as List?;
          final first = choices != null && choices.isNotEmpty ? choices.first : null;

          Map<String, dynamic>? message;
          if (first is Map<String, dynamic>) {
            message = first['message'] as Map<String, dynamic>?;
          } else if (first is Map) {
            final firstMap = Map<String, dynamic>.from(first);
            message = firstMap['message'] is Map ? Map<String, dynamic>.from(firstMap['message']) : null;
          }

          final content = message?['content'] as String?;
          debugPrint('🤖 Lumina JSON content: $content');
          if (content != null) {
            parsed = _tryParseJsonObject(content);
          }
        } catch (e) {
          debugPrint('Lumina parse root error: $e');
        }

        if (parsed == null) {
          throw Exception('Lumina returned no JSON object.');
        }

        // Basic validation: must look like a WLED payload (on/bri/seg at least)
        if (!parsed.containsKey('on') && !parsed.containsKey('bri') && !parsed.containsKey('seg')) {
          debugPrint('Lumina JSON lacks common WLED keys; proceeding anyway: $parsed');
        }
        return parsed;
      } on FirebaseFunctionsException catch (e) {
        debugPrint('Lumina Firebase function error: ${e.code} - ${e.message}');
        if (attempt >= 3) {
          throw Exception('Lumina AI failed: ${e.message}');
        }
        await Future.delayed(Duration(milliseconds: 300 * attempt));
      } catch (e) {
        if (attempt >= 3) rethrow;
        await Future.delayed(Duration(milliseconds: 300 * attempt));
      }
    }
  }

  static Map<String, dynamic>? _tryParseJsonObject(String content) {
    // Fast path: try direct decode
    try {
      final obj = jsonDecode(content);
      if (obj is Map<String, dynamic>) return obj;
    } catch (_) {}

    // Fallback: extract first JSON object substring
    final maybe = _extractBalancedJsonObject(content);
    if (maybe != null) {
      try {
        final obj = jsonDecode(maybe);
        if (obj is Map<String, dynamic>) return obj;
      } catch (_) {}
    }
    return null;
  }

  /// Extracts the first balanced JSON object substring in [text]. Returns null
  /// if none found.
  static String? _extractBalancedJsonObject(String text) {
    final start = text.indexOf('{');
    if (start < 0) return null;
    int depth = 0;
    for (int i = start; i < text.length; i++) {
      final ch = text[i];
      if (ch == '{') depth++;
      if (ch == '}') {
        depth--;
        if (depth == 0) {
          return text.substring(start, i + 1);
        }
      }
    }
    return null;
  }
}
