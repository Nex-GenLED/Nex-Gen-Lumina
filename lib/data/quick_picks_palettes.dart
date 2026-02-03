import 'package:flutter/material.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';

/// Quick Picks - Curated popular patterns for easy discovery.
/// This category appears first in the library and contains the most
/// commonly used and requested patterns across all categories.
class QuickPicksPalettes {
  QuickPicksPalettes._();

  // ================= SUB-CATEGORY FOLDERS =================

  static List<LibraryNode> getQuickPicksFolders() {
    return const [
      LibraryNode(
        id: 'quick_everyday',
        name: 'Everyday Favorites',
        description: 'Perfect for any night of the week',
        nodeType: LibraryNodeType.folder,
        parentId: LibraryCategoryIds.quickPicks,
        sortOrder: 0,
        imageUrl: 'https://images.unsplash.com/photo-1600585154154-8c857b74f2ab',
        metadata: {'icon': 'star', 'theme': 'everyday'},
      ),
      LibraryNode(
        id: 'quick_seasonal',
        name: 'Current Season',
        description: 'Trending patterns for right now',
        nodeType: LibraryNodeType.folder,
        parentId: LibraryCategoryIds.quickPicks,
        sortOrder: 1,
        imageUrl: 'https://images.unsplash.com/photo-1477587458883-47145ed94245',
        metadata: {'icon': 'calendar_today', 'theme': 'seasonal'},
      ),
      LibraryNode(
        id: 'quick_celebration',
        name: 'Celebration',
        description: 'Party-ready in one tap',
        nodeType: LibraryNodeType.folder,
        parentId: LibraryCategoryIds.quickPicks,
        sortOrder: 2,
        imageUrl: 'https://images.unsplash.com/photo-1544491843-0ce2884635f3',
        metadata: {'icon': 'celebration', 'theme': 'party'},
      ),
      LibraryNode(
        id: 'quick_relaxation',
        name: 'Relaxation',
        description: 'Calm and peaceful vibes',
        nodeType: LibraryNodeType.folder,
        parentId: LibraryCategoryIds.quickPicks,
        sortOrder: 3,
        imageUrl: 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e',
        metadata: {'icon': 'spa', 'theme': 'relax'},
      ),
      LibraryNode(
        id: 'quick_dramatic',
        name: 'Make a Statement',
        description: 'Bold patterns that turn heads',
        nodeType: LibraryNodeType.folder,
        parentId: LibraryCategoryIds.quickPicks,
        sortOrder: 4,
        imageUrl: 'https://images.unsplash.com/photo-1419242902214-272b3f66ee7a',
        metadata: {'icon': 'bolt', 'theme': 'dramatic'},
      ),
    ];
  }

  // ================= EVERYDAY FAVORITES ====================
  // Most commonly used patterns - the "Netflix Top 10" of lighting

