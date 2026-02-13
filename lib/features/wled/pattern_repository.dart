import 'package:flutter/foundation.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:nexgen_command/features/wled/wled_service.dart' show rgbToRgbw;
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';
import 'package:nexgen_command/features/wled/lumina_custom_effects.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/sports_library_builder.dart';
import 'package:nexgen_command/features/wled/big_event_library_builder.dart';
import 'package:nexgen_command/data/holiday_palettes.dart';
import 'package:nexgen_command/data/seasonal_colorways.dart';
import 'package:nexgen_command/data/party_event_palettes.dart';
import 'package:nexgen_command/data/ncaa_conferences.dart';
import 'package:nexgen_command/data/movies_superheroes_palettes.dart';
import 'package:nexgen_command/data/nature_outdoors_palettes.dart';
import 'package:nexgen_command/services/big_event_service.dart';
import 'package:flutter/material.dart';

/// In-memory data source for the Pattern Library.
/// Provides categories, sub-categories, and procedurally generated patterns.
class PatternRepository {
  PatternRepository();

  /// Dynamic big event nodes that can be updated at runtime
  List<LibraryNode> _bigEventNodes = [];

  /// Dynamic My Teams nodes based on user profile
  List<LibraryNode> _myTeamsNodes = [];

  /// Update the big event nodes (called when events change)
  void updateBigEventNodes(List<BigEvent> events) {
    _bigEventNodes = BigEventLibraryBuilder.buildBigEventHierarchy(events);
    // Clear cache to force rebuild with new events
    _cachedNodes = null;
    debugPrint('PatternRepository: Updated big event nodes with ${events.length} events');
  }

  /// Clear big event nodes (e.g., when no events are upcoming)
  void clearBigEventNodes() {
    _bigEventNodes = [];
    _cachedNodes = null;
  }

  /// Update My Teams based on user's saved team preferences.
  /// Call this when user profile loads or when sportsTeams changes.
  void updateMyTeams(List<String> userTeamNames) {
    _myTeamsNodes = SportsLibraryBuilder.getMyTeamsPalettes(userTeamNames);
    // Clear cache to force rebuild with new teams
    _cachedNodes = null;
    debugPrint('PatternRepository: Updated My Teams with ${_myTeamsNodes.length} teams from ${userTeamNames.length} user preferences');
  }

  /// Clear My Teams (e.g., when user logs out)
  void clearMyTeams() {
    _myTeamsNodes = [];
    _cachedNodes = null;
  }

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

  /// Curated effects for colorway pattern generation (respects user colors).
  /// These are selected to produce 30 visually distinct variations.
  /// Mix of classic effects and exotic/impressive effects for Nex-Gen brand.
  static const List<int> kColorwayEffectIds = [
    // Classic Effects
    0,   // Solid
    2,   // Breathe
    3,   // Wipe
    6,   // Sweep
    10,  // Scan
    12,  // Fade
    13,  // Theater
    15,  // Running
    17,  // Twinkle
    20,  // Sparkle
    28,  // Chase
    40,  // Scanner
    49,  // Fairy
    59,  // Multi Comet
    76,  // Meteor
    87,  // Glitter
    91,  // Bouncing Balls
    96,  // Drip
    // Exotic Effects - Forward-thinking, visually impressive
    46,  // Twinklefox - magical fairy-dust sparkle
    52,  // Ripple - expanding ripple waves
    65,  // Colorwaves - flowing color waves
    69,  // Aurora - northern lights simulation
    70,  // Lake - shimmering water reflection
    73,  // Pacifica - ocean-inspired flowing
    82,  // Plasma - plasma ball effect
    89,  // Fireworks Starburst - explosive celebration
    100, // Heartbeat - pulsing life rhythm
    107, // Flow - smooth flowing motion
    111, // Chunchun - unique flowing pattern
    112, // Dancing Shadows - dramatic shadow play
  ];

