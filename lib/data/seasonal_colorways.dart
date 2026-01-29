import 'package:flutter/material.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';

/// Named color palettes for all seasons.
/// Each season has 10+ themed colorways.
class SeasonalColorways {
  // ==================== SPRING ====================
  static const List<NamedPalette> spring = [
    NamedPalette(
      id: 'spring_cherryblossom',
      name: 'Cherry Blossom',
      description: 'Soft pink blossoms',
      colors: [Color(0xFFFFB7C5), Color(0xFFFF69B4), Color(0xFFFFFFFF)],
      suggestedEffects: [2, 43, 0], // Breathe, Twinkle, Solid
    ),
    NamedPalette(
      id: 'spring_freshgrass',
      name: 'Fresh Cut Grass',
      description: 'Vibrant spring green',
      colors: [Color(0xFF7CFC00), Color(0xFF32CD32), Color(0xFF90EE90)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'spring_tulipfield',
      name: 'Tulip Field',
      description: 'Red, yellow, and pink tulips',
      colors: [Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFFFF69B4)],
      suggestedEffects: [41, 0], // Running, Solid
    ),
    NamedPalette(
      id: 'spring_raindrop',
      name: 'Spring Rain',
      description: 'Fresh blue raindrops',
      colors: [Color(0xFF87CEEB), Color(0xFFADD8E6), Color(0xFFFFFFFF)],
      suggestedEffects: [43, 2, 0], // Twinkle, Breathe, Solid
    ),
    NamedPalette(
      id: 'spring_daffodil',
      name: 'Daffodil',
      description: 'Sunny yellow blooms',
      colors: [Color(0xFFFFFF00), Color(0xFFFFD700), Color(0xFFFFFFFF)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'spring_lavender',
      name: 'Lavender Field',
      description: 'Purple lavender rows',
      colors: [Color(0xFFE6E6FA), Color(0xFF9370DB), Color(0xFF90EE90)],
      suggestedEffects: [41, 2, 0], // Running, Breathe, Solid
    ),
    NamedPalette(
      id: 'spring_butterfly',
      name: 'Butterfly Garden',
      description: 'Colorful butterfly wings',
      colors: [Color(0xFFFF8C00), Color(0xFF4169E1), Color(0xFFFFFF00)],
      suggestedEffects: [41, 43, 0], // Running, Twinkle, Solid
    ),
    NamedPalette(
      id: 'spring_robinegg',
      name: 'Robin\'s Egg',
      description: 'Soft blue nest',
      colors: [Color(0xFF00CED1), Color(0xFFADD8E6), Color(0xFFFFFFFF)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'spring_meadow',
      name: 'Meadow',
      description: 'Green grass with wildflowers',
      colors: [Color(0xFF90EE90), Color(0xFFFF69B4), Color(0xFFFFFF00)],
      suggestedEffects: [41, 0], // Running, Solid
    ),
    NamedPalette(
      id: 'spring_renewal',
      name: 'Renewal',
      description: 'Fresh green new growth',
      colors: [Color(0xFF98FB98), Color(0xFF00FF7F), Color(0xFF32CD32)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'spring_peony',
      name: 'Peony',
      description: 'Soft pink peony petals',
      colors: [Color(0xFFFFC0CB), Color(0xFFFFB6C1), Color(0xFFFF69B4)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'spring_mint',
      name: 'Mint Fresh',
      description: 'Cool mint green',
      colors: [Color(0xFF98FF98), Color(0xFFADFF2F), Color(0xFFFFFFFF)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
  ];

  // ==================== SUMMER ====================
  static const List<NamedPalette> summer = [
    NamedPalette(
      id: 'summer_sunset',
      name: 'Summer Sunset',
      description: 'Orange and pink sky',
      colors: [Color(0xFFFF4500), Color(0xFFFF8C00), Color(0xFFFF69B4)],
      suggestedEffects: [2, 41, 0], // Breathe, Running, Solid
    ),
    NamedPalette(
      id: 'summer_ocean',
      name: 'Ocean Waves',
      description: 'Blue and teal sea',
      colors: [Color(0xFF00CED1), Color(0xFF0000FF), Color(0xFFFFFFFF)],
      suggestedEffects: [41, 2, 0], // Running, Breathe, Solid
    ),
    NamedPalette(
      id: 'summer_tropical',
      name: 'Tropical Paradise',
      description: 'Vibrant tropical colors',
      colors: [Color(0xFF00FFFF), Color(0xFFFF8C00), Color(0xFF32CD32)],
      suggestedEffects: [41, 0], // Running, Solid
    ),
    NamedPalette(
      id: 'summer_watermelon',
      name: 'Watermelon',
      description: 'Red with green rind',
      colors: [Color(0xFFFF6B6B), Color(0xFF00FF00), Color(0xFF000000)],
      suggestedEffects: [41, 0], // Running, Solid
    ),
    NamedPalette(
      id: 'summer_lemonade',
      name: 'Lemonade',
      description: 'Fresh yellow citrus',
      colors: [Color(0xFFFFFF00), Color(0xFFFFFDD0), Color(0xFFFFD700)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'summer_poolside',
      name: 'Poolside',
      description: 'Cool pool blue',
      colors: [Color(0xFF00BFFF), Color(0xFF87CEEB), Color(0xFFFFFFFF)],
      suggestedEffects: [41, 2, 0], // Running, Breathe, Solid
    ),
    NamedPalette(
      id: 'summer_bonfire',
      name: 'Beach Bonfire',
      description: 'Warm fire glow',
      colors: [Color(0xFFFF4500), Color(0xFFFF8C00), Color(0xFFFFD700)],
      suggestedEffects: [101, 0], // Candle, Solid
    ),
    NamedPalette(
      id: 'summer_seashell',
      name: 'Seashell',
      description: 'Soft beach pinks',
      colors: [Color(0xFFFFF5EE), Color(0xFFFFB6C1), Color(0xFFD2B48C)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'summer_palm',
      name: 'Palm Trees',
      description: 'Green palms and sunset',
      colors: [Color(0xFF228B22), Color(0xFFFF8C00), Color(0xFFFF4500)],
      suggestedEffects: [41, 0], // Running, Solid
    ),
    NamedPalette(
      id: 'summer_icecream',
      name: 'Ice Cream',
      description: 'Sweet pastel scoops',
      colors: [Color(0xFFFFB6C1), Color(0xFFFFFDD0), Color(0xFF8B4513)],
      suggestedEffects: [41, 0], // Running, Solid
    ),
    NamedPalette(
      id: 'summer_coral',
      name: 'Coral Reef',
      description: 'Coral and sea blue',
      colors: [Color(0xFFFF7F50), Color(0xFF00CED1), Color(0xFFFF69B4)],
      suggestedEffects: [41, 0], // Running, Solid
    ),
    NamedPalette(
      id: 'summer_bbq',
      name: 'BBQ Party',
      description: 'Warm grill tones',
      colors: [Color(0xFFFF4500), Color(0xFFFFD700), Color(0xFF8B4513)],
      suggestedEffects: [101, 0], // Candle, Solid
    ),
  ];

  // ==================== AUTUMN ====================
  static const List<NamedPalette> autumn = [
    NamedPalette(
      id: 'autumn_fallleaves',
      name: 'Fall Leaves',
      description: 'Red, orange, yellow leaves',
      colors: [Color(0xFFFF0000), Color(0xFFFF8C00), Color(0xFFFFD700)],
      suggestedEffects: [41, 0], // Running, Solid
    ),
    NamedPalette(
      id: 'autumn_pumpkinspice',
      name: 'Pumpkin Spice',
      description: 'Warm spice tones',
      colors: [Color(0xFFFF8C00), Color(0xFF8B4513), Color(0xFFFFD700)],
      suggestedEffects: [2, 101, 0], // Breathe, Candle, Solid
    ),
    NamedPalette(
      id: 'autumn_harvest',
      name: 'Harvest Moon',
      description: 'Golden harvest glow',
      colors: [Color(0xFFFFD700), Color(0xFFFF8C00), Color(0xFF8B4513)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'autumn_cranberry',
      name: 'Cranberry Bog',
      description: 'Deep red cranberries',
      colors: [Color(0xFF8B0000), Color(0xFFDC143C), Color(0xFF722F37)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'autumn_acorn',
      name: 'Acorn & Oak',
      description: 'Brown and tan oak',
      colors: [Color(0xFF8B4513), Color(0xFFD2B48C), Color(0xFF228B22)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'autumn_apple',
      name: 'Apple Orchard',
      description: 'Red and green apples',
      colors: [Color(0xFFFF0000), Color(0xFF228B22), Color(0xFFFFD700)],
      suggestedEffects: [41, 0], // Running, Solid
    ),
    NamedPalette(
      id: 'autumn_hayride',
      name: 'Hayride',
      description: 'Golden hay and brown',
      colors: [Color(0xFFDAA520), Color(0xFF8B4513), Color(0xFFFFD700)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'autumn_maple',
      name: 'Maple Syrup',
      description: 'Amber and gold maple',
      colors: [Color(0xFFFFB347), Color(0xFF8B4513), Color(0xFFFFD700)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'autumn_scarecrow',
      name: 'Scarecrow',
      description: 'Straw and denim',
      colors: [Color(0xFFDAA520), Color(0xFF4169E1), Color(0xFF8B4513)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'autumn_bonfire',
      name: 'Autumn Bonfire',
      description: 'Warm crackling fire',
      colors: [Color(0xFFFF4500), Color(0xFFFF8C00), Color(0xFFFFD700)],
      suggestedEffects: [101, 0], // Candle, Solid
    ),
    NamedPalette(
      id: 'autumn_rustic',
      name: 'Rustic Charm',
      description: 'Earthy rust and brown',
      colors: [Color(0xFFB7410E), Color(0xFF8B4513), Color(0xFFD2B48C)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'autumn_vineyard',
      name: 'Vineyard',
      description: 'Purple grape and green vine',
      colors: [Color(0xFF800080), Color(0xFF228B22), Color(0xFF8B4513)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
  ];

  // ==================== WINTER ====================
  static const List<NamedPalette> winter = [
    NamedPalette(
      id: 'winter_snowfall',
      name: 'Snowfall',
      description: 'Pure white snow',
      colors: [Color(0xFFFFFFFF), Color(0xFFF0F8FF), Color(0xFFE0FFFF)],
      suggestedEffects: [43, 2, 0], // Twinkle, Breathe, Solid
    ),
    NamedPalette(
      id: 'winter_frost',
      name: 'Frost',
      description: 'Icy blue frost',
      colors: [Color(0xFFADD8E6), Color(0xFF87CEEB), Color(0xFFFFFFFF)],
      suggestedEffects: [43, 0], // Twinkle, Solid
    ),
    NamedPalette(
      id: 'winter_aurora',
      name: 'Northern Lights',
      description: 'Aurora borealis greens',
      colors: [Color(0xFF00FF7F), Color(0xFF00CED1), Color(0xFF9370DB)],
      suggestedEffects: [38, 41, 0], // Aurora, Running, Solid
    ),
    NamedPalette(
      id: 'winter_cozy',
      name: 'Cozy Cabin',
      description: 'Warm fireplace glow',
      colors: [Color(0xFFFF4500), Color(0xFFFFB347), Color(0xFF8B4513)],
      suggestedEffects: [101, 0], // Candle, Solid
    ),
    NamedPalette(
      id: 'winter_icicle',
      name: 'Icicle',
      description: 'Crystal ice blue',
      colors: [Color(0xFFB0E0E6), Color(0xFFFFFFFF), Color(0xFF87CEEB)],
      suggestedEffects: [43, 0], // Twinkle, Solid
    ),
    NamedPalette(
      id: 'winter_evergreen',
      name: 'Evergreen',
      description: 'Deep forest green',
      colors: [Color(0xFF006400), Color(0xFF228B22), Color(0xFF2E8B57)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'winter_holly',
      name: 'Holly Berry',
      description: 'Green holly with red berries',
      colors: [Color(0xFF228B22), Color(0xFFFF0000), Color(0xFF006400)],
      suggestedEffects: [43, 0], // Twinkle, Solid
    ),
    NamedPalette(
      id: 'winter_midnight',
      name: 'Midnight Blue',
      description: 'Deep winter night',
      colors: [Color(0xFF00008B), Color(0xFF191970), Color(0xFFFFFFFF)],
      suggestedEffects: [43, 0], // Twinkle, Solid
    ),
    NamedPalette(
      id: 'winter_hotcocoa',
      name: 'Hot Cocoa',
      description: 'Warm brown and cream',
      colors: [Color(0xFF8B4513), Color(0xFFFFFDD0), Color(0xFFD2691E)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
    NamedPalette(
      id: 'winter_silver',
      name: 'Silver Snow',
      description: 'Glittering silver',
      colors: [Color(0xFFC0C0C0), Color(0xFFFFFFFF), Color(0xFFE8E8E8)],
      suggestedEffects: [43, 87, 0], // Twinkle, Glitter, Solid
    ),
    NamedPalette(
      id: 'winter_cardinal',
      name: 'Cardinal',
      description: 'Red bird on white snow',
      colors: [Color(0xFFFF0000), Color(0xFFFFFFFF), Color(0xFF8B0000)],
      suggestedEffects: [43, 0], // Twinkle, Solid
    ),
    NamedPalette(
      id: 'winter_pinecone',
      name: 'Pinecone',
      description: 'Brown pine with green',
      colors: [Color(0xFF8B4513), Color(0xFF228B22), Color(0xFFD2B48C)],
      suggestedEffects: [2, 0], // Breathe, Solid
    ),
  ];

  /// Get all palettes for a given season
  static List<NamedPalette> getPalettesForSeason(String seasonId) {
    switch (seasonId) {
      case 'season_spring':
        return spring;
      case 'season_summer':
        return summer;
      case 'season_autumn':
        return autumn;
      case 'season_winter':
        return winter;
      default:
        return [];
    }
  }

  /// Get all season folder definitions
  static List<LibraryNode> getSeasonFolders() {
    return const [
      LibraryNode(
        id: 'season_spring',
        name: 'Spring',
        description: 'Fresh blooms and new growth',
        nodeType: LibraryNodeType.folder,
        parentId: 'cat_season',
        sortOrder: 0,
        imageUrl: 'https://images.unsplash.com/photo-1490750967868-88aa4486c946',
      ),
      LibraryNode(
        id: 'season_summer',
        name: 'Summer',
        description: 'Sunny days and warm nights',
        nodeType: LibraryNodeType.folder,
        parentId: 'cat_season',
        sortOrder: 1,
        imageUrl: 'https://images.unsplash.com/photo-1473496169904-658ba7c44d8a',
      ),
      LibraryNode(
        id: 'season_autumn',
        name: 'Autumn',
        description: 'Fall colors and harvest',
        nodeType: LibraryNodeType.folder,
        parentId: 'cat_season',
        sortOrder: 2,
        imageUrl: 'https://images.unsplash.com/photo-1477587458883-47145ed94245',
      ),
      LibraryNode(
        id: 'season_winter',
        name: 'Winter',
        description: 'Snow and cozy warmth',
        nodeType: LibraryNodeType.folder,
        parentId: 'cat_season',
        sortOrder: 3,
        imageUrl: 'https://images.unsplash.com/photo-1483664852095-d6cc6870702d',
      ),
    ];
  }

  /// Convert all seasonal palettes to LibraryNodes
  static List<LibraryNode> getAllSeasonalPaletteNodes() {
    final nodes = <LibraryNode>[];

    void addPalettes(String parentId, List<NamedPalette> palettes) {
      for (var i = 0; i < palettes.length; i++) {
        nodes.add(palettes[i].toLibraryNode(parentId, sortOrder: i));
      }
    }

    addPalettes('season_spring', spring);
    addPalettes('season_summer', summer);
    addPalettes('season_autumn', autumn);
    addPalettes('season_winter', winter);

    return nodes;
  }
}