  static List<LibraryNode> _everydayPalettes() {
    return const [
      LibraryNode(
        id: 'quick_warm_white',
        name: 'Warm White Classic',
        description: 'The most popular choice - cozy and inviting',
        nodeType: LibraryNodeType.palette,
        parentId: 'quick_everyday',
        themeColors: [Color(0xFFFFB347), Color(0xFFFFE4B5)],
        sortOrder: 0,
        metadata: {'suggestedEffects': [0, 2], 'defaultSpeed': 0, 'defaultIntensity': 200, 'popularity': 100},
      ),
      LibraryNode(
        id: 'quick_cool_white',
        name: 'Crisp White',
        description: 'Clean, modern moonlight glow',
        nodeType: LibraryNodeType.palette,
        parentId: 'quick_everyday',
        themeColors: [Color(0xFFFFFFFF), Color(0xFFE8E8E8)],
        sortOrder: 1,
        metadata: {'suggestedEffects': [0, 2], 'defaultSpeed': 0, 'defaultIntensity': 200, 'popularity': 95},
      ),
      LibraryNode(
        id: 'quick_golden_hour',
        name: 'Golden Hour',
        description: 'Sunset warmth that never ends',
        nodeType: LibraryNodeType.palette,
        parentId: 'quick_everyday',
        themeColors: [Color(0xFFFFD700), Color(0xFFFF8C00), Color(0xFFFFB347)],
        sortOrder: 2,
        metadata: {'suggestedEffects': [0, 2, 88], 'defaultSpeed': 40, 'defaultIntensity': 180, 'popularity': 90},
      ),
      LibraryNode(
        id: 'quick_soft_twinkle',
        name: 'Soft Twinkle',
        description: 'Gentle starlight effect',
        nodeType: LibraryNodeType.palette,
        parentId: 'quick_everyday',
        themeColors: [Color(0xFFFFFFFF), Color(0xFFFFE4B5)],
        sortOrder: 3,
        metadata: {'suggestedEffects': [17, 49, 80], 'defaultSpeed': 60, 'defaultIntensity': 160, 'popularity': 88},
      ),
      LibraryNode(
        id: 'quick_ocean_breeze',
        name: 'Ocean Breeze',
        description: 'Calming teal and seafoam',
        nodeType: LibraryNodeType.palette,
        parentId: 'quick_everyday',
        themeColors: [Color(0xFF40E0D0), Color(0xFF20B2AA), Color(0xFFFFFFFF)],
        sortOrder: 4,
        metadata: {'suggestedEffects': [0, 2, 75], 'defaultSpeed': 50, 'defaultIntensity': 170, 'popularity': 85},
      ),
      LibraryNode(
        id: 'quick_sunset_glow',
        name: 'Sunset Glow',
        description: 'Orange, pink, and purple horizon',
        nodeType: LibraryNodeType.palette,
        parentId: 'quick_everyday',
        themeColors: [Color(0xFFFF4500), Color(0xFFFF69B4), Color(0xFF9932CC)],
        sortOrder: 5,
        metadata: {'suggestedEffects': [0, 2, 67], 'defaultSpeed': 40, 'defaultIntensity': 170, 'popularity': 82},
      ),
      LibraryNode(
        id: 'quick_candlelight',
        name: 'Candlelight',
        description: 'Flickering warm ambiance',
        nodeType: LibraryNodeType.palette,
        parentId: 'quick_everyday',
        themeColors: [Color(0xFFFF8C00), Color(0xFFFFBF00), Color(0xFFFFE4B5)],
        sortOrder: 6,
        metadata: {'suggestedEffects': [88, 102], 'defaultSpeed': 80, 'defaultIntensity': 150, 'popularity': 80},
      ),
      LibraryNode(
        id: 'quick_lavender_dream',
        name: 'Lavender Dream',
        description: 'Soft purple relaxation',
        nodeType: LibraryNodeType.palette,
        parentId: 'quick_everyday',
        themeColors: [Color(0xFFE6E6FA), Color(0xFF9370DB), Color(0xFFFFFFFF)],
        sortOrder: 7,
        metadata: {'suggestedEffects': [0, 2, 88], 'defaultSpeed': 40, 'defaultIntensity': 150, 'popularity': 78},
      ),
    ];
  }

  // ================= CURRENT SEASON ====================
  // Patterns that match the current time of year

