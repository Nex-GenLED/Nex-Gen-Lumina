import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/wled/mock_pattern_repository.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/utils/sun_utils.dart';
import 'package:nexgen_command/features/wled/event_theme_library.dart';

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
      effectId: 110,
      effectName: 'Flow',
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
        effectId: 110,
        effectName: 'Flow',
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
        effectId: 110,
        effectName: 'Flow',
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
