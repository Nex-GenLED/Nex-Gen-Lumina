import 'package:flutter/foundation.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:nexgen_command/features/wled/wled_service.dart' show rgbToRgbw;
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/sports_library_builder.dart';
import 'package:nexgen_command/data/holiday_palettes.dart';
import 'package:nexgen_command/data/seasonal_colorways.dart';
import 'package:nexgen_command/data/party_event_palettes.dart';
import 'package:nexgen_command/data/ncaa_conferences.dart';
import 'package:nexgen_command/data/movies_superheroes_palettes.dart';
import 'package:flutter/material.dart';

/// In-memory mock data source for the Pattern Library.
/// Provides a consistent set of categories and items for demos and tests.
class MockPatternRepository {
  MockPatternRepository();

  // ================= Procedural Generator Templates =================
  // Uses the curated effect IDs from WledEffectsCatalog for pattern generation.
  static List<int> get kMotionTemplateEffectIds => WledEffectsCatalog.curatedEffectIds;

  // ================= Vibe Grouping =================
  // Tag effect IDs into "vibe" filters to organize the generated grid.
  // Elegant: solids, fades, breaths, ambient flows, and soft sparkles
  static const Set<int> kElegantFxIds = {
    0,   // Solid
    2,   // Breathe
    12,  // Fade
    38,  // Aurora
    43,  // Rain
    56,  // Tri Fade
    67,  // Colorwaves
    75,  // Lake
    88,  // Candle
    97,  // Plasma
    101, // Pacifica
    102, // Candle Multi
    104, // Sunrise
    105, // Phased
    110, // Flow
    112, // Dancing Shadows
    115, // Blends
  };

  // Motion: chases, wipes, scanners, scanlines
  static const Set<int> kMotionFxIds = {
    3, 4, 6,        // Wipe, Wipe Random, Sweep
    10, 11,         // Scan, Scan Dual
    13, 14, 15, 16, // Theater, Theater Rainbow, Running, Saw
    27, 28, 29, 30, 31, 32, 37, // Android, Chase variants
    40, 41,         // Scanner, Lighthouse
    50, 52, 54,     // Two Dots, Running Dual, Chase 3
    55,             // Tri Wipe
    58, 60,         // ICU, Scanner Dual
    59,             // Multi Comet
    64,             // Juggle
    76, 77,         // Meteor, Meteor Smooth
    78,             // Railway
    92, 93, 94,     // Sinelon variants
    111,            // Chunchun
  };

  // Energy: strobes, fireworks, sparkles
  static const Set<int> kEnergyFxIds = {
    1,              // Blink
    17, 20, 21, 22, // Twinkle, Sparkle variants
    23, 24, 25,     // Strobe variants
    42,             // Fireworks
    49, 51,         // Fairy, Fairytwinkle
    57,             // Lightning
    74,             // Colortwinkles
    79, 99,         // Ripple, Ripple Rainbow
    80, 81,         // Twinklefox, Twinklecat
    87,             // Glitter
    89, 90,         // Fireworks Starburst, Fireworks 1D
    91, 95,         // Bouncing Balls, Popcorn
    103, 106,       // Solid Glitter, Twinkleup
  };

  /// Returns the vibe filter label for a given effect id.
  static String vibeForFx(int fxId) {
    if (kElegantFxIds.contains(fxId)) return 'Elegant';
    if (kEnergyFxIds.contains(fxId)) return 'Energy';
    // Default any remaining curated ids to Motion
    return 'Motion';
  }

  /// Helper to extract the effect id from a PatternItem payload.
  static int? effectIdFromPayload(Map<String, dynamic> payload) {
    try {
      final seg = payload['seg'];
      if (seg is List && seg.isNotEmpty) {
        final first = seg.first;
        if (first is Map && first['fx'] is int) return first['fx'] as int;
      }
    } catch (_) {}
    return null;
  }

  /// Get effect name from the centralized catalog.
  static String _effectName(int id) => WledEffectsCatalog.getName(id);

