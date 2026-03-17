import 'package:flutter/foundation.dart';

import 'package:nexgen_command/features/ai/compound_command_detector.dart';
import 'package:nexgen_command/features/ai/user_variety_profile.dart';

// ---------------------------------------------------------------------------
// Input model — resolved lighting theme
// ---------------------------------------------------------------------------

/// A fully resolved lighting theme: colors + WLED effect suggestions.
///
/// Built by [LuminaBrain] after tier-0 team/holiday resolution succeeds,
/// then passed to [LuminaSmartScheduler] for multi-day planning.
class ResolvedTheme {
  final String name; // e.g., "Kansas City Royals", "Christmas"

  /// Color entries in display order, each with a name and RGBW array.
  final List<Map<String, dynamic>> colorEntries; // [{name: str, rgb: [r,g,b,w]}]

  /// WLED effect IDs ordered by how well they suit this theme.
  /// The scheduler uses these as the base effect pool.
  final List<int> suggestedEffects;

  final int defaultSpeed;
  final int defaultIntensity;

  const ResolvedTheme({
    required this.name,
    required this.colorEntries,
    required this.suggestedEffects,
    this.defaultSpeed = 128,
    this.defaultIntensity = 180,
  });
}

// ---------------------------------------------------------------------------
// Output models
// ---------------------------------------------------------------------------

/// A single scheduled occurrence — one night (or day) with a specific pattern.
class ScheduledOccurrence {
  final int dayIndex; // 0 = first day/night, 1 = second, etc.
  final DateTime date;
  final String patternName;
  final String effectName;
  final int effectId;
  final int speed;
  final int intensity;
  final List<List<int>> colors; // RGBW arrays
  final Map<String, dynamic> wledPayload;
  final TimeTrigger startTrigger;
  final TimeTrigger endTrigger;

  const ScheduledOccurrence({
    required this.dayIndex,
    required this.date,
    required this.patternName,
    required this.effectName,
    required this.effectId,
    required this.speed,
    required this.intensity,
    required this.colors,
    required this.wledPayload,
    required this.startTrigger,
    required this.endTrigger,
  });
}

/// The complete multi-day schedule plan returned by [LuminaSmartScheduler].
class SmartSchedulePlan {
  final String themeName;
  final List<ScheduledOccurrence> occurrences;
  final UserVarietyProfile appliedProfile;
  final String summaryText;

  /// True when two or more different effect IDs appear in the plan.
  final bool hasVariety;

  const SmartSchedulePlan({
    required this.themeName,
    required this.occurrences,
    required this.appliedProfile,
    required this.summaryText,
    required this.hasVariety,
  });

  int get dayCount => occurrences.length;

  bool get usesSunsetSunrise =>
      occurrences.isNotEmpty &&
      (occurrences.first.startTrigger == TimeTrigger.sunset ||
          occurrences.first.endTrigger == TimeTrigger.sunrise);
}

// ---------------------------------------------------------------------------
// Scheduler
// ---------------------------------------------------------------------------

/// Converts compound voice commands into variety-aware multi-day schedule plans.
///
/// Design principle: the schedule should feel INTENTIONAL to the user.
/// A Royals fan who says "give me Royals designs all week" should see:
///   - Monday:    Breathe — calm and royal, sets the tone
///   - Tuesday:   Running — blue chasing gold along the roofline
///   - Wednesday: Twinkle — sparkle like stadium lights
///   - Thursday:  Theater Chase — crisp and classic
///   - Friday:    Fireworks — it's the weekend, let's celebrate
///   - Saturday:  Running (fast) — game day energy
///   - Sunday:    Solid — strong and proud closing night
///
/// OR, if user preference analysis shows they like consistency:
///   - Every night: Breathe — the same elegant pulse, reliably beautiful.
///
/// The [UserVarietyProfile] makes this call automatically.
class LuminaSmartScheduler {
  LuminaSmartScheduler._();

  // -----------------------------------------------------------------------
  // Effect pools and metadata
  // -----------------------------------------------------------------------

  /// Ordered effect IDs suited for team/sports/pride themes.
  static const List<int> _teamEffectPool = [
    2,   // Breathe        — elegant pulse, great opener/closer
    41,  // Running        — chase effect, directional energy
    43,  // Twinkle        — sparkle, stadium-light feel
    12,  // Theater Chase  — crisp, traditional chase
    52,  // Fireworks      — celebratory, peak moments
    0,   // Solid          — strong, proud, no movement
    63,  // Candle         — warm atmospheric glow
  ];

  /// Ordered effect IDs for holiday themes.
  static const List<int> _holidayEffectPool = [
    43,  // Twinkle   — classic holiday sparkle
    2,   // Breathe   — soft glow
    52,  // Fireworks — festive bursts
    41,  // Running   — chase effects
    12,  // Theater Chase
    63,  // Candle    — warm holiday warmth
    0,   // Solid     — bold color
  ];

