import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/models/commercial/commercial_brand_profile.dart';
import 'package:nexgen_command/models/commercial/commercial_event.dart';

/// AI service for Sales & Events design suggestions.
///
/// All Anthropic calls go through the Firebase Cloud Function
/// `claudeProxy` (region us-central1) — same proxy used by
/// lib/lumina_ai/lumina_ai_service.dart so the API key never lives in
/// the app. Uses claude-haiku-4-5 because the response is structured
/// JSON with a tight schema; Opus would burn tokens for no quality
/// gain on this kind of constrained output.
///
/// The model is constrained to a known-good set of WLED effects so we
/// never get back rainbow / random effects that wouldn't honor the
/// brand colors.
class EventLuminaService {
  EventLuminaService({FirebaseFunctions? functions})
      : _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseFunctions _functions;

  /// Effect IDs we allow the model to pick from. Same set the Lumina AI
  /// "smart" prompt classifies as color-respecting (lib/lumina_ai/
  /// lumina_ai_service.dart:226-230) — limited to the eight that map
  /// directly to BrandSignature WLED effect ids and to the brand
  /// design generator's solid-pattern variants.
  static const List<int> _allowedEffectIds = [
    0, // Solid
    2, // Breathe
    12, // Fade
    17, // Twinkle
    28, // Chase
    41, // Running
    83, // Solid Pattern (2 colors)
    84, // Solid Pattern Tri (3 colors)
  ];

  /// Generate exactly three distinct lighting design suggestions for
  /// the given event. Throws on empty / malformed model output so the
  /// caller can surface "Try again" UI per the Part-6 error spec.
  Future<List<EventDesignSuggestion>> generateEventDesigns({
    required String eventDescription,
    required EventType eventType,
    required CommercialBrandProfile brand,
  }) async {
    final brandColorsText = brand.colors
        .map((c) => '${c.colorName.isNotEmpty ? c.colorName : c.roleTag}: '
            '#${c.hexCode.toUpperCase()}')
        .join(', ');

    final prompt = _buildPrompt(
      brandName: brand.companyName,
      brandColorsText: brandColorsText,
      eventDescription: eventDescription,
      eventType: eventType,
    );

    final body = {
      'model': 'claude-haiku-4-5-20251001',
      'max_tokens': 1500,
      'temperature': 0.4,
      'system': _systemPrompt,
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
    };

    final callable = _functions.httpsCallable('claudeProxy');
    final result = await callable.call(body);

    final text = _extractText(result.data);
    if (text == null || text.trim().isEmpty) {
      throw const EventLuminaException('Lumina returned an empty response');
    }

    final parsed = _parseSuggestions(text);
    if (parsed.isEmpty) {
      throw const EventLuminaException(
          'Lumina did not return any usable suggestions');
    }
    return parsed;
  }

  // ─── Prompt construction ─────────────────────────────────────────────────

  static const String _systemPrompt =
      'You are an expert lighting designer for commercial businesses. '
      'You design WLED LED lighting that complements the business\'s '
      'brand identity and matches the energy of the event being lit.\n\n'
      'You ALWAYS reply with strict JSON in the exact schema requested. '
      'No prose outside the JSON, no code fences, no commentary.\n\n'
      'You MAY use only these WLED effects (fx ids):\n'
      '  0  = Solid\n'
      '  2  = Breathe\n'
      '  12 = Fade\n'
      '  17 = Twinkle\n'
      '  28 = Chase\n'
      '  41 = Running\n'
      '  83 = Solid Pattern (2 colors)\n'
      '  84 = Solid Pattern Tri (3 colors)\n'
      'Any other fx id is invalid.\n\n'
      'Colors are RGBW arrays [r, g, b, 0]. The white channel is ALWAYS 0 — '
      'the brand hex is the source of truth and the white LED would '
      'desaturate it.';

  String _buildPrompt({
    required String brandName,
    required String brandColorsText,
    required String eventDescription,
    required EventType eventType,
  }) {
    return '''
The business is "$brandName".
Their official brand colors: $brandColorsText.

The event is type "${eventType.displayName}":
"$eventDescription"

Generate exactly THREE distinct lighting design suggestions for this event.

Hard rules:
- Each suggestion MUST use or complement the brand colors above.
- Match the energy level to the event type and description.
- The three suggestions must be visually distinct from each other (do not
  return three variations of the same design).
- Allowed fx ids: 0, 2, 12, 17, 28, 41, 83, 84. No others.
- Colors are RGBW arrays. White channel is always 0.
- Each design must be applicable to a permanent exterior LED roofline.

Return ONLY this JSON object — no code fences, no commentary, no leading
text. The "suggestions" array MUST contain exactly three items:

{
  "suggestions": [
    {
      "name": "Design Name (max 4 words, title case)",
      "description": "One short sentence of designer rationale.",
      "mood": "energetic",
      "wledPayload": {
        "on": true,
        "bri": 255,
        "seg": [{
          "fx": 28,
          "sx": 150,
          "ix": 200,
          "pal": 5,
          "col": [[237, 29, 36, 0], [255, 255, 255, 0]]
        }]
      }
    }
  ]
}
''';
  }

