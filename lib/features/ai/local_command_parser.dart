import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/ai/lumina_command.dart';
import 'package:nexgen_command/features/scenes/scene_models.dart';
import 'package:nexgen_command/features/scenes/scene_providers.dart';

/// Tier 1 — Local keyword parser for instant command execution.
///
/// Uses regex and keyword matching to resolve simple, high-confidence commands
/// without any network round-trip. Returns a [LuminaCommand] with a confidence
/// score. Commands with confidence > 0.85 can be executed immediately.
class LocalCommandParser {
  // ---------------------------------------------------------------------------
  // Color name → RGB lookup
  // ---------------------------------------------------------------------------

  static const Map<String, Color> _colorMap = {
    // Primary
    'red': Color(0xFFFF0000),
    'green': Color(0xFF00FF00),
    'blue': Color(0xFF0000FF),
    'yellow': Color(0xFFFFFF00),
    'orange': Color(0xFFFFA500),
    'purple': Color(0xFF8B00FF),
    'violet': Color(0xFF7F00FF),
    'pink': Color(0xFFFF69B4),
    'magenta': Color(0xFFFF00FF),
    'cyan': Color(0xFF00FFFF),
    'teal': Color(0xFF008080),
    'indigo': Color(0xFF4B0082),
    'lime': Color(0xFF32CD32),
    'coral': Color(0xFFFF7F50),
    'salmon': Color(0xFFFA8072),
    'gold': Color(0xFFFFD700),
    'aqua': Color(0xFF00FFFF),
    'navy': Color(0xFF000080),
    'maroon': Color(0xFF800000),
    'olive': Color(0xFF808000),
    // Whites
    'white': Color(0xFFFFFFFF),
    'warm white': Color(0xFFFFF4E0),
    'cool white': Color(0xFFC8DCFF),
    'daylight': Color(0xFFFFFBF0),
    'bright white': Color(0xFFFFFFFF),
    'soft white': Color(0xFFFFE4C4),
    'natural white': Color(0xFFF5F0E8),
    'candlelight': Color(0xFFFFD28E),
    // Seasonal / mood
    'ice blue': Color(0xFF99CCFF),
    'sky blue': Color(0xFF87CEEB),
    'forest green': Color(0xFF228B22),
    'emerald': Color(0xFF50C878),
    'ruby': Color(0xFFE0115F),
    'amber': Color(0xFFFFBF00),
    'lavender': Color(0xFFE6E6FA),
    'mint': Color(0xFF98FF98),
    'peach': Color(0xFFFFDAB9),
  };

  // ---------------------------------------------------------------------------
  // Navigation keyword → route / tab mapping
  // ---------------------------------------------------------------------------

  static const Map<String, Map<String, dynamic>> _navigationMap = {
    'settings': {'route': '/settings', 'tabIndex': 3},
    'system': {'route': '/settings', 'tabIndex': 3},
    'schedule': {'route': null, 'tabIndex': 1},
    'schedules': {'route': null, 'tabIndex': 1},
    'calendar': {'route': null, 'tabIndex': 1},
    'explore': {'route': null, 'tabIndex': 2},
    'patterns': {'route': null, 'tabIndex': 2},
    'library': {'route': null, 'tabIndex': 2},
    'browse': {'route': null, 'tabIndex': 2},
    'home': {'route': null, 'tabIndex': 0},
    'dashboard': {'route': null, 'tabIndex': 0},
    'zones': {'route': '/wled/zones'},
    'scenes': {'route': '/my-scenes'},
    'my scenes': {'route': '/my-scenes'},
    'designs': {'route': '/my-designs'},
    'my designs': {'route': '/my-designs'},
    'design studio': {'route': '/design-studio'},
    'studio': {'route': '/design-studio'},
    'roofline': {'route': '/settings/roofline-editor'},
    'profile': {'route': '/settings/profile'},
  };

  // ---------------------------------------------------------------------------
  // Parse entry point
  // ---------------------------------------------------------------------------