  static const Map<int, String> _effectNames = {
    0: 'Solid',
    2: 'Breathe',
    12: 'Theater Chase',
    41: 'Running',
    43: 'Twinkle',
    52: 'Fireworks',
    63: 'Candle',
    65: 'Fire',
  };

  /// Visual category groups — effects within the same group look similar,
  /// so we spread across groups before repeating within one.
  static const Map<String, List<int>> _visualGroups = {
    'pulse':   [2, 63],      // Breathe, Candle
    'chase':   [12, 41],     // Theater Chase, Running
    'sparkle': [43, 52],     // Twinkle, Fireworks
    'solid':   [0],          // Solid
  };

  /// Returns the visual group key for an effect ID, or null if unmapped.
  static String? _groupOf(int fxId) {
    for (final entry in _visualGroups.entries) {
      if (entry.value.contains(fxId)) return entry.key;
    }
    return null;
  }

  /// Day-of-week energy multipliers applied to speed.
  static const Map<int, double> _dayEnergyMultiplier = {
    1: 0.70,  // Monday    — calm, fresh start
    2: 0.80,  // Tuesday   — building
    3: 0.85,  // Wednesday — mid-week
    4: 0.90,  // Thursday  — almost there
    5: 1.00,  // Friday    — peak energy
    6: 1.00,  // Saturday  — peak energy
    7: 0.75,  // Sunday    — reflective, winding down
  };

  // -----------------------------------------------------------------------
  // Variety-aware effect rotation
  // -----------------------------------------------------------------------

  /// Builds a deduplicated, visually varied effect rotation.
  ///
  /// For [VarietyPreferenceLevel.consistent], returns the same effect repeated.
  /// For [VarietyPreferenceLevel.subtle], alternates between 2 effects from
  /// different visual groups.
  /// For [varied] and [eclectic], spreads across visual groups round-robin
  /// before repeating within a group, and never repeats an fx ID until the
  /// pool is exhausted.
  static List<int> _buildVarietyRotation({
    required List<int> pool,
    required int count,
    required UserVarietyProfile profile,
  }) {
    if (pool.isEmpty) return List.filled(count, 0);

    // Consistent: same effect every day — no rotation needed.
    if (profile.level == VarietyPreferenceLevel.consistent) {
      return List.filled(count, pool.first);
    }

    // Subtle: pick at most 2 effects from DIFFERENT visual groups.
    if (profile.level == VarietyPreferenceLevel.subtle) {
      final picks = _pickFromDifferentGroups(pool, 2);
      return List.generate(count, (i) => picks[i % picks.length]);
    }

    // Varied / Eclectic: spread across all visual groups, then fill.
    final ordered = _spreadByVisualGroup(pool);

    // For eclectic users, boost effects they've recently engaged with
    // to the front if they exist in the pool.
    final List<int> final_;
    if (profile.level == VarietyPreferenceLevel.eclectic &&
        profile.recentEffectIds.isNotEmpty) {
      final boosted = ordered
          .where((id) => profile.recentEffectIds.contains(id))
          .toList();
      final rest = ordered
          .where((id) => !profile.recentEffectIds.contains(id))
          .toList();
      final_ = [...boosted, ...rest];
    } else {
      final_ = ordered;
    }

    // Generate rotation: cycle through the ordered list without repeating
    // until the pool is exhausted.
    return List.generate(count, (i) => final_[i % final_.length]);
  }

  /// Pick up to [maxPicks] effects from the pool, preferring effects
  /// from different visual groups.
  static List<int> _pickFromDifferentGroups(List<int> pool, int maxPicks) {
    final result = <int>[];
    final usedGroups = <String>{};

    // First pass: one per group
    for (final id in pool) {
      if (result.length >= maxPicks) break;
      final group = _groupOf(id);
      if (group != null && usedGroups.contains(group)) continue;
      result.add(id);
      if (group != null) usedGroups.add(group);
    }

    // If we still need more, fill from remaining pool
    for (final id in pool) {
      if (result.length >= maxPicks) break;
      if (!result.contains(id)) result.add(id);
    }

    return result.isEmpty ? [pool.first] : result;
  }

  /// Reorders the pool so that consecutive entries come from different
  /// visual groups as much as possible. Round-robins across groups,
  /// picking one effect per group per round.
  static List<int> _spreadByVisualGroup(List<int> pool) {
    // Bucket effects by visual group
    final buckets = <String, List<int>>{};
    final ungrouped = <int>[];

    for (final id in pool) {
      final group = _groupOf(id);
      if (group != null) {
        (buckets[group] ??= []).add(id);
      } else {
        ungrouped.add(id);
      }
    }

    // Round-robin across groups
    final result = <int>[];
    final groupKeys = buckets.keys.toList();
    final indices = {for (final k in groupKeys) k: 0};
    bool added = true;

    while (added) {
      added = false;
      for (final key in groupKeys) {
        final bucket = buckets[key]!;
        final idx = indices[key]!;
        if (idx < bucket.length) {
          result.add(bucket[idx]);
          indices[key] = idx + 1;
          added = true;
        }
      }
    }

    // Append ungrouped effects at the end
    result.addAll(ungrouped);
    return result;
  }

