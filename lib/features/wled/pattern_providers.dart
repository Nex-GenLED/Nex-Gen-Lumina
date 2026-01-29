import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/data/us_federal_holidays.dart';
import 'package:nexgen_command/features/autopilot/learning_providers.dart';
import 'package:nexgen_command/features/wled/mock_pattern_repository.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/services/sports_schedule_service.dart';
import 'package:nexgen_command/utils/sun_utils.dart';
import 'package:nexgen_command/features/wled/event_theme_library.dart';
import 'package:nexgen_command/models/usage_analytics_models.dart';

/// Repository provider for the Pattern Library.
/// For now we use an in-memory mock; can be swapped to Firestore later.
final patternRepositoryProvider = Provider<MockPatternRepository>((ref) => MockPatternRepository());

/// Loads all pattern categories (folders)
final patternCategoriesProvider = FutureProvider<List<PatternCategory>>((ref) async {
  final repo = ref.watch(patternRepositoryProvider);
  return repo.getCategories();
});

/// Loads items for a given category id
final patternItemsByCategoryProvider = FutureProvider.family<List<PatternItem>, String>((ref, categoryId) async {
  final repo = ref.watch(patternRepositoryProvider);
  return repo.getItemsByCategory(categoryId);
});

/// Loads sub-categories for a given category id
final patternSubCategoriesByCategoryProvider = FutureProvider.family<List<SubCategory>, String>((ref, categoryId) async {
  final repo = ref.watch(patternRepositoryProvider);
  return repo.getSubCategoriesByCategory(categoryId);
});

/// Lookup a sub-category by id
final subCategoryByIdProvider = FutureProvider.family<SubCategory?, String>((ref, subCategoryId) async {
  final repo = ref.watch(patternRepositoryProvider);
  return repo.getSubCategoryById(subCategoryId);
});

/// Procedurally generate 50 pattern items for a given sub-category
final patternGeneratedItemsBySubCategoryProvider = FutureProvider.family<List<PatternItem>, String>((ref, subCategoryId) async {
  // Use read to avoid rebuild churn and potential hot-reload method tear-off oddities on web
  final repo = ref.read(patternRepositoryProvider);
  try {
    final sub = await repo.getSubCategoryById(subCategoryId);
    if (sub == null) return const <PatternItem>[];
    final items = await repo.generatePatternsForTheme(sub);
    return items;
  } catch (e, st) {
    debugPrint('patternGeneratedItemsBySubCategoryProvider failed: $e\n$st');
    rethrow;
  }
});

