import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/features/ai/lumina_command.dart';
import 'package:nexgen_command/features/ai/lumina_lighting_suggestion.dart';
import 'package:nexgen_command/features/ai/light_effect_animator.dart';
import 'package:nexgen_command/features/ai/concept_palette_map.dart';
import 'package:nexgen_command/features/ai/effect_decision_tree.dart';
import 'package:nexgen_command/features/ai/brightness_context_calculator.dart';
import 'package:nexgen_command/features/ai/defaults_learning_tracker.dart';
import 'package:nexgen_command/features/wled/semantic_pattern_matcher.dart';
import 'package:nexgen_command/features/wled/event_theme_library.dart';
import 'package:nexgen_command/features/wled/effect_database.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';
import 'package:nexgen_command/data/sports_teams.dart';
import 'package:nexgen_command/utils/sky_darkness_provider.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';

// ---------------------------------------------------------------------------
// Confidence model
// ---------------------------------------------------------------------------

/// How a parameter's value was determined.
enum ParameterSource {
  /// User explicitly specified this parameter.
  userSpecified,

  /// Inferred from context (time, mood keywords, user profile, etc.).
  contextInferred,

  /// Pure fallback default — no signal available.
  systemDefault,
}

/// Per-parameter confidence for an enriched suggestion.
class DefaultsConfidence {
  final ParameterSource colorsSource;
  final ParameterSource effectSource;
  final ParameterSource brightnessSource;
  final ParameterSource speedSource;
  final ParameterSource zoneSource;

  const DefaultsConfidence({
    this.colorsSource = ParameterSource.systemDefault,
    this.effectSource = ParameterSource.systemDefault,
    this.brightnessSource = ParameterSource.systemDefault,
    this.speedSource = ParameterSource.systemDefault,
    this.zoneSource = ParameterSource.systemDefault,
  });

  /// Weighted average confidence: userSpecified → 1.0, contextInferred → 0.6,
  /// systemDefault → 0.3.
  double get overallConfidence {
    double score = 0;
    for (final s in [
      colorsSource,
      effectSource,
      brightnessSource,
      speedSource,
      zoneSource,
    ]) {
      switch (s) {
        case ParameterSource.userSpecified:
          score += 1.0;
        case ParameterSource.contextInferred:
          score += 0.6;
        case ParameterSource.systemDefault:
          score += 0.3;
      }
    }
    return score / 5;
  }
}

// ---------------------------------------------------------------------------
// Enriched suggestion
// ---------------------------------------------------------------------------

/// A complete [LuminaLightingSuggestion] paired with confidence metadata.
class EnrichedSuggestion {
  final LuminaLightingSuggestion suggestion;
  final DefaultsConfidence confidence;

  const EnrichedSuggestion({
    required this.suggestion,
    required this.confidence,
  });
}

// ---------------------------------------------------------------------------
// Engine
// ---------------------------------------------------------------------------

/// Fills in intelligent defaults for every unspecified lighting parameter.
///
/// Sits between the command parser (Tier 1 / Tier 2) and the final
/// [LuminaLightingSuggestion]. Given whatever the parser extracted, the
/// engine fills every gap using a priority cascade:
///
/// 1. **User-specified** — value came directly from the user's words
/// 2. **Context-inferred** — derived from time of day, mood, user profile
/// 3. **System default** — safe fallback when no signal is available
class LuminaDefaultsEngine {
  LuminaDefaultsEngine._();