  /// Creative name templates for effects.
  /// Keys are effect IDs, values are functions that transform colorway name.
  /// The function receives (colorwayName) and returns a creative pattern name.
  static String _creativePatternName(int effectId, String colorwayName) {
    // Pluralize helper - adds 's' if not already ending in 's'
    String plural(String name) {
      if (name.toLowerCase().endsWith('s')) return name;
      if (name.toLowerCase().endsWith('y') && !name.toLowerCase().endsWith('ay') && !name.toLowerCase().endsWith('ey')) {
        return '${name.substring(0, name.length - 1)}ies';
      }
      return '${name}s';
    }

    // Remove common suffixes for cleaner names
    String base(String name) {
      final lower = name.toLowerCase();
      if (lower.endsWith(' glow') || lower.endsWith(' vibes') || lower.endsWith(' palette')) {
        return name.substring(0, name.lastIndexOf(' '));
      }
      return name;
    }

    final baseName = base(colorwayName);

    switch (effectId) {
      case 0:   // Solid
        return 'Classic $baseName';
      case 2:   // Breathe
        return 'Breathing $baseName';
      case 3:   // Wipe
        return '$baseName Wave';
      case 6:   // Sweep
        return 'Sweeping $baseName';
      case 10:  // Scan
        return '$baseName Scanner';
      case 12:  // Fade
        return 'Fading ${plural(baseName)}';
      case 13:  // Theater
        return '$baseName Marquee';
      case 15:  // Running
        return 'Running ${plural(baseName)}';
      case 17:  // Twinkle
        return '$baseName Stars';
      case 20:  // Sparkle
        return 'Sparkling ${plural(baseName)}';
      case 28:  // Chase
        return '$baseName Chase';
      case 40:  // Scanner
        return '$baseName Spotlight';
      case 49:  // Fairy
        return '$baseName Fairy Lights';
      case 59:  // Multi Comet
        return '$baseName Comets';
      case 76:  // Meteor
        return '$baseName Meteors';
      case 87:  // Glitter
        return 'Glittering ${plural(baseName)}';
      case 91:  // Bouncing Balls
        return 'Bouncing ${plural(baseName)}';
      case 96:  // Drip
        return '$baseName Drips';
      // Exotic Effects
      case 46:  // Twinklefox
        return '$baseName Stardust';
      case 52:  // Ripple
        return '$baseName Ripples';
      case 65:  // Colorwaves
        return 'Flowing ${plural(baseName)}';
      case 69:  // Aurora
        return '$baseName Aurora';
      case 70:  // Lake
        return '$baseName Reflections';
      case 73:  // Pacifica
        return '$baseName Tides';
      case 82:  // Plasma
        return '$baseName Plasma';
      case 89:  // Fireworks Starburst
        return '$baseName Burst';
      case 100: // Heartbeat
        return '$baseName Pulse';
      case 107: // Flow
        return '$baseName Flow';
      case 111: // Chunchun
        return 'Dancing ${plural(baseName)}';
      case 112: // Dancing Shadows
        return '$baseName Shadows';
      default:
        // Fallback: check if it's a custom effect, otherwise use WLED name
        if (LuminaCustomEffectsCatalog.isCustomEffect(effectId)) {
          return '$colorwayName - ${LuminaCustomEffectsCatalog.getName(effectId)}';
        }
        return '$colorwayName - ${_effectName(effectId)}';
    }
  }

  static List<List<int>> _colorsToWledCol(List<Color> colors) {
    // WLED col expects up to 3 color slots; keep first 3 theme colors
    // Force W=0 to keep saturated colors accurate - WLED handles GRB conversion
    return colors.take(3).map((c) => rgbToRgbw(c.red, c.green, c.blue, forceZeroWhite: true)).toList(growable: false);
  }