  /// Parses [text] and returns a [LuminaCommand] with confidence score.
  ///
  /// If [savedScenes] is provided, the parser will also try to match against
  /// the user's saved scene names.
  static LuminaCommand parse(String text, {List<Scene>? savedScenes}) {
    final input = text.trim().toLowerCase();
    if (input.isEmpty) {
      return LuminaCommand(
        type: LuminaCommandType.unknown,
        parameters: {},
        confidence: 0.0,
        rawText: text,
      );
    }

    // Try each parser in priority order. Return the first high-confidence match.
    final parsers = [
      () => _parsePower(input, text),
      () => _parseBrightness(input, text),
      () => _parseNavigation(input, text),
      () => _parseSolidColor(input, text),
      () => _parseScene(input, text, savedScenes),
    ];

    LuminaCommand? best;
    for (final parser in parsers) {
      final result = parser();
      if (result != null) {
        if (best == null || result.confidence > best.confidence) {
          best = result;
        }
        // Short-circuit on very high confidence
        if (best.confidence >= 0.95) return best;
      }
    }

    return best ??
        LuminaCommand(
          type: LuminaCommandType.unknown,
          parameters: {},
          confidence: 0.0,
          rawText: text,
        );
  }

  // ---------------------------------------------------------------------------
  // Power
  // ---------------------------------------------------------------------------

  static final _powerOnPatterns = [
    RegExp(r'^(turn\s+)?on$'),
    RegExp(r'^lights?\s+on$'),
    RegExp(r'^turn\s+(the\s+)?lights?\s+on$'),
    RegExp(r'^power\s+on$'),
    RegExp(r'^switch\s+on$'),
    RegExp(r'^enable\s+lights?$'),
  ];

  static final _powerOffPatterns = [
    RegExp(r'^(turn\s+)?off$'),
    RegExp(r'^lights?\s+off$'),
    RegExp(r'^turn\s+(the\s+)?lights?\s+off$'),
    RegExp(r'^power\s+off$'),
    RegExp(r'^switch\s+off$'),
    RegExp(r'^disable\s+lights?$'),
    RegExp(r'^kill\s+(the\s+)?lights?$'),
    RegExp(r'^lights?\s+out$'),
    RegExp(r'^shut\s+(it\s+)?off$'),
    RegExp(r'^goodnight$'),
    RegExp(r'^good\s+night$'),
  ];