/// Rule-based personalized recommendations for gradient patterns.
///
/// Watches:
/// - currentUserProfileProvider for interests, sports teams, and lat/lon
/// - selectedDeviceIpProvider to ensure a device is targeted/compatible
/// - Current date/time to inject seasonal and time-of-day context
///
/// Returns 3-5 GradientPattern suggestions.
final recommendedPatternsProvider = Provider<List<GradientPattern>>((ref) {
  // We no longer gate recommendations on a connected device.
  // If no device is selected, we still produce suggestions; play actions will guard for device nulls.
  // final ip = ref.watch(selectedDeviceIpProvider);
  // if (ip == null || ip.isEmpty) {
  //   return const <GradientPattern>[];
  // }

  final now = DateTime.now();
  final month = now.month; // 1..12
  final day = now.day;

  final profileAsync = ref.watch(currentUserProfileProvider);
  final profile = profileAsync.maybeWhen(data: (u) => u, orElse: () => null);

  // Gather interests and coords (best-effort; null-safe)
  final interests = {
    ...?profile?.interestTags,
    ...?profile?.favoriteHolidays,
  }.map((e) => e.toLowerCase()).toSet();
  final teams = {...?profile?.sportsTeams}.map((e) => e.toLowerCase()).toSet();
  final lat = profile?.latitude;
  final lon = profile?.longitude;

  bool isAfterSunset = false;
  if (lat != null && lon != null) {
    try {
      final sunset = SunUtils.sunsetLocal(lat, lon, now);
      if (sunset != null) isAfterSunset = now.isAfter(sunset);
    } catch (e) {
      debugPrint('recommendedPatternsProvider sunset check failed: $e');
    }
  } else {
    // Heuristic fallback: consider evening/night after 6pm local
    isAfterSunset = now.hour >= 18 || now.hour < 6;
  }

  // Build a unique set of recommendations by name
  final List<GradientPattern> recs = [];
  final Set<String> added = {};
  void addOnce(GradientPattern p) {
    if (added.contains(p.name)) return;
    recs.add(p);
    added.add(p.name);
  }

  // Date-based rules
  if (month == 12) {
    addOnce(const GradientPattern(
      name: 'Christmas Classic',
      subtitle: 'Red & Green Theater Chase',
      colors: [Color(0xFFFF0000), Color(0xFF00FF00)], // Pure red & green
      effectId: 12,
      effectName: 'Theater Chase',
      direction: 'right',
      isStatic: false,
      speed: 80, // Slower, more elegant chase
      intensity: 200,
    ));
    addOnce(const GradientPattern(
      name: 'The Grinch',
      subtitle: 'Green Breathe with Red accents',
      colors: [Color(0xFF00FF00), Color(0xFFFF0000), Color(0xFF228B22)], // Pure green, pure red, forest green
      effectId: 2,
      effectName: 'Breathe',
      direction: 'none',
      isStatic: false,
      speed: 80,
      intensity: 180,
    ));
    addOnce(const GradientPattern(
      name: 'Winter Wonderland',
      subtitle: 'Icy Blue Twinkle',
      colors: [Color(0xFF00FFFF), Colors.white, Color(0xFF87CEEB)], // Pure cyan, white, sky blue
      effectId: 43,
      effectName: 'Twinkle',
      direction: 'alternating',
      isStatic: false,
      speed: 70, // Gentle twinkle
      intensity: 150,
    ));
  } else if (month == 10) {
    addOnce(const GradientPattern(
      name: 'Spooky Halloween',
      subtitle: 'Orange & Purple Twinkle',
      colors: [Color(0xFFFF8C00), Color(0xFF800080), Color(0xFF00FF00)], // Pure orange, purple, green
      effectId: 43,
      effectName: 'Twinkle',
      direction: 'alternating',
      isStatic: false,
      speed: 70, // Moderate twinkle speed
      intensity: 150,
    ));
    addOnce(const GradientPattern(
      name: 'Haunted House',
      subtitle: 'Purple & Green Flicker',
      colors: [Color(0xFF800080), Color(0xFF00FF00), Color(0xFFFF8C00)], // Purple, green, orange
      effectId: 52,
      effectName: 'Fireworks',
      direction: 'center-out',
      isStatic: false,
      speed: 90, // Slower, more dramatic bursts
      intensity: 180,
    ));
  } else if (month == 7 && day == 4) {
    addOnce(const GradientPattern(
      name: '4th of July Fireworks',
      subtitle: 'Red, White & Blue Burst',
      colors: [Color(0xFFFF0000), Colors.white, Color(0xFF0000FF)], // Pure red, white, pure blue
      effectId: 52,
      effectName: 'Fireworks',
      direction: 'center-out',
      isStatic: false,
      speed: 100, // Moderate fireworks speed
      intensity: 200,
    ));
  }

  // Interest/Sports placeholder logic
  if (interests.contains('chiefs') || teams.contains('chiefs')) {
    addOnce(const GradientPattern(
      name: 'Chiefs Game Day',
      subtitle: 'Gold Chasing Red',
      colors: [Color(0xFFFF0000), Color(0xFFFFD700)], // Pure red, gold
      effectId: 12, // Theater Chase - more faithful to colors than Chase (9)
      effectName: 'Theater Chase',
      direction: 'right',
      isStatic: false,
      speed: 85, // Moderate chase speed
      intensity: 180,
    ));
  }
  if (interests.contains('minimalist')) {
    addOnce(const GradientPattern(
      name: 'Minimalist Elegance',
      subtitle: 'Static Cool White',
      colors: [Color(0xFF708090), Colors.white], // Slate gray, white
      effectId: 0,
      effectName: 'Solid',
      direction: 'none',
      isStatic: true,
      brightness: 180,
    ));
  }
  if (interests.contains('party')) {
    addOnce(const GradientPattern(
      name: 'Party Neon',
      subtitle: 'Neon Fireworks',
      colors: [Color(0xFFFF69B4), Color(0xFF800080), Color(0xFF00FFFF)], // Hot pink, purple, cyan
      effectId: 52,
      effectName: 'Fireworks',
      direction: 'center-out',
      isStatic: false,
      speed: 150, // Energetic but not frantic
      intensity: 200,
    ));
  }
  if (interests.contains('sports')) {
    addOnce(const GradientPattern(
      name: 'Team Spirit',
      subtitle: 'Blue & White Running',
      colors: [Color(0xFF0000FF), Colors.white], // Pure blue, white
      effectId: 41,
      effectName: 'Running',
      direction: 'right',
      isStatic: false,
      speed: 80, // Moderate running speed
      intensity: 150,
    ));
  }

  // Time-of-day rule (past sunset)
  if (isAfterSunset) {
    addOnce(const GradientPattern(
      name: 'Evening Relaxation',
      subtitle: 'Warm Amber Breathe',
      colors: [Color(0xFFFFB347), Color(0xFFFFE4B5)],
      effectId: 2,
      effectName: 'Breathe',
      direction: 'none',
      isStatic: false,
      speed: 60,
      intensity: 150,
      brightness: 150,
    ));
    addOnce(const GradientPattern(
      name: 'Security Glow',
      subtitle: 'Static Warm White',
      colors: [Color(0xFFFFB347), Color(0xFFFFF8DC)], // Warm amber, cornsilk
      effectId: 0,
      effectName: 'Solid',
      direction: 'none',
      isStatic: true,
      brightness: 200,
    ));
  }

  // Ensure 3-5 items with tasteful fallbacks
  void addFallbacks() {
    addOnce(const GradientPattern(
      name: 'Warm White Glow',
      subtitle: 'Static Cozy Ambiance',
      colors: [Color(0xFFFFB347), Color(0xFFFFE4B5)],
      effectId: 0,
      effectName: 'Solid',
      direction: 'none',
      isStatic: true,
      brightness: 220,
    ));
    addOnce(const GradientPattern(
      name: 'Cool Moonlight',
      subtitle: 'Static Crisp White',
      colors: [Color(0xFF87CEFA), Colors.white], // Light sky blue, white
      effectId: 0,
      effectName: 'Solid',
      direction: 'none',
      isStatic: true,
      brightness: 200,
    ));
    addOnce(const GradientPattern(
      name: 'Soft Golden Hour',
      subtitle: 'Gentle Amber Flow',
      colors: [Color(0xFFFFB347), Color(0xFFFF8C00)], // Warm amber, dark orange
      effectId: 41, // Running - uses segment colors (Flow is palette-based)
      effectName: 'Running',
      direction: 'right',
      isStatic: false,
      speed: 80,
      intensity: 128,
      brightness: 200,
    ));
  }

  if (recs.length < 3) addFallbacks();
  if (recs.length > 5) return recs.sublist(0, 5);
  return recs;
});

