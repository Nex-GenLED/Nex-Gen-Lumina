import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';
import 'package:nexgen_command/lumina_ai/lumina_ai_service.dart';
import 'package:nexgen_command/features/wled/event_theme_library.dart';
import 'package:nexgen_command/features/wled/semantic_pattern_matcher.dart';
import 'package:nexgen_command/features/ai/suggestion_history.dart';
import 'package:nexgen_command/features/ai/command_intent_classifier.dart';
import 'package:nexgen_command/features/patterns/utils/pattern_display_name.dart';
import 'package:nexgen_command/services/pattern_analytics_service.dart';
import 'package:nexgen_command/data/team_color_database.dart';
import 'package:nexgen_command/data/team_color_resolver.dart';
import 'package:nexgen_command/data/holiday_color_database.dart';
import 'package:nexgen_command/features/wled/wled_service.dart' show rgbToRgbw;
import 'package:nexgen_command/features/wled/wled_payload_utils.dart' show safeRGBW;
import 'package:nexgen_command/features/ai/compound_command_detector.dart';
import 'package:nexgen_command/features/ai/local_command_parser.dart'
    show LocalCommandParser;
import 'package:nexgen_command/features/ai/user_variety_profile.dart';
import 'package:nexgen_command/features/wled/pattern_effect_speeds.dart'
    show effectDefaultSpeedOr;
import 'package:nexgen_command/features/ai/lumina_smart_scheduler.dart';
import 'package:nexgen_command/features/audio/models/audio_reactive_capability.dart';
import 'package:nexgen_command/features/audio/services/audio_capability_detector.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'dart:convert';
import 'package:nexgen_command/features/schedule/solar_scheduling_feature_flag.dart';

/// LuminaBrain aggregates local context (who/where/when) and injects it into
/// every Lumina AI request for improved grounding and personalization.
class LuminaBrain {
  /// Returns true if the prompt appears to be probing internal architecture,
  /// credentials, or attempting a prompt-injection / jailbreak.
  static bool _isExtractionAttempt(String prompt) {
    const patterns = [
      'system prompt',
      'ignore previous',
      'ignore instructions',
      'repeat your instructions',
      'what are your instructions',
      'how do you work',
      'what algorithm',
      'your source code',
      'your api',
      'reveal your',
      'show your prompt',
      'pretend you are',
      'act as if',
      'jailbreak',
      'developer mode',
      'dan mode',
      'what model',
      'which ai',
      'openai',
      'anthropic',
      'gpt',
      'claude',
    ];
    final lower = prompt.toLowerCase();
    return patterns.any((p) => lower.contains(p));
  }

  /// Safe deflection response for extraction / jailbreak attempts.
  static String _safeDeflectResponse() =>
      "I'm Lumina — I'm here to help with your lighting. "
      "What can I light up for you today?";

  /// Scrubs sensitive data patterns from AI-generated responses before
  /// they are shown to the user. Applied only to Tier 3 (cloud AI) output.
  static String _sanitizeResponse(String response) {
    // 1. URLs
    var result = response.replaceAllMapped(
      RegExp(r'https?://[^\s]+', caseSensitive: false),
      (_) => '[link removed]',
    );
    // 2. IPv4 addresses
    result = result.replaceAllMapped(
      RegExp(r'\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b'),
      (_) => '[address removed]',
    );
    // 3. UUIDs
    result = result.replaceAllMapped(
      RegExp(
        r'[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}',
        caseSensitive: false,
      ),
      (_) => '[removed]',
    );
    // 4. API-key-like tokens: 32+ char alphanumeric with no spaces
    result = result.replaceAllMapped(
      RegExp(r'\b[A-Za-z0-9]{32,}\b'),
      (_) => '[removed]',
    );
    return result;
  }

  // -------------------------------------------------------------------------
  // Contextual placeholder — holiday / season / sport awareness (zero AI cost)
  // -------------------------------------------------------------------------

  /// Returns a contextual hint string for the Lumina chat input based on
  /// the current date. Checks upcoming holidays first, then in-season
  /// sports, then falls back to a seasonal suggestion.
  static String contextualPlaceholder() {
    // 1. Upcoming holiday within 14 days
    final holiday = HolidayColorDatabase.getUpcomingHoliday(withinDays: 14);
    if (holiday != null) {
      return _holidayPlaceholder(holiday.name);
    }

    // 2. In-season sport suggestion (generic — no user data needed)
    final month = DateTime.now().month;
    final weekday = DateTime.now().weekday; // 1=Mon … 7=Sun
    final sportHint = _sportHint(month, weekday);
    if (sportHint != null) return sportHint;

    // 3. Seasonal fallback
    final season = HolidayColorDatabase.getCurrentSeason();
    return _seasonPlaceholder(season.id);
  }