  static List<LibraryNode> _seasonalPalettes() {
    return const [
      // Winter/Holiday defaults - would be dynamic in production
      LibraryNode(
        id: 'quick_winter_white',
        name: 'Winter Frost',
        description: 'Icy white and pale blue',
        nodeType: LibraryNodeType.palette,
        parentId: 'quick_seasonal',
        themeColors: [Color(0xFFFFFFFF), Color(0xFFADD8E6), Color(0xFFE0FFFF)],
        sortOrder: 0,
        metadata: {'suggestedEffects': [0, 17, 88], 'defaultSpeed': 40, 'defaultIntensity': 180, 'season': 'winter'},
      ),
      LibraryNode(
        id: 'quick_holiday_classic',
        name: 'Holiday Classic',
        description: 'Traditional red and green',
        nodeType: LibraryNodeType.palette,
        parentId: 'quick_seasonal',
        themeColors: [Color(0xFFFF0000), Color(0xFF00FF00), Color(0xFFFFFFFF)],
        sortOrder: 1,
        metadata: {'suggestedEffects': [12, 41, 17], 'defaultSpeed': 100, 'defaultIntensity': 200, 'season': 'winter'},
      ),
      LibraryNode(
        id: 'quick_cozy_cabin',
        name: 'Cozy Cabin',
        description: 'Warm amber fireplace vibes',
        nodeType: LibraryNodeType.palette,
        parentId: 'quick_seasonal',
        themeColors: [Color(0xFFFF8C00), Color(0xFFD2691E), Color(0xFFFFBF00)],
        sortOrder: 2,
        metadata: {'suggestedEffects': [88, 2, 0], 'defaultSpeed': 60, 'defaultIntensity': 160, 'season': 'winter'},
      ),
      LibraryNode(
        id: 'quick_spring_bloom',
        name: 'Spring Bloom',
        description: 'Fresh pastels awakening',
        nodeType: LibraryNodeType.palette,
        parentId: 'quick_seasonal',
        themeColors: [Color(0xFFFFB6C1), Color(0xFF98FB98), Color(0xFFFFFFFF)],
        sortOrder: 3,
        metadata: {'suggestedEffects': [0, 2, 41], 'defaultSpeed': 50, 'defaultIntensity': 160, 'season': 'spring'},
      ),
      LibraryNode(
        id: 'quick_summer_vibes',
        name: 'Summer Vibes',
        description: 'Bright tropical energy',
        nodeType: LibraryNodeType.palette,
        parentId: 'quick_seasonal',
        themeColors: [Color(0xFF00FFFF), Color(0xFFFF4500), Color(0xFFFFD700)],
        sortOrder: 4,
        metadata: {'suggestedEffects': [41, 67, 0], 'defaultSpeed': 100, 'defaultIntensity': 200, 'season': 'summer'},
      ),
      LibraryNode(
        id: 'quick_autumn_harvest',
        name: 'Autumn Harvest',
        description: 'Warm fall foliage',
        nodeType: LibraryNodeType.palette,
        parentId: 'quick_seasonal',
        themeColors: [Color(0xFFFF4500), Color(0xFFDC143C), Color(0xFFFFD700)],
        sortOrder: 5,
        metadata: {'suggestedEffects': [0, 2, 41], 'defaultSpeed': 50, 'defaultIntensity': 170, 'season': 'autumn'},
      ),
    ];
  }

  // ================= CELEBRATION ====================
  // Party-ready patterns

  static List<LibraryNode> _celebrationPalettes() {
    return const [
      LibraryNode(
        id: 'quick_birthday_bash',
        name: 'Birthday Bash',
        description: 'Festive and fun multicolor',
        nodeType: LibraryNodeType.palette,
        parentId: 'quick_celebration',
        themeColors: [Color(0xFFFF1493), Color(0xFF00FFFF), Color(0xFFFFD700)],
        sortOrder: 0,
        metadata: {'suggestedEffects': [41, 67, 89], 'defaultSpeed': 120, 'defaultIntensity': 220},
      ),
      LibraryNode(
        id: 'quick_romantic_night',
        name: 'Romantic Night',
        description: 'Red and pink for date night',
        nodeType: LibraryNodeType.palette,
        parentId: 'quick_celebration',
        themeColors: [Color(0xFFFF0000), Color(0xFFFF69B4), Color(0xFFFFFFFF)],
        sortOrder: 1,
        metadata: {'suggestedEffects': [0, 2, 88], 'defaultSpeed': 40, 'defaultIntensity': 160},
      ),
      LibraryNode(
        id: 'quick_patriotic',
        name: 'Patriotic Pride',
        description: 'Red, white, and blue',
        nodeType: LibraryNodeType.palette,
        parentId: 'quick_celebration',
        themeColors: [Color(0xFFFF0000), Color(0xFFFFFFFF), Color(0xFF0000FF)],
        sortOrder: 2,
        metadata: {'suggestedEffects': [12, 41, 89], 'defaultSpeed': 100, 'defaultIntensity': 200},
      ),
      LibraryNode(
        id: 'quick_victory',
        name: 'Victory!',
        description: 'Celebration fireworks',
        nodeType: LibraryNodeType.palette,
        parentId: 'quick_celebration',
        themeColors: [Color(0xFFFFD700), Color(0xFFFFFFFF), Color(0xFFFF4500)],
        sortOrder: 3,
        metadata: {'suggestedEffects': [89, 42, 87], 'defaultSpeed': 180, 'defaultIntensity': 255},
      ),
      LibraryNode(
        id: 'quick_elegant_gala',
        name: 'Elegant Gala',
        description: 'Sophisticated gold and white',
        nodeType: LibraryNodeType.palette,
        parentId: 'quick_celebration',
        themeColors: [Color(0xFFFFD700), Color(0xFFFFFFFF), Color(0xFFC0C0C0)],
        sortOrder: 4,
        metadata: {'suggestedEffects': [0, 2, 88], 'defaultSpeed': 40, 'defaultIntensity': 180},
      ),
      LibraryNode(
        id: 'quick_disco_party',
        name: 'Disco Party',
        description: 'Dance floor energy',
        nodeType: LibraryNodeType.palette,
        parentId: 'quick_celebration',
        themeColors: [Color(0xFFFF00FF), Color(0xFF00FFFF), Color(0xFFFFFF00)],
        sortOrder: 5,
        metadata: {'suggestedEffects': [41, 1, 67], 'defaultSpeed': 180, 'defaultIntensity': 240},
      ),
    ];
  }

