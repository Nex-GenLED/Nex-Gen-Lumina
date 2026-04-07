import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/autopilot/learning_providers.dart';
import 'package:nexgen_command/features/wled/pattern_repository.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/effect_mood_system.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/event_theme_library.dart';
import 'package:nexgen_command/models/usage_analytics_models.dart';

/// Repository provider for the Pattern Library.
/// For now we use an in-memory mock; can be swapped to Firestore later.
final patternRepositoryProvider = Provider<PatternRepository>((ref) {
  final repo = PatternRepository();
  return repo;
});

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

// ============================================================================
// LIBRARY SEARCH PROVIDERS
// ============================================================================

/// Search the pattern library for existing patterns.
/// Returns matching palettes, folders, and pre-built pattern items.
final librarySearchProvider = FutureProvider.family<LibrarySearchResults, String>((ref, query) async {
  final repo = ref.watch(patternRepositoryProvider);
  return repo.searchLibrary(query);
});

// ============================================================================
// Mood Filter System
// ============================================================================

/// Currently selected mood filter for the Explore Patterns page.
/// null = show all effects (no filter)
final selectedMoodFilterProvider = StateProvider<EffectMood?>((ref) => null);

/// Filtered patterns for a library node, respecting the mood filter.
/// If no mood is selected, returns all patterns.
/// If a mood is selected, filters to only patterns with matching effects.
final filteredLibraryNodePatternsProvider = FutureProvider.family<List<PatternItem>, String>((ref, nodeId) async {
  final allPatterns = await ref.watch(libraryNodePatternsProvider(nodeId).future);
  final selectedMood = ref.watch(selectedMoodFilterProvider);

  if (selectedMood == null) {
    return allPatterns;
  }

  // Filter patterns to only those matching the selected mood
  final moodEffectIds = EffectMoodSystem.getEffectIdsForMood(selectedMood);
  return allPatterns.where((pattern) {
    final effectId = PatternRepository.effectIdFromPayload(pattern.wledPayload);
    return effectId != null && moodEffectIds.contains(effectId);
  }).toList();
});

/// Get mood counts for the patterns of a specific node.
/// Useful for showing badges on mood filter chips.
final nodeMoodCountsProvider = FutureProvider.family<Map<EffectMood, int>, String>((ref, nodeId) async {
  final allPatterns = await ref.watch(libraryNodePatternsProvider(nodeId).future);

  final counts = <EffectMood, int>{};
  for (final mood in EffectMood.values) {
    counts[mood] = 0;
  }

  for (final pattern in allPatterns) {
    final effectId = PatternRepository.effectIdFromPayload(pattern.wledPayload);
    if (effectId != null) {
      final mood = EffectMoodSystem.getMood(effectId);
      if (mood != null) {
        counts[mood] = (counts[mood] ?? 0) + 1;
      }
    }
  }

  return counts;
});

// ============================================================================
// COLORWAY EFFECT SELECTOR PROVIDERS
// ============================================================================

/// Currently selected effect ID in the effect selector.
final selectorEffectIdProvider = StateProvider<int>((ref) => 0);

/// Speed value (0-255) in the effect selector.
final selectorSpeedProvider = StateProvider<int>((ref) => 128);

/// Intensity value (0-255) in the effect selector.
final selectorIntensityProvider = StateProvider<int>((ref) => 128);

/// Color layout (LEDs per color, 1-5) in the effect selector.
final selectorColorGroupProvider = StateProvider<int>((ref) => 1);

/// Spacing (dark LEDs between lit groups, 0-4) in the effect selector.
final selectorSpacingProvider = StateProvider<int>((ref) => 0);

/// Active gradient preset index for brightness gradient patterns.
final selectorGradientPresetProvider = StateProvider<int>((ref) => 0);

/// Breathing toggle for brightness gradient patterns.
final selectorBreathingProvider = StateProvider<bool>((ref) => false);

/// Which mood categories are expanded in the effect list.
final selectorExpandedMoodsProvider = StateProvider<Set<SelectorMood>>((ref) => {SelectorMood.calm});

/// Selected motion type filter (null = show top picks / all).
final selectorMotionTypeProvider = StateProvider<MotionType?>((ref) => null);

/// Selected color behavior filter (null = all).
final selectorColorBehaviorProvider = StateProvider<ColorBehavior?>((ref) => null);

/// Preview state for the Explore page roofline hero.
///
/// Set when a design card is tapped on the Explore page. Cleared when
/// navigating back to the folder list.
class ExplorePreviewState {
  final List<Color> colors;
  final int effectId;
  final int speed;
  final int brightness;
  final String name;

  /// LEDs per color group (WLED `grp`). 1 = no grouping.
  final int colorGroupSize;

  /// Dark (off) LEDs after each lit group (WLED `spc`). 0 = no spacing.
  final int spacing;

  const ExplorePreviewState({
    required this.colors,
    required this.effectId,
    this.speed = 128,
    this.brightness = 255,
    this.name = '',
    this.colorGroupSize = 1,
    this.spacing = 0,
  });
}

/// Provider for the Explore page roofline preview. Null = hidden.
final explorePreviewProvider = StateProvider<ExplorePreviewState?>((ref) => null);