  static String _holidayPlaceholder(String name) {
    const map = {
      'Christmas': 'Try "Christmas lights"',
      'Halloween': 'Try "spooky Halloween"',
      'Independence Day': 'Try "4th of July fireworks"',
      '4th of July': 'Try "4th of July fireworks"',
      "Valentine's Day": 'Try "romantic Valentine\'s glow"',
      "St. Patrick's Day": 'Try "St. Patrick\'s green"',
      'Thanksgiving': 'Try "warm Thanksgiving"',
      'Easter': 'Try "pastel Easter lights"',
      "New Year's Day": 'Try "New Year\'s celebration"',
      "New Year's Eve": 'Try "midnight countdown glow"',
      'Juneteenth': 'Try "Juneteenth celebration"',
      'Cinco de Mayo': 'Try "Cinco de Mayo fiesta"',
      'Mardi Gras': 'Try "Mardi Gras party"',
    };
    return map[name] ?? 'Try "$name lights"';
  }

  static String? _sportHint(int month, int weekday) {
    // NFL: Sep–Feb, games Sun/Mon/Thu
    if ((month >= 9 || month <= 2) && (weekday == 7 || weekday == 1 || weekday == 4)) {
      return 'Try "game day lights" 🏈';
    }
    // NBA/NHL: Oct–Jun, most games Tue–Sun
    if ((month >= 10 || month <= 6) && weekday >= 2) {
      // Only suggest on ~40% of eligible days to avoid being repetitive
      if (DateTime.now().day % 5 < 2) {
        return 'Try "game night lights" 🏀';
      }
    }
    // MLB: Apr–Oct, games nearly every day
    if (month >= 4 && month <= 10 && DateTime.now().day % 4 == 0) {
      return 'Try "ballpark lights" ⚾';
    }
    return null;
  }

  static String _seasonPlaceholder(String seasonId) => switch (seasonId) {
        'spring' => 'Try "fresh spring glow"',
        'summer' => 'Try "warm summer night"',
        'autumn' => 'Try "cozy autumn glow"',
        'winter' => 'Try "cool winter sparkle"',
        _ => 'Ask Lumina anything…',
      };

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
    // Guard: deflect prompt-extraction and jailbreak attempts immediately.
    if (_isExtractionAttempt(userPrompt)) return _safeDeflectResponse();

    final historyService = SuggestionHistoryService.instance;
    final isOpenEnded = SuggestionHistoryService.isOpenEndedQuery(userPrompt);

    // ── PRE-TIER: Audio Intent Detection ──────────────────────────────────
    // Runs before all other tiers so "pulse to music", "audio mode", etc.
    // always activate Audio Mode directly.
    {
      final audioResponse = await _handleAudioIntent(ref, userPrompt);
      if (audioResponse != null) return audioResponse;
    }

    // ── PRE-TIER: Compound Command Detection ──────────────────────────────
    // Detect and handle commands that combine lighting + scheduling intent
    // BEFORE tier resolution so temporal language doesn't corrupt team/holiday
    // fuzzy matching. e.g. "Royals design every night this week from sunset to sunrise"
    // → lightingIntent="Royals design", temporal=7 days sunset→sunrise
    {
      final compound = CompoundCommandDetector.detect(userPrompt);
      if (compound.isCompound && compound.temporal != null) {
        final scheduledResponse = await _handleCompoundCommand(
          ref,
          compound,
          historyService,
        );
        if (scheduledResponse != null) return scheduledResponse;
      }
    }

    // TIER 0.5 (run first): Holiday / season / cultural event resolution
    // Runs before team resolution to prevent holidays like "St. Patrick's" from
    // fuzzy-matching to sports teams (e.g., "patricks" → "patriots").
    {
      final holidayResult = HolidayColorDatabase.resolve(userPrompt);
      if (holidayResult.resolved && holidayResult.confidence >= 0.7) {
        final response = _buildHolidayResponse(holidayResult.holiday!);
        return response;
      }
    }