/// Public, predefined pattern sets used across the Explore screens.
///
/// These were previously static lists inside _ExplorePatternsScreenState.
/// Moved here so they can be reused and tested independently.
class PredefinedPatterns {
  final List<GradientPattern> architecturalElegant;
  final List<GradientPattern> holidaysEvents;
  final List<GradientPattern> sportsTeams;

  const PredefinedPatterns({
    required this.architecturalElegant,
    required this.holidaysEvents,
    required this.sportsTeams,
  });

  List<GradientPattern> get all => [
        ...architecturalElegant,
        ...holidaysEvents,
        ...sportsTeams,
      ];
}

/// Provider for event theme library (deterministic pattern matching)
final eventThemeLibraryProvider = Provider<List<EventTheme>>((ref) {
  return EventThemeLibrary.allThemes;
});

/// Provider to search/match event themes by query
final eventThemeMatchProvider = Provider.family<EventThemeMatch?, String>((ref, query) {
  return EventThemeLibrary.matchQuery(query);
});

/// Provider exposing the public pattern library lists.
final publicPatternLibraryProvider = Provider<PredefinedPatterns>((ref) {
  return const PredefinedPatterns(
    architecturalElegant: [
      GradientPattern(
        name: 'Warm White Glow',
        subtitle: 'Static Cozy Ambiance',
        colors: [Color(0xFFFFB347), Color(0xFFFFE4B5)],
        effectId: 0,
        effectName: 'Solid',
        isStatic: true,
        brightness: 220,
      ),
      GradientPattern(
        name: 'Cool Moonlight',
        subtitle: 'Static Crisp White',
        colors: [Color(0xFF87CEFA), Colors.white], // Light sky blue, white
        effectId: 0,
        effectName: 'Solid',
        isStatic: true,
        brightness: 200,
      ),
      GradientPattern(
        name: 'Golden Elegance',
        subtitle: 'Soft Amber Flow',
        colors: [Color(0xFFFFB347), Color(0xFFFFD700), Color(0xFFFF8C00)], // Warm amber, gold, dark orange
        effectId: 41, // Running - uses segment colors (Flow is palette-based)
        effectName: 'Running',
        direction: 'right',
        isStatic: false,
        speed: 60,
        intensity: 100,
        brightness: 200,
      ),
      GradientPattern(
        name: 'Candle Flicker',
        subtitle: 'Warm Flickering Glow',
        colors: [Color(0xFFFF8C00), Color(0xFFFFB347)],
        effectId: 101,
        effectName: 'Candle',
        isStatic: false,
        speed: 80,
        intensity: 180,
        brightness: 180,
      ),
    ],
    holidaysEvents: [
      GradientPattern(
        name: 'Christmas Classic',
        subtitle: 'Red & Green Chase',
        colors: [Color(0xFFFF0000), Color(0xFF00FF00)], // Pure red & green
        effectId: 12,
        effectName: 'Theater Chase',
        direction: 'right',
        isStatic: false,
        speed: 80, // Slower, elegant chase
        intensity: 180,
      ),
      GradientPattern(
        name: 'Christmas - The Grinch',
        subtitle: 'Green Breathe Effect',
        colors: [Color(0xFF00FF00), Color(0xFFFF0000), Color(0xFF228B22)], // Pure green, pure red
        effectId: 2,
        effectName: 'Breathe',
        isStatic: false,
        speed: 60, // Slow, relaxing breathe
        intensity: 150,
      ),
      GradientPattern(
        name: 'Spooky Halloween',
        subtitle: 'Orange & Purple Twinkle',
        colors: [Color(0xFFFF8C00), Color(0xFF800080), Color(0xFF00FF00)], // Pure orange, purple, green
        effectId: 43,
        effectName: 'Twinkle',
        direction: 'alternating',
        isStatic: false,
        speed: 70, // Moderate twinkle
        intensity: 150,
      ),
      GradientPattern(
        name: '4th of July Fireworks',
        subtitle: 'Red, White & Blue Burst',
        colors: [Color(0xFFFF0000), Colors.white, Color(0xFF0000FF)], // Pure red, white, pure blue
        effectId: 52,
        effectName: 'Fireworks',
        direction: 'center-out',
        isStatic: false,
        speed: 100, // Moderate fireworks
        intensity: 180,
      ),
      GradientPattern(
        name: 'Valentines Romance',
        subtitle: 'Pink & Red Breathe',
        colors: [Color(0xFFFF69B4), Color(0xFFFF0000), Color(0xFFFFB6C1)], // Hot pink, pure red, light pink
        effectId: 2,
        effectName: 'Breathe',
        isStatic: false,
        speed: 50, // Slow, romantic breathe
        intensity: 128,
        brightness: 180,
      ),
    ],
    sportsTeams: [
      GradientPattern(
        name: 'Chiefs - Gold Chasing Red',
        subtitle: 'KC Game Day Chase',
        colors: [Color(0xFFFF0000), Color(0xFFFFD700)], // Pure red, gold
        effectId: 12, // Theater Chase - more faithful to colors than Chase (9)
        effectName: 'Theater Chase',
        direction: 'right',
        isStatic: false,
        speed: 85, // Moderate chase speed
        intensity: 180,
      ),
      GradientPattern(
        name: 'Chiefs - Kingdom Solid',
        subtitle: 'Red & Gold Solid',
        colors: [Color(0xFFFF0000), Color(0xFFFFD700)], // Pure red, gold
        effectId: 0,
        effectName: 'Solid',
        isStatic: true,
        brightness: 255,
      ),
      GradientPattern(
        name: 'Titans - Navy Thunder',
        subtitle: 'Navy & Light Blue Running',
        colors: [Color(0xFF002244), Color(0xFF4B92DB), Color(0xFFC8102E)],
        effectId: 41,
        effectName: 'Running',
        direction: 'right',
        isStatic: false,
        speed: 80, // Moderate running speed
        intensity: 150,
      ),
      GradientPattern(
        name: 'Royals - Blue Wave',
        subtitle: 'Royal Blue Flow',
        colors: [Color(0xFF004687), Colors.white, Color(0xFF7AB2DD)],
        effectId: 41, // Running - uses segment colors (Flow is palette-based)
        effectName: 'Running',
        direction: 'right',
        isStatic: false,
        speed: 70, // Gentle flow
        intensity: 128,
      ),
      GradientPattern(
        name: 'Cowboys - Star Bright',
        subtitle: 'Silver & Blue Chase',
        colors: [Color(0xFF003594), Color(0xFFC0C0C0), Colors.white],
        effectId: 12, // Theater Chase - more faithful to colors
        effectName: 'Theater Chase',
        direction: 'right',
        isStatic: false,
        speed: 85, // Moderate chase speed
        intensity: 150,
      ),
    ],
  );
});