  // -----------------------------------------------------------------------
  // Main entry point
  // -----------------------------------------------------------------------

  static SmartSchedulePlan generatePlan({
    required ResolvedTheme theme,
    required CompoundCommandResult command,
    required UserVarietyProfile userProfile,
    bool isHolidayTheme = false,
  }) {
    final temporal = command.temporal;
    if (temporal == null) {
      throw ArgumentError(
          'LuminaSmartScheduler.generatePlan requires temporal intent');
    }

    final dayCount = temporal.dayCount;
    final today = DateTime.now();

    final basePool = isHolidayTheme ? _holidayEffectPool : _teamEffectPool;
    var effectPool = [
      ...theme.suggestedEffects,
      ...basePool,
    ].toSet().toList();

    // --- Motion filter: if user asked for "motion" or "animated",
    // remove Solid (fx 0) from the pool entirely.
    final promptLower = command.lightingIntent.toLowerCase();
    if (promptLower.contains('motion') || promptLower.contains('animated')) {
      effectPool.removeWhere((id) => id == 0);
      if (effectPool.isEmpty) effectPool = [2]; // fallback to Breathe
    }

    // --- Minimum variety warning
    if (effectPool.length < dayCount) {
      debugPrint('⚠️ AutopilotScheduler: only ${effectPool.length} distinct '
          'effects available for $dayCount-day request — some effects will repeat');
    }

    // --- Build variety-aware rotation using visual group spreading
    final effectRotation = _buildVarietyRotation(
      pool: effectPool,
      count: dayCount,
      profile: userProfile,
    );

    final dynamicParams = userProfile.buildDynamicVariation(count: dayCount);

    final segColors = theme.colorEntries
        .map((c) => (c['rgb'] as List<dynamic>).cast<int>())
        .toList();

    if (segColors.isEmpty) {
      segColors.add([0, 0, 255, 0]);
    }

    final occurrences = <ScheduledOccurrence>[];

    for (int i = 0; i < dayCount; i++) {
      final date = today.add(Duration(days: i));
      final dayOfWeek = date.weekday;
      final energyMultiplier = _dayEnergyMultiplier[dayOfWeek] ?? 0.85;

      final effectId = effectRotation[i];
      final effectName = _effectNames[effectId] ?? 'Effect $effectId';
      final baseParams = dynamicParams[i];

      final rawSpeed = baseParams['speed'] ?? theme.defaultSpeed;
      final speed = (rawSpeed * energyMultiplier).round().clamp(30, 255);
      final intensity = baseParams['intensity'] ?? theme.defaultIntensity;

      final wledPayload = {
        'on': true,
        'bri': 255,
        'seg': [
          {
            'id': 0,
            'on': true,
            'bri': 255,
            'col': segColors,
            'fx': effectId,
            'sx': speed,
            'ix': intensity,
          }
        ],
      };

      final dayLabel = _dayName(date);
      final patternName = '${theme.name} — $dayLabel (${_moodLabel(effectId)})';

      occurrences.add(ScheduledOccurrence(
        dayIndex: i,
        date: date,
        patternName: patternName,
        effectName: effectName,
        effectId: effectId,
        speed: speed,
        intensity: intensity,
        colors: segColors,
        wledPayload: wledPayload,
        startTrigger: temporal.startTrigger,
        endTrigger: temporal.endTrigger,
      ));

      debugPrint(
          '📅 Day ${i + 1} ($dayLabel): $effectName speed=$speed intensity=$intensity');
    }

    final hasVariety = occurrences.map((o) => o.effectId).toSet().length > 1;

    final summaryText = _buildSummaryText(
      theme: theme,
      occurrences: occurrences,
      userProfile: userProfile,
      temporal: temporal,
      hasVariety: hasVariety,
    );

    debugPrint('🗓️ SmartSchedulePlan: ${theme.name}, $dayCount days, '
        'variety=${userProfile.level.name}, hasVariety=$hasVariety');

    return SmartSchedulePlan(
      themeName: theme.name,
      occurrences: occurrences,
      appliedProfile: userProfile,
      summaryText: summaryText,
      hasVariety: hasVariety,
    );
  }

  // -----------------------------------------------------------------------
  // Response JSON builder
  // -----------------------------------------------------------------------