    // TIER 0: Smart team resolution with fuzzy matching + user context
    // Only run when the query mentions sports, a team keyword, or a KNOWN
    // TEAM NAME (+110 E2 item 3) — prevents "fireworks" or "exciting design"
    // from fuzzy-matching team aliases.
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
      } catch (e) {
        debugPrint('Error in LuminaBrain reading user profile for sports: $e');
      }

      final response = composeTeamResponse(
        userPrompt,
        userTeams: userTeams,
        userLocation: userLocation,
      );
      if (response != null) return response;
    }

    // TIER 1: Try to match against deterministic event theme library
    final themeMatch = EventThemeLibrary.matchQuery(userPrompt);

    if (themeMatch != null && !isOpenEnded) {
      final pattern = themeMatch.pattern;
      final wledPayload = pattern.toWledPayload();
      final response = _buildDeterministicResponse(pattern, wledPayload);
      return response;
    }

    // TIER 2: Check semantic cache for previously processed queries
    final hasSpecificTheme = SemanticPatternMatcher.extractTheme(userPrompt) != null;

    if (!isOpenEnded && hasSpecificTheme) {
      final cachedPattern = SemanticPatternMatcher.getCachedPattern(userPrompt);
      if (cachedPattern != null) {
        return _buildResponseFromCachedData(cachedPattern);
      }
    }

    // TIER 3: Fall back to AI for new queries
    String contextBlock = _buildContextBlock(ref);

    // Inject explicit time window constraint if the user specified clock times,
    // so the AI doesn't fabricate a different time in its confirmation.
    {
      final compound = CompoundCommandDetector.detect(userPrompt);
      if (compound.temporal != null && compound.temporal!.hasClockTime) {
        final tw = compound.temporal!.timeWindowLabel;
        contextBlock = '$contextBlock\n\nTIME CONSTRAINT: Apply this design $tw only. '
            'Do not say "all day" or any other time — echo "$tw" in your confirmation.';
      }
      if (compound.temporal != null && compound.temporal!.hasDateRange) {
        final dr = compound.temporal!.dateRangeLabel;
        contextBlock = '$contextBlock\n\nDATE RANGE: Schedule this design $dr. '
            'Echo "$dr" in your confirmation.';
      }
    }

    if (isOpenEnded) {
      final avoidanceContext = historyService.getAvoidanceContext(limit: 5);
      if (avoidanceContext != null) {
        contextBlock = '$contextBlock\n\n$avoidanceContext';
      }
    }

    // Inject global learning context from cross-user analytics
    try {
      final analyticsService = ref.read(patternAnalyticsServiceProvider);
      final globalContext = await analyticsService.buildGlobalLearningContext(userPrompt);
      if (globalContext != null && globalContext.isNotEmpty) {
        contextBlock = '$contextBlock\n\n$globalContext';
      }
    } catch (e) {
      debugPrint('Failed to inject global learning context: $e');
    }

    // Inject intent classification context
    final classification = ref.read(latestClassificationProvider);
    if (classification != null) {
      final classHint = CommandIntentClassifier.buildAIContextHint(classification);
      contextBlock = '$contextBlock\n\n$classHint';
    }

    final aiResponse = await LuminaAI.chat(
      userPrompt,
      contextBlock: contextBlock,
      temperature: isOpenEnded ? 0.7 : null,
      // Don't let the model offer sunrise/sunset scheduling the sync layer
      // will refuse. Read defensively — a flag read must never break chat.
      solarSchedulingEnabled: () {
        try {
          return ref.read(solarSchedulingEnabledSyncProvider);
        } catch (_) {
          return false;
        }
      }(),
    );

    // Extract and cache the pattern from AI response
    final parsed = _extractJsonFromContent(aiResponse);

    // Validate: reject AI responses that reference sports teams when the user
    // didn't ask for sports content.
    //
    // +110 E2 item 3a — THE ROOT CAUSE of "give me a chiefs design with
    // motion right now" → "I couldn't find a matching design". The old gate
    // (`_hasExplicitSportsKeyword`) looked for words like "team" or "nfl" and
    // never for a team NAME, so the prompt skipped Tier 0, went to the cloud,
    // came back as a correct Chiefs design whose name mentioned the NFL — and
    // was rejected HERE as "sports content in a non-sports query". The gate
    // now recognises a known team name (isSportsRequest), so a team request
    // is composed locally at Tier 0 and never reaches this guard; when the
    // guard does fire, it says what it did not understand (item 3e).
    if (parsed != null && !isSportsRequest(userPrompt)) {
      final patternName = (parsed.object['patternName'] as String? ?? '').toLowerCase();
      final thought = (parsed.object['thought'] as String? ?? '').toLowerCase();
      // Check if the AI injected sports team references
      const sportsIndicators = ['fc', 'nfl', 'mlb', 'nba', 'nhl', 'mls',
        'game day', 'gameday', 'team colors', 'championship'];
      final hasSportsRef = sportsIndicators.any((s) =>
          patternName.contains(s) || thought.contains(s));
      if (hasSportsRef) {
        debugPrint('🚫 Rejected AI response: sports team reference in non-sports query. '
            'Input: "$userPrompt" | patternName: "$patternName"');
        return describeMisunderstanding(userPrompt);
      }
    }

    if (parsed != null && !isOpenEnded && hasSpecificTheme) {
      SemanticPatternMatcher.cachePattern(userPrompt, parsed.object);
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

    return _sanitizeResponse(aiResponse);
  }

  // -------------------------------------------------------------------------
  // Compound command handler
  // -------------------------------------------------------------------------

  /// Handles a confirmed compound lighting+scheduling command.
  ///
  // -------------------------------------------------------------------------
  // Audio intent detection & handler
  // -------------------------------------------------------------------------

  /// Returns true when the prompt explicitly requests audio/music reactivity.
  static bool _isAudioIntent(String query) {
    final lower = query.toLowerCase();
    const patterns = [
      'pulse to', 'react to', 'audio', 'music', 'beat', 'bass',
      'sound reactive', 'audio mode', 'audio reactive', 'mic',
      'listen to', 'dance to', 'sync to music',
    ];
    return patterns.any((p) => lower.contains(p));
  }

  /// Handles audio-reactive intent by activating an audio effect on the
  /// connected controller. Returns null if the prompt isn't audio-related
  /// so the caller can fall through to normal tiers.
  static Future<String?> _handleAudioIntent(WidgetRef ref, String userPrompt) async {
    if (!_isAudioIntent(userPrompt)) return null;

    final ip = ref.read(selectedDeviceIpProvider);
    if (ip == null) {
      return 'Audio Mode needs a connected controller. '
          'Make sure your system is online first.';
    }

    // UX audit row 111: WAIT for the capability check. The provider used to
    // be read synchronously, so while the probe was still in flight the
    // controller was declared to lack AudioReactive firmware.
    AudioReactiveCapability? cap;
    try {
      cap = await ref
          .read(audioCapabilityProvider(ip).future)
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('Audio capability check failed: $e');
    }
    if (cap == null) {
      return "I couldn't check whether your controller supports Audio Mode "
          "just now. Make sure it's online and try again in a moment.";
    }
    if (!cap.hasAudioReactiveUsermod) {
      return 'Audio Mode needs AudioReactive firmware on your controller. '
          'Check your controller settings.';
    }

    if (cap.audioReactiveEffects.isEmpty) {
      return 'Your controller has AudioReactive firmware but no audio '
          'effects were detected. Try updating your firmware.';
    }

    // Pick the best default effect: prefer GEQ or Gravimeter
    final effectNames = ref.read(wledEffectNamesProvider(ip)).valueOrNull ?? [];
    int chosenId = cap.audioReactiveEffects.first;
    String chosenName = 'Audio Effect';

    for (final fxId in cap.audioReactiveEffects) {
      if (fxId < effectNames.length) {
        final raw = effectNames[fxId];
        final name = raw.startsWith('* ') ? raw.substring(2) : raw;
        final lower = name.toLowerCase();
        if (lower.contains('geq') || lower.contains('gravimeter')) {
          chosenId = fxId;
          chosenName = name;
          break;
        }
      }
    }

    // Resolve display name if we fell through without matching
    if (chosenName == 'Audio Effect' && chosenId < effectNames.length) {
      final raw = effectNames[chosenId];
      chosenName = raw.startsWith('* ') ? raw.substring(2) : raw;
    }

    // Apply via the repository. applyToDevice returns false (does NOT throw)
    // on a device-write failure — gate the spoken confirmation on it so the
    // AI never claims "Audio Mode is on" when the write failed (Audit-2 S18,
    // brand-critical: the assistant must not lie about device state).
    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) {
      return 'Audio Mode needs a connected controller. '
          'Make sure your system is online first.';
    }
    final ok = await ref.read(wledStateProvider.notifier).applyToDevice({
      'on': true,
      'bri': 220,
      'seg': [
        {
          // No 'id' — applyToDevice fans this out per effective channel.
          'fx': chosenId,
          'sx': 128,
          'ix': 180,
          'col': [
            [255, 255, 255, 180]
          ],
        }
      ]
    }, labelHint: null);
    if (!ok) {
      return "I couldn't reach your lights to start Audio Mode — "
          "check your connection and try again.";
    }

    // Update local preview so the dashboard reflects the change immediately.
    try {
      ref.read(wledStateProvider.notifier).applyPreviewSync(
        colors: [const Color(0xFF00D4FF)],
        effectId: chosenId,
        effectName: chosenName,
        brightness: 220,
        speed: 128,
        intensity: 180,
      );
    } catch (e) {
      debugPrint('Audio intent applyPreviewSync error: $e');
    }

    return "Audio Mode is on — your lights will now pulse to whatever's "
        "playing in the room. $chosenName is active.";
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
    // Read the inferred user variety profile
    UserVarietyProfile varietyProfile;
    try {
      varietyProfile = ref.read(userVarietyProfileProvider);
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
                  // Funnel through safeRGBW for consistency with the team
                  // path. rgbToRgbw(forceZeroWhite: true) already produces a
                  // 4-channel result; safeRGBW just guarantees clamping and
                  // an explicit W slot so future regressions can't slip in.
                  'rgb':
                      safeRGBW(rgbToRgbw(c.r, c.g, c.b, forceZeroWhite: true)),
                })
            .toList(),
        suggestedEffects: holiday.suggestedEffects,
        defaultSpeed: holiday.defaultSpeed,
        defaultIntensity: holiday.defaultIntensity,
      );
    }

    // --- Attempt team resolution if holiday didn't match ---
    // Only resolve teams when the query mentions sports context or a known
    // team name (the same gate Tier 0 uses; item 3).
    if (theme == null && !_isScheduleOrTimeQuery(lightingPrompt) && isSportsRequest(lightingPrompt)) {
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
      } catch (e) {
        debugPrint('Error in LuminaBrain reading user profile for team resolution: $e');
      }

      final teamResult = TeamColorResolver.resolve(
        lightingPrompt,
        userTeams: userTeams,
        userLocation: userLocation,
      );

      if (teamResult != null && teamResult.isHighConfidence) {
        final ledRgb = teamResult.team.ledOptimizedRgb;
        // Item 3b: "with motion" on a multi-night plan → no Solid nights.
        // The scheduler already drops fx 0 for "motion"/"animated"; the
        // pool is ordered so an animated effect leads when motion is asked.
        final motion = wantsMotion(lightingPrompt);
        final suggested = teamResult.team.suggestedEffects.isNotEmpty
            ? teamResult.team.suggestedEffects
            : const [2, 41, 43, 12, 0];
        theme = ResolvedTheme(
          name: teamResult.team.officialName,
          colorEntries: teamResult.team.colors.asMap().entries.map((e) {
            final i = e.key;
            final tc = e.value;
            // Funnel every team color through safeRGBW so the W channel is
            // explicit (W=0) — prevents WLED from auto-extracting W and
            // washing dark branded reds (e.g. Chiefs `[227,24,55]`) into pink.
            final rgb = i < ledRgb.length
                ? safeRGBW(ledRgb[i])
                : safeRGBW([tc.r, tc.g, tc.b]);
            return {
              'name': tc.name,
              'rgb': rgb,
            };
          }).toList(),
          suggestedEffects: motion
              ? [for (final fx in suggested) if (fx != 0) fx]
              : suggested,
          defaultSpeed: teamResult.team.defaultSpeed,
          defaultIntensity: teamResult.team.defaultIntensity,
        );
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

  // ── Team requests (+110 E2 item 3) ──────────────────────────────────────

  /// Motion words: "with motion", "moving", "animated", "with movement",
  /// "make it move", "chase", "flowing"…
  static final RegExp _motionPattern = RegExp(
    r'\b(motion|moving|moves?|movement|animat(?:ed|ion|e)|chas(?:e|ing)|'
    r'flow(?:ing)?|dynamic|running|sparkl(?:e|ing)|twinkl(?:e|ing)|'
    r'pulsing|breathing|wave|waving)\b',
    caseSensitive: false,
  );

  /// D5 — words that ask for NO motion: "no motion", "without motion", "not
  /// moving", "no movement", "don't move", "static", "still". They win over a
  /// motion word in the same sentence, because "no motion" contains one.
  static final RegExp _noMotionPattern = RegExp(
    r"\b(?:no|without|not|never|don'?t|do\s+not|zero)\s+(?:any\s+)?"
    r'(?:motion|movement|moving|move|animation|animated|chas(?:e|ing)|'
    r'running|flow(?:ing)?)\b'
    r'|\bnot\s+(?:be\s+)?moving\b'
    r'|\b(?:static|still|stationary|motionless)\b',
    caseSensitive: false,
  );

  /// D5 — "colors"/"colours". A bare `<team> colors` wants the colours, not a
  /// show.
  static final RegExp _colorsPattern =
      RegExp(r'\bcolou?rs?\b', caseSensitive: false);

  /// True when the customer asked for the lights to MOVE — and did not, in
  /// the same breath, ask them not to (D5: "no motion" is not a motion ask).
  static bool wantsMotion(String prompt) =>
      _motionPattern.hasMatch(prompt) && !asksStatic(prompt);

  /// True when the customer asked for NO motion (D5).
  static bool asksStatic(String prompt) => _noMotionPattern.hasMatch(prompt);

  /// True for a bare `<team> colors` with no motion word (D5): Solid.
  static bool asksColorsOnly(String prompt) =>
      _colorsPattern.hasMatch(prompt) && !_motionPattern.hasMatch(prompt);

  /// Immediacy words. They change nothing about the design — a Tier 0 result
  /// is applied as soon as it is composed — but they must never be mistaken
  /// for part of a team name or for a schedule.
  static final RegExp _immediacyPattern = RegExp(
    r'\b(right\s+now|now|immediately|straight\s+away|asap)\b',
    caseSensitive: false,
  );

  /// The team's colours (LED-corrected, W explicit) as the response's colour
  /// entries and as the segment `col` array.
  static List<List<int>> _teamSegmentColors(UnifiedTeamEntry team) {
    final ledRgb = team.ledOptimizedRgb;
    return [
      for (var i = 0; i < team.colors.length; i++)
        i < ledRgb.length
            ? safeRGBW(ledRgb[i])
            : safeRGBW([team.colors[i].r, team.colors[i].g, team.colors[i].b]),
    ];
  }

  /// The first ANIMATED effect a team suggests, else Running (41).
  static int _animatedEffectFor(UnifiedTeamEntry team) {
    for (final fx in team.suggestedEffects) {
      if (fx != 0) return fx;
    }
    return 41;
  }

  /// Tier 0 for a team request, as one pure step: resolves the team named in
  /// [prompt], picks an effect from the prompt's mood and motion words, and
  /// returns the same verbal+JSON reply [chat] hands to the parser. Null when
  /// the prompt names no team (or names one too ambiguously to act on), so
  /// the caller falls through to the next tier.
  ///
  /// Visible so the phrase table in `lumina_team_request_test.dart` can drive
  /// the real composition without a widget or a cloud call.
  @visibleForTesting
  static String? composeTeamResponse(
    String prompt, {
    List<String>? userTeams,
    String? userLocation,
  }) {
    if (!isSportsRequest(prompt)) return null;
    final teamResult = TeamColorResolver.resolve(
      // Immediacy words are not part of any team's name and only lower the
      // resolver's confidence for the words that are.
      prompt.replaceAll(_immediacyPattern, ' '),
      userTeams: userTeams,
      userLocation: userLocation,
    );
    // Only return team response for high-confidence matches (>= 0.8).
    // Low-confidence fuzzy matches fall through to Tier 1/3 for better handling.
    if (teamResult == null || !teamResult.isHighConfidence) return null;
    // D5 — "no motion" / "not moving" / "static" / "still" read as Solid, and
    // so does a bare "<team> colors". "<team> design" / "<team> look" with no
    // motion word keeps the team's own default (Theater Chase for most).
    final wantsStatic = asksStatic(prompt) || asksColorsOnly(prompt);
    final context = wantsStatic
        ? EventContext.staticSimple
        : EventThemeLibrary.detectContext(prompt.toLowerCase());
    return _buildCanonicalTeamResponse(
      teamResult.team,
      context,
      motion: !wantsStatic && wantsMotion(prompt),
    );
  }

  static String _buildCanonicalTeamResponse(
    UnifiedTeamEntry team,
    EventContext context, {
    bool motion = false,
  }) {
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
        // The per-effect table (E1 item D) decides the pace, as every other
        // picker does; the team's own default is the fallback.
        speed = effectDefaultSpeedOr(effectId, team.defaultSpeed);
        intensity = team.defaultIntensity;
        isStatic = effectId == 0;
        break;
    }

    // Item 3b: motion was asked for, so the effect MOVES — whatever the
    // team's first suggestion is. "Solid … with motion" is a contradiction
    // the customer resolved by asking for motion. The speed comes from the
    // per-effect table E1 introduced (pickers use the table), so a Chase and
    // a Breathe start at the speed each looks right at.
    if (motion && effectId == 0) {
      effectId = _animatedEffectFor(team);
      effectName = _effectIdToName(effectId);
      speed = effectDefaultSpeedOr(effectId, team.defaultSpeed);
      intensity = team.defaultIntensity;
      isStatic = false;
    }

    final shortName = _teamShortName(team.officialName);
    String patternName;
    String subtitle;

    switch (context) {
      case EventContext.party:
        patternName = '$shortName $effectName';
        subtitle = 'High-energy $shortName colors chase';
        break;
      case EventContext.celebration:
        patternName = '$shortName $effectName';
        subtitle = 'Festive $shortName sparkle';
        break;
      case EventContext.elegant:
        patternName = '$shortName $effectName';
        subtitle = 'Sophisticated $shortName glow';
        break;
      case EventContext.staticSimple:
        patternName = '$shortName $effectName';
        subtitle = 'Pure $shortName team colors';
        break;
      case EventContext.romantic:
      case EventContext.neutral:
        patternName = '$shortName $effectName';
        subtitle = '$shortName team pride';
        break;
    }

    // Every team color is funneled through safeRGBW so the W channel is
    // explicit (W=0). Without this, WLED auto-extracts W = min(R,G,B) from
    // any 3-channel input, washing dark branded reds (Chiefs `[227,24,55]`)
    // into pink on RGBW strips. The colours are the team's LED table
    // (`ledOptimizedRgb`), never the brand hex.
    final segCol = _teamSegmentColors(team);
    final colorsArray = <Map<String, dynamic>>[
      for (var i = 0; i < team.colors.length; i++)
        {'name': team.colors[i].name, 'rgb': segCol[i]},
    ];

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

    // Funnel every holiday color through safeRGBW for consistency with the
    // team path. rgbToRgbw(forceZeroWhite: true) already produces a 4-channel
    // result; safeRGBW guarantees clamping and an explicit W slot, so a
    // future regression that introduces a 3-channel array can't cause WLED
    // to auto-extract the white channel.
    final colorsArray = holiday.colors.map((c) {
      return {
        'name': c.name,
        'rgb': safeRGBW(rgbToRgbw(c.r, c.g, c.b, forceZeroWhite: true)),
      };
    }).toList();

    final segCol = holiday.colors
        .map((c) => safeRGBW(rgbToRgbw(c.r, c.g, c.b, forceZeroWhite: true)))
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
              ? [safeRGBW(rgbToRgbw(255, 255, 255, forceZeroWhite: true))]
              : segCol,
          'fx': effectId,
          'sx': speed,
          'ix': intensity,
        }
      ],
    };

    final jsonObject = {
      'patternName': '${holiday.name} $effectName',
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

  /// Returns a short, recognizable team name for pattern naming.
  /// Delegates to teamShortName() in pattern_display_name.dart, which owns
  /// the override map used by both LuminaBrain composition and the Now
  /// Playing display chain.
  @Deprecated(
      'Use teamShortName() from lib/features/patterns/utils/pattern_display_name.dart. '
      'Kept as a thin delegation for one release cycle so prior internal callers '
      'don\'t need to be migrated in this commit.')
  static String _teamShortName(String officialName) {
    return teamShortName(officialName);
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
      WidgetRef ref, String userPrompt, {double temperature = 0.1}) async {
    final contextBlock = _buildContextBlock(ref);
    return LuminaAI.generateWledJson(userPrompt,
        contextBlock: contextBlock, temperature: temperature);
  }

  static Future<Map<String, dynamic>> generateWledJsonFromRef(
      Ref ref, String userPrompt, {double temperature = 0.1}) async {
    final contextBlock = _buildContextBlockFromRef(ref);
    return LuminaAI.generateWledJson(userPrompt,
        contextBlock: contextBlock, temperature: temperature);
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
      buffer.writeln('LED range ${config.globalStartOf(segment)} to '
          '${config.globalEndOf(segment)}');
    }

    if (highlightAnchors) {
      final anchors = <String>[];
      for (final segment in config.segments) {
        for (final anchorIdx in segment.anchorPixels) {
          final globalIdx = config.globalStartOf(segment) + anchorIdx;
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
        // Hand the AI proxy the user's IANA zone so it grounds "tonight"/
        // "tomorrow" against the real local clock (day-part bug fix).
        if (profile.timeZone != null && profile.timeZone!.trim().isNotEmpty) {
          LuminaAI.clientTimeZone = profile.timeZone!.trim();
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
    } catch (e) {
      debugPrint('LuminaBrain variety profile read error: $e');
    }

    // Audio reactivity context — enables AI to suggest mic-driven
    // effects when controller hardware supports it
    try {
      final ip = ref.read(selectedDeviceIpProvider);
      if (ip != null) {
        final capAsync = ref.read(audioCapabilityProvider(ip));
        capAsync.whenData((cap) {
          if (cap.isSupported) {
            buffer.write('\n\nAUDIO REACTIVITY:\n');
            buffer.writeln('- Supported: YES (onboard MEMS microphone detected)');
            if (cap.audioReactiveEffects.isNotEmpty) {
              // Fetch effect names to build a readable list
              final effectNamesAsync = ref.read(wledEffectNamesProvider(ip));
              final effectNames = effectNamesAsync.valueOrNull ?? [];
              final arEffectNames = <String>[];
              for (final fxId in cap.audioReactiveEffects) {
                if (fxId < effectNames.length) {
                  final raw = effectNames[fxId];
                  arEffectNames.add(raw.startsWith('* ') ? raw.substring(2) : raw);
                } else {
                  arEffectNames.add('Effect $fxId');
                }
              }
              buffer.writeln('- Available Audio Effects (${arEffectNames.length}): ${arEffectNames.join(', ')}');
            }
            // Check if current effect is audio-reactive
            try {
              final state = ref.read(wledStateProvider);
              if (cap.audioReactiveEffects.contains(state.effectId)) {
                buffer.writeln('- Currently Active Audio Effect: YES (effect ID ${state.effectId})');
              }
            } catch (e) {
              debugPrint('Error in LuminaBrain checking audio-reactive state: $e');
            }
          } else {
            buffer.writeln('\nAUDIO REACTIVITY: Not supported on this controller');
          }
        });
      }
    } catch (e) {
      debugPrint('LuminaBrain audio context read error: $e');
    }

    // Defensive sanitization: strip any sensitive values that could have been
    // entered freeform by the user (IPs, URLs, tokens) before sending to AI.
    return _sanitizeResponse(buffer.toString());
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
        // Hand the AI proxy the user's IANA zone so it grounds "tonight"/
        // "tomorrow" against the real local clock (day-part bug fix).
        if (profile.timeZone != null && profile.timeZone!.trim().isNotEmpty) {
          LuminaAI.clientTimeZone = profile.timeZone!.trim();
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

    // Audio reactivity context — enables AI to suggest mic-driven
    // effects when controller hardware supports it
    try {
      final ip = ref.read(selectedDeviceIpProvider);
      if (ip != null) {
        final capAsync = ref.read(audioCapabilityProvider(ip));
        capAsync.whenData((cap) {
          if (cap.isSupported) {
            buffer.write('\n\nAUDIO REACTIVITY:\n');
            buffer.writeln('- Supported: YES (onboard MEMS microphone detected)');
            if (cap.audioReactiveEffects.isNotEmpty) {
              final effectNamesAsync = ref.read(wledEffectNamesProvider(ip));
              final effectNames = effectNamesAsync.valueOrNull ?? [];
              final arEffectNames = <String>[];
              for (final fxId in cap.audioReactiveEffects) {
                if (fxId < effectNames.length) {
                  final raw = effectNames[fxId];
                  arEffectNames.add(raw.startsWith('* ') ? raw.substring(2) : raw);
                } else {
                  arEffectNames.add('Effect $fxId');
                }
              }
              buffer.writeln('- Available Audio Effects (${arEffectNames.length}): ${arEffectNames.join(', ')}');
            }
          } else {
            buffer.writeln('\nAUDIO REACTIVITY: Not supported on this controller');
          }
        });
      }
    } catch (e) {
      debugPrint('LuminaBrain audio context read error: $e');
    }

    // Defensive sanitization: strip any sensitive values that could have been
    // entered freeform by the user (IPs, URLs, tokens) before sending to AI.
    return _sanitizeResponse(buffer.toString());
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
      buffer.write(': LEDs ${config.globalStartOf(segment)}-'
          '${config.globalEndOf(segment)}');
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

  /// True when the query is about a team: it mentions a sport or team keyword
  /// (game day, NFL, playoffs…) OR it names a known team ("Chiefs", "KC
  /// Chiefs", "the Chiefs", "Kansas City Chiefs"). Gates team colour
  /// resolution so "fireworks" cannot fuzzy-match a "fire" alias.
  ///
  /// +110 E2 item 3: the keyword-only gate ([hasExplicitSportsKeyword]) was
  /// why "give me a chiefs design with motion right now" never reached the
  /// team tier — the sentence has no sports KEYWORD, only a team NAME.
  @visibleForTesting
  static bool isSportsRequest(String query) =>
      hasExplicitSportsKeyword(query) || mentionsKnownTeam(query);

  /// Single-word aliases that are also ordinary lighting words. A prompt
  /// that contains only one of these ("fire effect", "heat wave", "blues")
  /// is not a team request; a multi-word alias ("chicago fire") still is.
  static const Set<String> _ambiguousTeamWords = {
    'fire', 'heat', 'magic', 'jazz', 'wild', 'sun', 'suns', 'thunder',
    'lightning', 'blues', 'reds', 'giants', 'rangers', 'kings', 'stars',
    'wings', 'storm', 'united', 'city', 'dc', 'red', 'blue', 'gold', 'white',
    'orange', 'green', 'browns', 'brown', 'wave', 'flames', 'flame', 'crew',
    'union', 'galaxy', 'earthquakes', 'rapids', 'dynamo', 'revolution',
    'nets', 'rockets', 'spurs', 'bucks', 'jets', 'sharks', 'wizards',
  };

  /// True when [query] names a team the app knows: an exact alias match on
  /// at least one whole word, and not a lone ordinary word.
  @visibleForTesting
  static bool mentionsKnownTeam(String query) {
    final cleaned = query.replaceAll(_immediacyPattern, ' ');
    final result = TeamColorResolver.resolve(cleaned);
    if (result == null) return false;
    if (result.matchType != TeamMatchType.exact &&
        result.matchType != TeamMatchType.partial) {
      return false;
    }
    final alias = result.matchedAlias.trim();
    if (alias.contains(' ')) return true;
    if (alias.length < 3) return false;
    return !_ambiguousTeamWords.contains(alias);
  }

  /// The words the app knows for a lighting prompt, so a miss can say what
  /// was and was not understood instead of "describe the colors or mood"
  /// (+110 E2 item 3e). Pure.
  static String describeMisunderstanding(String prompt) {
    final words = prompt
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    const known = {
      // request scaffolding
      'give', 'me', 'a', 'an', 'the', 'my', 'some', 'please', 'can', 'you',
      'i', 'want', 'lights', 'light', 'design', 'pattern', 'look', 'make',
      'set', 'do', 'show', 'put', 'on', 'to', 'with', 'and', 'for', 'of',
      'it', 'them', 'up', 'in', 'at', 'now', 'right', 'tonight', 'today',
      'this', 'that', 'like', 'something', 'kind', 'colors', 'colours',
      'color', 'colour', 'effect', 'mode', 'theme', 'vibe', 'vibes',
      'lumina', 'house', 'roofline', 'home', 'whole', 'all', 'just', 'only',
    };
    final colourWords = LocalCommandParser.knownColorWords;
    final understood = <String>[];
    final unknown = <String>[];
    for (final w in words) {
      if (known.contains(w)) continue;
      if (colourWords.contains(w) ||
          _motionPattern.hasMatch(w) ||
          hasExplicitSportsKeyword(w) ||
          HolidayColorDatabase.resolve(w).resolved) {
        understood.add(w);
      } else {
        unknown.add(w);
      }
    }
    final tail = 'Tell me the colours you want, a team, or a holiday and '
        "I'll build it.";
    if (unknown.isEmpty) {
      return "I couldn't turn that into a design. $tail";
    }
    final quoted = unknown.map((w) => '"$w"').join(', ');
    if (understood.isEmpty) {
      return "I didn't recognise $quoted. $tail";
    }
    return 'I understood ${understood.map((w) => '"$w"').join(', ')} but '
        "not $quoted, so I couldn't build a design from it. $tail";
  }

  /// Returns true when the query explicitly mentions a sport, team keyword,
  /// or game-day context. This is the PRE-+110 gate, kept for the phrase
  /// table: it never matched a bare team name.
  @visibleForTesting
  static bool hasExplicitSportsKeyword(String query) {
    final lower = query.toLowerCase();
    const sportsKeywords = [
      'team', 'teams', 'game day', 'gameday', 'game night',
      'sports', 'sport', 'football', 'baseball', 'basketball',
      'hockey', 'soccer', 'nfl', 'mlb', 'nba', 'nhl', 'mls',
      'ncaa', 'college', 'playoff', 'playoffs', 'super bowl',
      'superbowl', 'world series', 'stanley cup', 'march madness',
      'my team', 'my teams', 'our team', 'go team',
      // Common team-related request patterns
      'colors for the', 'show me the', 'give me the',
    ];
    // Check for explicit sports keywords
    if (sportsKeywords.any((kw) => lower.contains(kw))) return true;

    // Check if the query is primarily a team name (very short, 1-3 words)
    // like "chiefs", "royals", "go royals" — let team resolver handle these
    final words = lower.split(RegExp(r'\s+')).where((w) => w.length > 1).toList();
    if (words.length <= 3) {
      // Short queries that are just team names should go through
      // But only if they don't contain design/effect keywords
      const designKeywords = [
        'design', 'effect', 'pattern', 'fireworks', 'twinkle',
        'chase', 'rainbow', 'sparkle', 'fire', 'glitter', 'mood',
        'calm', 'party', 'romantic', 'elegant', 'spooky', 'ocean',
        'warm', 'cool', 'bright', 'dim', 'color', 'colours',
      ];
      if (designKeywords.any((kw) => lower.contains(kw))) return false;
    }

    return false;
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