/// Smart recommendations provider that combines:
/// 1. Upcoming holidays (within 2 weeks, Christmas all December)
/// 2. Sports teams with games within 7 days
/// 3. Architectural patterns from learning system
/// 4. Time-of-day and seasonal context
final smartRecommendedPatternsProvider = FutureProvider<List<GradientPattern>>((ref) async {
  final now = DateTime.now();
  final recs = <GradientPattern>[];
  final addedNames = <String>{};

  void addOnce(GradientPattern p) {
    if (addedNames.contains(p.name)) return;
    recs.add(p);
    addedNames.add(p.name);
  }

  // ================== 1. UPCOMING HOLIDAYS (2 weeks, Christmas all December) ==================
  final holidayStart = now;
  // Christmas exception: show all December
  final isDecember = now.month == 12;
  final holidayEnd = isDecember
      ? DateTime(now.year, 12, 31, 23, 59, 59)
      : now.add(const Duration(days: 14));

  final holidays = USFederalHolidays.getHolidaysInRange(holidayStart, holidayEnd);

  for (final holiday in holidays.take(2)) { // Max 2 holiday recommendations
    // Create a pattern from the holiday colors
    final effectId = holiday.suggestedEffectId;
    final effectName = _effectNameFromId(effectId);

    addOnce(GradientPattern(
      name: holiday.name,
      subtitle: _holidaySubtitle(holiday.name),
      colors: holiday.suggestedColors,
      effectId: effectId,
      effectName: effectName,
      isStatic: effectId == 0,
      speed: effectId == 0 ? 0 : 80,
      intensity: effectId == 0 ? 0 : 150,
      brightness: 200,
    ));
  }

  // ================== 2. SPORTS TEAMS WITH UPCOMING GAMES (7 days) ==================
  final profileAsync = ref.watch(currentUserProfileProvider);
  final profile = profileAsync.maybeWhen(data: (u) => u, orElse: () => null);

  if (profile != null && profile.sportsTeams.isNotEmpty) {
    try {
      final sportsService = ref.read(sportsScheduleServiceProvider);
      final gameEnd = now.add(const Duration(days: 7));
      final games = await sportsService.getGamesInRange(
        profile.sportsTeams,
        now,
        gameEnd,
      );

      // Get unique teams with upcoming games
      final teamsWithGames = <String>{};
      for (final game in games) {
        if (teamsWithGames.length >= 2) break; // Max 2 sports recommendations
        teamsWithGames.add(game.teamName);
      }

      // Add pattern for each team with an upcoming game
      for (final teamName in teamsWithGames) {
        final teamColors = _getTeamColorsForPattern(teamName);
        if (teamColors != null && teamColors.isNotEmpty) {
          // Find the game for context
          final game = games.firstWhere((g) => g.teamName == teamName);
          final daysUntil = game.gameTime.difference(now).inDays;
          final gameContext = daysUntil == 0
              ? 'Game Day!'
              : daysUntil == 1
                  ? 'Game Tomorrow'
                  : 'Game in $daysUntil days';

          addOnce(GradientPattern(
            name: '$teamName - $gameContext',
            subtitle: 'vs ${game.opponent}',
            colors: teamColors,
            effectId: 12, // Theater Chase
            effectName: 'Theater Chase',
            direction: 'right',
            isStatic: false,
            speed: 85,
            intensity: 180,
            brightness: 220,
          ));
        }
      }
    } catch (e) {
      debugPrint('smartRecommendedPatternsProvider: Sports fetch failed: $e');
    }
  }

  // ================== 3. ARCHITECTURAL PATTERN FROM LEARNING SYSTEM ==================
  // Check user's pattern preferences and add an architectural recommendation
  try {
    final frequency = await ref.read(patternFrequencyProvider(30).future).catchError((_) => <String, int>{});

    // Look for frequently used architectural-style patterns
    final archPatternNames = ['warm white', 'cool white', 'moonlight', 'golden', 'candle', 'elegance', 'glow'];
    String? preferredArch;
    int maxCount = 0;

    for (final entry in frequency.entries) {
      final lowerName = entry.key.toLowerCase();
      if (archPatternNames.any((arch) => lowerName.contains(arch)) && entry.value > maxCount) {
        preferredArch = entry.key;
        maxCount = entry.value;
      }
    }

    // Add recommended architectural pattern based on preference or time of day
    if (preferredArch != null && maxCount >= 3) {
      // User has a clear architectural preference - recommend similar
      addOnce(GradientPattern(
        name: 'Architectural: $preferredArch',
        subtitle: 'Based on your preferences',
        colors: const [Color(0xFFFFB347), Color(0xFFFFE4B5)],
        effectId: 0,
        effectName: 'Solid',
        isStatic: true,
        brightness: 220,
      ));
    } else {
      // Default architectural recommendation based on time of day
      final hour = now.hour;
      if (hour >= 18 || hour < 6) {
        // Evening/night: warm white
        addOnce(const GradientPattern(
          name: 'Evening Elegance',
          subtitle: 'Warm architectural glow',
          colors: [Color(0xFFFFB347), Color(0xFFFFE4B5)],
          effectId: 0,
          effectName: 'Solid',
          isStatic: true,
          brightness: 200,
        ));
      } else {
        // Daytime: cool white
        addOnce(const GradientPattern(
          name: 'Daylight Accent',
          subtitle: 'Clean architectural lighting',
          colors: [Color(0xFF87CEFA), Colors.white],
          effectId: 0,
          effectName: 'Solid',
          isStatic: true,
          brightness: 180,
        ));
      }
    }
  } catch (e) {
    debugPrint('smartRecommendedPatternsProvider: Architectural preference check failed: $e');
    // Fallback architectural pattern
    addOnce(const GradientPattern(
      name: 'Classic Elegance',
      subtitle: 'Timeless architectural lighting',
      colors: [Color(0xFFFFB347), Color(0xFFFFE4B5)],
      effectId: 0,
      effectName: 'Solid',
      isStatic: true,
      brightness: 200,
    ));
  }

  // ================== 4. FILL WITH BASE RECOMMENDATIONS IF NEEDED ==================
  // Add base seasonal/contextual recommendations if we have room
  final baseRecs = ref.read(recommendedPatternsProvider);
  for (final rec in baseRecs) {
    if (recs.length >= 5) break;
    addOnce(rec);
  }

  return recs.take(5).toList();
});