  // ─── Response parsing ────────────────────────────────────────────────────

  String? _extractText(Object? rawData) {
    Map<String, dynamic>? data;
    if (rawData is Map<String, dynamic>) {
      data = rawData;
    } else if (rawData is Map) {
      data = Map<String, dynamic>.from(rawData);
    }
    if (data == null) return null;

    final content = data['content'];
    if (content is List) {
      for (final block in content) {
        final m = block is Map<String, dynamic>
            ? block
            : (block is Map ? Map<String, dynamic>.from(block) : null);
        if (m == null) continue;
        if (m['type'] == 'text' && m['text'] is String) {
          return m['text'] as String;
        }
      }
    }
    return null;
  }

  List<EventDesignSuggestion> _parseSuggestions(String text) {
    final json = _tryDecodeJsonObject(text);
    if (json == null) return const [];

    final suggestions = json['suggestions'];
    if (suggestions is! List) return const [];

    final out = <EventDesignSuggestion>[];
    for (final item in suggestions) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);

      final wledPayload = m['wledPayload'];
      if (wledPayload is! Map) continue;
      final payload = Map<String, dynamic>.from(wledPayload);
      if (!_isValidPayload(payload)) {
        debugPrint('EventLumina: rejected suggestion with invalid payload');
        continue;
      }

      out.add(EventDesignSuggestion(
        name: (m['name'] as String?)?.trim().isNotEmpty == true
            ? (m['name'] as String).trim()
            : 'Untitled Design',
        description: (m['description'] as String?) ?? '',
        mood: (m['mood'] as String?) ?? '',
        wledPayload: payload,
      ));
    }
    return out;
  }

  /// Robust JSON extraction: strips code fences, falls back to scanning
  /// for the outermost balanced object. Mirrors the helper in
  /// lib/lumina_ai/lumina_ai_service.dart so the two AI surfaces parse
  /// model output identically.
  Map<String, dynamic>? _tryDecodeJsonObject(String content) {
    try {
      final obj = jsonDecode(content);
      if (obj is Map<String, dynamic>) return obj;
    } catch (_) {}

    final stripped = content
        .replaceAll(RegExp(r'```json\s*'), '')
        .replaceAll(RegExp(r'```\s*'), '')
        .trim();
    try {
      final obj = jsonDecode(stripped);
      if (obj is Map<String, dynamic>) return obj;
    } catch (_) {}

    final start = stripped.indexOf('{');
    if (start < 0) return null;
    int depth = 0;
    for (int i = start; i < stripped.length; i++) {
      if (stripped[i] == '{') depth++;
      if (stripped[i] == '}') {
        depth--;
        if (depth == 0) {
          try {
            final sub = stripped.substring(start, i + 1);
            final obj = jsonDecode(sub);
            if (obj is Map<String, dynamic>) return obj;
          } catch (_) {}
          break;
        }
      }
    }
    return null;
  }

  /// Validates that a returned `wledPayload` matches the constrained
  /// schema we asked for. Rejects anything with a disallowed fx id or a
  /// missing color array — the create-event UI will silently drop
  /// invalid suggestions and surface only the valid ones.
  bool _isValidPayload(Map<String, dynamic> payload) {
    final seg = payload['seg'];
    if (seg is! List || seg.isEmpty) return false;

    for (final entry in seg) {
      if (entry is! Map) return false;
      final m = Map<String, dynamic>.from(entry);

      final fx = m['fx'];
      if (fx is! num) return false;
      if (!_allowedEffectIds.contains(fx.toInt())) return false;

      final col = m['col'];
      if (col is! List || col.isEmpty) return false;
      for (final c in col) {
        if (c is! List || c.length < 3) return false;
        for (final v in c) {
          if (v is! num) return false;
          final n = v.toInt();
          if (n < 0 || n > 255) return false;
        }
      }
    }
    return true;
  }
}

/// Distinct exception type so the create-event UI can show the
/// "Try Again" button only for AI-side failures (vs network or other
/// transient Functions errors which it also handles).
class EventLuminaException implements Exception {
  const EventLuminaException(this.message);
  final String message;

  @override
  String toString() => 'EventLuminaException: $message';
}

/// Riverpod provider for [EventLuminaService]. Singleton — the
/// underlying FirebaseFunctions instance is itself a singleton.
final eventLuminaServiceProvider = Provider<EventLuminaService>(
  (ref) => EventLuminaService(),
);