  /// Produce a complete suggestion by filling defaults for any missing params.
  static Future<EnrichedSuggestion> fillDefaults({
    required LuminaCommand? command,
    required LuminaCommandResult commandResult,
    required String rawQuery,
    required WidgetRef ref,
  }) async {
    // ---- Context gathering ----
    final analysis = SemanticPatternMatcher.analyzeQuery(rawQuery);

    final skyDarkness = ref.read(currentSkyDarknessProvider);

    final userProfile = ref.read(currentUserProfileProvider).maybeWhen(
          data: (p) => p,
          orElse: () => null,
        );

    // ---- Resolve each parameter ----
    final colorRes = _resolveColors(
      commandResult: commandResult,
      command: command,
      analysis: analysis,
      rawQuery: rawQuery,
    );

    final effectRes = _resolveEffect(
      command: command,
      commandResult: commandResult,
      analysis: analysis,
      hasColors: colorRes.colors.isNotEmpty,
      userPreferredStyles: userProfile?.preferredEffectStyles,
    );

    final brightnessRes = await _resolveBrightness(
      command: command,
      commandResult: commandResult,
      skyDarkness: skyDarkness,
      userProfile: userProfile,
      contentEnergy: analysis.energyLevel,
      ref: ref,
    );

    final speedRes = _resolveSpeed(
      command: command,
      commandResult: commandResult,
      effectId: effectRes.effectInfo.id,
      energy: analysis.energyLevel,
    );

    final zoneRes = _resolveZone(command: command);

    // ---- Build palette info ----
    final paletteInfo = PaletteInfo(
      name: colorRes.paletteName,
      colorNames: colorRes.colorNames,
    );

    // ---- Build WLED payload ----
    final wledPayload = commandResult.wledPayload ?? _buildWledPayload(
      colors: colorRes.colors,
      effectId: effectRes.effectInfo.id,
      brightness: (brightnessRes.brightness * 255).round().clamp(0, 255),
      speed: WledEffectsCatalog.getAdjustedSpeed(
        effectRes.effectInfo.id,
        (speedRes.speed * 255).round(),
      ),
    );

    // ---- Construct suggestion ----
    final suggestion = LuminaLightingSuggestion(
      responseText: commandResult.responseText,
      colors: colorRes.colors,
      palette: paletteInfo,
      effect: effectRes.effectInfo,
      brightness: brightnessRes.brightness,
      speed: effectRes.effectInfo.isStatic ? null : speedRes.speed,
      zone: zoneRes.zone,
      confidence: brightnessRes.source == ParameterSource.userSpecified ? 0.95 : 0.75,
      wledPayload: wledPayload,
    );

    final confidence = DefaultsConfidence(
      colorsSource: colorRes.source,
      effectSource: effectRes.source,
      brightnessSource: brightnessRes.source,
      speedSource: speedRes.source,
      zoneSource: zoneRes.source,
    );

    return EnrichedSuggestion(
      suggestion: suggestion,
      confidence: confidence,
    );
  }

  // =========================================================================
  // Color resolution
  // =========================================================================

  static _ColorResolution _resolveColors({
    required LuminaCommandResult commandResult,
    required LuminaCommand? command,
    required QueryAnalysis analysis,
    required String rawQuery,
  }) {
    // Priority 1: User-specified colors from the command result
    if (commandResult.previewColors.isNotEmpty) {
      return _ColorResolution(
        colors: commandResult.previewColors,
        colorNames: const [],
        paletteName: 'Lumina Palette',
        source: ParameterSource.userSpecified,
      );
    }

    // Priority 1b: Solid color from local parser
    if (command?.type == LuminaCommandType.solidColor) {
      final c = command!.parameters['color'] as Color?;
      final name = command.parameters['colorName'] as String? ?? 'Color';
      if (c != null) {
        return _ColorResolution(
          colors: [c],
          colorNames: [name],
          paletteName: name,
          source: ParameterSource.userSpecified,
        );
      }
    }

    // Priority 2: Sports team match
    final team = SportsTeamsDatabase.findTeamInQuery(rawQuery);
    if (team != null && team.colors.isNotEmpty) {
      return _ColorResolution(
        colors: team.colors,
        colorNames: [team.displayName],
        paletteName: '${team.displayName} Colors',
        source: ParameterSource.contextInferred,
      );
    }

    // Priority 3: Event theme match
    final themeMatch = EventThemeLibrary.matchQuery(rawQuery);
    if (themeMatch != null) {
      final pattern = themeMatch.pattern;
      return _ColorResolution(
        colors: pattern.colors,
        colorNames: pattern.colorNames,
        paletteName: pattern.name,
        source: ParameterSource.contextInferred,
      );
    }

    // Priority 4: Concept palette match
    final concept = ConceptPaletteMap.findForQuery(rawQuery);
    if (concept != null) {
      return _ColorResolution(
        colors: concept.colorValues,
        colorNames: concept.colorNames,
        paletteName: concept.displayName,
        source: ParameterSource.contextInferred,
      );
    }

    // Priority 5: SemanticPatternMatcher color preferences
    if (analysis.hasColorPreferences) {
      return _ColorResolution(
        colors: analysis.colorPreferences,
        colorNames: const [],
        paletteName: 'Custom Palette',
        source: ParameterSource.contextInferred,
      );
    }

    // Priority 6: Mood-based concept palette
    if (analysis.mood != null) {
      final moodPalette = ConceptPaletteMap.findForMood(analysis.mood!);
      if (moodPalette != null) {
        return _ColorResolution(
          colors: moodPalette.colorValues,
          colorNames: moodPalette.colorNames,
          paletteName: moodPalette.displayName,
          source: ParameterSource.contextInferred,
        );
      }
    }

    // Fallback: warm white
    final fallback = ConceptPaletteMap.warmWhiteFallback;
    return _ColorResolution(
      colors: fallback.colorValues,
      colorNames: fallback.colorNames,
      paletteName: fallback.displayName,
      source: ParameterSource.systemDefault,
    );
  }