  static List<List<int>> _colorsToWledCol(List<Color> colors) {
    // WLED col expects up to 3 color slots; keep first 3 theme colors
    // Force W=0 to keep saturated colors accurate - WLED handles GRB conversion
    return colors.take(3).map((c) => rgbToRgbw(c.red, c.green, c.blue, forceZeroWhite: true)).toList(growable: false);
  }

  /// Generate 50 PatternItems for a given sub-category using its theme palette.
  Future<List<PatternItem>> generatePatternsForTheme(SubCategory subCat) async {
    final List<List<int>> col = _colorsToWledCol(subCat.themeColors);
    // Determine a backdrop image based on parent category if possible
    final catImage = _categories.firstWhere((c) => c.id == subCat.parentCategoryId, orElse: () => _categories.first).imageUrl;

    final List<PatternItem> items = [];
    for (final fxId in kMotionTemplateEffectIds) {
      final effectName = _effectName(fxId);
      final name = '${subCat.name} - $effectName';
      final payload = {
        'seg': [
          {
            'fx': fxId,
            'col': col,
            'sx': 128,
            'ix': 128,
          }
        ]
      };
      items.add(PatternItem(
        id: 'gen_${subCat.id}_fx_$fxId',
        name: name,
        imageUrl: catImage,
        categoryId: subCat.parentCategoryId,
        wledPayload: payload,
      ));
    }
    return items;
  }

  // Premium Categories
  static const PatternCategory catArchitectural = PatternCategory(
    id: 'cat_arch',
    name: 'Architectural Downlighting (White)',
    // Warm white lit home exterior
    imageUrl: 'https://images.unsplash.com/photo-1600585154154-8c857b74f2ab',
  );

  static const PatternCategory catHoliday = PatternCategory(
    id: 'cat_holiday',
    name: 'Holidays',
    // Christmas/Holiday lights
    imageUrl: 'https://images.unsplash.com/photo-1482517967863-00e15c9b44be',
  );

  static const PatternCategory catSports = PatternCategory(
    id: 'cat_sports',
    name: 'Game Day Fan Zone',
    // Stadium / team colors
    imageUrl: 'https://images.unsplash.com/photo-1518600506278-4e8ef466b810',
  );

  static const PatternCategory catSeasonal = PatternCategory(
    id: 'cat_season',
    name: 'Seasonal Vibes',
    // Autumn leaves / Spring flowers
    imageUrl: 'https://images.unsplash.com/photo-1477587458883-47145ed94245',
  );

  static const PatternCategory catParty = PatternCategory(
    id: 'cat_party',
    name: 'Parties & Events',
    // Colorful balloons / confetti
    imageUrl: 'https://images.unsplash.com/photo-1544491843-0ce2884635f3',
  );

  static const PatternCategory catSecurity = PatternCategory(
    id: 'cat_security',
    name: 'Security & Alerts',
    // Bright white floodlights
    imageUrl: 'https://images.unsplash.com/photo-1579403124614-197f69d8187b',
  );

  static const PatternCategory catMovies = PatternCategory(
    id: 'cat_movies',
    name: 'Movies & Superheroes',
    // Cinema / movie theme
    imageUrl: 'https://images.unsplash.com/photo-1536440136628-849c177e76a1',
  );

  static const List<PatternCategory> _categories = [
    catArchitectural,
    catHoliday,
    catSports,
    catSeasonal,
    catParty,
    catMovies,
    catSecurity,
  ];