/// Helper to get effect name from WLED effect ID
String _effectNameFromId(int effectId) {
  const effectNames = {
    0: 'Solid',
    2: 'Breathe',
    9: 'Chase',
    12: 'Theater Chase',
    41: 'Running',
    43: 'Twinkle',
    52: 'Fireworks',
    63: 'Candle',
    74: 'Fireworks',
    82: 'Heartbeat',
    101: 'Candle',
    108: 'Halloween Eyes',
  };
  return effectNames[effectId] ?? 'Effect';
}

/// Helper to generate subtitle for holiday patterns
String _holidaySubtitle(String holidayName) {
  final lower = holidayName.toLowerCase();
  if (lower.contains('christmas')) return 'Red & Green Festive';
  if (lower.contains('halloween')) return 'Spooky Orange & Purple';
  if (lower.contains('valentine')) return 'Romantic Pink & Red';
  if (lower.contains('july') || lower.contains('independence')) return 'Red, White & Blue';
  if (lower.contains('patrick')) return 'Lucky Green';
  if (lower.contains('thanksgiving')) return 'Warm Harvest Colors';
  if (lower.contains('easter')) return 'Pastel Spring Colors';
  if (lower.contains('new year')) return 'Gold & Silver Celebration';
  if (lower.contains('hanukkah')) return 'Blue & White Glow';
  if (lower.contains('diwali')) return 'Festival of Lights';
  return 'Festive Colors';
}

