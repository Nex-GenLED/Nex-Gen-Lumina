import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';
import 'package:nexgen_command/openai/openai_config.dart';
import 'package:nexgen_command/features/wled/event_theme_library.dart';
import 'package:nexgen_command/features/wled/semantic_pattern_matcher.dart';
import 'package:nexgen_command/features/ai/suggestion_history.dart';
import 'package:nexgen_command/features/ai/command_intent_classifier.dart';
import 'package:nexgen_command/services/pattern_analytics_service.dart';
import 'package:nexgen_command/data/team_color_database.dart';
import 'package:nexgen_command/data/team_color_resolver.dart';
import 'package:nexgen_command/data/holiday_color_database.dart';
import 'package:nexgen_command/features/wled/wled_service.dart' show rgbToRgbw;
import 'package:nexgen_command/features/ai/compound_command_detector.dart';
import 'package:nexgen_command/features/ai/user_variety_profile.dart';
import 'package:nexgen_command/features/ai/lumina_smart_scheduler.dart';
import 'dart:convert';

/// LuminaBrain aggregates local context (who/where/when) and injects it into
/// every OpenAI request for improved grounding and personalization.
class LuminaBrain {
  /// Sends a conversational request enriched with context.
  /// Three-tier matching system for maximum consistency and scalability:
  /// 1. Check pre-defined theme library (fastest, for common themes)
  /// 2. Check semantic cache (for previously seen queries) - BYPASSED for open-ended queries
  /// 3. Fall back to AI with caching (for new queries)
  ///
  /// For open-ended queries ("surprise me", "give me a party", etc.), we:
  /// - Skip the semantic cache to ensure variety
  /// - Inject recent suggestion history so AI avoids repetition
  /// - Use slightly higher temperature for creativity
  static Future<String> chat(WidgetRef ref, String userPrompt) async {
    final historyService = SuggestionHistoryService.instance;
    final isOpenEnded = SuggestionHistoryService.isOpenEndedQuery(userPrompt);

    if (isOpenEnded) {
      debugPrint('🎲 Open-ended query detected: "$userPrompt" - will ensure variety');
    }

    // ── PRE-TIER: Compound Command Detection ──────────────────────────────
    // Detect and handle commands that combine lighting + scheduling intent
    // BEFORE tier resolution so temporal language doesn't corrupt team/holiday
    // fuzzy matching. e.g. "Royals design every night this week from sunset to sunrise"
    // → lightingIntent="Royals design", temporal=7 days sunset→sunrise
    {
      final compound = CompoundCommandDetector.detect(userPrompt);
      if (compound.isCompound && compound.temporal != null) {
        debugPrint('🗓️ Compound command detected: '
            'lighting="${compound.lightingIntent}", '
            'days=${compound.temporal!.dayCount}, '
            'start=${compound.temporal!.startTrigger.name}');

        final scheduledResponse = await _handleCompoundCommand(
          ref,
          compound,
          historyService,
        );
        if (scheduledResponse != null) return scheduledResponse;

        // If resolution failed, fall through using the original prompt.
        debugPrint('⚠️ Compound resolution failed — falling through to normal tiers');
      }
    }

    // TIER 0.5 (run first): Holiday / season / cultural event resolution
    // Runs before team resolution to prevent holidays like "St. Patrick's" from
    // fuzzy-matching to sports teams (e.g., "patricks" → "patriots").
    {
      final holidayResult = HolidayColorDatabase.resolve(userPrompt);
      if (holidayResult.resolved && holidayResult.confidence >= 0.7) {
        debugPrint('🎄 TIER 0.5: Resolved holiday: ${holidayResult.holiday!.name} '
            'confidence=${holidayResult.confidence.toStringAsFixed(2)}');
        final response = _buildHolidayResponse(holidayResult.holiday!);
        return response;
      }
    }

    // TIER 0: Smart team resolution with fuzzy matching + user context
    // Skip when query is clearly about schedules/time — prevents "sunset" fuzzy-matching "suns"
    if (!isOpenEnded && !_isScheduleOrTimeQuery(userPrompt)) {
      List<String>? userTeams;
      String? userLocation;
      try {
        final profile = ref.read(currentUserProfileProvider).maybeWhen(
              data: (u) => u,
              orElse: () => null,
            );
        if (profile != null) {
          userTeams = profile.sportsTeams;
          userLocation = profile.location;
        }
      } catch (_) {}

      final teamResult = TeamColorResolver.resolve(
        userPrompt,
        userTeams: userTeams,
        userLocation: userLocation,
      );

      if (teamResult != null && teamResult.isHighConfidence) {
        debugPrint('🏈 TIER 0: Resolved team: ${teamResult.team.officialName} '
            '(${teamResult.team.league}) confidence=${teamResult.confidence.toStringAsFixed(2)} '
            'via ${teamResult.matchType.name}');
        if (teamResult.alternatives.isNotEmpty) {
          debugPrint('   Alternatives: ${teamResult.alternatives.map((a) => '${a.team.officialName}(${a.confidence})').join(', ')}');
        }
        final context = EventThemeLibrary.detectContext(userPrompt.toLowerCase());
        debugPrint('   Context modifier: $context');
        final response = _buildCanonicalTeamResponse(teamResult.team, context);
        return response;
      } else if (teamResult != null) {
        debugPrint('🏈 TIER 0: Low-confidence team match: ${teamResult.team.officialName} '
            '(${teamResult.confidence.toStringAsFixed(2)}) - using anyway');
        final context = EventThemeLibrary.detectContext(userPrompt.toLowerCase());
        final response = _buildCanonicalTeamResponse(teamResult.team, context);
        return response;
      }
    }

    // TIER 1: Try to match against deterministic event theme library
    final themeMatch = EventThemeLibrary.matchQuery(userPrompt);

    if (themeMatch != null && !isOpenEnded) {
      debugPrint('🎯 TIER 1: Matched pre-defined theme: ${themeMatch.theme.name} with context: ${themeMatch.context}');
      final pattern = themeMatch.pattern;
      final wledPayload = pattern.toWledPayload();
      final response = _buildDeterministicResponse(pattern, wledPayload);
      return response;
    }

    // TIER 2: Check semantic cache for previously processed queries
    final detectedTheme = SemanticPatternMatcher.extractTheme(userPrompt);
    final hasSpecificTheme = detectedTheme != null;

    if (!isOpenEnded && hasSpecificTheme) {
      final cachedPattern = SemanticPatternMatcher.getCachedPattern(userPrompt);
      if (cachedPattern != null) {
        debugPrint('💾 TIER 2: Using cached pattern (hash: ${SemanticPatternMatcher.createQueryHash(userPrompt)})');
        final context = SemanticPatternMatcher.extractContext(userPrompt);
        debugPrint('   Theme: $detectedTheme, Context: $context');
        return _buildResponseFromCachedData(cachedPattern);
      }
    } else if (isOpenEnded) {
      debugPrint('⏭️ Skipping semantic cache for open-ended query');
    } else if (!hasSpecificTheme) {
      debugPrint('⏭️ Skipping semantic cache for generic query (no specific theme detected)');
    }

    // TIER 3: Fall back to AI for new queries
    debugPrint('🤖 TIER 3: Using AI${isOpenEnded ? " (with variety context)" : " (will cache result)"}');
    final theme = SemanticPatternMatcher.extractTheme(userPrompt);
    final context = SemanticPatternMatcher.extractContext(userPrompt);
    debugPrint('   Detected theme: $theme, context: $context');

    String contextBlock = _buildContextBlock(ref);

    if (isOpenEnded) {
      final avoidanceContext = historyService.getAvoidanceContext(limit: 5);
      if (avoidanceContext != null) {
        contextBlock = '$contextBlock\n\n$avoidanceContext';
        debugPrint('📋 Injected avoidance context (${historyService.historySize} suggestions in history)');
      }
    }

    // Inject global learning context from cross-user analytics
    try {
      final analyticsService = ref.read(patternAnalyticsServiceProvider);
      final globalContext = await analyticsService.buildGlobalLearningContext(userPrompt);
      if (globalContext != null && globalContext.isNotEmpty) {
        contextBlock = '$contextBlock\n\n$globalContext';
        debugPrint('🌐 Injected global learning context from analytics');
      }
    } catch (e) {
      debugPrint('Failed to inject global learning context: $e');
    }

    // Inject intent classification context
    final classification = ref.read(latestClassificationProvider);
    if (classification != null) {
      final classHint = CommandIntentClassifier.buildAIContextHint(classification);
      contextBlock = '$contextBlock\n\n$classHint';
      debugPrint('🏷️ Injected classification context: '
          '${classification.classification.name}');
    }

    final aiResponse = await LuminaAI.chat(
      userPrompt,
      contextBlock: contextBlock,
      temperature: isOpenEnded ? 0.7 : null,
    );

    // Extract and cache the pattern from AI response
    final parsed = _extractJsonFromContent(aiResponse);
    if (parsed != null && !isOpenEnded && hasSpecificTheme) {
      SemanticPatternMatcher.cachePattern(userPrompt, parsed.object);
      debugPrint('   ✅ Cached AI response for theme "$detectedTheme" (cache size: ${SemanticPatternMatcher.cacheSize})');
    } else if (parsed != null && !hasSpecificTheme) {
      debugPrint('   ⏭️ Not caching generic query (would cause false matches)');
    }

    // Record in suggestion history for variety tracking
    if (parsed != null) {
      final effectObj = parsed.object['effect'];
      final effectId = effectObj is Map ? (effectObj['id'] as num?)?.toInt() : null;
      final effectName = effectObj is Map ? effectObj['name'] as String? : null;
      final colorsArr = parsed.object['colors'];
      final colorNames = <String>[];
      if (colorsArr is List) {
        for (final c in colorsArr) {
          final n = (c as Map?)?['name'] as String?;
          if (n != null) colorNames.add(n);
        }
      }
      historyService.recordSuggestion(
        patternName: parsed.object['patternName'] as String? ?? 'Pattern',
        colorNames: colorNames,
        effectId: effectId,
        effectName: effectName,
        queryType: isOpenEnded ? 'open_ended' : 'specific',
      );
    }

    return aiResponse;
  }