  // ================= Sub-Categories (3-tier navigation) =================
  static final List<SubCategory> _subCategories = [
    // Holidays
    SubCategory(
      id: 'sub_xmas',
      name: 'Christmas',
      themeColors: const [Color(0xFFFF0000), Color(0xFF00FF00), Colors.white], // Pure red & green
      parentCategoryId: catHoliday.id,
    ),
    SubCategory(
      id: 'sub_halloween',
      name: 'Halloween',
      themeColors: const [Color(0xFFFF8C00), Color(0xFF800080), Colors.black], // Pure orange, purple
      parentCategoryId: catHoliday.id,
    ),
    SubCategory(
      id: 'sub_july4',
      name: '4th of July',
      themeColors: const [Color(0xFFFF0000), Colors.white, Color(0xFF0000FF)], // Pure red, white, blue
      parentCategoryId: catHoliday.id,
    ),
    SubCategory(
      id: 'sub_easter',
      name: 'Easter',
      themeColors: const [Color(0xFFFFB6C1), Color(0xFFADD8E6), Color(0xFFBFFF00)], // Light pink, light blue, lime
      parentCategoryId: catHoliday.id,
    ),
    SubCategory(
      id: 'sub_valentines',
      name: "Valentine's",
      themeColors: const [Color(0xFFFF0000), Color(0xFFFF69B4), Colors.white], // Pure red, hot pink
      parentCategoryId: catHoliday.id,
    ),
    SubCategory(
      id: 'sub_st_patricks',
      name: "St. Patrick's",
      themeColors: const [Color(0xFF00FF00), Color(0xFF90EE90), Colors.white], // Pure green, light green
      parentCategoryId: catHoliday.id,
    ),

    // Game Day - Using pure RGB colors for accurate LED display
    SubCategory(
      id: 'sub_kc',
      name: 'Kansas City',
      themeColors: const [Color(0xFFFF0000), Color(0xFFFFD700)], // Pure red, gold
      parentCategoryId: catSports.id,
    ),
    SubCategory(
      id: 'sub_seattle',
      name: 'Seattle',
      themeColors: const [Color(0xFF0000FF), Color(0xFF00FF00)], // Pure blue, pure green
      parentCategoryId: catSports.id,
    ),
    SubCategory(
      id: 'sub_rb_generic',
      name: 'General Red/Blue',
      themeColors: const [Color(0xFFFF0000), Color(0xFF0000FF), Colors.white], // Pure red, pure blue
      parentCategoryId: catSports.id,
    ),
    SubCategory(
      id: 'sub_gy_generic',
      name: 'General Green/Yellow',
      themeColors: const [Color(0xFF00FF00), Color(0xFFFFFF00)], // Pure green, pure yellow
      parentCategoryId: catSports.id,
    ),
    SubCategory(
      id: 'sub_ob_generic',
      name: 'General Orange/Blue',
      themeColors: const [Color(0xFFFF8C00), Color(0xFF0000FF)], // Pure orange, pure blue
      parentCategoryId: catSports.id,
    ),

    // Seasonal - Using pure RGB colors for accurate LED display
    SubCategory(
      id: 'sub_spring',
      name: 'Spring Pastels',
      themeColors: const [Color(0xFFFFB6C1), Color(0xFFDDA0DD), Color(0xFF90EE90)], // Light pink, plum, light green
      parentCategoryId: catSeasonal.id,
    ),
    SubCategory(
      id: 'sub_summer',
      name: 'Summer Vibrance',
      themeColors: const [Color(0xFF00FFFF), Color(0xFFFF8C00), Color(0xFF32CD32)], // Cyan, orange, lime green
      parentCategoryId: catSeasonal.id,
    ),
    SubCategory(
      id: 'sub_autumn',
      name: 'Autumn Harvest',
      themeColors: const [Color(0xFFFF8C00), Color(0xFF8B4513), Color(0xFFFF0000)], // Orange, saddle brown, red
      parentCategoryId: catSeasonal.id,
    ),
    SubCategory(
      id: 'sub_winter',
      name: 'Winter Frost',
      themeColors: const [Color(0xFF708090), Color(0xFFADD8E6), Colors.white], // Slate gray, light blue, white
      parentCategoryId: catSeasonal.id,
    ),

    // Architectural - Warm tones use specific hex values for LED accuracy
    SubCategory(
      id: 'sub_warm_whites',
      name: 'Warm Whites',
      themeColors: const [Color(0xFFFFB347), Color(0xFFFF8C00), Colors.white], // Warm amber, orange, white
      parentCategoryId: catArchitectural.id,
    ),
    SubCategory(
      id: 'sub_cool_whites',
      name: 'Cool Whites',
      themeColors: const [Color(0xFF708090), Colors.white], // Slate gray, white
      parentCategoryId: catArchitectural.id,
    ),
    SubCategory(
      id: 'sub_gold_accents',
      name: 'Gold Accents',
      themeColors: const [Color(0xFFFFD700), Color(0xFFFFFF00), Colors.white], // Gold, yellow, white
      parentCategoryId: catArchitectural.id,
    ),
    SubCategory(
      id: 'sub_security_floods',
      name: 'Security Floods',
      themeColors: const [Colors.white],
      parentCategoryId: catArchitectural.id,
    ),

    // Party - Using pure RGB colors for accurate LED display
    SubCategory(
      id: 'sub_birthday',
      name: 'Birthday Brights',
      themeColors: const [Color(0xFF00FFFF), Color(0xFFFF69B4), Color(0xFFFFFF00)], // Cyan, hot pink, yellow
      parentCategoryId: catParty.id,
    ),
    SubCategory(
      id: 'sub_elegant_dinner',
      name: 'Elegant Dinner',
      themeColors: const [Color(0xFFFFB347), Color(0xFF8B4513), Colors.white], // Amber, saddle brown, white
      parentCategoryId: catParty.id,
    ),
    SubCategory(
      id: 'sub_rave',
      name: 'Rave / Strobe',
      themeColors: const [Color(0xFF800080), Color(0xFF00FFFF), Color(0xFFFF69B4)], // Purple, cyan, hot pink
      parentCategoryId: catParty.id,
    ),
    SubCategory(
      id: 'sub_baby_shower',
      name: 'Baby Shower',
      themeColors: const [Color(0xFFADD8E6), Color(0xFFFFB6C1), Colors.white], // Light blue, light pink, white
      parentCategoryId: catParty.id,
    ),
  ];