  static LuminaCommand? _parsePower(String input, String raw) {
    for (final p in _powerOnPatterns) {
      if (p.hasMatch(input)) {
        return LuminaCommand(
          type: LuminaCommandType.power,
          parameters: {'on': true},
          confidence: 0.98,
          rawText: raw,
        );
      }
    }
    for (final p in _powerOffPatterns) {
      if (p.hasMatch(input)) {
        return LuminaCommand(
          type: LuminaCommandType.power,
          parameters: {'on': false},
          confidence: 0.98,
          rawText: raw,
        );
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Brightness
  // ---------------------------------------------------------------------------

  static LuminaCommand? _parseBrightness(String input, String raw) {
    // "X percent" or "X%" — absolute
    final percentMatch =
        RegExp(r'(\d{1,3})\s*(%|percent)').firstMatch(input);
    if (percentMatch != null) {
      final pct = int.tryParse(percentMatch.group(1)!) ?? -1;
      if (pct >= 0 && pct <= 100) {
        return LuminaCommand(
          type: LuminaCommandType.brightness,
          parameters: {
            'brightness': (pct / 100 * 255).round().clamp(0, 255),
            'relative': false,
          },
          confidence: 0.95,
          rawText: raw,
        );
      }
    }

    // "set brightness to X"
    final setBriMatch =
        RegExp(r'(?:set\s+)?brightness\s+(?:to\s+)?(\d{1,3})').firstMatch(input);
    if (setBriMatch != null) {
      final val = int.tryParse(setBriMatch.group(1)!) ?? -1;
      if (val >= 0 && val <= 255) {
        return LuminaCommand(
          type: LuminaCommandType.brightness,
          parameters: {'brightness': val, 'relative': false},
          confidence: 0.93,
          rawText: raw,
        );
      }
      // Interpret as percent if <= 100
      if (val > 0 && val <= 100) {
        return LuminaCommand(
          type: LuminaCommandType.brightness,
          parameters: {
            'brightness': (val / 100 * 255).round().clamp(0, 255),
            'relative': false,
          },
          confidence: 0.90,
          rawText: raw,
        );
      }
    }

    // Named levels
    final namedBrightness = <String, int>{
      'full brightness': 255,
      'max brightness': 255,
      'maximum': 255,
      'full': 255,
      'half brightness': 128,
      'half': 128,
      'dim': 50,
      'very dim': 25,
      'night light': 15,
      'nightlight': 15,
      'movie mode': 30,
      'low': 40,
      'medium': 128,
    };

    for (final entry in namedBrightness.entries) {
      if (input == entry.key || input == 'set ${entry.key}') {
        return LuminaCommand(
          type: LuminaCommandType.brightness,
          parameters: {'brightness': entry.value, 'relative': false},
          confidence: 0.93,
          rawText: raw,
        );
      }
    }

    // Relative: "brighter", "darker", "dimmer"
    if (RegExp(r'\b(brighter|bright(?:er)?|increase|raise|up)\b').hasMatch(input) &&
        !RegExp(r'\b(color|red|blue|green|white)\b').hasMatch(input)) {
      return LuminaCommand(
        type: LuminaCommandType.brightness,
        parameters: {'relative': true, 'delta': 30},
        confidence: 0.88,
        rawText: raw,
      );
    }
    if (RegExp(r'\b(darker|dimmer|dim(?:mer)?|decrease|lower|down)\b')
            .hasMatch(input) &&
        !RegExp(r'\b(color|red|blue|green|white)\b').hasMatch(input)) {
      return LuminaCommand(
        type: LuminaCommandType.brightness,
        parameters: {'relative': true, 'delta': -30},
        confidence: 0.88,
        rawText: raw,
      );
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Single solid color
  // ---------------------------------------------------------------------------

  static LuminaCommand? _parseSolidColor(String input, String raw) {
    // Try longest keys first so "warm white" matches before "white"
    final sortedKeys = _colorMap.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final name in sortedKeys) {
      // Match patterns: "red", "set red", "make it red", "turn red",
      // "set lights to red", "change to red"
      final patterns = [
        RegExp('^$name\$'),
        RegExp('^set\\s+(?:it\\s+|lights?\\s+)?(?:to\\s+)?$name\$'),
        RegExp('^(?:make|turn)\\s+(?:it\\s+|them\\s+|lights?\\s+)?$name\$'),
        RegExp('^(?:change|switch)\\s+(?:to\\s+)?$name\$'),
        RegExp('^$name\\s+(?:lights?|color|mode)\$'),
      ];

      for (final p in patterns) {
        if (p.hasMatch(input)) {
          return LuminaCommand(
            type: LuminaCommandType.solidColor,
            parameters: {
              'color': _colorMap[name]!,
              'colorName': name,
            },
            confidence: 0.92,
            rawText: raw,
          );
        }
      }
    }

    // Hex color: "#FF0000" or "hex FF0000"
    final hexMatch =
        RegExp(r'(?:#|hex\s*)([0-9a-fA-F]{6})').firstMatch(input);
    if (hexMatch != null) {
      final hex = hexMatch.group(1)!;
      final color = Color(int.parse('FF$hex', radix: 16));
      return LuminaCommand(
        type: LuminaCommandType.solidColor,
        parameters: {'color': color, 'colorName': '#$hex'},
        confidence: 0.95,
        rawText: raw,
      );
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Saved scenes / favorites
  // ---------------------------------------------------------------------------

  static LuminaCommand? _parseScene(
      String input, String raw, List<Scene>? scenes) {
    if (scenes == null || scenes.isEmpty) return null;

    for (final scene in scenes) {
      final sceneName = scene.name.toLowerCase();
      if (sceneName.isEmpty) continue;

      // Exact match or "run X", "play X", "set X", "activate X"
      final patterns = [
        RegExp('^${RegExp.escape(sceneName)}\$'),
        RegExp('^(?:run|play|set|activate|start|load|apply)\\s+${RegExp.escape(sceneName)}\$'),
        RegExp('^${RegExp.escape(sceneName)}\\s+(?:scene|mode|pattern)\$'),
      ];

      for (final p in patterns) {
        if (p.hasMatch(input)) {
          return LuminaCommand(
            type: LuminaCommandType.scene,
            parameters: {
              'sceneId': scene.id,
              'sceneName': scene.name,
            },
            confidence: 0.93,
            rawText: raw,
          );
        }
      }

      // Fuzzy: scene name contained in input and input is short
      if (input.contains(sceneName) && input.length < sceneName.length + 20) {
        return LuminaCommand(
          type: LuminaCommandType.scene,
          parameters: {
            'sceneId': scene.id,
            'sceneName': scene.name,
          },
          confidence: 0.80,
          rawText: raw,
        );
      }
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  static LuminaCommand? _parseNavigation(String input, String raw) {
    // Sort by longest key first for "my scenes" vs "scenes" priority
    final sortedKeys = _navigationMap.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final key in sortedKeys) {
      final patterns = [
        RegExp('^(?:go\\s+to|open|show|navigate\\s+to|take\\s+me\\s+to)\\s+(?:the\\s+)?$key\$'),
        RegExp('^$key\\s+(?:screen|page|tab|view)\$'),
        RegExp('^show\\s+(?:me\\s+)?(?:the\\s+)?$key\$'),
      ];

      for (final p in patterns) {
        if (p.hasMatch(input)) {
          final nav = _navigationMap[key]!;
          return LuminaCommand(
            type: LuminaCommandType.navigate,
            parameters: {
              if (nav['route'] != null) 'route': nav['route'],
              if (nav['tabIndex'] != null) 'tabIndex': nav['tabIndex'],
            },
            confidence: 0.95,
            rawText: raw,
          );
        }
      }
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Utility: generate WLED payload from a parsed command
  // ---------------------------------------------------------------------------

  /// Converts a [LuminaCommand] into a WLED JSON payload for immediate execution.
  /// Returns null for command types that don't translate to WLED commands
  /// (e.g., navigation).
  static Map<String, dynamic>? toWledPayload(LuminaCommand cmd) {
    switch (cmd.type) {
      case LuminaCommandType.power:
        return {'on': cmd.parameters['on'] as bool};

      case LuminaCommandType.brightness:
        final isRelative = cmd.parameters['relative'] as bool? ?? false;
        if (isRelative) {
          // Relative brightness needs current state — return delta marker
          return {
            'on': true,
            '_relativeBri': cmd.parameters['delta'] as int,
          };
        }
        final bri = cmd.parameters['brightness'] as int;
        return {'on': true, 'bri': bri};

      case LuminaCommandType.solidColor:
        final color = cmd.parameters['color'] as Color;
        final r = (color.r * 255).round();
        final g = (color.g * 255).round();
        final b = (color.b * 255).round();
        return {
          'on': true,
          'seg': [
            {
              'fx': 0,
              'col': [
                [r, g, b]
              ],
            }
          ],
        };

      case LuminaCommandType.effect:
        final effectId = cmd.parameters['effectId'] as int;
        final payload = <String, dynamic>{
          'on': true,
          'seg': [
            {'fx': effectId}
          ],
        };
        if (cmd.parameters['speed'] != null) {
          (payload['seg'] as List).first['sx'] = cmd.parameters['speed'];
        }
        if (cmd.parameters['intensity'] != null) {
          (payload['seg'] as List).first['ix'] = cmd.parameters['intensity'];
        }
        return payload;

      case LuminaCommandType.scene:
      case LuminaCommandType.navigate:
      case LuminaCommandType.unknown:
        return null;
    }
  }

  /// Human-readable response text for a locally-parsed command.
  static String responseText(LuminaCommand cmd) {
    switch (cmd.type) {
      case LuminaCommandType.power:
        return cmd.parameters['on'] == true
            ? 'Turning your lights on.'
            : 'Turning your lights off.';

      case LuminaCommandType.brightness:
        final isRelative = cmd.parameters['relative'] as bool? ?? false;
        if (isRelative) {
          final delta = cmd.parameters['delta'] as int;
          return delta > 0
              ? 'Increasing brightness.'
              : 'Decreasing brightness.';
        }
        final bri = cmd.parameters['brightness'] as int;
        final pct = (bri / 255 * 100).round();
        return 'Setting brightness to $pct%.';

      case LuminaCommandType.solidColor:
        final name = cmd.parameters['colorName'] as String;
        return 'Setting lights to ${name[0].toUpperCase()}${name.substring(1)}.';

      case LuminaCommandType.effect:
        final name = cmd.parameters['effectName'] as String? ?? 'effect';
        return 'Applying $name.';

      case LuminaCommandType.scene:
        final name = cmd.parameters['sceneName'] as String;
        return 'Running $name.';

      case LuminaCommandType.navigate:
        return 'Opening that for you.';

      case LuminaCommandType.unknown:
        return '';
    }
  }
}

/// Riverpod provider that exposes a pre-built [LocalCommandParser.parse]
/// function with the user's saved scenes already injected.
final localCommandParserProvider = Provider<LuminaCommand Function(String)>((ref) {
  final scenesAsync = ref.watch(allScenesProvider);
  final scenes = scenesAsync.whenOrNull(data: (s) => s);

  return (text) => LocalCommandParser.parse(text, savedScenes: scenes);
});