  // ================= RELAXATION ====================
  // Calm and peaceful patterns

  static List<LibraryNode> _relaxationPalettes() {
    return const [
      LibraryNode(
        id: 'quick_zen_garden',
        name: 'Zen Garden',
        description: 'Peaceful greens and creams',
        nodeType: LibraryNodeType.palette,
        parentId: 'quick_relaxation',
        themeColors: [Color(0xFF90EE90), Color(0xFFFFF8DC), Color(0xFFFFFFFF)],
        sortOrder: 0,
        metadata: {'suggestedEffects': [0, 2], 'defaultSpeed': 30, 'defaultIntensity': 140},
      ),
      LibraryNode(
        id: 'quick_deep_breath',
        name: 'Deep Breath',
        description: 'Slow breathing rhythm',
        nodeType: LibraryNodeType.palette,
        parentId: 'quick_relaxation',
        themeColors: [Color(0xFF87CEEB), Color(0xFFFFFFFF)],
        sortOrder: 1,
        metadata: {'suggestedEffects': [2], 'defaultSpeed': 20, 'defaultIntensity': 130},
      ),
      LibraryNode(
        id: 'quick_moonlit_night',
        name: 'Moonlit Night',
        description: 'Soft silver glow',
        nodeType: LibraryNodeType.palette,
        parentId: 'quick_relaxation',
        themeColors: [Color(0xFFC0C0C0), Color(0xFFE8E8E8), Color(0xFF191970)],
        sortOrder: 2,
        metadata: {'suggestedEffects': [0, 2, 88], 'defaultSpeed': 30, 'defaultIntensity': 120},
      ),
      LibraryNode(
        id: 'quick_aurora_calm',
        name: 'Aurora Calm',
        description: 'Gentle northern lights',
        nodeType: LibraryNodeType.palette,
        parentId: 'quick_relaxation',
        themeColors: [Color(0xFF00FF7F), Color(0xFF9370DB), Color(0xFF00CED1)],
        sortOrder: 3,
        metadata: {'suggestedEffects': [38, 101, 110], 'defaultSpeed': 40, 'defaultIntensity': 140},
      ),
      LibraryNode(
        id: 'quick_spa_retreat',
        name: 'Spa Retreat',
        description: 'Soft aqua tranquility',
        nodeType: LibraryNodeType.palette,
        parentId: 'quick_relaxation',
        themeColors: [Color(0xFFE0FFFF), Color(0xFF98FB98), Color(0xFFFFFFFF)],
        sortOrder: 4,
        metadata: {'suggestedEffects': [0, 2], 'defaultSpeed': 30, 'defaultIntensity': 130},
      ),
      LibraryNode(
        id: 'quick_forest_mist',
        name: 'Forest Mist',
        description: 'Misty woodland peace',
        nodeType: LibraryNodeType.palette,
        parentId: 'quick_relaxation',
        themeColors: [Color(0xFF708090), Color(0xFF8FBC8F), Color(0xFFFFFFFF)],
        sortOrder: 5,
        metadata: {'suggestedEffects': [0, 2, 88], 'defaultSpeed': 30, 'defaultIntensity': 120},
      ),
    ];
  }