  // -------------------------------------------------------------------------
  // Compound command handler
  // -------------------------------------------------------------------------

  /// Handles a confirmed compound lighting+scheduling command.
  ///
  /// Runs tier 0/0.5 resolution on [compound.lightingIntent] (temporal
  /// language already stripped), then hands off to [LuminaSmartScheduler]
  /// to build a variety-aware multi-day plan using [UserVarietyProfile].
  ///
  /// Returns null if theme resolution fails — caller falls through to normal tiers.
  static Future<String?> _handleCompoundCommand(
    WidgetRef ref,
    CompoundCommandResult compound,
    SuggestionHistoryService historyService,
  ) async {
    final lightingPrompt = compound.lightingIntent;
    final temporal = compound.temporal!;

    // Read the inferred user variety profile
    UserVarietyProfile varietyProfile;
    try {
      varietyProfile = ref.read(userVarietyProfileProvider);
      debugPrint('👤 Variety profile for schedule: ${varietyProfile.level.name} '
          '(score=${varietyProfile.varietyScore.toStringAsFixed(2)})');
    } catch (e) {
      debugPrint('⚠️ Could not read variety profile, using default: $e');
      varietyProfile = UserVarietyProfile.defaultProfile();
    }

    ResolvedTheme? theme;
    bool isHolidayTheme = false;

    // --- Attempt holiday resolution on the stripped lighting intent ---
    final holidayResult = HolidayColorDatabase.resolve(lightingPrompt);
    if (holidayResult.resolved && holidayResult.confidence >= 0.7) {
      final holiday = holidayResult.holiday!;
      isHolidayTheme = true;
      theme = ResolvedTheme(
        name: holiday.name,
        colorEntries: holiday.colors
            .map((c) => {
                  'name': c.name,
                  'rgb': rgbToRgbw(c.r, c.g, c.b, forceZeroWhite: true),
                })
            .toList(),
        suggestedEffects: holiday.suggestedEffects,
        defaultSpeed: holiday.defaultSpeed,
        defaultIntensity: holiday.defaultIntensity,
      );
      debugPrint('🎄 Compound: resolved holiday "${holiday.name}"');
    }

    // --- Attempt team resolution if holiday didn't match ---
    if (theme == null && !_isScheduleOrTimeQuery(lightingPrompt)) {
      List<String>? userTeams;
      String? userLocation;
      try {
        final profile = ref.read(currentUserProfileProvider).maybeWhen(
              data: (u) => u,
              orElse: () => null,
            );
        if (profile != null) {
          userTeams = profile.sportsTeams;
          userLocation = profile.location;
        }
      } catch (_) {}

      final teamResult = TeamColorResolver.resolve(
        lightingPrompt,
        userTeams: userTeams,
        userLocation: userLocation,
      );

      if (teamResult != null) {
        final ledRgb = teamResult.team.ledOptimizedRgb;
        theme = ResolvedTheme(
          name: teamResult.team.officialName,
          colorEntries: teamResult.team.colors.asMap().entries.map((e) {
            final i = e.key;
            final tc = e.value;
            final rgb =
                i < ledRgb.length ? ledRgb[i] : [tc.r, tc.g, tc.b, 0];
            return {
              'name': tc.name,
              'rgb': rgb.length >= 4 ? rgb : [...rgb, 0],
            };
          }).toList(),
          suggestedEffects: teamResult.team.suggestedEffects.isNotEmpty
              ? teamResult.team.suggestedEffects
              : [2, 41, 43, 12, 0],
          defaultSpeed: teamResult.team.defaultSpeed,
          defaultIntensity: teamResult.team.defaultIntensity,
        );
        debugPrint('🏈 Compound: resolved team "${teamResult.team.officialName}"');
      }
    }

    // Could not resolve the theme — caller will fall through to normal tiers
    if (theme == null) return null;

    // Generate the smart multi-day schedule plan
    final plan = LuminaSmartScheduler.generatePlan(
      theme: theme,
      command: compound,
      userProfile: varietyProfile,
      isHolidayTheme: isHolidayTheme,
    );

    // Record each occurrence in suggestion history for future variety analysis
    for (final occ in plan.occurrences) {
      historyService.recordSuggestion(
        patternName: occ.patternName,
        effectId: occ.effectId,
        effectName: occ.effectName,
        colorNames: occ.colors.isNotEmpty
            ? [LuminaSmartScheduler.colorNameFromRgbw(occ.colors.first)]
            : null,
        queryType: 'scheduled',
      );
    }

    // Build the response JSON and verbal summary
    final responseJson = LuminaSmartScheduler.planToResponseJson(plan);
    return '${plan.summaryText} ${jsonEncode(responseJson)}';
  }