/// Helper to get team colors for pattern generation
List<Color>? _getTeamColorsForPattern(String teamName) {
  final lower = teamName.toLowerCase();

  // NFL teams
  if (lower.contains('chiefs')) return const [Color(0xFFFF0000), Color(0xFFFFD700)];
  if (lower.contains('bills')) return const [Color(0xFF00338D), Color(0xFFC60C30)];
  if (lower.contains('ravens')) return const [Color(0xFF241773), Color(0xFF000000)];
  if (lower.contains('bengals')) return const [Color(0xFFFB4F14), Color(0xFF000000)];
  if (lower.contains('cowboys')) return const [Color(0xFF003594), Color(0xFFC0C0C0)];
  if (lower.contains('eagles')) return const [Color(0xFF004C54), Color(0xFFA5ACAF)];
  if (lower.contains('49ers')) return const [Color(0xFFAA0000), Color(0xFFB3995D)];
  if (lower.contains('packers')) return const [Color(0xFF203731), Color(0xFFFFB612)];
  if (lower.contains('lions')) return const [Color(0xFF0076B6), Color(0xFFB0B7BC)];
  if (lower.contains('broncos')) return const [Color(0xFFFB4F14), Color(0xFF002244)];
  if (lower.contains('raiders')) return const [Color(0xFF000000), Color(0xFFA5ACAF)];
  if (lower.contains('chargers')) return const [Color(0xFF0080C6), Color(0xFFFFC20E)];

  // NBA teams
  if (lower.contains('lakers')) return const [Color(0xFF552583), Color(0xFFFDB927)];
  if (lower.contains('celtics')) return const [Color(0xFF007A33), Color(0xFFFFFFFF)];
  if (lower.contains('warriors')) return const [Color(0xFF1D428A), Color(0xFFFFC72C)];
  if (lower.contains('bulls')) return const [Color(0xFFCE1141), Color(0xFF000000)];
  if (lower.contains('heat')) return const [Color(0xFF98002E), Color(0xFFF9A01B)];

  // MLB teams
  if (lower.contains('yankees')) return const [Color(0xFF003087), Color(0xFFFFFFFF)];
  if (lower.contains('dodgers')) return const [Color(0xFF005A9C), Color(0xFFFFFFFF)];
  if (lower.contains('royals')) return const [Color(0xFF004687), Color(0xFFFFFFFF)];
  if (lower.contains('cardinals')) return const [Color(0xFFC41E3A), Color(0xFF0C2340)];

  // NHL teams
  if (lower.contains('blues')) return const [Color(0xFF002F87), Color(0xFFFCB514)];
  if (lower.contains('bruins')) return const [Color(0xFFFFB81C), Color(0xFF000000)];

  // MLS teams
  if (lower.contains('sporting')) return const [Color(0xFF91B0D5), Color(0xFF002F65)];

  // Default fallback
  return null;
}