  // =========================================================================
  // Effect resolution
  // =========================================================================

  static _EffectResolution _resolveEffect({
    required LuminaCommand? command,
    required LuminaCommandResult commandResult,
    required QueryAnalysis analysis,
    required bool hasColors,
    List<String>? userPreferredStyles,
  }) {
    // Priority 1: User explicitly requested an effect
    if (command?.type == LuminaCommandType.effect) {
      final id = command!.parameters['effectId'] as int?;
      if (id != null) {
        final name = command.parameters['effectName'] as String? ??
            EffectDatabase.effects[id]?.name ?? 'Effect $id';
        return _EffectResolution(
          effectInfo: EffectInfo(
            id: id,
            name: name,
            category: effectTypeFromWledId(id),
          ),
          source: ParameterSource.userSpecified,
        );
      }
    }

    // Priority 1b: Effect from WLED payload
    final seg = _firstSeg(commandResult.wledPayload);
    if (seg != null) {
      final fx = (seg['fx'] as num?)?.toInt();
      if (fx != null) {
        final name = EffectDatabase.effects[fx]?.name ?? 'Effect $fx';
        return _EffectResolution(
          effectInfo: EffectInfo(
            id: fx,
            name: name,
            category: effectTypeFromWledId(fx),
          ),
          source: ParameterSource.userSpecified,
        );
      }
    }

    // Priority 2: Event theme match has an effect
    final themeMatch = EventThemeLibrary.matchQuery(analysis.originalQuery);
    if (themeMatch != null) {
      final pattern = themeMatch.pattern;
      return _EffectResolution(
        effectInfo: EffectInfo(
          id: pattern.effectId,
          name: pattern.effectName ?? 'Effect ${pattern.effectId}',
          category: effectTypeFromWledId(pattern.effectId),
        ),
        source: ParameterSource.contextInferred,
      );
    }

    // Priority 3: Decision tree from semantic analysis
    final selection = EffectDecisionTree.selectEffect(
      analysis: analysis,
      hasUserColors: hasColors,
      userPreferredStyles: userPreferredStyles,
    );

    return _EffectResolution(
      effectInfo: selection.effectInfo,
      source: selection.isInferred
          ? ParameterSource.contextInferred
          : ParameterSource.systemDefault,
    );
  }

  // =========================================================================
  // Brightness resolution
  // =========================================================================

  static Future<_BrightnessResolution> _resolveBrightness({
    required LuminaCommand? command,
    required LuminaCommandResult commandResult,
    required double skyDarkness,
    required dynamic userProfile,
    required EnergyLevel? contentEnergy,
    required WidgetRef ref,
  }) async {
    // Priority 1: User explicitly specified brightness
    if (command?.type == LuminaCommandType.brightness) {
      final bri = command!.parameters['brightness'] as int?;
      if (bri != null) {
        return _BrightnessResolution(
          brightness: (bri / 255.0).clamp(0.0, 1.0),
          source: ParameterSource.userSpecified,
        );
      }
    }

    // Priority 1b: Brightness from WLED payload
    final payload = commandResult.wledPayload;
    if (payload != null) {
      final bri = (payload['bri'] as num?)?.toInt();
      if (bri != null) {
        return _BrightnessResolution(
          brightness: (bri / 255.0).clamp(0.0, 1.0),
          source: ParameterSource.userSpecified,
        );
      }
    }

    // Priority 2: Context-aware calculation
    double? vibeLevel;
    int? quietStart;
    int? quietEnd;
    bool hoaCompliance = false;

    if (userProfile != null) {
      vibeLevel = userProfile.vibeLevel as double?;
      quietStart = userProfile.quietHoursStartMinutes as int?;
      quietEnd = userProfile.quietHoursEndMinutes as int?;
      hoaCompliance = (userProfile.hoaComplianceEnabled as bool?) ?? false;
    }

    final rec = BrightnessContextCalculator.calculate(
      skyDarkness: skyDarkness,
      userVibeLevel: vibeLevel,
      quietHoursStart: quietStart,
      quietHoursEnd: quietEnd,
      hoaCompliance: hoaCompliance,
      contentEnergy: contentEnergy,
    );

    // Apply learning bias if tracker is available
    double finalBrightness = rec.brightness;
    final tracker = ref.read(defaultsLearningTrackerProvider);
    if (tracker != null) {
      try {
        final bias = await tracker.getBrightnessBias(
          skyDarkness: skyDarkness,
          hourOfDay: DateTime.now().hour,
        );
        finalBrightness = (finalBrightness * bias).clamp(0.05, 1.0);
      } catch (_) {
        // Learning data unavailable — use unbiased value
      }
    }

    return _BrightnessResolution(
      brightness: finalBrightness,
      source: ParameterSource.contextInferred,
    );
  }