  // -------------------------------------------------------------------------
  // Existing helpers (unchanged)
  // -------------------------------------------------------------------------

  static String _buildResponseFromCachedData(Map<String, dynamic> cachedData) {
    final patternName = cachedData['patternName'] as String? ?? 'Pattern';
    final thought = cachedData['thought'] as String? ?? '';
    final verbal = thought.isNotEmpty
        ? '$thought - here we go!'
        : 'Perfect! Applying $patternName now.';
    return '$verbal ${jsonEncode(cachedData)}';
  }

  static _JsonExtraction? _extractJsonFromContent(String content) {
    try {
      final start = content.indexOf('{');
      if (start < 0) return null;
      int depth = 0;
      for (int i = start; i < content.length; i++) {
        final ch = content[i];
        if (ch == '{') depth++;
        if (ch == '}') {
          depth--;
          if (depth == 0) {
            final sub = content.substring(start, i + 1);
            final obj = jsonDecode(sub);
            if (obj is Map<String, dynamic>) {
              return _JsonExtraction(object: obj, substring: sub);
            }
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('extractJsonFromContent failed: $e');
    }
    return null;
  }

  static String _buildDeterministicResponse(
    dynamic pattern,
    Map<String, dynamic> wledPayload,
  ) {
    final name = pattern.name as String? ?? 'Custom Pattern';
    final subtitle = pattern.subtitle as String? ?? '';
    final colors = pattern.colors as List<dynamic>? ?? [];
    final effectId = pattern.effectId as int? ?? 0;
    final effectName = pattern.effectName as String? ?? 'Solid';
    final direction = pattern.direction as String? ?? 'none';
    final isStatic = pattern.isStatic as bool? ?? true;
    final speed = pattern.speed as int? ?? 128;
    final intensity = pattern.intensity as int? ?? 128;

    final colorsArray = colors.map((c) {
      final color = c as dynamic;
      return {
        'name': _colorToName(color),
        'rgb': [color.red, color.green, color.blue, 0],
      };
    }).toList();

    final jsonObject = {
      'patternName': name,
      'thought': subtitle.isNotEmpty ? subtitle : 'Perfect choice for this occasion!',
      'colors': colorsArray,
      'effect': {
        'name': effectName,
        'id': effectId,
        'direction': direction,
        'isStatic': isStatic,
      },
      'speed': speed,
      'intensity': intensity,
      'wled': wledPayload,
    };

    final verbal = subtitle.isNotEmpty
        ? '$subtitle - here we go!'
        : 'Perfect! Applying $name now.';
    return '$verbal ${jsonEncode(jsonObject)}';
  }

  static String _buildCanonicalTeamResponse(
    UnifiedTeamEntry team,
    EventContext context,
  ) {
    int effectId;
    String effectName;
    int speed;
    int intensity;
    bool isStatic;

    switch (context) {
      case EventContext.party:
        effectId = 41; effectName = 'Running'; speed = 180; intensity = 220; isStatic = false;
        break;
      case EventContext.celebration:
        effectId = 43; effectName = 'Twinkle'; speed = 120; intensity = 180; isStatic = false;
        break;
      case EventContext.elegant:
        effectId = 2; effectName = 'Breathe'; speed = 50; intensity = 140; isStatic = false;
        break;
      case EventContext.staticSimple:
        effectId = 0; effectName = 'Solid'; speed = 128; intensity = 128; isStatic = true;
        break;
      case EventContext.romantic:
      case EventContext.neutral:
        effectId = team.suggestedEffects.isNotEmpty ? team.suggestedEffects.first : 2;
        effectName = _effectIdToName(effectId);
        speed = team.defaultSpeed;
        intensity = team.defaultIntensity;
        isStatic = effectId == 0;
        break;
    }

    final ledRgb = team.ledOptimizedRgb;
    final shortName = team.officialName.split(' ').last;
    String patternName;
    String subtitle;

    switch (context) {
      case EventContext.party:
        patternName = '${team.officialName} Party';
        subtitle = 'High-energy $shortName colors chase';
        break;
      case EventContext.celebration:
        patternName = '${team.officialName} Celebration';
        subtitle = 'Festive $shortName sparkle';
        break;
      case EventContext.elegant:
        patternName = '${team.officialName} Elegance';
        subtitle = 'Sophisticated $shortName glow';
        break;
      case EventContext.staticSimple:
        patternName = '${team.officialName} Colors';
        subtitle = 'Pure $shortName team colors';
        break;
      case EventContext.romantic:
      case EventContext.neutral:
        patternName = '${team.officialName} Spirit';
        subtitle = '$shortName team pride';
        break;
    }

    final colorsArray = <Map<String, dynamic>>[];
    for (var i = 0; i < team.colors.length; i++) {
      final tc = team.colors[i];
      final rgb = i < ledRgb.length ? ledRgb[i] : [tc.r, tc.g, tc.b, 0];
      colorsArray.add({
        'name': tc.name,
        'rgb': rgb.length >= 4 ? rgb : [...rgb, 0],
      });
    }

    final segCol = <List<int>>[];
    for (var i = 0; i < team.colors.length; i++) {
      final rgb = i < ledRgb.length
          ? ledRgb[i]
          : [team.colors[i].r, team.colors[i].g, team.colors[i].b, 0];
      segCol.add(rgb);
    }

    final wledPayload = {
      'on': true,
      'bri': 255,
      'seg': [
        {
          'id': 0,
          'on': true,
          'bri': 255,
          'col': segCol.isEmpty ? [[255, 255, 255, 0]] : segCol,
          'fx': effectId,
          'sx': speed,
          'ix': intensity,
        }
      ],
    };

    final jsonObject = {
      'patternName': patternName,
      'thought': subtitle,
      'colors': colorsArray,
      'effect': {
        'name': effectName,
        'id': effectId,
        'direction': effectId == 41 ? 'right' : 'none',
        'isStatic': isStatic,
      },
      'speed': speed,
      'intensity': intensity,
      'wled': wledPayload,
    };

    final verbal = 'Go ${team.officialName}! $subtitle - here we go!';
    return '$verbal ${jsonEncode(jsonObject)}';
  }

  static String _buildHolidayResponse(HolidayColorEntry holiday) {
    final effectId =
        holiday.suggestedEffects.isNotEmpty ? holiday.suggestedEffects.first : 0;
    final effectName = _effectIdToName(effectId);
    final speed = holiday.defaultSpeed;
    final intensity = holiday.defaultIntensity;
    final isStatic = effectId == 0;

    final colorsArray = holiday.colors.map((c) {
      return {
        'name': c.name,
        'rgb': rgbToRgbw(c.r, c.g, c.b, forceZeroWhite: true),
      };
    }).toList();

    final segCol = holiday.colors
        .map((c) => rgbToRgbw(c.r, c.g, c.b, forceZeroWhite: true))
        .toList();

    final wledPayload = {
      'on': true,
      'bri': 255,
      'seg': [
        {
          'id': 0,
          'on': true,
          'bri': 255,
          'col': segCol.isEmpty
              ? [rgbToRgbw(255, 255, 255, forceZeroWhite: true)]
              : segCol,
          'fx': effectId,
          'sx': speed,
          'ix': intensity,
        }
      ],
    };

    final jsonObject = {
      'patternName': '${holiday.name} Theme',
      'thought': 'Beautiful ${holiday.name} colors for your roofline!',
      'colors': colorsArray,
      'effect': {
        'name': effectName,
        'id': effectId,
        'direction': 'none',
        'isStatic': isStatic,
      },
      'speed': speed,
      'intensity': intensity,
      'wled': wledPayload,
    };

    final verbal =
        'Here are your ${holiday.name} colors! ${jsonObject['thought']}';
    return '$verbal ${jsonEncode(jsonObject)}';
  }

  static String _effectIdToName(int id) {
    const names = <int, String>{
      0: 'Solid',
      2: 'Breathe',
      12: 'Theater Chase',
      41: 'Running',
      43: 'Twinkle',
      52: 'Fireworks',
      63: 'Candle',
      65: 'Fire',
    };
    return names[id] ?? 'Effect $id';
  }

  static String _colorToName(dynamic color) {
    final r = color.red as int;
    final g = color.green as int;
    final b = color.blue as int;

    if (r > 200 && g < 100 && b < 100) return 'Red';
    if (g > 200 && r < 100 && b < 100) return 'Green';
    if (b > 200 && r < 100 && g < 100) return 'Blue';
    if (r > 200 && g > 200 && b < 100) return 'Yellow';
    if (r > 200 && g > 150 && b > 200) return 'Pink';
    if (r > 200 && g > 100 && b < 100) return 'Orange';
    if (r < 100 && g > 150 && b > 200) return 'Cyan';
    if (r > 150 && g < 100 && b > 150) return 'Purple';
    if (r > 200 && g > 200 && b > 200) return 'White';
    if (r > 200 && g > 160 && b < 150) return 'Gold';
    if (r > 200 && g > 180 && b > 150) return 'Champagne';
    return 'Color';
  }

  static Future<Map<String, dynamic>> generateWledJson(
      WidgetRef ref, String userPrompt) async {
    final contextBlock = _buildContextBlock(ref);
    return LuminaAI.generateWledJson(userPrompt, contextBlock: contextBlock);
  }

  static Future<Map<String, dynamic>> generateWledJsonFromRef(
      Ref ref, String userPrompt) async {
    final contextBlock = _buildContextBlockFromRef(ref);
    return LuminaAI.generateWledJson(userPrompt, contextBlock: contextBlock);
  }

  static Future<String> chatRefinement(
    WidgetRef ref,
    String refinementPrompt, {
    required Map<String, dynamic> currentPattern,
  }) async {
    String contextBlock = _buildContextBlock(ref);

    try {
      final analyticsService = ref.read(patternAnalyticsServiceProvider);
      final originalQuery =
          currentPattern['originalQuery'] as String? ?? refinementPrompt;
      final globalContext =
          await analyticsService.buildGlobalLearningContext(originalQuery);
      if (globalContext != null && globalContext.isNotEmpty) {
        contextBlock = '$contextBlock\n\n$globalContext';
      }
    } catch (e) {
      debugPrint('Failed to inject global learning context for refinement: $e');
    }

    return LuminaAI.chatRefinement(
      refinementPrompt,
      currentPattern: currentPattern,
      contextBlock: contextBlock,
    );
  }

  static Future<Map<String, dynamic>> generateSegmentAwarePattern(
    WidgetRef ref,
    String userPrompt, {
    bool highlightAnchors = true,
    bool useSymmetry = true,
  }) async {
    final rooflineConfig = ref.read(currentRooflineConfigProvider).maybeWhen(
          data: (config) => config,
          orElse: () => null,
        );

    if (rooflineConfig == null || rooflineConfig.segments.isEmpty) {
      return generateWledJson(ref, userPrompt);
    }

    final enhancedPrompt = _buildSegmentAwarePrompt(
      userPrompt,
      rooflineConfig,
      highlightAnchors: highlightAnchors,
      useSymmetry: useSymmetry,
    );

    final contextBlock = _buildContextBlock(ref);
    return LuminaAI.generateWledJson(enhancedPrompt, contextBlock: contextBlock);
  }

  static String _buildSegmentAwarePrompt(
    String userPrompt,
    RooflineConfiguration config, {
    required bool highlightAnchors,
    required bool useSymmetry,
  }) {
    final buffer = StringBuffer(userPrompt);
    buffer.writeln('\n\nIMPORTANT - Apply this pattern to my specific roofline layout:');
    buffer.writeln('Total LEDs: ${config.totalPixelCount}');
    buffer.writeln('\nSegments:');
    for (final segment in config.segments) {
      buffer.write('- ${segment.name} (${_segmentTypeName(segment.type)}): ');
      buffer.writeln('LED range ${segment.startPixel} to ${segment.endPixel}');
    }

    if (highlightAnchors) {
      final anchors = <String>[];
      for (final segment in config.segments) {
        for (final anchorIdx in segment.anchorPixels) {
          final globalIdx = segment.startPixel + anchorIdx;
          anchors.add('LED $globalIdx (${segment.name})');
        }
      }
      if (anchors.isNotEmpty) {
        buffer.writeln('\nAccent points that should be highlighted:');
        for (final anchor in anchors.take(10)) {
          buffer.writeln('- $anchor');
        }
        if (anchors.length > 10) {
          buffer.writeln('- ... and ${anchors.length - 10} more');
        }
      }
    }

    if (useSymmetry) {
      final peaks =
          config.segments.where((s) => s.type == SegmentType.peak).toList();
      if (peaks.isNotEmpty) {
        final mainPeak =
            peaks.reduce((a, b) => a.pixelCount > b.pixelCount ? a : b);
        buffer.writeln(
            '\nSymmetry: The main peak "${mainPeak.name}" is the visual center.');
        buffer.writeln(
            'Consider mirroring colors/effects on either side of the peak.');
      }
    }

    buffer.writeln(
        '\nGenerate a WLED payload that applies this pattern across all segments.');
    return buffer.toString();
  }

  static String _buildContextBlock(WidgetRef ref) {
    String location = 'Unknown';
    String interests = 'None';
    String avoid = '';
    String rooflineContext = '';

    try {
      final profile = ref.read(currentUserProfileProvider).maybeWhen(
            data: (u) => u,
            orElse: () => null,
          );
      if (profile != null) {
        if (profile.location != null && profile.location!.trim().isNotEmpty) {
          location = profile.location!.trim();
        }
        if (profile.interestTags.isNotEmpty) {
          interests = profile.interestTags.join(', ');
        }
        if (profile.dislikes.isNotEmpty) {
          avoid = profile.dislikes.join(', ');
        }
      }
    } catch (e) {
      debugPrint('LuminaBrain context profile read error: $e');
    }

    try {
      final rooflineConfig = ref.read(currentRooflineConfigProvider).maybeWhen(
            data: (config) => config,
            orElse: () => null,
          );
      if (rooflineConfig != null && rooflineConfig.segments.isNotEmpty) {
        rooflineContext = _buildRooflineContext(rooflineConfig);
      }
    } catch (e) {
      debugPrint('LuminaBrain roofline config read error: $e');
    }

    final now = DateTime.now();
    final dateStr = _formatFullDate(now);
    final tod = _timeOfDayLabel(now);

    final buffer = StringBuffer('CONTEXT:\n'
        '- User Location: $location\n'
        '- Current Date: $dateStr\n'
        '- Known Interests: $interests\n'
        '- Time of Day: $tod');

    if (avoid.isNotEmpty) {
      buffer.write('\n- AVOID THESE: $avoid');
    }

    if (rooflineContext.isNotEmpty) {
      buffer.write('\n\n$rooflineContext');
    }

    // Inject user variety preference for scheduling and multi-day requests
    try {
      final varietyProfile = ref.read(userVarietyProfileProvider);
      buffer.write('\n\n${varietyProfile.buildAIContextHint()}');
      debugPrint('🎨 Injected variety profile into context: ${varietyProfile.level.name}');
    } catch (e) {
      debugPrint('LuminaBrain variety profile read error: $e');
    }

    return buffer.toString();
  }

  static String _buildContextBlockFromRef(Ref ref) {
    String location = 'Unknown';
    String interests = 'None';
    String avoid = '';
    String rooflineContext = '';

    try {
      final profile = ref.read(currentUserProfileProvider).maybeWhen(
            data: (u) => u,
            orElse: () => null,
          );
      if (profile != null) {
        if (profile.location != null && profile.location!.trim().isNotEmpty) {
          location = profile.location!.trim();
        }
        if (profile.interestTags.isNotEmpty) {
          interests = profile.interestTags.join(', ');
        }
        if (profile.dislikes.isNotEmpty) {
          avoid = profile.dislikes.join(', ');
        }
      }
    } catch (e) {
      debugPrint('LuminaBrain context profile read error: $e');
    }

    try {
      final rooflineConfig = ref.read(currentRooflineConfigProvider).maybeWhen(
            data: (config) => config,
            orElse: () => null,
          );
      if (rooflineConfig != null && rooflineConfig.segments.isNotEmpty) {
        rooflineContext = _buildRooflineContext(rooflineConfig);
      }
    } catch (e) {
      debugPrint('LuminaBrain roofline config read error: $e');
    }

    final now = DateTime.now();
    final dateStr = _formatFullDate(now);
    final tod = _timeOfDayLabel(now);

    final buffer = StringBuffer('CONTEXT:\n'
        '- User Location: $location\n'
        '- Current Date: $dateStr\n'
        '- Known Interests: $interests\n'
        '- Time of Day: $tod');

    if (avoid.isNotEmpty) {
      buffer.write('\n- AVOID THESE: $avoid');
    }

    if (rooflineContext.isNotEmpty) {
      buffer.write('\n\n$rooflineContext');
    }

    return buffer.toString();
  }

  static String _buildRooflineContext(RooflineConfiguration config) {
    final buffer = StringBuffer('ROOFLINE INSTALLATION:\n');
    buffer.writeln('- Total LED Count: ${config.totalPixelCount}');
    buffer.writeln('- Number of Segments: ${config.segmentCount}');

    final typeCounts = <SegmentType, int>{};
    for (final segment in config.segments) {
      typeCounts[segment.type] = (typeCounts[segment.type] ?? 0) + 1;
    }

    if (typeCounts.isNotEmpty) {
      final typeDescriptions = typeCounts.entries
          .map((e) =>
              '${e.value} ${_segmentTypeName(e.key)}${e.value > 1 ? 's' : ''}')
          .join(', ');
      buffer.writeln('- Segment Types: $typeDescriptions');
    }

    final roleCounts = <ArchitecturalRole, int>{};
    for (final segment in config.segments) {
      if (segment.architecturalRole != null) {
        final role = segment.architecturalRole!;
        roleCounts[role] = (roleCounts[role] ?? 0) + 1;
      }
    }

    if (roleCounts.isNotEmpty) {
      final roleDescriptions = roleCounts.entries
          .map((e) => '${e.value} ${e.key.pluralName}')
          .join(', ');
      buffer.writeln('- Architectural Features: $roleDescriptions');
    }

    final totalAnchors =
        config.segments.fold(0, (sum, s) => sum + s.anchorPixels.length);
    if (totalAnchors > 0) {
      buffer.writeln('- Accent Points (corners/peaks): $totalAnchors');
    }

    buffer.writeln('\nSegments (in order from LED #0):');
    for (final segment in config.segments) {
      buffer.write('  ${segment.name}');
      if (segment.architecturalRole != null) {
        buffer.write(' [${segment.architecturalRole!.displayName}]');
      } else {
        buffer.write(' (${_segmentTypeName(segment.type)})');
      }
      if (segment.location != null && segment.location!.isNotEmpty) {
        buffer.write(' - ${segment.location}');
      }
      buffer.write(': LEDs ${segment.startPixel}-${segment.endPixel}');
      buffer.write(' (${segment.pixelCount} pixels)');
      if (segment.anchorPixels.isNotEmpty) {
        buffer.write(' [${segment.anchorPixels.length} anchors]');
      }
      if (segment.isProminent) {
        buffer.write(' *PROMINENT*');
      }
      buffer.writeln();
    }

    buffer.writeln();
    buffer.writeln('ROOFLINE-AWARE PATTERN GUIDANCE:');
    buffer.writeln('- User can request patterns by architectural feature (e.g., "light the peaks")');
    buffer.writeln('- For downlighting effects, ensure corners and peaks are always lit');
    buffer.writeln('- Chase effects should flow naturally along the roofline direction');
    buffer.writeln('- Use anchor points as accent areas for special colors');
    buffer.writeln('- Peak segments are great focal points for holiday themes');
    buffer.writeln('- Symmetry suggestions: mirror patterns across the main peak when possible');
    buffer.writeln('- Prominent segments should be prioritized in design suggestions');

    return buffer.toString();
  }

  static String _segmentTypeName(SegmentType type) {
    switch (type) {
      case SegmentType.run: return 'horizontal run';
      case SegmentType.corner: return 'corner';
      case SegmentType.peak: return 'peak';
      case SegmentType.column: return 'column';
      case SegmentType.connector: return 'connector';
    }
  }

  static String _timeOfDayLabel(DateTime dt) {
    final h = dt.hour;
    return (h >= 5 && h < 17) ? 'Morning' : 'Night';
  }

  static const _weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  static String _formatFullDate(DateTime dt) {
    final weekday = _weekdays[(dt.weekday - 1).clamp(0, 6)];
    final month = _months[(dt.month - 1).clamp(0, 11)];
    final day = dt.day;
    final year = dt.year;
    final hour12 = ((dt.hour + 11) % 12) + 1;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$weekday, $month $day, $year, $hour12:$minute $ampm';
  }

  static Future<Map<String, dynamic>?> parseDesignIntent(
    WidgetRef ref,
    String userPrompt,
  ) async {
    final rooflineConfig = ref.read(currentRooflineConfigProvider).maybeWhen(
          data: (config) => config,
          orElse: () => null,
        );

    final systemPrompt = '''
You are a lighting design parser for permanent outdoor LED systems.
Parse the user's natural language request into a structured design intent.

${rooflineConfig != null ? _buildRooflineContext(rooflineConfig) : ''}

Parse the request into this JSON structure:
{
  "layers": [
    {
      "name": "Layer name",
      "zone": {
        "type": "all|architectural|location|level",
        "roles": ["peak", "corner", "run"],
        "location": "front|back|left|right"
      },
      "colors": {
        "primary": [R, G, B],
        "secondary": [R, G, B],
        "accent": [R, G, B]
      },
      "spacing": {
        "type": "continuous|everyOther|oneOnTwoOff|equallySpaced|anchorsOnly",
        "onCount": 1,
        "offCount": 1
      },
      "motion": {
        "type": "none|chase|wave|pulse|twinkle",
        "direction": "leftToRight|rightToLeft|inward|outward",
        "speed": 128
      }
    }
  ],
  "globalBrightness": 200,
  "ambiguities": ["description of anything unclear"]
}

Rules:
- Colors should be in [R, G, B] format (0-255 each)
- If something is ambiguous, note it in "ambiguities"
- Use common color names: red=[255,0,0], green=[0,255,0], blue=[0,0,255], etc.
- "dark green" = [0,100,0], "light green" = [144,238,144], "forest green" = [34,139,34]
- "warm white" = [255,244,229], "cool white" = [240,255,255], "soft white" = [250,240,230]
- Spacing "everyOther" means 1 on, 1 off. "oneOnTwoOff" means 1 on, 2 off.
''';

    try {
      final response = await LuminaAI.chat(
        'Parse this lighting design request: "$userPrompt"',
        contextBlock: systemPrompt,
        temperature: 0.3,
      );

      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(response);
      if (jsonMatch != null) {
        try {
          return jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
        } catch (e) {
          debugPrint('Failed to parse AI response JSON: $e');
        }
      }
    } catch (e) {
      debugPrint('AI design intent parsing failed: $e');
    }

    return null;
  }

  static Future<String> chatCalendar(
    WidgetRef ref,
    String systemContext,
    String userMessage,
  ) async {
    return LuminaAI.chatDirect(
      userMessage,
      systemPrompt: systemContext,
      temperature: 0.1,
    );
  }

  static bool _isScheduleOrTimeQuery(String query) {
    final lower = query.toLowerCase();
    const timeKeywords = [
      'schedule', 'sunrise', 'sunset', 'dusk', 'dawn',
      'timer', 'automate', 'automation', 'every day',
      'every night', 'recurring', 'turn on at', 'turn off at',
    ];
    return timeKeywords.any((kw) => lower.contains(kw));
  }
}

class _JsonExtraction {
  final Map<String, dynamic> object;
  final String substring;
  const _JsonExtraction({required this.object, required this.substring});
}