  // Holiday items
  static final List<PatternItem> _holidayItems = [
    PatternItem(
      id: 'pat_candy_cane_chase',
      name: 'Candy Cane Chase',
      imageUrl: 'https://images.unsplash.com/photo-1543589077-47d81606c1bf',
      categoryId: catHoliday.id,
      wledPayload: const {
        'on': true,
        'bri': 255,
        'seg': [
          {
            'id': 0,
            'fx': 12, // Chase
            'pal': 3, // Red/White
            'sx': 180,
            'ix': 200
          }
        ]
      },
    ),
    PatternItem(
      id: 'pat_july4_sparkle',
      name: 'July 4th Sparkle',
      imageUrl: 'https://images.unsplash.com/photo-1475724017904-b712052c192a',
      categoryId: catHoliday.id,
      wledPayload: const {
        'on': true,
        'bri': 230,
        'seg': [
          {
            'id': 0,
            'fx': 120, // Sparkle
            'pal': 6, // Red/White/Blue
            'sx': 170,
            'ix': 180
          }
        ]
      },
    ),
    PatternItem(
      id: 'pat_spooky_halloween',
      name: 'Spooky Halloween',
      imageUrl: 'https://images.unsplash.com/photo-1509557965875-b88c97052f0e',
      categoryId: catHoliday.id,
      wledPayload: const {
        'on': true,
        'bri': 255,
        'seg': [
          {
            'id': 0,
            'fx': 76, // Lightning
            'pal': 5, // Purple/Orange
            'sx': 210,
            'ix': 200
          }
        ]
      },
    ),
    PatternItem(
      id: 'pat_easter_pastels',
      name: 'Easter Pastels',
      imageUrl: 'https://images.unsplash.com/photo-1522938974444-f12497b69347',
      categoryId: catHoliday.id,
      wledPayload: const {
        'on': true,
        'bri': 200,
        'seg': [
          {
            'id': 0,
            'fx': 9, // Color Waves
            'pal': 12, // Pastel-like
            'sx': 140,
            'ix': 160
          }
        ]
      },
    ),
  ];

  // Index all items
  static final List<PatternItem> _items = [
    ..._holidayItems,
  ];

  Future<List<PatternCategory>> getCategories() async {
    debugPrint('MockPatternRepository.getCategories');
    return _categories;
  }

  Future<List<PatternItem>> getItemsByCategory(String categoryId) async {
    debugPrint('MockPatternRepository.getItemsByCategory($categoryId)');
    return _items.where((e) => e.categoryId == categoryId).toList(growable: false);
  }

  Future<List<PatternItem>> getAllItems() async {
    debugPrint('MockPatternRepository.getAllItems');
    return _items;
  }