  // =========================================================================
  // Speed resolution
  // =========================================================================

  static _SpeedResolution _resolveSpeed({
    required LuminaCommand? command,
    required LuminaCommandResult commandResult,
    required int effectId,
    required EnergyLevel? energy,
  }) {
    // Priority 1: Speed from WLED payload
    final seg = _firstSeg(commandResult.wledPayload);
    if (seg != null) {
      final sx = (seg['sx'] as num?)?.toInt();
      if (sx != null) {
        return _SpeedResolution(
          speed: (sx / 255.0).clamp(0.0, 1.0),
          source: ParameterSource.userSpecified,
        );
      }
    }

    // Priority 2: Effect metadata default adjusted by energy
    final recommended = EffectDecisionTree.recommendSpeed(effectId, energy);
    return _SpeedResolution(
      speed: recommended,
      source: energy != null
          ? ParameterSource.contextInferred
          : ParameterSource.systemDefault,
    );
  }

  // =========================================================================
  // Zone resolution
  // =========================================================================

  static _ZoneResolution _resolveZone({required LuminaCommand? command}) {
    // Currently only supports the explicit zone specification or fallback
    // to all zones. Future: read user's "default zone" preference.
    return const _ZoneResolution(
      zone: ZoneInfo(name: 'All Zones'),
      source: ParameterSource.systemDefault,
    );
  }

  // =========================================================================
  // WLED payload builder
  // =========================================================================

  static Map<String, dynamic> _buildWledPayload({
    required List<Color> colors,
    required int effectId,
    required int brightness,
    required int speed,
  }) {
    final cols = colors.take(3).map((c) => [
          (c.r * 255).round(),
          (c.g * 255).round(),
          (c.b * 255).round(),
          0,
        ]).toList();
    if (cols.isEmpty) {
      cols.add([255, 255, 255, 0]);
    }

    return {
      'on': true,
      'bri': brightness.clamp(0, 255),
      'seg': [
        {
          'fx': effectId,
          'sx': speed.clamp(0, 255),
          'col': cols,
          'pal': 5, // "Colors Only"
        },
      ],
    };
  }

  // =========================================================================
  // Helpers
  // =========================================================================

  /// Extract the first segment from a WLED payload, if present.
  static Map<String, dynamic>? _firstSeg(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    final wled = payload['wled'] ?? payload;
    final seg = wled['seg'];
    if (seg is List && seg.isNotEmpty && seg.first is Map) {
      return seg.first as Map<String, dynamic>;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Internal resolution types
// ---------------------------------------------------------------------------

class _ColorResolution {
  final List<Color> colors;
  final List<String> colorNames;
  final String paletteName;
  final ParameterSource source;
  const _ColorResolution({
    required this.colors,
    required this.colorNames,
    required this.paletteName,
    required this.source,
  });
}

class _EffectResolution {
  final EffectInfo effectInfo;
  final ParameterSource source;
  const _EffectResolution({required this.effectInfo, required this.source});
}

class _BrightnessResolution {
  final double brightness;
  final ParameterSource source;
  const _BrightnessResolution({required this.brightness, required this.source});
}

class _SpeedResolution {
  final double speed;
  final ParameterSource source;
  const _SpeedResolution({required this.speed, required this.source});
}

class _ZoneResolution {
  final ZoneInfo zone;
  final ParameterSource source;
  const _ZoneResolution({required this.zone, required this.source});
}