// ==================== PINNED CATEGORIES & SAVED DESIGNS ====================

/// Provider for user's pinned category IDs from their profile
final pinnedCategoryIdsProvider = Provider<List<String>>((ref) {
  final profileAsync = ref.watch(currentUserProfileProvider);
  return profileAsync.maybeWhen(
    data: (profile) => profile?.preferredCategoryIds ?? [],
    orElse: () => [],
  );
});

/// Provider for full pinned category objects with their patterns
final pinnedCategoriesProvider = FutureProvider<List<PinnedCategoryData>>((ref) async {
  final pinnedIds = ref.watch(pinnedCategoryIdsProvider);
  if (pinnedIds.isEmpty) return [];

  final repo = ref.read(patternRepositoryProvider);
  final categories = await repo.getCategories();
  final result = <PinnedCategoryData>[];

  for (final categoryId in pinnedIds) {
    final category = categories.firstWhere(
      (c) => c.id == categoryId,
      orElse: () => PatternCategory(id: categoryId, name: 'Unknown', imageUrl: ''),
    );

    // Get sub-categories for this category
    final subCategories = await repo.getSubCategoriesByCategory(categoryId);

    result.add(PinnedCategoryData(
      category: category,
      subCategories: subCategories,
    ));
  }

  return result;
});

/// Data class for a pinned category with its sub-categories
class PinnedCategoryData {
  final PatternCategory category;
  final List<SubCategory> subCategories;

  const PinnedCategoryData({
    required this.category,
    required this.subCategories,
  });
}

/// Notifier for managing pinned categories
class PinnedCategoriesNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Add a category to pinned list
  Future<bool> pinCategory(String categoryId) async {
    final profileAsync = ref.read(currentUserProfileProvider);
    final profile = profileAsync.valueOrNull;
    if (profile == null) return false;

    final currentPinned = List<String>.from(profile.preferredCategoryIds);
    if (currentPinned.contains(categoryId)) return true; // Already pinned

    currentPinned.add(categoryId);

    try {
      final userService = ref.read(userServiceProvider);
      await userService.updateUserProfile(
        profile.id,
        {'preferred_category_ids': currentPinned},
      );
      ref.invalidate(currentUserProfileProvider);
      return true;
    } catch (e) {
      debugPrint('Failed to pin category: $e');
      return false;
    }
  }

  /// Remove a category from pinned list
  Future<bool> unpinCategory(String categoryId) async {
    final profileAsync = ref.read(currentUserProfileProvider);
    final profile = profileAsync.valueOrNull;
    if (profile == null) return false;

    final currentPinned = List<String>.from(profile.preferredCategoryIds);
    if (!currentPinned.contains(categoryId)) return true; // Not pinned

    currentPinned.remove(categoryId);

    try {
      final userService = ref.read(userServiceProvider);
      await userService.updateUserProfile(
        profile.id,
        {'preferred_category_ids': currentPinned},
      );
      ref.invalidate(currentUserProfileProvider);
      return true;
    } catch (e) {
      debugPrint('Failed to unpin category: $e');
      return false;
    }
  }

  /// Check if a category is pinned
  bool isPinned(String categoryId) {
    final pinnedIds = ref.read(pinnedCategoryIdsProvider);
    return pinnedIds.contains(categoryId);
  }
}

final pinnedCategoriesNotifierProvider = AsyncNotifierProvider<PinnedCategoriesNotifier, void>(
  () => PinnedCategoriesNotifier(),
);

// ==================== RECENT PATTERNS ====================