  // ================= MAKE A STATEMENT ====================
  // Bold, dramatic patterns

  static List<LibraryNode> _dramaticPalettes() {
    return const [
      LibraryNode(
        id: 'quick_electric_storm',
        name: 'Electric Storm',
        description: 'Lightning strikes',
        nodeType: LibraryNodeType.palette,
        parentId: 'quick_dramatic',
        themeColors: [Color(0xFF4169E1), Color(0xFFFFFFFF), Color(0xFF9400D3)],
        sortOrder: 0,
        metadata: {'suggestedEffects': [57, 1, 23], 'defaultSpeed': 200, 'defaultIntensity': 255},
      ),
      LibraryNode(
        id: 'quick_neon_night',
        name: 'Neon Night',
        description: 'Cyberpunk city vibes',
        nodeType: LibraryNodeType.palette,
        parentId: 'quick_dramatic',
        themeColors: [Color(0xFFFF00FF), Color(0xFF00FFFF), Color(0xFFFF1493)],
        sortOrder: 1,
        metadata: {'suggestedEffects': [41, 12, 67], 'defaultSpeed': 150, 'defaultIntensity': 230},
      ),
      LibraryNode(
        id: 'quick_fire_ice',
        name: 'Fire & Ice',
        description: 'Hot orange meets cold blue',
        nodeType: LibraryNodeType.palette,
        parentId: 'quick_dramatic',
        themeColors: [Color(0xFFFF4500), Color(0xFF00BFFF), Color(0xFFFFFFFF)],
        sortOrder: 2,
        metadata: {'suggestedEffects': [12, 41, 67], 'defaultSpeed': 120, 'defaultIntensity': 210},
      ),
      LibraryNode(
        id: 'quick_galaxy',
        name: 'Galaxy',
        description: 'Deep space purple and blue',
        nodeType: LibraryNodeType.palette,
        parentId: 'quick_dramatic',
        themeColors: [Color(0xFF4B0082), Color(0xFF0000CD), Color(0xFFFFFFFF)],
        sortOrder: 3,
        metadata: {'suggestedEffects': [17, 49, 87], 'defaultSpeed': 70, 'defaultIntensity': 200},
      ),
      LibraryNode(
        id: 'quick_volcanic',
        name: 'Volcanic',
        description: 'Molten lava flow',
        nodeType: LibraryNodeType.palette,
        parentId: 'quick_dramatic',
        themeColors: [Color(0xFFFF0000), Color(0xFFFF4500), Color(0xFF000000)],
        sortOrder: 4,
        metadata: {'suggestedEffects': [38, 42, 110], 'defaultSpeed': 100, 'defaultIntensity': 220},
      ),
      LibraryNode(
        id: 'quick_rainbow_chase',
        name: 'Rainbow Chase',
        description: 'Full spectrum motion',
        nodeType: LibraryNodeType.palette,
        parentId: 'quick_dramatic',
        themeColors: [Color(0xFFFF0000), Color(0xFFFFD700), Color(0xFF00FF00)],
        sortOrder: 5,
        metadata: {'suggestedEffects': [41, 67, 101], 'defaultSpeed': 150, 'defaultIntensity': 230},
      ),
    ];
  }

  // ================= PUBLIC API =================

  /// Get all Quick Picks folder nodes
  static List<LibraryNode> getAllQuickPicksFolders() => getQuickPicksFolders();

  /// Get all Quick Picks palette nodes
  static List<LibraryNode> getAllQuickPicksPaletteNodes() {
    return [
      ..._everydayPalettes(),
      ..._seasonalPalettes(),
      ..._celebrationPalettes(),
      ..._relaxationPalettes(),
      ..._dramaticPalettes(),
    ];
  }
}