  static Map<String, dynamic> planToResponseJson(SmartSchedulePlan plan) {
    if (plan.occurrences.isEmpty) return {};

    final first = plan.occurrences.first;
    final previewColors = first.colors
        .map((rgb) => {
              'name': colorNameFromRgbw(rgb),
              'rgb': rgb,
            })
        .toList();

    return {
      'patternName': '${plan.themeName} — ${plan.dayCount}-Night Schedule',
      'thought': plan.summaryText,
      'colors': previewColors,
      'effect': {
        'name': first.effectName,
        'id': first.effectId,
        'isStatic': first.effectId == 0,
        'direction': first.effectId == 41 ? 'right' : 'none',
      },
      'speed': first.speed,
      'intensity': first.intensity,
      'isSchedule': true,
      'scheduleType': 'multi_day',
      'dayCount': plan.dayCount,
      'hasVariety': plan.hasVariety,
      'varietyLevel': plan.appliedProfile.level.name,
      'startTrigger': first.startTrigger.name,
      'endTrigger': first.endTrigger.name,
      'usesSunsetSunrise': plan.usesSunsetSunrise,
      'schedule': plan.occurrences
          .map((o) => {
                'dayIndex': o.dayIndex,
                'date': o.date.toIso8601String(),
                'dayName': _dayName(o.date),
                'patternName': o.patternName,
                'effectId': o.effectId,
                'effectName': o.effectName,
                'speed': o.speed,
                'intensity': o.intensity,
                'colors': o.colors
                    .map((rgb) => {
                          'name': colorNameFromRgbw(rgb),
                          'rgb': rgb,
                        })
                    .toList(),
                'startTrigger': o.startTrigger.name,
                'endTrigger': o.endTrigger.name,
                'wled': o.wledPayload,
              })
          .toList(),
      'wled': first.wledPayload,
    };
  }

  // -----------------------------------------------------------------------
  // Summary text
  // -----------------------------------------------------------------------

  static String _buildSummaryText({
    required ResolvedTheme theme,
    required List<ScheduledOccurrence> occurrences,
    required UserVarietyProfile userProfile,
    required TemporalIntent temporal,
    required bool hasVariety,
  }) {
    final days = occurrences.length;
    final timeDesc = temporal.startTrigger == TimeTrigger.sunset
        ? 'sunset to sunrise'
        : temporal.startTrigger == TimeTrigger.dusk
            ? 'dusk to dawn'
            : temporal.startTrigger == TimeTrigger.allDay
                ? 'all ${days > 1 ? "night" : "day"}'
                : 'each night';

    if (days == 1) {
      return "I've set up a ${occurrences.first.effectName} design "
          "in ${theme.name} colors running $timeDesc. Looking good! ✨";
    }

    if (hasVariety) {
      final uniqueEffects = occurrences
          .map((o) => o.effectName)
          .toSet()
          .take(4)
          .join(', ');

      return "I've scheduled $days nights of ${theme.name} colors running "
          "$timeDesc — rotating through $uniqueEffects and more. "
          "Every night brings something fresh to your roofline! 🎨";
    } else {
      return "I've scheduled $days nights of ${theme.name} colors with a "
          "consistent ${occurrences.first.effectName} effect running "
          "$timeDesc. Reliable and beautiful every night. ✨";
    }
  }

  // -----------------------------------------------------------------------
  // Helpers
  // -----------------------------------------------------------------------

  static String _dayName(DateTime date) {
    const names = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    return names[(date.weekday - 1).clamp(0, 6)];
  }

  static String _moodLabel(int effectId) {
    const labels = {
      0: 'Bold & Solid',
      2: 'Breathe',
      12: 'Chase',
      41: 'Running',
      43: 'Sparkle',
      52: 'Fireworks',
      63: 'Candle Glow',
    };
    return labels[effectId] ?? 'Dynamic';
  }

  /// Public color name helper — called externally by [LuminaBrain]
  /// when recording schedule occurrences into suggestion history.
  static String colorNameFromRgbw(List<int> rgbw) {
    if (rgbw.isEmpty) return 'Color';
    final r = rgbw[0];
    final g = rgbw.length > 1 ? rgbw[1] : 0;
    final b = rgbw.length > 2 ? rgbw[2] : 0;

    if (r > 150 && g < 80 && b < 80) return 'Red';
    if (g > 150 && r < 80 && b < 80) return 'Green';
    if (b > 150 && r < 80 && g < 80) return 'Blue';
    if (r > 180 && g > 150 && b < 80) return 'Gold';
    if (r > 200 && g > 200 && b > 200) return 'White';
    if (r > 150 && g < 80 && b > 150) return 'Purple';
    if (r < 80 && g > 150 && b > 150) return 'Cyan';
    if (r > 180 && g > 80 && b < 80) return 'Orange';
    return 'Custom';
  }
}