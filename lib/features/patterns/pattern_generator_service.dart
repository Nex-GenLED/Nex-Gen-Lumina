import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:nexgen_command/models/smart_pattern.dart';
import 'package:nexgen_command/features/patterns/canonical_palettes.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';

/// Generates WLED patterns for a given query by mapping a theme palette to
/// a curated list of effects.
///
/// Uses [CanonicalPalettes] for consistent, deterministic recommendations.
/// The canonical palette is always returned as the primary option, with
/// variations available through style modifiers.
class PatternGenerator {
  /// A curated list of common WLED effects that preserve custom color palettes.
  /// Uses the centralized WledEffectsCatalog for effect data.
  /// NOTE: Rainbow effects are separated because they override any color palette.
  static List<Map<String, dynamic>> get wledEffects {
    return WledEffectsCatalog.curatedEffectIds
        .map((id) => {'id': id, 'name': WledEffectsCatalog.getName(id)})
        .toList();
  }

  /// Get the adjusted speed for a specific effect.
  /// Uses the centralized speed multipliers from WledEffectsCatalog.
  static int getAdjustedSpeed(int effectId, int baseSpeed) {
    return WledEffectsCatalog.getAdjustedSpeed(effectId, baseSpeed);
  }

  /// Rainbow effects that override color palettes with rainbow colors.
  /// Only use these when user explicitly requests rainbow/multicolor effects.
  static List<Map<String, dynamic>> get rainbowEffects {
    return WledEffectsCatalog.rainbowEffectIds
        .map((id) => {'id': id, 'name': WledEffectsCatalog.getName(id)})
        .toList();
  }

  /// Keywords that indicate user wants rainbow effects
  static const List<String> rainbowKeywords = [
    'rainbow', 'multicolor', 'multi-color', 'all colors', 'colorful',
    'spectrum', 'pride colors', 'lgbtq', 'gay pride',
  ];