  /// Generate pattern items for a given sub-category using its theme palette.
  /// Uses creative naming combining the theme name with effect types.
  Future<List<PatternItem>> generatePatternsForTheme(SubCategory subCat) async {
    final List<List<int>> col = _colorsToWledCol(subCat.themeColors);
    // Determine a backdrop image based on parent category if possible
    final catImage = _categories.firstWhere((c) => c.id == subCat.parentCategoryId, orElse: () => _categories.first).imageUrl;

    final List<PatternItem> items = [];
    for (final fxId in kColorwayEffectIds) {
      // Use creative naming for consistency
      final creativeName = _creativePatternName(fxId, subCat.name);
      final adjustedSpeed = WledEffectsCatalog.getAdjustedSpeed(fxId, 128);
      final payload = {
        'seg': [
          {
            'fx': fxId,
            'col': col,
            'sx': adjustedSpeed,
            'ix': 128,
            'pal': 5, // "Colors Only" - use segment colors only, no rainbow blending
          }
        ]
      };
      items.add(PatternItem(
        id: 'gen_${subCat.id}_fx_$fxId',
        name: creativeName,
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

  static const PatternCategory catNature = PatternCategory(
    id: 'cat_nature',
    name: 'Nature & Outdoors',
    // Stars / space / nature
    imageUrl: 'https://images.unsplash.com/photo-1419242902214-272b3f66ee7a',
  );

  static const List<PatternCategory> _categories = [
    catArchitectural,
    catHoliday,
    catSports,
    catSeasonal,
    catParty,
    catMovies,
    catSecurity,
    catNature,
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
    debugPrint('PatternRepository.getCategories');
    return _categories;
  }

  Future<List<PatternItem>> getItemsByCategory(String categoryId) async {
    debugPrint('PatternRepository.getItemsByCategory($categoryId)');
    return _items.where((e) => e.categoryId == categoryId).toList(growable: false);
  }

  Future<List<PatternItem>> getAllItems() async {
    debugPrint('PatternRepository.getAllItems');
    return _items;
  }

  Future<PatternItem?> getItem(String id) async {
    debugPrint('PatternRepository.getItem($id)');
    try {
      return _items.firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }

  // ================= Sub-Category Queries =================
  Future<List<SubCategory>> getSubCategoriesByCategory(String categoryId) async {
    debugPrint('PatternRepository.getSubCategoriesByCategory($categoryId)');
    return _subCategories.where((e) => e.parentCategoryId == categoryId).toList(growable: false);
  }

  Future<SubCategory?> getSubCategoryById(String subCategoryId) async {
    debugPrint('PatternRepository.getSubCategoryById($subCategoryId)');
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

    // Big Events (dynamic - appears first in Game Day Fan Zone if active)
    if (_bigEventNodes.isNotEmpty) {
      nodes.addAll(_bigEventNodes);
    }

    // My Teams folder (always present, palettes added dynamically based on user profile)
    nodes.add(SportsLibraryBuilder.getMyTeamsFolder());
    if (_myTeamsNodes.isNotEmpty) {
      nodes.addAll(_myTeamsNodes);
    }

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

    // Nature & Outdoors: environments + palettes
    nodes.addAll(NatureOutdoorsPalettes.getAllNatureFolders());
    nodes.addAll(NatureOutdoorsPalettes.getAllNaturePaletteNodes());

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
      LibraryNode(
        id: 'cat_nature',
        name: 'Nature & Outdoors',
        nodeType: LibraryNodeType.category,
        sortOrder: 7,
        imageUrl: 'https://images.unsplash.com/photo-1419242902214-272b3f66ee7a',
      ),
    ];
  }

  /// Architectural white style definitions — Kelvin color temperature ramp.
  /// RGB values derived from the Tanner Helland algorithm for each Kelvin step.
  static const _archWhiteStyles = [
    (id: 'k2000', name: '2000K', desc: 'Candlelight', colors: [Color(0xFFFF890E), Color(0xFFFFAB47)]),
    (id: 'k2700', name: '2700K', desc: 'Incandescent', colors: [Color(0xFFFFA757), Color(0xFFFFC78D)]),
    (id: 'k3000', name: '3000K', desc: 'Warm White', colors: [Color(0xFFFFB16E), Color(0xFFFFCFA0)]),
    (id: 'k3500', name: '3500K', desc: 'Soft White', colors: [Color(0xFFFFC18D), Color(0xFFFFDABB)]),
    (id: 'k4000', name: '4000K', desc: 'Neutral White', colors: [Color(0xFFFFCEA6), Color(0xFFFFE2CA)]),
    (id: 'k4500', name: '4500K', desc: 'Cool White', colors: [Color(0xFFFFDABB), Color(0xFFFFEAD8)]),
    (id: 'k5000', name: '5000K', desc: 'Daylight', colors: [Color(0xFFFFE4CE), Color(0xFFFFF0E4)]),
    (id: 'k5500', name: '5500K', desc: 'Bright Daylight', colors: [Color(0xFFFFEEDE), Color(0xFFFFF6EE)]),
    (id: 'k6500', name: '6500K', desc: 'Moonlight', colors: [Color(0xFFFFFEFA), Color(0xFFEEF2FF)]),
  ];

  /// Galaxy & Starlight style definitions - combines with dim levels
  static const _galaxyDimLevels = [
    (level: 50, name: '50%', desc: 'Half brightness dim'),
    (level: 40, name: '40%', desc: 'Subtle dim'),
    (level: 30, name: '30%', desc: 'Low dim'),
  ];

  /// Build architectural downlighting folders and spacing pattern palettes
  List<LibraryNode> _buildArchitecturalPalettes() {
    final nodes = <LibraryNode>[];

    // Create a folder for each white style
    for (var i = 0; i < _archWhiteStyles.length; i++) {
      final style = _archWhiteStyles[i];

      // Add the folder node for this white style
      nodes.add(LibraryNode(
        id: 'arch_${style.id}',
        name: style.name,
        description: style.desc,
        nodeType: LibraryNodeType.folder,
        parentId: 'cat_arch',
        themeColors: style.colors,
        sortOrder: i,
      ));

      // "All On" solid pattern — every LED lit, no spacing
      nodes.add(LibraryNode(
        id: 'arch_${style.id}_all',
        name: 'All ${style.name}',
        description: 'All LEDs solid ${style.desc.toLowerCase()}',
        nodeType: LibraryNodeType.palette,
        parentId: 'arch_${style.id}',
        themeColors: style.colors,
        sortOrder: 0,
        metadata: {
          'suggestedEffects': [0], // Solid effect
          'defaultSpeed': 0,
          'defaultIntensity': 128,
          'grouping': 1,
          'spacing': 0,
        },
      ));

      // Generate spacing patterns: X on Y off (X: 1-4, Y: 1-4)
      var patternIndex = 1; // Start after "All On"
      for (var onCount = 1; onCount <= 4; onCount++) {
        for (var offCount = 1; offCount <= 4; offCount++) {
          final patternName = '$onCount On $offCount Off';
          final patternDesc = '$onCount LED${onCount > 1 ? 's' : ''} on, $offCount off';

          nodes.add(LibraryNode(
            id: 'arch_${style.id}_${onCount}on${offCount}off',
            name: patternName,
            description: patternDesc,
            nodeType: LibraryNodeType.palette,
            parentId: 'arch_${style.id}',
            themeColors: style.colors,
            sortOrder: patternIndex,
            metadata: {
              'suggestedEffects': [0], // Solid effect for downlighting
              'defaultSpeed': 0,
              'defaultIntensity': 128,
              'grouping': onCount,
              'spacing': offCount,
            },
          ));
          patternIndex++;
        }
      }
    }

    // Add Galaxy & Starlight section
    final styleCount = _archWhiteStyles.length;
    nodes.add(const LibraryNode(
      id: 'arch_galaxy',
      name: 'Galaxy & Starlight',
      description: 'Elegant stars with dimmed twinkling accents',
      nodeType: LibraryNodeType.folder,
      parentId: 'cat_arch',
      themeColors: [Color(0xFFFFFFFF), Color(0xFF87CEEB)],
      sortOrder: 100, // After regular styles
    ));

    // Create sub-folders for each white style within Galaxy section
    for (var i = 0; i < _archWhiteStyles.length; i++) {
      final style = _archWhiteStyles[i];

      nodes.add(LibraryNode(
        id: 'arch_galaxy_${style.id}',
        name: '${style.name} Stars',
        description: 'Galaxy effect with ${style.name.toLowerCase()}',
        nodeType: LibraryNodeType.folder,
        parentId: 'arch_galaxy',
        themeColors: style.colors,
        sortOrder: i,
      ));

      // Generate Galaxy patterns: X bright Y dimmed (X: 1-4, Y: 1-4) at various dim levels
      var patternIndex = 0;
      for (final dimLevel in _galaxyDimLevels) {
        // Add a sub-folder for each dim level
        final dimFolderId = 'arch_galaxy_${style.id}_dim${dimLevel.level}';
        nodes.add(LibraryNode(
          id: dimFolderId,
          name: 'Dim at ${dimLevel.name}',
          description: 'Accents dimmed to ${dimLevel.level}% brightness',
          nodeType: LibraryNodeType.folder,
          parentId: 'arch_galaxy_${style.id}',
          themeColors: style.colors,
          sortOrder: patternIndex ~/ 16,
        ));

        for (var brightCount = 1; brightCount <= 4; brightCount++) {
          for (var dimCount = 1; dimCount <= 4; dimCount++) {
            final patternName = '$brightCount Bright $dimCount Dim';
            final patternDesc = '$brightCount bright, $dimCount at ${dimLevel.level}%';

            nodes.add(LibraryNode(
              id: 'arch_galaxy_${style.id}_${dimLevel.level}_${brightCount}b${dimCount}d',
              name: patternName,
              description: patternDesc,
              nodeType: LibraryNodeType.palette,
              parentId: dimFolderId,
              themeColors: style.colors,
              sortOrder: patternIndex % 16,
              metadata: {
                'suggestedEffects': [0, 17, 49], // Solid, Twinkle, Fairy
                'defaultSpeed': 60,
                'defaultIntensity': 128,
                'grouping': brightCount,
                'spacing': dimCount,
                'isGalaxyPattern': true,
                'dimLevel': dimLevel.level,
                'brightCount': brightCount,
                'dimCount': dimCount,
              },
            ));
            patternIndex++;
          }
        }
      }

      // Add special "Twinkling Stars" patterns with twinkle effect
      final twinkleFolderId = 'arch_galaxy_${style.id}_twinkle';
      nodes.add(LibraryNode(
        id: twinkleFolderId,
        name: 'Twinkling Stars',
        description: 'Soft twinkling star effect',
        nodeType: LibraryNodeType.folder,
        parentId: 'arch_galaxy_${style.id}',
        themeColors: style.colors,
        sortOrder: 10,
      ));

      for (var brightCount = 1; brightCount <= 4; brightCount++) {
        for (var dimCount = 1; dimCount <= 4; dimCount++) {
          final patternName = '$brightCount Solid $dimCount Twinkle';
          final patternDesc = '$brightCount steady, $dimCount twinkling';

          nodes.add(LibraryNode(
            id: 'arch_galaxy_${style.id}_twinkle_${brightCount}s${dimCount}t',
            name: patternName,
            description: patternDesc,
            nodeType: LibraryNodeType.palette,
            parentId: twinkleFolderId,
            themeColors: style.colors,
            sortOrder: (brightCount - 1) * 4 + (dimCount - 1),
            metadata: {
              'suggestedEffects': [17, 49, 80], // Twinkle, Fairy, Twinklefox
              'defaultSpeed': 80,
              'defaultIntensity': 180,
              'grouping': brightCount,
              'spacing': dimCount,
              'isTwinklePattern': true,
              'brightCount': brightCount,
              'dimCount': dimCount,
            },
          ));
        }
      }
    }

    return nodes;
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

  /// Generate patterns for a palette node with creative naming.
  /// Produces 23 pattern variations with clever names combining the
  /// colorway name with the effect type.
  Future<List<PatternItem>> generatePatternsForNode(LibraryNode node) async {
    if (!node.isPalette) return [];

    final colors = node.themeColors!;
    final col = _colorsToWledCol(colors);

    // Check for special pattern types
    final isGalaxyPattern = node.metadata?['isGalaxyPattern'] == true;
    final isTwinklePattern = node.metadata?['isTwinklePattern'] == true;
    final hasSpacingMetadata = node.metadata?['grouping'] != null && node.metadata?['spacing'] != null;
    final grouping = node.metadata?['grouping'] as int?;
    final spacing = node.metadata?['spacing'] as int?;

    // Handle Galaxy patterns (bright + dimmed)
    if (isGalaxyPattern) {
      return _generateGalaxyPatterns(node, col);
    }

    // Handle Twinkle patterns (bright + twinkling)
    if (isTwinklePattern) {
      return _generateTwinklePatterns(node, col);
    }

    // For architectural spacing patterns, generate fewer effects focused on solid/simple
    // For regular palettes, use full kColorwayEffectIds for creative pattern variations
    // Note: include 3-color effects (12, 6, 51, 46) so palettes with 3+ colors display properly
    final effectIds = hasSpacingMetadata
        ? const [0, 2, 12, 6, 15, 51, 46, 41] // Solid, Breathe, Fade, Sweep, Running, Gradient, Twinklefox, Lighthouse
        : kColorwayEffectIds;

    final items = <PatternItem>[];
    for (final fxId in effectIds) {
      // Generate creative pattern name
      final creativeName = hasSpacingMetadata && fxId == 0
          ? node.name // For solid effect, just use the spacing name (e.g., "1 On 2 Off")
          : _creativePatternName(fxId, node.name);

      // Apply speed adjustment from catalog
      final adjustedSpeed = WledEffectsCatalog.getAdjustedSpeed(fxId, node.defaultSpeed);

      // Build segment data
      // CRITICAL: Set 'pal': 5 ("Colors Only" palette) to ensure effects use
      // only the segment colors in 'col', not the rainbow default palette.
      // This fixes issues with effects like Spots Fade, Twinkle Fox, etc.
      // showing rainbow colors instead of the selected theme colors.
      final segData = <String, dynamic>{
        'fx': fxId,
        'col': col,
        'sx': adjustedSpeed,
        'ix': node.defaultIntensity,
        'pal': 5, // "Colors Only" - prevents rainbow palette blending
      };

      // Add grouping and spacing for architectural patterns
      // WLED JSON API uses 'grp' for grouping and 'spc' for spacing
      if (hasSpacingMetadata && grouping != null && spacing != null) {
        segData['grp'] = grouping;
        segData['spc'] = spacing;
      }

      items.add(PatternItem(
        id: 'gen_${node.id}_fx_$fxId',
        name: creativeName,
        imageUrl: '',
        categoryId: _findRootCategoryId(node.id),
        wledPayload: {
          'on': true,
          'bri': 200,
          'seg': [segData]
        },
      ));
    }

    return items;
  }

  /// Generate Galaxy patterns with bright and dimmed sections.
  /// Creates an elegant starfield effect with some lights brighter than others.
  List<PatternItem> _generateGalaxyPatterns(LibraryNode node, List<List<int>> col) {
    final dimLevel = (node.metadata?['dimLevel'] as int?) ?? 50;
    final brightCount = (node.metadata?['brightCount'] as int?) ?? 1;
    final dimCount = (node.metadata?['dimCount'] as int?) ?? 1;

    // Calculate brightness values
    final fullBrightness = 255;
    final dimBrightness = (255 * dimLevel / 100).round();

    final items = <PatternItem>[];

    // Pattern variations for galaxy effect
    final galaxyEffects = [
      (id: 0, name: 'Solid Stars', desc: 'Static starfield'),
      (id: 2, name: 'Breathing Stars', desc: 'Gently pulsing'),
      (id: 17, name: 'Sparkling Galaxy', desc: 'Random sparkles'),
      (id: 49, name: 'Fairy Stars', desc: 'Magical shimmer'),
    ];

    for (final effect in galaxyEffects) {
      // Create pattern with grouping/spacing to simulate bright/dim pattern
      // The "dim" effect is achieved via lower intensity on the spacing pixels
      items.add(PatternItem(
        id: 'gen_${node.id}_galaxy_${effect.id}',
        name: '${node.name} - ${effect.name}',
        imageUrl: '',
        categoryId: _findRootCategoryId(node.id),
        wledPayload: {
          'on': true,
          'bri': fullBrightness,
          'seg': [
            {
              'fx': effect.id,
              'col': col,
              'sx': effect.id == 0 ? 0 : 80,
              'ix': dimBrightness, // Use dim level for intensity
              'grp': brightCount,
              'spc': dimCount,
              'pal': 5, // "Colors Only" - use segment colors only
            }
          ]
        },
      ));
    }

    // Add a special "Cascade" pattern that alternates brightness
    items.add(PatternItem(
      id: 'gen_${node.id}_galaxy_cascade',
      name: '${node.name} - Star Cascade',
      imageUrl: '',
      categoryId: _findRootCategoryId(node.id),
      wledPayload: {
        'on': true,
        'bri': fullBrightness,
        'seg': [
          {
            'fx': 12, // Fade effect
            'col': col,
            'sx': 60,
            'ix': dimBrightness,
            'grp': brightCount,
            'spc': dimCount,
            'pal': 5, // "Colors Only" - use segment colors only
          }
        ]
      },
    ));

    return items;
  }

  /// Generate Twinkle patterns with solid and twinkling sections.
  /// Creates an elegant effect with some lights steady and others twinkling.
  List<PatternItem> _generateTwinklePatterns(LibraryNode node, List<List<int>> col) {
    final brightCount = (node.metadata?['brightCount'] as int?) ?? 1;
    final dimCount = (node.metadata?['dimCount'] as int?) ?? 1;

    final items = <PatternItem>[];

    // Twinkle effect variations
    final twinkleEffects = [
      (id: 17, name: 'Classic Twinkle', speed: 80, intensity: 180),
      (id: 49, name: 'Fairy Twinkle', speed: 100, intensity: 200),
      (id: 80, name: 'Twinklefox', speed: 90, intensity: 190),
      (id: 74, name: 'Colortwinkles', speed: 70, intensity: 160),
      (id: 87, name: 'Glitter Stars', speed: 120, intensity: 220),
    ];

    for (final effect in twinkleEffects) {
      items.add(PatternItem(
        id: 'gen_${node.id}_twinkle_${effect.id}',
        name: '${node.name} - ${effect.name}',
        imageUrl: '',
        categoryId: _findRootCategoryId(node.id),
        wledPayload: {
          'on': true,
          'bri': 220,
          'seg': [
            {
              'fx': effect.id,
              'col': col,
              'sx': effect.speed,
              'ix': effect.intensity,
              'grp': brightCount,
              'spc': dimCount,
              'pal': 5, // "Colors Only" - use segment colors only
            }
          ]
        },
      ));
    }

    // Add slow/medium/fast variations of the basic twinkle
    final speedVariations = [
      (name: 'Slow Shimmer', speed: 40),
      (name: 'Gentle Sparkle', speed: 80),
      (name: 'Lively Stars', speed: 150),
    ];

    for (final variation in speedVariations) {
      items.add(PatternItem(
        id: 'gen_${node.id}_twinkle_speed_${variation.speed}',
        name: '${node.name} - ${variation.name}',
        imageUrl: '',
        categoryId: _findRootCategoryId(node.id),
        wledPayload: {
          'on': true,
          'bri': 220,
          'seg': [
            {
              'fx': 17, // Twinkle
              'col': col,
              'sx': variation.speed,
              'ix': 180,
              'grp': brightCount,
              'spc': dimCount,
              'pal': 5, // "Colors Only" - use segment colors only
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

  // ================= PATTERN LIBRARY SEARCH =================

  /// Search result containing a matching library node or pattern item.
  /// Contains the match data and the navigation path to reach it.

  /// Search through all existing patterns in the library.
  /// Returns matching LibraryNodes (palettes, folders) and PatternItems.
  /// Uses fuzzy matching on names, descriptions, and related keywords.
  Future<LibrarySearchResults> searchLibrary(String query) async {
    if (query.trim().isEmpty) {
      return const LibrarySearchResults(palettes: [], folders: [], patterns: []);
    }

    final searchTerms = query.toLowerCase().split(RegExp(r'\s+'));
    final matchingPalettes = <LibraryNode>[];
    final matchingFolders = <LibraryNode>[];
    final matchingPatterns = <PatternItem>[];

    // Search all library nodes
    for (final node in _allNodes) {
      final score = _calculateMatchScore(node, searchTerms);
      if (score > 0) {
        if (node.isPalette) {
          matchingPalettes.add(node);
        } else if (node.nodeType == LibraryNodeType.folder || node.nodeType == LibraryNodeType.category) {
          matchingFolders.add(node);
        }
      }
    }

    // Search existing pattern items
    for (final item in _items) {
      if (_patternMatchesQuery(item, searchTerms)) {
        matchingPatterns.add(item);
      }
    }

    // Sort by relevance (name starts with query first)
    matchingPalettes.sort((a, b) => _compareByRelevance(a.name, b.name, query));
    matchingFolders.sort((a, b) => _compareByRelevance(a.name, b.name, query));
    matchingPatterns.sort((a, b) => _compareByRelevance(a.name, b.name, query));

    return LibrarySearchResults(
      palettes: matchingPalettes.take(10).toList(),
      folders: matchingFolders.take(5).toList(),
      patterns: matchingPatterns.take(10).toList(),
    );
  }

  /// Calculate match score for a library node against search terms.
  int _calculateMatchScore(LibraryNode node, List<String> searchTerms) {
    int score = 0;
    final nameLower = node.name.toLowerCase();
    final descLower = (node.description ?? '').toLowerCase();

    for (final term in searchTerms) {
      // Exact name match (highest score)
      if (nameLower == term) {
        score += 100;
      }
      // Name starts with term
      else if (nameLower.startsWith(term)) {
        score += 50;
      }
      // Name contains term
      else if (nameLower.contains(term)) {
        score += 25;
      }
      // Description contains term
      else if (descLower.contains(term)) {
        score += 10;
      }
      // Related keyword matching
      else if (_matchesRelatedKeywords(node, term)) {
        score += 15;
      }
    }

    return score;
  }

  /// Check if a node matches related keywords (synonyms, common associations).
  bool _matchesRelatedKeywords(LibraryNode node, String term) {
    // Build keyword associations based on node type and content
    final keywords = <String>[];
    final nameLower = node.name.toLowerCase();

    // Holiday-related keywords
    if (nameLower.contains('christmas') || nameLower.contains('xmas')) {
      keywords.addAll(['holiday', 'festive', 'winter', 'december', 'santa', 'red', 'green']);
    }
    if (nameLower.contains('halloween')) {
      keywords.addAll(['spooky', 'scary', 'october', 'orange', 'purple', 'ghost', 'pumpkin']);
    }
    if (nameLower.contains('july') || nameLower.contains('independence')) {
      keywords.addAll(['patriotic', 'america', 'usa', 'fireworks', 'red', 'white', 'blue']);
    }
    if (nameLower.contains('valentine')) {
      keywords.addAll(['love', 'romantic', 'heart', 'pink', 'red', 'february']);
    }
    if (nameLower.contains('easter')) {
      keywords.addAll(['spring', 'pastel', 'bunny', 'egg']);
    }
    if (nameLower.contains('patrick')) {
      keywords.addAll(['irish', 'lucky', 'shamrock', 'green', 'march']);
    }
    if (nameLower.contains('thanksgiving')) {
      keywords.addAll(['fall', 'autumn', 'harvest', 'turkey', 'november', 'orange']);
    }

    // Sports-related keywords
    if (node.parentId?.contains('sports') == true || node.parentId?.contains('nfl') == true ||
        node.parentId?.contains('nba') == true || node.parentId?.contains('mlb') == true) {
      keywords.addAll(['game', 'team', 'fan', 'sport', 'gameday']);
    }

    // Architectural keywords
    if (nameLower.contains('white') || nameLower.contains('warm') || nameLower.contains('cool')) {
      keywords.addAll(['elegant', 'architectural', 'downlight', 'accent', 'subtle']);
    }

    // Party keywords
    if (nameLower.contains('party') || nameLower.contains('birthday') || nameLower.contains('rave')) {
      keywords.addAll(['fun', 'celebration', 'festive', 'disco', 'dance']);
    }

    return keywords.any((kw) => kw.contains(term) || term.contains(kw));
  }

  /// Check if a pattern item matches the search terms.
  bool _patternMatchesQuery(PatternItem item, List<String> searchTerms) {
    final nameLower = item.name.toLowerCase();
    return searchTerms.any((term) => nameLower.contains(term));
  }

  /// Compare two strings by relevance to a query (for sorting).
  int _compareByRelevance(String a, String b, String query) {
    final queryLower = query.toLowerCase();
    final aLower = a.toLowerCase();
    final bLower = b.toLowerCase();

    // Exact match first
    if (aLower == queryLower && bLower != queryLower) return -1;
    if (bLower == queryLower && aLower != queryLower) return 1;

    // Starts with query
    if (aLower.startsWith(queryLower) && !bLower.startsWith(queryLower)) return -1;
    if (bLower.startsWith(queryLower) && !aLower.startsWith(queryLower)) return 1;

    // Alphabetical
    return aLower.compareTo(bLower);
  }
}

/// Search results from the library search.
class LibrarySearchResults {
  final List<LibraryNode> palettes;
  final List<LibraryNode> folders;
  final List<PatternItem> patterns;

  const LibrarySearchResults({
    required this.palettes,
    required this.folders,
    required this.patterns,
  });

  /// Returns true if there are any results.
  bool get hasResults => palettes.isNotEmpty || folders.isNotEmpty || patterns.isNotEmpty;

  /// Total number of results.
  int get totalCount => palettes.length + folders.length + patterns.length;
}