/// Provider for recent patterns (last 5 patterns used, converted to GradientPattern)
final recentPatternsProvider = Provider<AsyncValue<List<GradientPattern>>>((ref) {
  final usageAsync = ref.watch(recentUsageProvider(5));

  return usageAsync.whenData((usageEvents) {
    final patterns = <GradientPattern>[];

    for (final event in usageEvents) {
      // Skip if no meaningful data
      if (event.patternName == null && event.effectName == null && event.colorNames == null) {
        continue;
      }

      // Extract colors from wled payload or color names
      final colors = _extractColorsFromUsageEvent(event);

      patterns.add(GradientPattern(
        name: event.patternName ?? event.effectName ?? 'Recent Pattern',
        subtitle: _formatUsageTime(event.createdAt),
        colors: colors.isNotEmpty ? colors : const [Color(0xFFFFB347), Color(0xFFFFE4B5)],
        effectId: event.effectId ?? 0,
        effectName: event.effectName ?? 'Solid',
        isStatic: event.effectId == null || event.effectId == 0,
        brightness: event.brightness ?? 200,
        speed: event.speed ?? 80,
        intensity: event.intensity ?? 150,
      ));
    }

    return patterns.take(5).toList();
  });
});

/// Extract colors from a usage event
List<Color> _extractColorsFromUsageEvent(PatternUsageEvent event) {
  final colors = <Color>[];

  // Try to extract from wled payload first
  if (event.wledPayload != null) {
    final seg = event.wledPayload!['seg'];
    if (seg is List && seg.isNotEmpty) {
      final firstSeg = seg[0];
      if (firstSeg is Map) {
        final col = firstSeg['col'];
        if (col is List) {
          for (final c in col) {
            if (c is List && c.length >= 3) {
              colors.add(Color.fromARGB(
                255,
                (c[0] as num).toInt().clamp(0, 255),
                (c[1] as num).toInt().clamp(0, 255),
                (c[2] as num).toInt().clamp(0, 255),
              ));
            }
          }
        }
      }
    }
  }

  // Fallback to color names
  if (colors.isEmpty && event.colorNames != null) {
    for (final name in event.colorNames!) {
      final color = _colorFromName(name);
      if (color != null) colors.add(color);
    }
  }

  return colors;
}

/// Convert color name to Color
Color? _colorFromName(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('red')) return Colors.red;
  if (lower.contains('green')) return Colors.green;
  if (lower.contains('blue')) return Colors.blue;
  if (lower.contains('yellow')) return Colors.yellow;
  if (lower.contains('orange')) return Colors.orange;
  if (lower.contains('purple')) return Colors.purple;
  if (lower.contains('pink')) return Colors.pink;
  if (lower.contains('cyan')) return Colors.cyan;
  if (lower.contains('white')) return Colors.white;
  if (lower.contains('warm')) return const Color(0xFFFFB347);
  if (lower.contains('gold')) return const Color(0xFFFFD700);
  return null;
}

/// Format usage time as relative time string
String _formatUsageTime(DateTime time) {
  final now = DateTime.now();
  final diff = now.difference(time);

  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${time.month}/${time.day}';
}

// ============================================================================
// LIBRARY HIERARCHY PROVIDERS
// ============================================================================

/// Provider to get child nodes of a parent node in the library hierarchy.
/// Pass null for parentId to get root categories.
final libraryChildNodesProvider = FutureProvider.family<List<LibraryNode>, String?>((ref, parentId) async {
  final repo = ref.watch(patternRepositoryProvider);
  return repo.getChildNodes(parentId);
});

/// Provider to get a single node by its ID.
final libraryNodeByIdProvider = FutureProvider.family<LibraryNode?, String>((ref, nodeId) async {
  final repo = ref.watch(patternRepositoryProvider);
  return repo.getNodeById(nodeId);
});

/// Provider to get the ancestor chain for breadcrumb navigation.
/// Returns list from root to parent (does not include current node).
final libraryAncestorsProvider = FutureProvider.family<List<LibraryNode>, String>((ref, nodeId) async {
  final repo = ref.watch(patternRepositoryProvider);
  return repo.getAncestors(nodeId);
});

/// Provider to check if a node has children (determines navigation behavior).
final nodeHasChildrenProvider = FutureProvider.family<bool, String>((ref, nodeId) async {
  final repo = ref.watch(patternRepositoryProvider);
  return repo.hasChildren(nodeId);
});

/// Provider to generate patterns for a palette node.
/// Returns empty list if the node is not a palette.
final libraryNodePatternsProvider = FutureProvider.family<List<PatternItem>, String>((ref, nodeId) async {
  final repo = ref.watch(patternRepositoryProvider);
  final node = await repo.getNodeById(nodeId);
  if (node != null && node.isPalette) {
    return repo.generatePatternsForNode(node);
  }
  return [];
});