  /// Generate SmartPattern suggestions using canonical palettes for consistency.
  ///
  /// The canonical palette is always the primary recommendation. Use [style]
  /// to request a specific variation (subtle, bold, vintage, etc.).
  ///
  /// Parameters:
  /// - [query]: Search term (e.g., "4th of july", "chiefs", "ocean")
  /// - [style]: Optional style variation (defaults to classic/canonical)
  /// - [includeVariations]: If true, includes patterns for all style variations
  /// - [limitEffects]: If > 0, limits the number of effects returned
  List<SmartPattern> generatePatterns(
    String query, {
    ThemeStyle style = ThemeStyle.classic,
    bool includeVariations = false,
    int limitEffects = 0,
  }) {
    final q = query.trim().toLowerCase();
    debugPrint('PatternGenerator: generatePatterns called with q="$q"');

    // 1) Try to find a canonical theme first
    final canonicalResult = CanonicalPalettes.getPalette(q, style: style);
    debugPrint('PatternGenerator: canonicalResult=${canonicalResult?.theme.displayName ?? "null"}');

    String displayKey;
    List<List<int>> resolvedPalette;
    int defaultSpeed;
    int defaultIntensity;
    List<int> suggestedEffects;

    if (canonicalResult != null) {
      // Use canonical theme - consistent and deterministic
      displayKey = canonicalResult.theme.displayName;
      resolvedPalette = canonicalResult.colors;
      defaultSpeed = canonicalResult.theme.defaultSpeed;
      defaultIntensity = canonicalResult.theme.defaultIntensity;
      suggestedEffects = canonicalResult.theme.suggestedEffects;
    } else {
      // Fallback to random palette for unknown queries
      displayKey = q.isEmpty ? 'Custom' : _capitalizeFirst(q);
      resolvedPalette = _randomPalette(3);
      defaultSpeed = 128;
      defaultIntensity = 128;
      suggestedEffects = [];
    }

    // 2) Check if this is a rainbow-related query
    final isRainbowQuery = rainbowKeywords.any((kw) => q.contains(kw));

    // 3) Determine which effects to use
    // Combine base effects with rainbow effects ONLY if user wants rainbow
    final allAvailableEffects = isRainbowQuery
        ? [...wledEffects, ...rainbowEffects]
        : wledEffects;

    List<Map<String, dynamic>> effectsToUse;
    if (suggestedEffects.isNotEmpty) {
      // Filter suggested effects to only include those from available effects
      // (this prevents rainbow effects from being suggested for non-rainbow themes)
      final availableIds = allAvailableEffects.map((e) => e['id'] as int).toSet();
      final filteredSuggested = suggestedEffects.where((id) => availableIds.contains(id)).toList();

      // Put suggested effects first, then add others
      final suggested = filteredSuggested
          .map((id) => allAvailableEffects.firstWhere(
                (e) => e['id'] == id,
                orElse: () => {'id': id, 'name': 'Effect $id'},
              ))
          .toList();
      final others = allAvailableEffects.where((e) => !filteredSuggested.contains(e['id'])).toList();
      effectsToUse = [...suggested, ...others];
    } else {
      effectsToUse = allAvailableEffects.toList();
    }

    // Apply limit if specified
    if (limitEffects > 0 && effectsToUse.length > limitEffects) {
      effectsToUse = effectsToUse.take(limitEffects).toList();
    }

    // 3) Build SmartPattern list
    final List<SmartPattern> out = [];

    // Add patterns for the primary style
    for (final e in effectsToUse) {
      final id = e['id'] as int;
      final name = e['name'] as String;
      final isSuggested = suggestedEffects.contains(id);
      // Apply effect-specific speed adjustment
      final adjustedSpeed = getAdjustedSpeed(id, defaultSpeed);

      out.add(SmartPattern(
        id: _uuidV4(),
        name: '$displayKey $name${isSuggested ? ' ★' : ''}',
        effectId: id,
        colors: resolvedPalette,
        speed: adjustedSpeed,
        intensity: defaultIntensity,
      ));
    }

    // 4) Optionally add variations for other styles
    if (includeVariations && canonicalResult != null) {
      for (final varStyle in ThemeStyle.values) {
        if (varStyle == style) continue; // Skip the primary style

        final varColors = canonicalResult.theme.getRgbForStyle(varStyle);
        if (varColors == resolvedPalette) continue; // Skip if same as primary

        // Add just the top suggested effect for each variation
        final topEffect = effectsToUse.first;
        final topEffectId = topEffect['id'] as int;
        final adjustedSpeed = getAdjustedSpeed(topEffectId, defaultSpeed);
        out.add(SmartPattern(
          id: _uuidV4(),
          name: '$displayKey ${topEffect['name']} (${varStyle.displayName})',
          effectId: topEffectId,
          colors: varColors,
          speed: adjustedSpeed,
          intensity: defaultIntensity,
        ));
      }
    }

    return out;
  }

  /// Generate a single "best match" pattern for quick application.
  /// Uses canonical palette and first suggested effect.
  SmartPattern? generateBestMatch(String query, {ThemeStyle style = ThemeStyle.classic}) {
    final patterns = generatePatterns(query, style: style, limitEffects: 1);
    return patterns.isNotEmpty ? patterns.first : null;
  }

  /// Get all available style variations for a theme.
  /// Returns null if the theme is not found.
  Map<ThemeStyle, List<List<int>>>? getStyleVariations(String query) {
    final theme = CanonicalPalettes.findTheme(query);
    if (theme == null) return null;

    final variations = <ThemeStyle, List<List<int>>>{
      ThemeStyle.classic: theme.canonicalRgb,
    };

    for (final style in ThemeStyle.values) {
      if (style == ThemeStyle.classic) continue;
      final colors = theme.getRgbForStyle(style);
      if (colors != theme.canonicalRgb) {
        variations[style] = colors;
      }
    }

    return variations;
  }

  /// Search for themes matching a query, returning metadata for UI display.
  List<CanonicalTheme> searchThemes(String query, {int limit = 5}) {
    return CanonicalPalettes.searchThemes(query, limit: limit);
  }

  static String _capitalizeFirst(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static List<List<int>> _randomPalette(int n) {
    final r = Random();
    return List<List<int>>.generate(n, (_) => [r.nextInt(256), r.nextInt(256), r.nextInt(256)], growable: false);
  }

  // Simple UUID v4-like generator (sufficient for client-side IDs without package deps)
  static String _uuidV4() {
    final r = Random();
    String hex(int len) => List.generate(len, (_) => r.nextInt(16).toRadixString(16)).join();
    return '${hex(8)}-${hex(4)}-${hex(4)}-${hex(4)}-${hex(12)}';
  }
}