  Future<PatternItem?> getItem(String id) async {
    debugPrint('MockPatternRepository.getItem($id)');
    try {
      return _items.firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }

  // ================= Sub-Category Queries =================
  Future<List<SubCategory>> getSubCategoriesByCategory(String categoryId) async {
    debugPrint('MockPatternRepository.getSubCategoriesByCategory($categoryId)');
    return _subCategories.where((e) => e.parentCategoryId == categoryId).toList(growable: false);
  }

  Future<SubCategory?> getSubCategoryById(String subCategoryId) async {
    debugPrint('MockPatternRepository.getSubCategoryById($subCategoryId)');
    try {
      return _subCategories.firstWhere((e) => e.id == subCategoryId);
    } catch (_) {
      return null;
    }
  }

  // ================= NEW HIERARCHY SYSTEM =================

  /// Lazily built full hierarchy of all library nodes
  List<LibraryNode>? _cachedNodes;

  /// Get the full library hierarchy
  List<LibraryNode> get _allNodes {
    _cachedNodes ??= _buildFullHierarchy();
    return _cachedNodes!;
  }

  /// Build the complete library hierarchy from all data sources
  List<LibraryNode> _buildFullHierarchy() {
    final nodes = <LibraryNode>[];

    // Root categories
    nodes.addAll(_buildRootCategories());

    // Sports: leagues + teams + NCAA
    nodes.addAll(SportsLibraryBuilder.buildFullSportsHierarchy());

    // Holidays: folders + palettes
    nodes.addAll(HolidayPalettes.getHolidayFolders());
    nodes.addAll(HolidayPalettes.getAllHolidayPaletteNodes());

    // Seasonal: folders + colorways
    nodes.addAll(SeasonalColorways.getSeasonFolders());
    nodes.addAll(SeasonalColorways.getAllSeasonalPaletteNodes());

    // Parties & Events: folders + palettes
    nodes.addAll(PartyEventPalettes.getEventFolders());
    nodes.addAll(PartyEventPalettes.getAllEventPaletteNodes());

    // Movies & Superheroes: franchises + palettes
    nodes.addAll(MoviesSuperheroesPalettes.getAllFranchiseFolders());
    nodes.addAll(MoviesSuperheroesPalettes.getAllMoviesPaletteNodes());

    // Architectural & Security: direct palettes
    nodes.addAll(_buildArchitecturalPalettes());
    nodes.addAll(_buildSecurityPalettes());

    return nodes;
  }

  /// Build root category nodes
  List<LibraryNode> _buildRootCategories() {
    return const [
      LibraryNode(
        id: 'cat_sports',
        name: 'Game Day Fan Zone',
        nodeType: LibraryNodeType.category,
        sortOrder: 0,
        imageUrl: 'https://images.unsplash.com/photo-1518600506278-4e8ef466b810',
      ),
      LibraryNode(
        id: 'cat_holiday',
        name: 'Holidays',
        nodeType: LibraryNodeType.category,
        sortOrder: 1,
        imageUrl: 'https://images.unsplash.com/photo-1482517967863-00e15c9b44be',
      ),
      LibraryNode(
        id: 'cat_season',
        name: 'Seasonal Vibes',
        nodeType: LibraryNodeType.category,
        sortOrder: 2,
        imageUrl: 'https://images.unsplash.com/photo-1477587458883-47145ed94245',
      ),
      LibraryNode(
        id: 'cat_party',
        name: 'Parties & Events',
        nodeType: LibraryNodeType.category,
        sortOrder: 3,
        imageUrl: 'https://images.unsplash.com/photo-1544491843-0ce2884635f3',
      ),
      LibraryNode(
        id: 'cat_movies',
        name: 'Movies & Superheroes',
        nodeType: LibraryNodeType.category,
        sortOrder: 4,
        imageUrl: 'https://images.unsplash.com/photo-1536440136628-849c177e76a1',
      ),
      LibraryNode(
        id: 'cat_arch',
        name: 'Architectural Downlighting (White)',
        nodeType: LibraryNodeType.category,
        sortOrder: 5,
        imageUrl: 'https://images.unsplash.com/photo-1600585154154-8c857b74f2ab',
      ),
      LibraryNode(
        id: 'cat_security',
        name: 'Security & Alerts',
        nodeType: LibraryNodeType.category,
        sortOrder: 6,
        imageUrl: 'https://images.unsplash.com/photo-1579403124614-197f69d8187b',
      ),
    ];
  }

  /// Build architectural downlighting palettes
  List<LibraryNode> _buildArchitecturalPalettes() {
    return const [
      LibraryNode(
        id: 'arch_warmwhite',
        name: 'Warm White',
        description: 'Cozy amber glow',
        nodeType: LibraryNodeType.palette,
        parentId: 'cat_arch',
        themeColors: [Color(0xFFFFB347), Color(0xFFFFE4B5)],
        sortOrder: 0,
        metadata: {'suggestedEffects': [0, 2], 'defaultSpeed': 60, 'defaultIntensity': 128},
      ),
      LibraryNode(
        id: 'arch_coolwhite',
        name: 'Cool White',
        description: 'Crisp moonlight',
        nodeType: LibraryNodeType.palette,
        parentId: 'cat_arch',
        themeColors: [Color(0xFFFFFFFF), Color(0xFFE0E0E0)],
        sortOrder: 1,
        metadata: {'suggestedEffects': [0, 2], 'defaultSpeed': 60, 'defaultIntensity': 128},
      ),
      LibraryNode(
        id: 'arch_daylight',
        name: 'Daylight',
        description: 'Natural sunlight',
        nodeType: LibraryNodeType.palette,
        parentId: 'cat_arch',
        themeColors: [Color(0xFFFFFFFF), Color(0xFFFFFDD0)],
        sortOrder: 2,
        metadata: {'suggestedEffects': [0], 'defaultSpeed': 0, 'defaultIntensity': 128},
      ),
      LibraryNode(
        id: 'arch_candlelight',
        name: 'Candlelight',
        description: 'Flickering warm glow',
        nodeType: LibraryNodeType.palette,
        parentId: 'cat_arch',
        themeColors: [Color(0xFFFF8C00), Color(0xFFFFB347)],
        sortOrder: 3,
        metadata: {'suggestedEffects': [101, 88], 'defaultSpeed': 80, 'defaultIntensity': 180},
      ),
      LibraryNode(
        id: 'arch_moonlight',
        name: 'Moonlight',
        description: 'Soft blue night',
        nodeType: LibraryNodeType.palette,
        parentId: 'cat_arch',
        themeColors: [Color(0xFF87CEEB), Color(0xFFFFFFFF)],
        sortOrder: 4,
        metadata: {'suggestedEffects': [0, 2], 'defaultSpeed': 60, 'defaultIntensity': 128},
      ),
      LibraryNode(
        id: 'arch_golden',
        name: 'Golden Hour',
        description: 'Sunset gold tones',
        nodeType: LibraryNodeType.palette,
        parentId: 'cat_arch',
        themeColors: [Color(0xFFFFD700), Color(0xFFFF8C00), Color(0xFFFFB347)],
        sortOrder: 5,
        metadata: {'suggestedEffects': [0, 2, 41], 'defaultSpeed': 60, 'defaultIntensity': 128},
      ),
    ];
  }

  /// Build security/alert palettes
  List<LibraryNode> _buildSecurityPalettes() {
    return const [
      LibraryNode(
        id: 'security_bright',
        name: 'Security Bright',
        description: 'Maximum brightness white',
        nodeType: LibraryNodeType.palette,
        parentId: 'cat_security',
        themeColors: [Color(0xFFFFFFFF)],
        sortOrder: 0,
        metadata: {'suggestedEffects': [0], 'defaultSpeed': 0, 'defaultIntensity': 255},
      ),
      LibraryNode(
        id: 'security_alert_red',
        name: 'Alert Red',
        description: 'Emergency red flash',
        nodeType: LibraryNodeType.palette,
        parentId: 'cat_security',
        themeColors: [Color(0xFFFF0000), Color(0xFF000000)],
        sortOrder: 1,
        metadata: {'suggestedEffects': [1, 23], 'defaultSpeed': 200, 'defaultIntensity': 255},
      ),
      LibraryNode(
        id: 'security_police',
        name: 'Police Lights',
        description: 'Red and blue flash',
        nodeType: LibraryNodeType.palette,
        parentId: 'cat_security',
        themeColors: [Color(0xFFFF0000), Color(0xFF0000FF)],
        sortOrder: 2,
        metadata: {'suggestedEffects': [1, 12], 'defaultSpeed': 180, 'defaultIntensity': 255},
      ),
      LibraryNode(
        id: 'security_amber',
        name: 'Caution Amber',
        description: 'Warning amber',
        nodeType: LibraryNodeType.palette,
        parentId: 'cat_security',
        themeColors: [Color(0xFFFFBF00), Color(0xFF000000)],
        sortOrder: 3,
        metadata: {'suggestedEffects': [1, 2], 'defaultSpeed': 150, 'defaultIntensity': 255},
      ),
      LibraryNode(
        id: 'security_motion',
        name: 'Motion Detected',
        description: 'Bright white on motion',
        nodeType: LibraryNodeType.palette,
        parentId: 'cat_security',
        themeColors: [Color(0xFFFFFFFF), Color(0xFFFFD700)],
        sortOrder: 4,
        metadata: {'suggestedEffects': [0], 'defaultSpeed': 0, 'defaultIntensity': 255},
      ),
    ];
  }

  // ================= Hierarchy Query Methods =================

  /// Get child nodes for any parent (null for root categories)
  Future<List<LibraryNode>> getChildNodes(String? parentId) async {
    if (parentId == null) {
      // Return root categories
      return _allNodes
          .where((n) => n.nodeType == LibraryNodeType.category && n.parentId == null)
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }

    return _allNodes
        .where((n) => n.parentId == parentId)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  /// Get a single node by ID
  Future<LibraryNode?> getNodeById(String nodeId) async {
    try {
      return _allNodes.firstWhere((n) => n.id == nodeId);
    } catch (_) {
      return null;
    }
  }

  /// Get ancestor chain (breadcrumb) for a node
  Future<List<LibraryNode>> getAncestors(String nodeId) async {
    final ancestors = <LibraryNode>[];
    var current = await getNodeById(nodeId);

    while (current != null && current.parentId != null) {
      current = await getNodeById(current.parentId!);
      if (current != null) {
        ancestors.insert(0, current);
      }
    }

    return ancestors;
  }

  /// Check if a node has children
  Future<bool> hasChildren(String nodeId) async {
    return _allNodes.any((n) => n.parentId == nodeId);
  }

  /// Generate patterns for a palette node
  Future<List<PatternItem>> generatePatternsForNode(LibraryNode node) async {
    if (!node.isPalette) return [];

    final colors = node.themeColors!;
    final col = _colorsToWledCol(colors);
    final effectIds = node.suggestedEffects.isNotEmpty
        ? node.suggestedEffects
        : kMotionTemplateEffectIds;

    final items = <PatternItem>[];
    for (final fxId in effectIds) {
      final effectName = _effectName(fxId);
      items.add(PatternItem(
        id: 'gen_${node.id}_fx_$fxId',
        name: '${node.name} - $effectName',
        imageUrl: '',
        categoryId: _findRootCategoryId(node.id),
        wledPayload: {
          'on': true,
          'bri': 200,
          'seg': [
            {
              'fx': fxId,
              'col': col,
              'sx': node.defaultSpeed,
              'ix': node.defaultIntensity,
            }
          ]
        },
      ));
    }

    return items;
  }

  /// Find the root category ID for a node
  String _findRootCategoryId(String nodeId) {
    var current = _allNodes.firstWhere(
      (n) => n.id == nodeId,
      orElse: () => const LibraryNode(id: '', name: '', nodeType: LibraryNodeType.palette),
    );

    while (current.parentId != null) {
      current = _allNodes.firstWhere(
        (n) => n.id == current.parentId,
        orElse: () => const LibraryNode(id: '', name: '', nodeType: LibraryNodeType.category),
      );
    }

    return current.id;
  }
}
